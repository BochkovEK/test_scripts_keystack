#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

DOCKER_COMPOSE_COMMAND='docker compose'

# Parse command-line arguments
SKIP_DOCKER_UPLOAD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-docker-upload)
      SKIP_DOCKER_UPLOAD=1
      shift
      ;;
    --ignore-prechecks)
      IGNORE_PRECHECKS=1
      shift
      ;;
    --help|-h)
      cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --skip-docker-upload    Skip the upload_docker_nexus step (keystack-*-docker-images.tar)
  --ignore-prechecks      Show all pre-check warnings but continue on user approval
  --help, -h              Show this help message

Environment Variables:
  KS_INSTALL_HOME         Installation home directory (default: /installer)
  KS_INSTALL_LCM_IP       LCM IP address (auto-detected if not set)
  KS_CLIENT_NEXUS         Use remote Nexus (y/n)
  KS_LDAP_USE             Enable LDAP authentication (y/n)
  KS_INSTALL_DOMAIN       Root domain for KeyStack (default: demo.local)
  KS_INSTALL_SILENT       Skip confirmation prompts
  ... and more (see script for full list)

EOF
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# check os release
os=unknown
# shellcheck disable=SC1091
[[ -f /etc/os-release ]] && os=$({ . /etc/os-release; echo "${ID,,}"; })

# check for elevated privileges
if [ "$(id -u)" -ne 0 ]; then
  echo "This script has to be run as root or via sudo."
  exit 1
fi

log_info() {
    # Вывод зеленым цветом
    echo -e "\033[1;32m$1\033[0m"
}

log_info_block() {
    echo "================================================="
    # Вывод зеленым цветом
    echo -e "\033[1;32m$1\033[0m"
    echo "================================================="
}

exit_on_error() {
    # Вывод красным цветом
    echo -e "\033[1;31m$1\033[0m" >&2
    exit 1
}

check_file_exists() {
    if [ ! -f "$1" ]; then
        exit_on_error "Файл $1 не найден."
    fi
}

check_directory_exists() {
    if [ ! -d "$1" ]; then
        exit_on_error "Директория $1 не найдена."
    fi
}

escape_sed() {
  # Escape only what's needed for the sed replacement part
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}
replace_in_file() {
  local placeholder="$1" value="$2" file="$3"
  sed -i "s|${placeholder}|$(escape_sed "$value")|g" "$file"
}

# push_pypi_with_curl <dist_dir> <nexus_fqdn> <pypi_repo_name> <user> <pass>
# - Uploads all files (whl, tar.gz, zip) from dist_dir to Nexus PyPI via curl (no twine).
# - Reuses helpers & flags like CURL_INSECURE; supports parallelism and skip-existing.
# - Requires: bash, curl, jq (optional), awk, sed, sha256sum, hexdump, stat, tr, xargs
# - Env:
#     PARALLEL_UPLOADS: number of workers (default: half CPU cores, min 1)
#     PYPI_SKIP_EXISTING=1: do not re-upload files that already exist
#     CURL_INSECURE=1: allow self-signed TLS (-k)
push_pypi_with_curl() {
  local DIST_DIR="$1" FQDN="$2" REPO="$3" USER="$4" PASS="$5"

  [[ -d "$DIST_DIR" && -n "$FQDN" && -n "$REPO" && -n "$USER" && -n "$PASS" ]] || {
    echo "Usage: push_pypi_with_curl <dist_dir> <nexus_fqdn> <repo> <user> <pass>" >&2; return 2; }

  # ── deps ─────────────────────────────────────────────
  for bin in curl awk sed sha256sum stat tr xargs; do
    command -v "$bin" >/dev/null || { echo "Missing dependency: $bin" >&2; return 2; }
  done

  # ── parallelism ─────────────────────────────────────
  local CPU_CORES PARALLEL
  if command -v nproc >/dev/null 2>&1; then CPU_CORES="$(nproc)"; else CPU_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"; fi
  PARALLEL=${PARALLEL_UPLOADS:-$(( CPU_CORES / 2 ))}
  (( PARALLEL < 1 )) && PARALLEL=1
  echo "🧩 Parallel uploads: using $PARALLEL workers (half of $CPU_CORES cores)"

  # ── curl base ───────────────────────────────────────
  local CURL="curl -sS --fail-with-body --retry 3 --retry-connrefused --retry-delay 2 --max-time 0"
  [[ -n "${CURL_INSECURE-}" ]] && CURL+=" -k"
  CURL+=" -u $USER:$PASS"

  # ── helpers (reuses your style) ─────────────────────
  _ts(){ date '+%H:%M:%S'; }
  _pp(){ local tag="$1"; while IFS= read -r line; do printf '[%s][%s] %s\n' "$(_ts)" "$tag" "$line"; done; }
  human_readable_size(){ local b=$1; local kb=1024 mb=$((1024*1024)) gb=$((1024*1024*1024));
    if   (( b < kb )); then echo "${b}B";
    elif (( b < mb )); then awk -v b="$b" 'BEGIN{printf "%.1f KB", b/1024}';
    elif (( b < gb )); then awk -v b="$b" 'BEGIN{printf "%.1f MB", b/1048576}';
    else                     awk -v b="$b" 'BEGIN{printf "%.2f GB", b/1073741824}';
    fi; }

  # PEP 503 normalize: lowercase + collapse [-_.]+ to -
  _pep503_norm(){
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[-_.]+/-/g'
  }

  # Parse name/version from filename (wheel & sdist)
  _parse_name_version(){
    # prints: "<name>|<version>|<filetype>|<pyversion>"
    local f="$1" base; base="$(basename "$f")"
    if [[ "$base" == *.whl ]]; then
      # wheel: {name}-{version}(-{build})?-{py}-{abi}-{plat}.whl
      local name ver rest; name="${base%%-*}"; rest="${base#*-}"
      ver="${rest%%-*}"
      # python tag is the next component after optional build
      # detect build tag (contains a digit + dot maybe); use 5 components total if no build
      local noext="${base%.whl}"
      IFS='-' read -r n v _maybe_build py _abi _plat <<< "$noext"
      if [[ -n "$plat" ]]; then
        echo "$n|$v|bdist_wheel|${py}"
      else
        # fallback simple
        echo "$name|$ver|bdist_wheel|py3"
      fi
    else
      # sdist: {name}-{version}.tar.gz / .zip
      local name="${base%%-*}"
      local ver_ext="${base#*-}"
      local ver="${ver_ext%%.*}"  # crude; handles first dot; better: strip known suffixes
      # improve: strip .tar.gz or .zip
      ver="${base#"${name}"-}"
      ver="${ver%.tar.gz}"
      ver="${ver%.zip}"
      ver="${ver%.tar.bz2}"
      echo "$name|$ver|sdist|source"
    fi
  }

  # Check if a filename already exists in /simple/<name> index
  _pypi_exists(){
    local name="$1"
    local filename="$2"
    local url
    url="https://$FQDN/repository/$REPO/simple/$(_pep503_norm "$name")/"
    $CURL -I "$url" >/dev/null 2>&1 || return 1
    # fetch page and look for the exact filename (case-sensitive)
    $CURL "$url" 2>/dev/null | grep -Fq ">$filename<"
  }

  # Upload one distribution file using the legacy multipart form (Warehouse/Nexus)
  _pypi_upload_one(){
    local f="$1"; [[ -f "$f" ]] || { echo "skip: not a file: $f"; return 0; }
    local base size shas; base="$(basename "$f")"
    size=$(stat -c '%s' "$f" 2>/dev/null || stat -f '%z' "$f")
    shas="$(sha256sum "$f" | awk '{print $1}')"

    IFS='|' read -r name ver filetype pyver <<< "$(_parse_name_version "$f")"
    local tag="$name==$ver"

    if [[ -n "${PYPI_SKIP_EXISTING-}" ]]; then
      if _pypi_exists "$name" "$base"; then
        printf '[%s][%s] %s exists in repo, skipping\n' "$(_ts)" "$tag" "$base"
        return 0
      fi
    fi

    printf '\n[%s] \033[1;36m[%s] UPLOAD %s (%s)\033[0m\n' "$(_ts)" "$tag" "$base" "$(human_readable_size "$size")"

    # The legacy upload form fields expected by Warehouse/Nexus
    # See: :action=file_upload, protocol_version=1
    # Required fields vary; these work for Nexus hosted PyPI.
    local url="https://$FQDN/repository/$REPO/"

    # We do not send md5; sha256 is accepted. If your Nexus requires md5, add it.
    # Summary/home_page/etc are optional; Nexus ignores most extras.
    if $CURL -X POST "$url" \
        -F ":action=file_upload" \
        -F "protocol_version=1" \
        -F "name=$name" \
        -F "version=$ver" \
        -F "filetype=$filetype" \
        -F "pyversion=$pyver" \
        -F "sha256_digest=$shas" \
        -F "content=@$f;filename=$base" >/dev/null; then
      printf '[%s] \033[1;32m[%s] DONE %s\033[0m\n' "$(_ts)" "$tag" "$base"
    else
      printf '[%s] \033[1;31m[%s] FAIL %s\033[0m\n' "$(_ts)" "$tag" "$base"
      return 1
    fi
  }

  export -f _ts _pp human_readable_size _pep503_norm _parse_name_version _pypi_exists _pypi_upload_one
  export FQDN REPO USER PASS CURL PYPI_SKIP_EXISTING

  # Collect candidate files
  mapfile -t FILES < <(find "$DIST_DIR" -maxdepth 1 -type f \( -name '*.whl' -o -name '*.tar.gz' -o -name '*.zip' \) | sort)
  local COUNT="${#FILES[@]}"
  (( COUNT == 0 )) && { echo "No distribution files in $DIST_DIR"; return 0; }

  echo "Found $COUNT file(s) to upload from $DIST_DIR"

  # Progress trackers (like your docker pusher)
  local PROGRESS_FILE PROGRESS_LOCK
  PROGRESS_FILE="$(mktemp)"; PROGRESS_LOCK="${PROGRESS_FILE}.lock"; echo 0 > "$PROGRESS_FILE"; : > "$PROGRESS_LOCK"
  export PROGRESS_FILE PROGRESS_LOCK TOTAL_TASKS="$COUNT"

  # Wrapper to keep the nice progress output
  _worker(){
    local f="$1"
    if _pypi_upload_one "$f"; then
      (
        flock 9
        local progress_done; progress_done=$(($(<"$PROGRESS_FILE") + 1))
        echo "$progress_done" > "$PROGRESS_FILE"
        printf "\r[%s] Progress: %d/%d packages complete..." "$(_ts)" "$progress_done" "$TOTAL_TASKS" >&2
      ) 9>"$PROGRESS_LOCK"
      return 0
    else
      return 1
    fi
  }
  export -f _worker

  printf '%s\0' "${FILES[@]}" | xargs -0 -n1 -P"$PARALLEL" bash -c '_worker "$@"' _

  local FINAL_DONE; FINAL_DONE=$(<"$PROGRESS_FILE")
  echo -e "\n[$(_ts)] ✅ All $FINAL_DONE/$TOTAL_TASKS packages processed"

  rm -f "$PROGRESS_FILE" "$PROGRESS_LOCK"
}

# push_docker_archive_with_curl <archive.tar> <registry_fqdn> <user> <pass> [src_prefix=repo.itkey.com]
# - Pushes all images/tags from a docker-archive tar straight into a Registry v2 (Nexus) via curl.
# - Requires: bash, curl, jq, tar, sha256sum, awk, hexdump, stat
# - Optional: export CURL_INSECURE=1 to allow self-signed TLS
push_docker_archive_with_curl() {
  local ARCHIVE="$1" REGISTRY="$2" USER="$3" PASS="$4" SRC_PREFIX="${5:-repo.itkey.com}"

  [[ -f "$ARCHIVE" && -n "$REGISTRY" && -n "$USER" && -n "$PASS" ]] || {
    echo "Usage: push_docker_archive_with_curl <archive.tar> <registry> <user> <pass> [src_prefix]" >&2; return 2; }

  for bin in curl jq tar sha256sum awk hexdump stat date; do
    command -v "$bin" >/dev/null || { echo "Missing dependency: $bin" >&2; return 2; }
  done

  # ── system parallelism ───────────────────────────────
  local CPU_CORES PARALLEL
  if command -v nproc >/dev/null 2>&1; then
    CPU_CORES="$(nproc)"
  else
    CPU_CORES="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"
  fi
  PARALLEL=${PARALLEL_UPLOADS:-$(( CPU_CORES / 2 ))}
  (( PARALLEL < 1 )) && PARALLEL=1
  echo "🧩 Parallel uploads: using $PARALLEL workers (half of $CPU_CORES cores)"

  # ── curl base config ─────────────────────────────────
  local CURL="curl -sS --fail-with-body --retry 3 --retry-connrefused --retry-delay 2 --max-time 0"

  # If CURL_INSECURE is set and non-empty, add -k
  if [[ -n "${CURL_INSECURE-}" ]]; then
    CURL+=" -k"
  fi

  CURL+=" -u $USER:$PASS"

  # ── helpers ──────────────────────────────────────────
    _ts() { date '+%H:%M:%S'; }

    human_readable_size() {
      local bytes=$1
      local kb=1024 mb=$((1024*1024)) gb=$((1024*1024*1024))
      if ((bytes < kb)); then
        echo "${bytes}B"
      elif ((bytes < mb)); then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}'
      elif ((bytes < gb)); then
        awk -v b="$bytes" 'BEGIN {printf "%.1f MB", b/1048576}'
      else
        awk -v b="$bytes" 'BEGIN {printf "%.2f GB", b/1073741824}'
      fi
    }

    _pp() {
      local tag="$1"
      # Prefix each incoming line at runtime with timestamp + tag
      while IFS= read -r line; do
        printf '[%s][%s] %s\n' "$(_ts)" "$tag" "$line"
      done
    }

  _blob_exists(){ $CURL -I "https://$REGISTRY/v2/$1/blobs/$2" >/dev/null 2>&1; }

  _upload_blob(){  # name digest file_in_tar size_bytes
    local name="$1" digest="$2" file_in_tar="$3"
    local loc tmp
    loc="$(
      $CURL --http1.1 -i -X POST "https://$REGISTRY/v2/$name/blobs/uploads/" \
        | awk -v IGNORECASE=1 '/^Location: /{sub(/\r/,"");print $2; exit}'
    )" || return 1
    loc="$(printf '%s' "$loc" | tr -d '\r')"
    if [[ "$loc" != http*://* ]]; then
      [[ "$loc" = /* ]] || loc="/$loc"
      loc="https://$REGISTRY${loc}"
    fi
    tmp="$(mktemp)" || return 1
    tar -xOf "$ARCHIVE" "$file_in_tar" > "$tmp" || { rm -f "$tmp"; return 1; }

    $CURL --http1.1 -X PATCH "$loc" -H "Content-Type: application/octet-stream" --upload-file "$tmp" || { rm -f "$tmp"; return 1; }
    $CURL --http1.1 -X PUT "${loc}?digest=${digest}" -H "Content-Length: 0" -d '' || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
  }

  # ── read manifest ────────────────────────────────────
  local MANIFEST_JSON; MANIFEST_JSON="$(tar -xOf "$ARCHIVE" manifest.json)" || { echo "Cannot read manifest.json"; return 1; }
  local rec_cnt; rec_cnt="$(echo "$MANIFEST_JSON" | jq 'length')" || rec_cnt=0
  echo "Found $rec_cnt image record(s) in $ARCHIVE"
  (( rec_cnt == 0 )) && return 0

  # ── build task list ──────────────────────────────────
  local TASKS_FILE; TASKS_FILE="$(mktemp)"
  for idx in $(seq 0 $((rec_cnt-1))); do
    local cfg_file layers tags
    cfg_file="$(echo "$MANIFEST_JSON" | jq -r ".[$idx].Config")"
    layers="$(echo "$MANIFEST_JSON" | jq -r ".[$idx].Layers[]" | paste -sd',' -)"
    tags="$(echo "$MANIFEST_JSON" | jq -r ".[$idx].RepoTags[]")"
    while IFS= read -r t; do
      [[ "$t" =~ ^${SRC_PREFIX}/ ]] || continue
      printf '%s|%s|%s|%s\n' "$idx" "$t" "$cfg_file" "$layers" >> "$TASKS_FILE"
    done <<< "$tags"
  done
    local TOTAL_TASKS; TOTAL_TASKS=$(wc -l <"$TASKS_FILE")
    echo "Prepared $TOTAL_TASKS push task(s)."

    # progress counters
    local PROGRESS_FILE; PROGRESS_FILE="$(mktemp)"
    echo 0 > "$PROGRESS_FILE"

    # lock file path and ensure it exists
    local PROGRESS_LOCK="${PROGRESS_FILE}.lock"
    : > "$PROGRESS_LOCK"

    # export to workers (this was missing)
    export TOTAL_TASKS PROGRESS_FILE PROGRESS_LOCK

  # ── worker ───────────────────────────────────────────
  _push_one() {
    IFS='|' read -r _rec_id src_tag cfg_file layers_csv <<< "$1"

    local image_path="${src_tag#"${SRC_PREFIX}"/}"
    local tag="${image_path##*:}"
    local name="${image_path%:*}"
    local dst_tag="$REGISTRY/$name:$tag"

    printf '[%s] \033[1;36m[%s] START\033[0m\n' "$(_ts)" "$dst_tag"

    local tmp_cfg cfg_size cfg_digest
    tmp_cfg="$(mktemp)" || { echo "[$(_ts)] [$dst_tag] mktemp failed"; return 1; }
    tar -xOf "$ARCHIVE" "$cfg_file" > "$tmp_cfg" || { echo "[$(_ts)] [$dst_tag] missing $cfg_file"; rm -f "$tmp_cfg"; return 1; }
    cfg_size=$(stat -c '%s' "$tmp_cfg" 2>/dev/null || stat -f '%z' "$tmp_cfg")
    cfg_digest="sha256:$(sha256sum "$tmp_cfg" | awk '{print $1}')"
    local cfg_human; cfg_human=$(human_readable_size "$cfg_size")

    if _blob_exists "$name" "$cfg_digest"; then
      echo "[$(_ts)] [$dst_tag] config exists $cfg_digest"
    else
      echo "[$(_ts)] [$dst_tag] uploading config $cfg_digest ($cfg_human)"
      _upload_blob "$name" "$cfg_digest" "$cfg_file" "$cfg_size" | _pp "$dst_tag" \
        || { echo "[$(_ts)] [$dst_tag] FAIL config upload"; rm -f "$tmp_cfg"; return 1; }
    fi

    local -a L_SIZES=() L_DIGS=() L_TYPES=()
    IFS=',' read -ra L_FILES <<< "$layers_csv"
    local lf sz dg magic mt szh
    for lf in "${L_FILES[@]}"; do
      [[ -z "$lf" ]] && continue
      sz=$(tar -xOf "$ARCHIVE" "$lf" | wc -c)
      dg="sha256:$(tar -xOf "$ARCHIVE" "$lf" | sha256sum | awk '{print $1}')"
      szh=$(human_readable_size "$sz")
      magic="$(tar -xOf "$ARCHIVE" "$lf" | head -c3 | hexdump -v -e '/1 "%02x"')"
      [[ "$magic" == "1f8b08" ]] && mt="application/vnd.docker.image.rootfs.diff.tar.gzip" || mt="application/vnd.docker.image.rootfs.diff.tar"

      if _blob_exists "$name" "$dg"; then
        echo "[$(_ts)] [$dst_tag] layer exists $dg"
      else
        echo "[$(_ts)] [$dst_tag] uploading layer $dg ($szh)"
        _upload_blob "$name" "$dg" "$lf" "$sz" | _pp "$dst_tag" \
          || { echo "[$(_ts)] [$dst_tag] FAIL layer upload $dg"; rm -f "$tmp_cfg"; return 1; }
      fi

      L_SIZES+=("$sz"); L_DIGS+=("$dg"); L_TYPES+=("$mt")
    done

    local manifest
    manifest="$(
      jq -n \
        --arg mt "application/vnd.docker.distribution.manifest.v2+json" \
        --arg cfgMedia "application/vnd.docker.container.image.v1+json" \
        --arg cfgDigest "$cfg_digest" \
        --argjson cfgSize "$cfg_size" \
        --argjson sizes "$(printf '%s\n' "${L_SIZES[@]}" | jq -R . | jq -s '.')" \
        --argjson digests "$(printf '%s\n' "${L_DIGS[@]}" | jq -R . | jq -s '.')" \
        --argjson types "$(printf '%s\n' "${L_TYPES[@]}" | jq -R . | jq -s '.')" '
        {
          schemaVersion: 2,
          mediaType: $mt,
          config: { mediaType: $cfgMedia, size: $cfgSize, digest: $cfgDigest },
          layers: [ range(0; ($sizes|length)) as $i |
            { mediaType: $types[$i], size: ($sizes[$i]|tonumber), digest: $digests[$i] }
          ]
        }'
    )"

    if $CURL -X PUT -H "Content-Type: application/vnd.docker.distribution.manifest.v2+json" \
             -d "$manifest" "https://$REGISTRY/v2/$name/manifests/$tag" >/dev/null; then
      printf '[%s] \033[1;32m[%s] DONE\033[0m\n' "$(_ts)" "$dst_tag"
    else
      printf '[%s] \033[1;31m[%s] FAIL manifest PUT\033[0m\n' "$(_ts)" "$dst_tag"
      rm -f "$tmp_cfg"; return 1
    fi
    rm -f "$tmp_cfg"

    (
      flock 9
      local progress_done; progress_done=$(($(<"$PROGRESS_FILE") + 1))
      echo "$progress_done" > "$PROGRESS_FILE"
      echo "[$(_ts)] Progress: $progress_done/$TOTAL_TASKS images complete..."
    ) 9>"$PROGRESS_LOCK"
  }

  export -f _upload_blob _blob_exists _pp _push_one _ts human_readable_size
  export ARCHIVE REGISTRY USER PASS SRC_PREFIX CURL

  xargs -a "$TASKS_FILE" -n1 -P"$PARALLEL" bash -c '_push_one "$@"' _

  local FINAL_DONE; FINAL_DONE=$(<"$PROGRESS_FILE")
  echo "[$(_ts)] ✅ All $FINAL_DONE/$TOTAL_TASKS images processed"

  rm -f "$TASKS_FILE" "$PROGRESS_FILE" "$PROGRESS_LOCK"
}


# wait_http_200 URL NAME [TIMEOUT_SEC]
wait_http_200() {
  local url="$1" name="$2" timeout="${3:-1200}"
  local start now code

  printf "\nWaiting for %s readiness" "$name"
  start=$(date +%s)
  while :; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)
    if [[ "$code" == "200" ]]; then
      echo -e "\n✅ $name is ready"
      return 0
    fi
    printf .
    sleep 5
    now=$(date +%s)
    (( now - start > timeout )) && { echo -e "\n❌ $name not ready after $((timeout/60))m"; exit 1; }
  done
}

# wait_json_eq URL JQ_FILTER EXPECTED NAME [TIMEOUT_SEC]
# Example: wait_json_eq "https://gitlab/-/readiness" ".status" "ok" "GitLab"
wait_json_eq() {
  local url="$1" jq_filter="$2" expected="$3" name="$4" timeout="${5:-1200}"
  local start now body value

  printf "\nWaiting for %s readiness" "$name"
  start=$(date +%s)
  while :; do
    body=$(curl -s --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || true)

    if command -v jq >/dev/null 2>&1; then
      value=$(printf '%s' "$body" | jq -r "$jq_filter" 2>/dev/null || true)
    else
      # crude jq-less fallback for simple .status fields
      # pulls "status":"ok" or "status": "ok"
      value=$(printf '%s' "$body" | sed -nE 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')
    fi

    if [[ "$value" == "$expected" ]]; then
      echo -e "\n✅ $name is ready"
      return 0
    fi

    printf .
    sleep 5
    now=$(date +%s)
    (( now - start > timeout )) && { echo -e "\n❌ $name not ready after $((timeout/60))m"; exit 1; }
  done
}

#---------------------------------------------#
# * Check and install Docker if not present * #
#---------------------------------------------#

if ! command -v docker >/dev/null 2>&1; then
  log_info_block "Docker not found on the system."

  # Check if offline package exists
  IFS="-"; read -r RELEASE_TMP < version; unset IFS
  IFS="-"; read -r BASE_TMP < version-base; unset IFS
  OFFLINE_PACKAGE="lcmpackages-${BASE_TMP}.gz"

  if [[ -f "$OFFLINE_PACKAGE" ]]; then
    echo "⚠️  Docker is not installed, but offline package found: $OFFLINE_PACKAGE"
    echo "Docker will be installed from offline packages during installation."
    log_info "Skipping online Docker installation (offline package available)"
  else
    echo
    echo "⚠️  Docker installation requires Internet access to download packages."
    echo "If you are offline, provide the $OFFLINE_PACKAGE file or install Docker manually."

    if [[ -t 0 ]]; then
      read -rp "Do you want to proceed with online Docker installation? [y/N]: " DOCKER_INSTALL_CONFIRM
      DOCKER_INSTALL_CONFIRM=${DOCKER_INSTALL_CONFIRM,,}   # to lowercase
      DOCKER_INSTALL_CONFIRM=${DOCKER_INSTALL_CONFIRM:-n}

      if [[ "$DOCKER_INSTALL_CONFIRM" != "y" ]]; then
        exit_on_error "Docker is required to continue. Please install it manually and re-run the installer."
      fi

      log_info "Proceeding with Docker installation..."

      case "$os" in
        ubuntu)
          apt-get update -y
          apt-get install -y ca-certificates curl gnupg lsb-release
          install -m 0755 -d /etc/apt/keyrings
          curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
          chmod a+r /etc/apt/keyrings/docker.asc
          echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
            https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
            > /etc/apt/sources.list.d/docker.list
          apt-get update -y
          apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
          systemctl enable --now docker
          ;;

        sberlinux|rhel|centos|rocky)
          dnf install -y dnf-plugins-core
          dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
          dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
          systemctl enable --now docker
          ;;

        *)
          exit_on_error "Unsupported OS: $os. Please install Docker manually."
          ;;
      esac

      log_info "✅ Docker installed successfully."
    else
      exit_on_error "Docker is required but not installed. Running in non-interactive mode. Please install Docker manually or provide $OFFLINE_PACKAGE."
    fi
  fi
else
  log_info "Docker is already installed. Skipping installation."
fi

###############################
# * Preinstall Phase        * #
# * Asking user for configs * #
###############################

IFS="-"; read -r RELEASE < version; unset IFS
IFS="-"; read -r BASE < version-base; unset IFS

echo $'\n\n'"*** KeyStack Installer v1.0 ($RELEASE-$BASE) ***"$'\n\n'

# Safe echo for unset vars with set -u
getval() { printf '%s' "${!1-}"; }

# Read/compute default LCM IP (first IPv4 from hostname -I)
auto_ip_default() {
  hostname -I 2>/dev/null | { read -r ip _ || true; printf '%s' "$ip"; }
}

# Universal prompt:
# prompt_var VAR_NAME KS_ENV_NAME "Prompt text" "default" flags
# flags (comma-separated): required,secret,minlen=8
prompt_var() {
  local VAR_NAME="$1" KS_ENV="$2" PROMPT="$3" DEFAULT="$4" FLAGS="${5:-}"
  local REQUIRED="" SECRET="" MINLEN=0
  local tmp ans

  # Parse flags
  IFS=',' read -r -a _flags <<<"$FLAGS"
  for f in "${_flags[@]}"; do
    case "$f" in
      required) REQUIRED=1 ;;
      secret)   SECRET=1 ;;
      minlen=*) MINLEN="${f#minlen=}" ;;
    esac
  done

  # If KS_ env provided, use it
  if [[ -n "${!KS_ENV-}" ]]; then
    printf -v "$VAR_NAME" '%s' "${!KS_ENV}"
    return
  fi

  # Otherwise, prompt interactively
  while :; do
    if [[ -n "$SECRET" ]]; then
      # secret prompt (no echo)
      read -r -s -p "${PROMPT} [hidden]: " ans; printf '\n'
      # apply default only if empty and default provided
      if [[ -z "$ans" && -n "$DEFAULT" ]]; then ans="$DEFAULT"; fi
    else
      read -r -p "${PROMPT} ${DEFAULT:+[$DEFAULT]}: " ans
      if [[ -z "$ans" && -n "$DEFAULT" ]]; then ans="$DEFAULT"; fi
    fi

    # Required check
    if [[ -n "$REQUIRED" && -z "$ans" ]]; then
      echo "Value is required." >&2; continue
    fi

    # Min length check
    if (( MINLEN > 0 )) && (( ${#ans} < MINLEN )); then
      echo "Value must be at least ${MINLEN} characters." >&2; continue
    fi

    break
  done

  printf -v "$VAR_NAME" '%s' "$ans"
}

# Validate LDAP DN format
# Returns 0 if valid, 1 if invalid (with warnings printed to stderr)
validate_dn() {
  local dn="$1"
  local issues=()

  # Empty check
  if [[ -z "$dn" ]]; then
    return 1  # Will be caught by required flag
  fi

  # Basic format check: should contain at least one "="
  if [[ ! "$dn" =~ = ]]; then
    issues+=("Missing '=' character - DN should contain attribute=value pairs")
  fi

  # Check for common LDAP attribute prefixes (case insensitive)
  # Valid examples: dc=, ou=, cn=, uid=, o=, l=, st=, c=
  if ! echo "$dn" | grep -qiE '(dc|ou|cn|uid|o|l|st|c)='; then
    issues+=("No recognized LDAP attributes found (dc, ou, cn, uid, etc.)")
  fi

  # Check for spaces around equals (common mistake)
  if [[ "$dn" =~ [[:space:]]=[[:space:]] ]] || [[ "$dn" =~ =[[:space:]] ]] || [[ "$dn" =~ [[:space:]]= ]]; then
    issues+=("Spaces around '=' detected - should be attribute=value without spaces")
  fi

  # Check for missing commas between components
  if [[ "$dn" =~ [a-zA-Z][a-zA-Z][[:space:]][a-zA-Z][a-zA-Z]= ]]; then
    issues+=("Missing comma between DN components")
  fi

  # Check for double commas
  if [[ "$dn" =~ ,, ]]; then
    issues+=("Double comma detected")
  fi

  # Check for trailing/leading commas
  if [[ "$dn" =~ ^, ]] || [[ "$dn" =~ ,$ ]]; then
    issues+=("Leading or trailing comma detected")
  fi

  # If there are issues, print them
  if [[ ${#issues[@]} -gt 0 ]]; then
    echo "DN validation issues:" >&2
    for issue in "${issues[@]}"; do
      echo "  - $issue" >&2
    done
    echo "Example formats: cn=admin,dc=example,dc=com  ou=groups,dc=company,dc=local" >&2
    return 1
  fi

  return 0
}

# Prompt for LDAP DN with validation
# prompt_dn VAR_NAME KS_ENV_NAME "Prompt text" "default" flags
prompt_dn() {
  local VAR_NAME="$1" KS_ENV="$2" PROMPT="$3" DEFAULT="$4" FLAGS="${5:-}"
  local ans

  # If KS_ env provided, use it without validation
  if [[ -n "${!KS_ENV-}" ]]; then
    printf -v "$VAR_NAME" '%s' "${!KS_ENV}"
    return
  fi

  # Interactive prompt with validation loop
  while :; do
    # Use prompt_var to get the input (handles required, etc.)
    prompt_var "$VAR_NAME" "$KS_ENV" "$PROMPT" "$DEFAULT" "$FLAGS"
    ans="${!VAR_NAME}"

    # Validate the DN
    if validate_dn "$ans"; then
      # Valid DN, accept it
      echo "  [OK] DN format looks valid"
      return 0
    else
      # Invalid DN, ask if they want to retry or proceed anyway
      local choice
      read -r -p "DN validation failed. (r)etry or (p)roceed anyway? [r/p]: " choice
      case "${choice,,}" in
        ''|r|retry)
          echo "Please re-enter the value..."
          continue
          ;;
        p|proceed)
          echo "Proceeding with current value..."
          return 0
          ;;
        *)
          echo "Please answer 'r' (retry) or 'p' (proceed)." >&2
          continue
          ;;
      esac
    fi
  done
}

# Normalize yes/no with default (n/Y), returns var set to y or n
prompt_yn() {
  local VAR_NAME="$1" KS_ENV="$2" PROMPT="$3" DEFAULT="${4:-n}" ans
  if [[ -n "${!KS_ENV-}" ]]; then
    ans="${!KS_ENV}"
  else
    read -r -p "$PROMPT [${DEFAULT}]: " ans
    ans="${ans:-$DEFAULT}"
  fi
  case "${ans,,}" in
    y|yes)  printf -v "$VAR_NAME" 'y' ;;
    n|no|'') printf -v "$VAR_NAME" 'n' ;;
    *) echo "Please answer y or n." >&2; prompt_yn "$@"; return ;;
  esac
}

# Replace variable if empty with default
default_if_empty() {
  local VAR_NAME="$1" DEFAULT="$2"
  if [[ -z "$(getval "$VAR_NAME")" ]]; then
    printf -v "$VAR_NAME" '%s' "$DEFAULT"
  fi
}

getv() {  # print value of variable by name, empty if unset
  local name="$1"
  printf '%s' "${!name-}"
}

mask_val() {  # mask a secret but keep it recognizable
  local name="$1" v
  v="$(getv "$name")"
  if [[ -z "$v" ]]; then
    printf ''
  else
    local n=${#v}
    if (( n <= 4 )); then
      printf '****'
    else
      printf '%s...%s' "${v:0:2}" "${v: -2}"
    fi
  fi
}

print_kv() {  # print "Label: value" (plain or secret)
  local label="$1" var="$2" mode="${3:-plain}" val
  if [[ "$mode" == "secret" ]]; then
    val="$(mask_val "$var")"
  else
    val="$(getv "$var")"
  fi
  printf '%s: %s\n' "$label" "$val"
}

fqdn_of() {  # build "<name>.<domain>" safely
  local name_var="$1" domain_var="${2:-DOMAIN}"
  local name domain
  name="$(getv "$name_var")"
  domain="$(getv "$domain_var")"
  if [[ -n "$name" && -n "$domain" ]]; then
    printf '%s.%s' "$name" "$domain"
  else
    printf '%s' "$name"
  fi
}

is_true() {
  case "${1,,}" in
    y|yes|true|1) return 0 ;;
    *)            return 1 ;;
  esac
}

# Helper to extract a key from .env file and fail if not found
get_env_var() {
  local key="$1" file="$2" val

  # Check if file exists
  if [[ ! -f "$file" ]]; then
    echo "❌ File not found: $file" >&2
    exit 1
  fi

  val=$(grep -E "^${key}=" "$file" | tail -n1 | cut -d'=' -f2- | xargs)
  if [[ -z "$val" ]]; then
    echo "❌ Missing required variable '$key' in $file" >&2
    echo "   File contents:" >&2
    head -5 "$file" >&2
    exit 1
  fi
  printf '%s' "$val"
}

# ============================================================================
# Pre-check Functions
# ============================================================================

check_system_resources() {
    local ignore_failures="${1:-0}"
    local min_memory_gb=4 min_cpu_cores=2
    local total_mem_kb total_mem_gb cpu_cores msg

    log_info "Checking system resources..."

    # Memory check
    if [[ -f /proc/meminfo ]]; then
        total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        total_mem_gb=$((total_mem_kb / 1024 / 1024))
        if (( total_mem_gb < min_memory_gb )); then
            msg="Insufficient memory: ${total_mem_gb}GB available, ${min_memory_gb}GB required"
            echo "⚠️  Warning: ${msg}"
            PRECHECK_WARNINGS+=("${msg}")
        else
            log_info "Memory: ${total_mem_gb}GB available"
        fi
    else
        echo "⚠️  Warning: Cannot check memory (/proc/meminfo not available)"
    fi

    # CPU cores check
    if command -v nproc >/dev/null 2>&1; then
        cpu_cores=$(nproc)
        if (( cpu_cores < min_cpu_cores )); then
            msg="Insufficient CPU cores: ${cpu_cores} available, ${min_cpu_cores} required"
            echo "⚠️  Warning: ${msg}"
            PRECHECK_WARNINGS+=("${msg}")
        else
            log_info "CPU cores: ${cpu_cores} available"
        fi
    else
        echo "⚠️  Warning: Cannot check CPU cores (nproc not available)"
    fi
}

detect_python() {
    if command -v python3 >/dev/null 2>&1; then
        PYTHON_CMD="python3"
    elif command -v python >/dev/null 2>&1; then
        PYTHON_CMD="python"
    else
        PYTHON_CMD=""
    fi
}

check_required_dependencies() {
    local ignore_failures="${1:-0}"
    local deps=("curl" "tar" "openssl" "jq" "git" "ssh-keygen" "sed" "awk")
    local missing_deps=() dep msg

    log_info "Checking required dependencies..."

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        else
            log_info "Dependency found: $dep"
        fi
    done

    # Check for Python (python3 or python)
    detect_python
    if [[ -z "$PYTHON_CMD" ]]; then
        missing_deps+=("python3 or python")
        echo "⚠️  Warning: Python not found (tried python3 and python)"
    else
        log_info "Dependency found: $PYTHON_CMD"
    fi

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        msg="Missing dependencies: ${missing_deps[*]}"
        echo "⚠️  Warning: ${msg}"
        PRECHECK_ERRORS+=("${msg}")
    fi
}

check_docker_availability() {
    local msg package_file

    log_info "Checking Docker availability..."

    if command -v docker >/dev/null 2>&1; then
        local docker_version=$(docker --version 2>/dev/null || echo "unknown")
        log_info "Docker is installed: $docker_version"
    else
        echo "⚠️  Warning: Docker is not currently installed"

        # Check if we have packages to install Docker
        package_file="lcmpackages-${BASE}.gz"

        if [[ -f "$package_file" ]]; then
            log_info "Docker package archive found: $package_file (will be installed)"
        else
            msg="Docker is not installed and package archive not found: $package_file"
            echo "⚠️  Warning: ${msg}"
            PRECHECK_ERRORS+=("${msg}")
        fi
    fi
}

check_required_files() {
    local required_files=(
        "compose.yaml"
        "cert.cnf"
        "daemon.json"
        "docker_auth.json"
        "pip.conf"
        "nginx.conf"
    )
    local msg

    log_info "Checking required configuration files..."

    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            msg="Required file not found: $file"
            echo "⚠️  Warning: ${msg}"
            PRECHECK_ERRORS+=("${msg}")
        else
            log_info "File found: $file"
        fi
    done
}

check_port_availability() {
    local ports=(80 443 2204 8200)
    local msg

    log_info "Checking port availability..."

    for port in "${ports[@]}"; do
        if command -v ss >/dev/null 2>&1; then
            if ss -tuln | grep -q ":$port "; then
                msg="Port $port is already in use"
                echo "⚠️  Warning: ${msg}"
                PRECHECK_ERRORS+=("${msg}")
            else
                log_info "Port $port is available"
            fi
        elif command -v netstat >/dev/null 2>&1; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                msg="Port $port is already in use"
                echo "⚠️  Warning: ${msg}"
                PRECHECK_ERRORS+=("${msg}")
            else
                log_info "Port $port is available"
            fi
        else
            echo "⚠️  Warning: Cannot check port $port (ss/netstat not available)"
            break
        fi
    done
}

check_disk_space() {
    local min_disk_gb=20
    local available_gb msg

    log_info "Checking disk space..."

    if command -v df >/dev/null 2>&1; then
        available_gb=$(df / | awk 'NR==2 {print int($4/1024/1024)}' 2>/dev/null || echo 0)

        if (( available_gb < min_disk_gb )); then
            msg="Insufficient disk space: ${available_gb}GB available, ${min_disk_gb}GB required"
            echo "⚠️  Warning: ${msg}"
            PRECHECK_WARNINGS+=("${msg}")
        else
            log_info "Disk space: ${available_gb}GB available"
        fi
    else
        echo "⚠️  Warning: Cannot check disk space (df not available)"
    fi
}

check_os_compatibility() {
    local supported_os=("ubuntu" "sberlinux" "rhel" "centos" "rocky")
    local current_os="unknown"

    log_info "Checking OS compatibility..."

    # shellcheck disable=SC1091
    [[ -f /etc/os-release ]] && current_os=$({ . /etc/os-release; echo "${ID,,}"; })

    if [[ ! " ${supported_os[*]} " =~ ${current_os} ]]; then
        echo "⚠️  Warning: Unsupported OS detected: $current_os"
        echo "Supported OS: ${supported_os[*]}"
        if [[ -t 0 ]]; then
            read -rp "Continue anyway? [y/N]: " confirm
            if [[ "${confirm,,}" != "y" ]]; then
                exit 1
            fi
        else
            echo "Proceeding with unsupported OS (non-interactive mode)"
        fi
    else
        log_info "OS compatibility: $current_os is supported"
    fi
}

check_ldap_certificate() {
    local msg

    log_info "Checking LDAP certificate requirements..."

    if [[ "${LDAP_USE:-n}" == "y" ]]; then
        if [[ ! -f "certs/ldaps.pem" ]]; then
            msg="LDAP is enabled but certs/ldaps.pem not found. Please provide the LDAP certificate chain."
            echo "⚠️  Warning: ${msg}"
            PRECHECK_ERRORS+=("${msg}")
        else
            log_info "LDAP certificate found: certs/ldaps.pem"
        fi
    else
        log_info "LDAP not enabled, skipping certificate check"
    fi
}

check_client_nexus_certificate() {
    local nexus_cert msg

    log_info "Checking Client Nexus certificate requirements..."

    if [[ "${CLIENT_NEXUS:-n}" == "y" ]]; then
        nexus_cert="certs/${CLIENT_NEXUS_NAME}.pem"
        if [[ ! -f "$nexus_cert" ]]; then
            msg="Client Nexus is enabled but $nexus_cert not found. Please provide the certificate chain."
            echo "⚠️  Warning: ${msg}"
            PRECHECK_ERRORS+=("${msg}")
        else
            log_info "Client Nexus certificate found: $nexus_cert"
        fi
    else
        log_info "Client Nexus not enabled, skipping certificate check"
    fi
}

check_docker_images_archive() {
    local archive msg

    log_info "Checking Docker images archive..."

    if [[ "${SKIP_DOCKER_UPLOAD:-0}" == "1" ]]; then
        log_info "Docker upload skipped (--skip-docker-upload flag set)"
        return 0
    fi

    archive="keystack-${RELEASE:-unknown}-docker-images.tar"

    if [[ -z "${RELEASE:-}" ]]; then
        echo "⚠️  Warning: RELEASE variable not set, cannot verify archive name"
        return 0
    fi

    if [[ ! -f "$archive" ]]; then
        msg="Docker images archive not found: $archive (use --skip-docker-upload to skip)"
        echo "⚠️  Warning: ${msg}"
        PRECHECK_ERRORS+=("${msg}")
    else
        log_info "Docker images archive found: $archive"
    fi
}

check_network_connectivity() {
    log_info "Checking network connectivity..."

    # Check Client Nexus connectivity if enabled
    if [[ "${CLIENT_NEXUS:-n}" == "y" ]] && [[ -n "${CLIENT_NEXUS_NAME:-}" ]]; then
        log_info "Checking connectivity to Client Nexus: ${CLIENT_NEXUS_NAME}"

        if command -v curl >/dev/null 2>&1; then
            if curl -s --connect-timeout 5 --max-time 10 "https://${CLIENT_NEXUS_NAME}" >/dev/null 2>&1; then
                log_info "Client Nexus is reachable: ${CLIENT_NEXUS_NAME}"
            else
                echo "⚠️  Warning: Cannot connect to Client Nexus: ${CLIENT_NEXUS_NAME}"
                echo "    This may be expected if certificates are not yet trusted"
            fi
        fi
    else
        log_info "Client Nexus not enabled, skipping connectivity check"
    fi
}

check_firewalld() {
    log_info "Checking firewalld status..."

    if command -v firewall-cmd >/dev/null 2>&1; then
        if systemctl is-active --quiet firewalld 2>/dev/null; then
            echo "⚠️  Warning: firewalld is running"
            echo "    Required ports: 80, 443, 2204, 8200"
            echo "    You may need to configure firewall rules:"
            echo "    firewall-cmd --permanent --add-port=80/tcp"
            echo "    firewall-cmd --permanent --add-port=443/tcp"
            echo "    firewall-cmd --reload"

            # Check if ports are allowed
            local ports_configured=0
            for port in 80 443; do
                if firewall-cmd --list-ports 2>/dev/null | grep -q "${port}/tcp"; then
                    ((ports_configured++))
                fi
            done

            if (( ports_configured == 4 )); then
                log_info "All required ports are configured in firewalld"
            elif (( ports_configured > 0 )); then
                echo "⚠️  Warning: Only $ports_configured/4 required ports are configured"
            else
                echo "⚠️  Warning: Required ports do not appear to be configured in firewalld"
            fi
        else
            log_info "firewalld is not active"
        fi
    else
        log_info "firewalld not installed"
    fi
}

check_certificates_for_non_selfsigned() {
    local cert_dir="certs"
    local required_certs cert_name cert_file key_file missing_certs=() msg

    log_info "Checking certificate requirements..."

    if [[ "${SELF_SIG:-y}" != "y" ]]; then
        log_info "Self-signed certificates disabled, checking for provided certificates..."

        required_certs=(
            "${NEXUS_NAME:-nexus}"
            "${GITLAB_NAME:-ks-lcm}"
            "${VAULT_NAME:-vault}"
            "${NETBOX_NAME:-netbox}"
        )

        for cert_name in "${required_certs[@]}"; do
            cert_file="${cert_dir}/${cert_name}.crt"
            key_file="${cert_dir}/${cert_name}.key"

            if [[ ! -f "$cert_file" ]]; then
                missing_certs+=("$cert_file")
            fi
            if [[ ! -f "$key_file" ]]; then
                missing_certs+=("$key_file")
            fi
        done

        if [[ ${#missing_certs[@]} -gt 0 ]]; then
            msg="Self-signed certificates disabled but some certificate files are missing: ${missing_certs[*]}. Either provide these certificates or set SELF_SIG=y"
            echo "⚠️  Warning: Self-signed certificates disabled but some certificate files are missing:"
            for cert in "${missing_certs[@]}"; do
                echo "    - $cert"
            done
            echo "    Either provide these certificates or set SELF_SIG=y"
            PRECHECK_WARNINGS+=("${msg}")
        else
            log_info "All required certificates found"
        fi
    else
        log_info "Self-signed certificates enabled, will generate certificates"
    fi
}

check_write_permissions() {
    local dirs_to_check dir parent_dir msg

    log_info "Checking write permissions..."

    dirs_to_check=(
        "${INSTALL_HOME:-/installer}"
        "/etc/docker"
    )

    for dir in "${dirs_to_check[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ -w "$dir" ]]; then
                log_info "Write permission OK: $dir"
            else
                msg="No write permission to: $dir"
                echo "⚠️  Warning: ${msg}"
                PRECHECK_ERRORS+=("${msg}")
            fi
        else
            # Directory doesn't exist, check if we can create it
            parent_dir=$(dirname "$dir")
            if [[ -w "$parent_dir" ]]; then
                log_info "Can create directory: $dir"
            else
                msg="Cannot create directory: $dir (no write permission to $parent_dir)"
                echo "⚠️  Warning: ${msg}"
                PRECHECK_ERRORS+=("${msg}")
            fi
        fi
    done
}

# Comprehensive pre-checks
run_prechecks() {
    local ignore_failures="${1:-0}"

    # Initialize arrays for warnings and errors
    PRECHECK_WARNINGS=()
    PRECHECK_ERRORS=()

    log_info_block "Running system pre-checks"

    # 1. OS compatibility
    check_os_compatibility "$ignore_failures"

    # 2. System resource checks
    check_system_resources "$ignore_failures"

    # 3. Dependency validation
    check_required_dependencies "$ignore_failures"

    # 4. Docker availability
    check_docker_availability "$ignore_failures"

    # 5. Configuration files
    check_required_files "$ignore_failures"

    # 6. Port availability
    check_port_availability "$ignore_failures"

    # 7. Disk space
    check_disk_space "$ignore_failures"

    # 8. Write permissions
    check_write_permissions "$ignore_failures"

    # 9. Firewalld status
    check_firewalld "$ignore_failures"

    # 10. LDAP certificate (if LDAP enabled)
    check_ldap_certificate "$ignore_failures"

    # 11. Client Nexus certificate (if Client Nexus enabled)
    check_client_nexus_certificate "$ignore_failures"

    # 12. Certificate requirements for non-self-signed mode
    check_certificates_for_non_selfsigned "$ignore_failures"

    # 13. Docker images archive (if not skipped)
    check_docker_images_archive "$ignore_failures"

    # 14. Network connectivity (if Client Nexus enabled)
    check_network_connectivity "$ignore_failures"

    # Summary and decision
    local total_errors=${#PRECHECK_ERRORS[@]}
    local total_warnings=${#PRECHECK_WARNINGS[@]}

    echo
    if [[ $total_errors -eq 0 ]] && [[ $total_warnings -eq 0 ]]; then
        log_info "✅ All pre-checks passed"
        return 0
    fi

    # Print summary
    echo "================================================="
    echo "Pre-check Summary:"
    echo "  Errors:   $total_errors"
    echo "  Warnings: $total_warnings"
    echo "================================================="

    if [[ $total_errors -gt 0 ]]; then
        echo
        echo "ERRORS (must be fixed):"
        for err in "${PRECHECK_ERRORS[@]}"; do
            echo "  ❌ $err"
        done
    fi

    if [[ $total_warnings -gt 0 ]]; then
        echo
        echo "WARNINGS (may affect installation):"
        for warn in "${PRECHECK_WARNINGS[@]}"; do
            echo "  ⚠️  $warn"
        done
    fi

    echo
    if [[ "$ignore_failures" == "1" ]]; then
        log_info "⚠️  Continuing despite issues (--ignore-prechecks flag set)"
        return 0
    fi

    # If there are errors and not in silent mode, ask for confirmation
    if [[ $total_errors -gt 0 ]]; then
        if [[ -t 0 ]]; then
            echo
            read -rp "Continue despite errors? [y/N]: " confirm
            if [[ "${confirm,,}" == "y" ]]; then
                log_info "⚠️  Continuing with errors as per user confirmation"
                return 0
            else
                exit_on_error "Pre-check failed. Please fix the errors above and try again."
            fi
        else
            exit_on_error "Pre-check failed in non-interactive mode. Use --ignore-prechecks to bypass."
        fi
    elif [[ $total_warnings -gt 0 ]]; then
        # Only warnings, ask for confirmation
        if [[ -t 0 ]]; then
            echo
            read -rp "Continue despite warnings? [Y/n]: " confirm
            if [[ "${confirm,,}" != "n" ]]; then
                log_info "✅ Continuing with warnings as per user confirmation"
                return 0
            else
                exit 1
            fi
        else
            log_info "⚠️  Continuing with warnings in non-interactive mode"
            return 0
        fi
    fi
}

# -------- inputs --------

# INSTALL_HOME
prompt_var INSTALL_HOME KS_INSTALL_HOME \
  "Enter the home dir for the installation" "/installer"

mkdir -p -- "$INSTALL_HOME"
export INSTALL_HOME

# Machine IP (auto-detect default)
_lcm_ip_default="$(auto_ip_default)"
prompt_var lcm_ip KS_INSTALL_LCM_IP \
  "Enter the IP address of this machine" "$_lcm_ip_default"

# Client Nexus (y/n)
prompt_yn CLIENT_NEXUS KS_CLIENT_NEXUS \
  "Use remote/existing Artifactory y/n" "n"
export CLIENT_NEXUS

if [[ "$CLIENT_NEXUS" == "y" ]]; then
  prompt_var CLIENT_NEXUS_NAME   KS_CLIENT_NEXUS_NAME   \
    "Enter the remote/existing Artifactory FQDN for the KeyStack" "" required
  prompt_var CLIENT_NEXUS_ADMIN  KS_CLIENT_NEXUS_ADMIN  \
    "Enter the remote/existing Artifactory user name" "" required
  prompt_var CLIENT_NEXUS_PASSWORD KS_CLIENT_NEXUS_PASSWORD \
    "Enter the remote/existing Artifactory password (at least 8 characters)" "" "required,secret,minlen=8"
fi

# LDAP use (y/n)
prompt_yn LDAP_USE KS_LDAP_USE "Enable auth LDAP for Gitlab and Netbox y/n" "n"
export LDAP_USE

if [[ "$LDAP_USE" == "y" ]]; then
  # LDAP configuration with validation
  # Non-DN fields
  prompt_var LDAP_SERVER_URI        KS_LDAP_SERVER_URI        "Enter the LDAP Server URI"                    ""    required
  prompt_var LDAP_SERVER_PORT       KS_LDAP_SERVER_PORT       "Enter the LDAP Server Port"                   "636" ""

  # DN fields with validation
  prompt_dn  LDAP_BIND_DN           KS_LDAP_BIND_DN           "Enter the LDAP BIND DN"                       ""    required
  prompt_var LDAP_BIND_PASSWORD     KS_LDAP_BIND_PASSWORD     "Enter the LDAP BIND Password"                 ""    "required,secret"
  prompt_dn  LDAP_USER_SEARCH_BASEDN KS_LDAP_USER_SEARCH_BASEDN "Enter the LDAP USER SEARCH BASEDN"          ""    required
  prompt_dn  LDAP_GROUP_SEARCH_BASEDN KS_LDAP_GROUP_SEARCH_BASEDN "Enter the LDAP GROUP SEARCH BASEDN"       ""    required
  prompt_dn  LDAP_READER_GROUP_DN   KS_LDAP_READER_GROUP_DN   "Enter the LDAP GROUP for reader role"         ""    required
  prompt_dn  LDAP_AUDITOR_GROUP_DN  KS_LDAP_AUDITOR_GROUP_DN  "Enter the LDAP GROUP for auditor role"        ""    required
  prompt_dn  LDAP_ADMIN_GROUP_DN    KS_LDAP_ADMIN_GROUP_DN    "Enter the LDAP GROUP for admin role"          ""    required
fi

# Domain & service names
prompt_var DOMAIN      KS_INSTALL_DOMAIN  "Enter the LCM root domain for the KeyStack" "demo.local"
prompt_var NEXUS_NAME  KS_NEXUS_NAME      "Enter the LCM Nexus domain name for the KeyStack" "nexus"
prompt_var GITLAB_NAME KS_GITLAB_NAME     "Enter the LCM Gitlab domain name for the KeyStack" "ks-lcm"
prompt_var VAULT_NAME  KS_VAULT_NAME      "Enter the LCM Vault domain name for the KeyStack"  "vault"
prompt_var NETBOX_NAME KS_NETBOX_NAME     "Enter the LCM Netbox domain name for the KeyStack" "netbox"

export DOMAIN NEXUS_NAME GITLAB_NAME VAULT_NAME NETBOX_NAME

# Self-signed certs (y/n)
prompt_yn SELF_SIG KS_SELF_SIG "Generate Self-signed certificates for KeyStack LCM services y/n" "y"
export SELF_SIG

## ask the user if everything is good
printf "\n"

# ------- output -------
echo "*** Provided settings: ***"
print_kv "Installer HOME"            INSTALL_HOME
print_kv "LCM IP"                    lcm_ip
print_kv "KeyStack LCM Root Domain"  DOMAIN
printf 'KeyStack LCM Nexus Domain: %s\n'   "$(fqdn_of NEXUS_NAME)"
printf 'KeyStack LCM Gitlab Domain: %s\n'  "$(fqdn_of GITLAB_NAME)"
printf 'KeyStack LCM Vault Domain: %s\n'   "$(fqdn_of VAULT_NAME)"
printf 'KeyStack LCM Netbox Domain: %s\n'  "$(fqdn_of NETBOX_NAME)"
print_kv "KeyStack generate Self-signed certificate" SELF_SIG

echo "-----------------Client artifactory-------------------"
print_kv "Use client artifactory" CLIENT_NEXUS
if [[ "$(getv CLIENT_NEXUS)" == "y" ]]; then
  printf 'Client Artifactory full domain name: %s\n' "$(fqdn_of CLIENT_NEXUS_NAME DOMAIN)"  # if you want FQDN; or use print_kv with CLIENT_NEXUS_NAME
  print_kv "Client Artifactory user name" CLIENT_NEXUS_ADMIN
  print_kv "Client Artifactory password"  CLIENT_NEXUS_PASSWORD secret
fi

echo "-----------------LDAP Configs-------------------------"
print_kv "Enable auth LDAP for Netbox and Gitlab" LDAP_USE
if [[ "$(getv LDAP_USE)" == "y" ]]; then
  print_kv "LDAP Server URI"              LDAP_SERVER_URI
  print_kv "LDAP Server Port"             LDAP_SERVER_PORT
  print_kv "LDAP BIND DN"                 LDAP_BIND_DN
  print_kv "LDAP BIND Password"           LDAP_BIND_PASSWORD secret
  print_kv "LDAP USER SEARCH BASEDN"      LDAP_USER_SEARCH_BASEDN
  print_kv "LDAP GROUP SEARCH BASEDN"     LDAP_GROUP_SEARCH_BASEDN
  print_kv "LDAP GROUP for reader role"   LDAP_READER_GROUP_DN
  print_kv "LDAP GROUP for auditor role"  LDAP_AUDITOR_GROUP_DN
  print_kv "LDAP GROUP for admin role"    LDAP_ADMIN_GROUP_DN
fi

# ---- confirm (skipped in silent/CI or when stdin not a TTY) ----
if ! is_true "${KS_INSTALL_SILENT-}" && [[ -t 0 ]]; then
  echo
  echo "Does it look good?"
  read -n1 -s -r -p "Press any key to continue or CTRL+C to break"
  echo
  echo "Awesome! Proceeding with the installation..."
  echo
fi

# ---- Nexus credentials ----
if [[ "${CLIENT_NEXUS-}" == "y" ]]; then
  # Require these when using a client/remote Nexus
  : "${CLIENT_NEXUS_NAME:?CLIENT_NEXUS_NAME is required when CLIENT_NEXUS=y}"
  : "${CLIENT_NEXUS_ADMIN:?CLIENT_NEXUS_ADMIN is required when CLIENT_NEXUS=y}"
  : "${CLIENT_NEXUS_PASSWORD:?CLIENT_NEXUS_PASSWORD is required when CLIENT_NEXUS=y}"

  NEXUS_FQDN="${CLIENT_NEXUS_NAME}"
  NEXUS_USER="${CLIENT_NEXUS_ADMIN}"
  NEXUS_PASSWORD="${CLIENT_NEXUS_PASSWORD}"
else
  # Local LCM Nexus defaults
  NEXUS_FQDN="${NEXUS_NAME}.${DOMAIN}"
  NEXUS_USER="${NEXUS_USER:-admin}"
  NEXUS_PASSWORD="${NEXUS_PASSWORD:-cdf9f167-f60e-4360-88d5-84e45fa02a99}"
fi

export NEXUS_FQDN NEXUS_USER NEXUS_PASSWORD

###########################
# * General preparation * #
###########################

INSTALL_DIR=$(pwd)

# --- normalize & derive first (safe for set -u) ---
RELEASE="${RELEASE:-}${BASE:+-$BASE}"

# If you collected 'lcm_ip' earlier in lower case, prefer it when LCM_IP is unset
LCM_IP="${LCM_IP:-${lcm_ip-}}"

INSTALL_DIR="${INSTALL_DIR:-$(pwd)}"
INSTALL_HOME="${INSTALL_HOME:-/installer}"

BACKUP_HOME="${BACKUP_HOME:-${INSTALL_HOME}/backup}"
UPDATE_HOME="${UPDATE_HOME:-${INSTALL_HOME}/update}"
CFG_HOME="${CFG_HOME:-${INSTALL_HOME}/config}"

CA_HOME="${CA_HOME:-${INSTALL_HOME}/data/ca}"
GITLAB_HOME="${GITLAB_HOME:-${INSTALL_HOME}/data/gitlab}"
GITLAB_RUNNER_HOME="${GITLAB_RUNNER_HOME:-${INSTALL_HOME}/data/gitlab-runner}"
NEXUS_HOME="${NEXUS_HOME:-${INSTALL_HOME}/data/nexus}"
VAULT_HOME="${VAULT_HOME:-${INSTALL_HOME}/data/vault}"
NGINX_HOME="${NGINX_HOME:-${INSTALL_HOME}/data/nginx}"
NETBOX_HOME="${NETBOX_HOME:-${INSTALL_HOME}/data/netbox}"

# Domains/names may be empty; set sane fallbacks if you want
DOMAIN="${DOMAIN:-demo.local}"
NEXUS_NAME="${NEXUS_NAME:-nexus}"
GITLAB_NAME="${GITLAB_NAME:-ks-lcm}"
VAULT_NAME="${VAULT_NAME:-vault}"
NETBOX_NAME="${NETBOX_NAME:-netbox}"

# Prefer explicit NEXUS_FQDN, else compose from name+domain
NEXUS_FQDN="${NEXUS_FQDN:-${NEXUS_NAME}.${DOMAIN}}"

SSL_CERT_FILE="${SSL_CERT_FILE:-${CA_HOME}/cert/chain-ca.pem}"
CURL_CA_BUNDLE="${CURL_CA_BUNDLE:-${CA_HOME}/cert/chain-ca.pem}"

export RELEASE LCM_IP DOMAIN GITLAB_NAME VAULT_NAME NETBOX_NAME NEXUS_NAME NEXUS_FQDN
export INSTALL_DIR INSTALL_HOME BACKUP_HOME UPDATE_HOME CFG_HOME
export CA_HOME GITLAB_HOME GITLAB_RUNNER_HOME NEXUS_HOME VAULT_HOME NGINX_HOME NETBOX_HOME
export SSL_CERT_FILE CURL_CA_BUNDLE

# ---- Run pre-checks ----
run_prechecks "${IGNORE_PRECHECKS:-0}"

# --- write settings safely ---
SETTINGS_FILE="./settings"
{
  echo "#!/usr/bin/env bash"
  echo "# Auto-generated settings file"
  echo "# Source it later:  source ./settings"
  echo

  printf 'export RELEASE=%q\n'             "$RELEASE"
  printf 'export LCM_IP=%q\n'              "$LCM_IP"
  printf 'export DOMAIN=%q\n'              "$DOMAIN"
  printf 'export GITLAB_NAME=%q\n'         "$GITLAB_NAME"
  printf 'export VAULT_NAME=%q\n'          "$VAULT_NAME"
  printf 'export NETBOX_NAME=%q\n'         "$NETBOX_NAME"
  printf 'export NEXUS_NAME=%q\n'          "$NEXUS_NAME"
  printf 'export NEXUS_FQDN=%q\n'          "$NEXUS_FQDN"
  printf 'export INSTALL_DIR=%q\n'         "$INSTALL_DIR"
  printf 'export BACKUP_HOME=%q\n'         "$BACKUP_HOME"
  printf 'export UPDATE_HOME=%q\n'         "$UPDATE_HOME"
  printf 'export INSTALL_HOME=%q\n'        "$INSTALL_HOME"
  printf 'export CFG_HOME=%q\n'            "$CFG_HOME"
  printf 'export CA_HOME=%q\n'             "$CA_HOME"
  printf 'export GITLAB_HOME=%q\n'         "$GITLAB_HOME"
  printf 'export GITLAB_RUNNER_HOME=%q\n'  "$GITLAB_RUNNER_HOME"
  printf 'export NEXUS_HOME=%q\n'          "$NEXUS_HOME"
  printf 'export VAULT_HOME=%q\n'          "$VAULT_HOME"
  printf 'export NGINX_HOME=%q\n'          "$NGINX_HOME"
  printf 'export NETBOX_HOME=%q\n'         "$NETBOX_HOME"
  printf 'export SSL_CERT_FILE=%q\n'       "$SSL_CERT_FILE"
  printf 'export CURL_CA_BUNDLE=%q\n'      "$CURL_CA_BUNDLE"
} > "$SETTINGS_FILE"
chmod 600 "$SETTINGS_FILE"

# --- source safely ---
# shellcheck disable=SC1090
source "$SETTINGS_FILE"

mkdir -p "$CFG_HOME" "$BACKUP_HOME" "$VAULT_HOME" "$NEXUS_HOME" "$NETBOX_HOME" "$UPDATE_HOME"
cp settings "$CFG_HOME"
cp version "$CFG_HOME"
cp compose.yaml "$CFG_HOME/"

####################
# * Certificates * #
####################
function gencrt() {
  cp cert.cnf "$CFG_HOME"
  openssl genrsa -out "$CA_HOME/root/ca.key" 2048
  chmod 400 "$CA_HOME/root/ca.key"
  openssl req -new -x509 -nodes -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=KeyStack Root CA" \
      -key "$CA_HOME/root/ca.key" -sha256 \
      -days 3650 -out "$CA_HOME/root/ca.crt"
  chmod 444 "$CA_HOME/root/ca.crt"
  cat "$CA_HOME/root/ca.crt" > "$CA_HOME/cert/chain-ca.pem"
  chmod 444 "$CA_HOME/cert/chain-ca.pem"
  for ca in "$NEXUS_NAME" "$GITLAB_NAME" "$VAULT_NAME" "$NETBOX_NAME"; do
    openssl genrsa -out "$CA_HOME/cert/$ca.key" 2048
    openssl req -new -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=$ca.$DOMAIN" \
        -key "$CA_HOME/cert/$ca.key" -out "$CA_HOME/cert/$ca.csr"
    export SAN=DNS:$ca.$DOMAIN
    openssl x509 -req -in "$CA_HOME/cert/$ca.csr" \
        -extfile "$CFG_HOME/cert.cnf" -CA "$CA_HOME/root/ca.crt" \
        -CAkey "$CA_HOME/root/ca.key" -CAcreateserial \
        -out "$CA_HOME/cert/$ca.crt" -days 728 -sha256
    cat "$CA_HOME/cert/$ca.crt" "$CA_HOME/root/ca.crt" > "$CA_HOME/cert/chain-$ca.pem"
  done
}

mkdir -p "$CA_HOME"/{root,cert}
if [[ $SELF_SIG == "y" ]]; then
  gencrt
else
  for ca in "$NEXUS_NAME" "$GITLAB_NAME" "$VAULT_NAME" "$NETBOX_NAME"; do
    [[ ! -f "certs/$ca.crt" ]] || [[ ! -f "certs/$ca.key" ]] && echo "Certificate or private key $ca.crt/$ca.key not found in certs" && exit 1
  done
  [[ ! -f certs/ca.crt ]] && echo "CA certificate ca.crt not found in certs" && exit 1
  for ca in "$NEXUS_NAME" "$GITLAB_NAME" "$VAULT_NAME" "$NETBOX_NAME"; do
    cp "certs/$ca.crt" "$CA_HOME/cert/$ca.crt"
    cp "certs/$ca.key" "$CA_HOME/cert/$ca.key"
    cat "certs/$ca.crt" certs/ca.crt > "$CA_HOME/cert/chain-$ca.pem"
  done
  cp certs/chain-ca.pem "$CA_HOME/cert/chain-ca.pem"
  cp certs/ca.crt "$CA_HOME/root/ca.crt"
  chmod 444 "$CA_HOME/root/ca.crt"
fi

# Copy certificates (already validated in pre-checks)
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp certs/"$NEXUS_FQDN.pem" "$CA_HOME/cert/$NEXUS_FQDN.pem"
fi

if [[ $LDAP_USE == "y" ]]; then
  cp certs/ldaps.pem "$CA_HOME/cert/ldaps.pem"
fi

#######################
# * GitLab & Runner * #
#######################

mkdir -p "$GITLAB_HOME"/{data,logs,config/trusted-certs}
mkdir -p "$GITLAB_RUNNER_HOME"/{certs,builds,cache}
cp "$CA_HOME/cert/chain-$GITLAB_NAME.pem" "$GITLAB_RUNNER_HOME/certs/$GITLAB_NAME.$DOMAIN.crt"
cp "$CA_HOME/cert/chain-ca.pem" "$GITLAB_RUNNER_HOME/certs/ca.crt"
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp "$CA_HOME/cert/$NEXUS_FQDN.pem" "$GITLAB_RUNNER_HOME/certs/$NEXUS_FQDN.crt"
fi
cp config-template.toml "$GITLAB_RUNNER_HOME"
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" "$GITLAB_RUNNER_HOME/config-template.toml"
sed -i "s/RELEASE/$RELEASE/g" "$GITLAB_RUNNER_HOME/config-template.toml"
sed -i "s|GITLAB_RUNNER_HOME|$GITLAB_RUNNER_HOME|g" "$GITLAB_RUNNER_HOME/config-template.toml"
openssl rand -base64 20 > "$CFG_HOME/gitlab_runner_token"
ssh-keygen -qt rsa -b 2048 -N "" -f "$CFG_HOME/gitlab_key" -C "root@gitlab"
if [[ $LDAP_USE == "y" ]]; then
  # Copy certificates
  cp certs/ldaps.pem "$GITLAB_HOME/config/trusted-certs/ldaps.pem"
  cat "certs/ldaps.pem" >> "$GITLAB_RUNNER_HOME/certs/ca.crt"

  # Use a portable delimiter (| can conflict if value has /)
  # Always escape sed-sensitive characters in replacement values
  sed -i "s|LDAP_USE|true|" "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-SERVER-URI|$(escape_sed "$LDAP_SERVER_URI")|" \
         "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-SERVER-PORT|$(escape_sed "$LDAP_SERVER_PORT")|" \
         "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-USER-SEARCH-BASEDN|$(escape_sed "$LDAP_USER_SEARCH_BASEDN")|" \
         "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-READER-GROUP-DN|$(escape_sed "$LDAP_READER_GROUP_DN")|" \
         "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-AUDITOR-GROUP-DN|$(escape_sed "$LDAP_AUDITOR_GROUP_DN")|" \
         "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-ADMIN-GROUP-DN|$(escape_sed "$LDAP_ADMIN_GROUP_DN")|" \
         "$CFG_HOME/compose.yaml"
  sed -i "s|LDAP-BIND-DN|$(escape_sed "$LDAP_BIND_DN")|" \
         "$CFG_HOME/compose.yaml"

  # Remove LDAP-BIND-DN & LDAP-BIND-PASSWORD if defined
  sed -i '/LDAP-BIND-DN/d;/LDAP-BIND-PASSWORD/d' "$CFG_HOME/compose.yaml"
else
  sed -i "s|LDAP_USE|false|" "$CFG_HOME/compose.yaml"
fi


##############
# * Netbox * #
##############
NETBOX_ENV_FILE="$NETBOX_HOME/env/netbox.env"
mkdir -p "$NETBOX_HOME"/{postgres,redis,redis-cache} "$NETBOX_HOME"/netbox/{configuration,media,reports,scripts}
chown -R 994:994 "$NETBOX_HOME"/{postgres,redis,redis-cache}
cp netbox-docker/docker-compose.yml "$CFG_HOME/netbox-compose.yml"
cp -r netbox-docker/env "$NETBOX_HOME" || exit_on_error "Failed to copy netbox-docker/env to $NETBOX_HOME"
cp -r netbox-docker/configuration "$NETBOX_HOME"/netbox

# Verify the env file was copied correctly
if [[ ! -f "$NETBOX_ENV_FILE" ]]; then
  exit_on_error "Netbox env file was not created at: $NETBOX_ENV_FILE"
fi

log_info "Reading Netbox configuration from $NETBOX_ENV_FILE"
netbox_admin_password=$(get_env_var "SUPERUSER_PASSWORD" "$NETBOX_ENV_FILE")
netbox_db_password=$(get_env_var "DB_PASSWORD" "$NETBOX_ENV_FILE")
netbox_redis_password=$(get_env_var "REDIS_PASSWORD" "$NETBOX_ENV_FILE")
netbox_redis_cache_password=$(get_env_var "REDIS_CACHE_PASSWORD" "$NETBOX_ENV_FILE")


########################
# * Sonatype Nexus 3 * #
########################
mkdir -p "$NEXUS_HOME"/{data,blobs,restore-from-backup}
mkdir -p /etc/docker/certs.d/"$NEXUS_FQDN"
if [[ $CLIENT_NEXUS == "y" ]]; then
  cp "$CA_HOME/cert/$NEXUS_FQDN.pem" /etc/docker/certs.d/"$NEXUS_FQDN"/"$NEXUS_FQDN".crt
  cat "$CA_HOME/cert/$NEXUS_FQDN.pem" >> "$CA_HOME/cert/chain-ca.pem"
else
  cp "$CA_HOME/cert/chain-ca.pem" /etc/docker/certs.d/"$NEXUS_FQDN"/ca.crt
fi
chown -R 200:200 "$NEXUS_HOME"

#######################
# * Hashicorp Vault * #
#######################
mkdir -p "$VAULT_HOME"/{config,file,logs}
cp vault.json "$VAULT_HOME/config"
cp policy_secret.hcl "$VAULT_HOME/config"
cp "$CA_HOME/cert/chain-ca.pem" "$VAULT_HOME/config"
if [[ $SELF_SIG == "y" ]]; then
  cat "$CA_HOME/root/ca.key" "$CA_HOME/root/ca.crt" > "$VAULT_HOME/config/root.pem"
else
  openssl genrsa -out /tmp/ca.key 2048
  chmod 400 /tmp/ca.key
  openssl req -new -x509 -nodes -subj "/C=RU/ST=Msk/L=Moscow/O=ITKey/OU=KeyStack/CN=KeyStack Root CA" \
      -key /tmp/ca.key -sha256 \
      -days 3650 -out /tmp/ca.crt
  chmod 444 /tmp/ca.crt
  cat /tmp/ca.key /tmp/ca.crt > "$VAULT_HOME/config/root.pem"
  rm -f /tmp/ca.*
fi

##########################
# * LCM not Internet * #
##########################
# download images and packages
if [ "$os" == "ubuntu" ] && [ -f "lcmpackages-$BASE.gz" ]; then
  echo "LCM packages exist => untar and install"
  tar -xf lcmpackages-"$BASE.gz"
  dpkg -i  packages/*.deb
fi

if [ "$os" == "sberlinux" ] && [ -f "lcmpackages-$BASE.gz" ]; then
  echo "LCM packages exist => untar and install"
  tar -xf lcmpackages-"$BASE.gz"
  yum install -y packages/*rpm
  systemctl enable docker
  systemctl start docker
fi

if [ -f "nexus-$RELEASE.tar" ]; then
  echo "Nexus image exist => loading"
  docker load -i nexus-"$RELEASE.tar"
  docker tag repo.itkey.com/project_k/lcm/nexus3:"$RELEASE" "$NEXUS_FQDN/project_k/lcm/nexus3":"$RELEASE"
fi

if [ -f "nginx-$RELEASE.tar" ]; then
  echo "Nginx image exist => loading"
  docker load -i nginx-"$RELEASE.tar"
  docker tag repo.itkey.com/project_k/lcm/nginx:"$RELEASE" "$NEXUS_FQDN/project_k/lcm/nginx":"$RELEASE"
fi

##########################
# * Offline Nexus data * #
##########################
if [ -f "keystack-$RELEASE-nexus-blob-offline.tar.gz" ]; then
    echo "keystack-$RELEASE-nexus-blob-offline.tar.gz exist"
    cp "keystack-$RELEASE-nexus-blob-offline.tar.gz" "$NEXUS_HOME/data/nexus-blob-offline.tar.gz"
  else
    echo "try to download keystack-$RELEASE-nexus-blob-offline.tar.gz"
    curl -L https://repo.itkey.com/repository/k-install/keystack-"$RELEASE"-nexus-blob-offline.tar.gz -o "$NEXUS_HOME/data/nexus-blob-offline.tar.gz"
fi

if [ -f "keystack-$RELEASE-nexus-db-offline.tar.gz" ]; then
    echo "keystack-$RELEASE-nexus-db-offline.tar.gz exist."
    cp "keystack-$RELEASE-nexus-db-offline.tar.gz" "$NEXUS_HOME/data/nexus-db-offline.tar.gz"
  else
    echo "try to download keystack-$RELEASE-nexus-db-offline.tar.gz"
    curl -L https://repo.itkey.com/repository/k-install/keystack-"$RELEASE"-nexus-db-offline.tar.gz -o "$NEXUS_HOME/data/nexus-db-offline.tar.gz"
fi

####################################
# SberLinux root cert installation #
####################################
[[ "$os" == "sberlinux" ]] && { cp "$CA_HOME/root/ca.crt"  /etc/pki/ca-trust/source/anchors/;  update-ca-trust; }

#################################
# Ubuntu root cert installation #
#################################
[[ "$os" == "ubuntu" ]] && { cp "$CA_HOME/root/ca.crt" /usr/local/share/ca-certificates; update-ca-certificates; }
################################

##################################
# add ssh authorized key for lcm #refactor this
echo -e "\n$(cat "$INSTALL_HOME/config/gitlab_key.pub")" >> /root/.ssh/authorized_keys
echo -e "$(cat "$INSTALL_HOME/config/gitlab_key")" > /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa

#####################
# * Configuration * #
#####################

# copy docker auth config
mkdir -p /root/.docker
cp docker_auth.json /root/.docker/config.json
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" /root/.docker/config.json
chmod 600 /root/.docker/config.json
if [[ $CLIENT_NEXUS == "y" ]]; then
  printf '%s' "$NEXUS_PASSWORD" | docker login "$NEXUS_FQDN" -u "$NEXUS_USER" --password-stdin
fi

# copy pip.conf
cp pip.conf /etc/pip.conf
sed -i "s/NEXUS_FQDN/$NEXUS_FQDN/g" /etc/pip.conf

# copy daemon.json
cp daemon.json /etc/docker/daemon.json

# Nginx settings
mkdir -p "$NGINX_HOME/conf.d/certs"
cp nginx.conf "$NGINX_HOME"
sed -i "s/DOMAIN/$DOMAIN/g" "$NGINX_HOME/nginx.conf"
sed -i "s/NEXUS_NAME/$NEXUS_NAME/g" "$NGINX_HOME/nginx.conf"
sed -i "s/GITLAB_NAME/$GITLAB_NAME/g" "$NGINX_HOME/nginx.conf"
sed -i "s/VAULT_NAME/$VAULT_NAME/g" "$NGINX_HOME/nginx.conf"
sed -i "s/NETBOX_NAME/$NETBOX_NAME/g" "$NGINX_HOME/nginx.conf"

for ca in "$NEXUS_NAME" "$GITLAB_NAME" "$VAULT_NAME" "$NETBOX_NAME"; do
  cp "$CA_HOME/cert/chain-$ca.pem" "$NGINX_HOME/conf.d/certs/chain-$ca.pem"
  cp "$CA_HOME/cert/$ca.key" "$NGINX_HOME/conf.d/certs/$ca.key"
done

# nexus configuration
echo "Unpacking the archive for Nexus. Please wait."
cd "$NEXUS_HOME"/blobs && sudo tar -xzf "$NEXUS_HOME/data/nexus-blob-offline.tar.gz" --checkpoint=10000 --checkpoint-action="ttyout=\b->"
cd "$NEXUS_HOME"/restore-from-backup && sudo tar -xzf "$NEXUS_HOME/data/nexus-db-offline.tar.gz"
cd "$INSTALL_DIR" && rm -rf "$NEXUS_HOME/data"
echo
chown -R 200:200 "$NEXUS_HOME"

$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml up -d nexus
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml up -d nginx

# Nexus: HTTP 200 at /service/rest/v1/status
wait_http_200 "https://${NEXUS_FQDN}/service/rest/v1/status" "Nexus"
rm -f "$NEXUS_HOME"/restore-from-backup/*

# Upload data to Nexus
upload_data_nexus() {
    local ARCHIVE="keystack-$RELEASE-nexus-data.tar.gz"
    check_file_exists "$ARCHIVE"
    log_info_block "Распаковка данных и их загрузка в Nexus"
    tar -xf "$ARCHIVE" --checkpoint=10000 --checkpoint-action="ttyout=\b->"
    echo
    function upload_files_to_nexus {
        local directory="$1"
        for file in "$directory"/*; do
            echo "Загрузка $file"
            case "${file##*.}" in
                "deb")
                    response=$(curl -ks -L -w "%{http_code}" -o /dev/null -u "$NEXUS_USER:$NEXUS_PASSWORD" -H "Content-Type: multipart/form-data" --data-binary "@./$file" "https://$NEXUS_FQDN/repository/$directory/")
                    ;;
                *)
                    ENCODED_FILENAME=$("$PYTHON_CMD" -c 'import urllib.parse; print(urllib.parse.quote("'"$file"'"))')
                    response=$(curl -ks -L -w "%{http_code}" -o /dev/null -u "$NEXUS_USER:$NEXUS_PASSWORD" --upload-file ./"$file" "https://$NEXUS_FQDN/repository/$ENCODED_FILENAME")
                    ;;
            esac
            if [[ "$response" =~ ^2 ]]; then
                log_info "$file успешно загружен"
            elif [[ "$response" = 400 ]]; then
                log_info "Файл $file уже есть в Nexus."
            else
                exit_on_error "Ошибка загрузки $file. HTTP Response: $response. Check Nexus server logs for details."
            fi
        done
    }
    cd nexus-"$BASE"
    for directory in *; do
        case $directory in
            "docker-$BASE")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "images")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "k-add")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "$BASE")
                upload_files_to_nexus "$directory" "https://$NEXUS_FQDN/repository"
                ;;
            "k-pip")
                export PYPI_SKIP_EXISTING=1        # mimic --skip-existing
                # optional:
                # export PARALLEL_UPLOADS=8
                # export CURL_INSECURE=1

                push_pypi_with_curl "k-pip" "$NEXUS_FQDN" "k-pip" "$NEXUS_USER" "$NEXUS_PASSWORD" || true

                ;;
            *)
                echo -e "\033[1;31mWARNING: \033[0m Неизвестная $directory, пропускаем..."
                ;;
        esac
    done
    cd -
}

upload_data_nexus

# Helpers assumed to exist:
# - check_file_exists <path>
# - log_info_block <msg>

# Tunables (optional env vars)
#   CONCURRENCY: parallel workers for xargs (default 4)
#   KEEP_NEXUS_REGEX: regex of Nexus images to KEEP after push (default '(lcm|kolla-ansible)')

upload_lcm_nexus() {
  local ARCHIVE="keystack-$RELEASE-lcm-images.tar"
  check_file_exists "$ARCHIVE"
  log_info_block "Загрузка образов LCM в Nexus (без docker load)."
  push_docker_archive_with_curl "$ARCHIVE" "$NEXUS_FQDN" "$NEXUS_USER" "$NEXUS_PASSWORD" "repo.itkey.com"
}

upload_lcm_nexus

# starting the services
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml up -d
##project_k netbox start
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/netbox-compose.yml up -d
# $DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml restart nginx

#Nexus images
upload_docker_nexus() {
  local ARCHIVE="keystack-$RELEASE-docker-images.tar"
  check_file_exists "$ARCHIVE"
  log_info_block "Загрузка Docker образов в Nexus (без docker load)."
  push_docker_archive_with_curl "$ARCHIVE" "$NEXUS_FQDN" "$NEXUS_USER" "$NEXUS_PASSWORD" "repo.itkey.com"
}

if [[ "$SKIP_DOCKER_UPLOAD" == "1" ]]; then
  log_info "Skipping upload_docker_nexus (--skip-docker-upload flag set)"
else
  upload_docker_nexus
fi

# Wait for GitLab to generate initial root password (max 5 minutes)
echo -n "⏳ Waiting for GitLab root password file"
timeout=300   # 5 minutes
interval=2
start=$(date +%s)

gitlab_root_password=""

while :; do
  gitlab_root_password=$(
    docker exec gitlab sh -c '[ -f /etc/gitlab/initial_root_password ] && grep "Password:" /etc/gitlab/initial_root_password' \
    | awk '{print $2}' 2>/dev/null || true
  )

  if [[ -n "$gitlab_root_password" ]]; then
    echo -e "\n✅ GitLab root password found"
    break
  fi

  printf .
  sleep "$interval"

  now=$(date +%s)
  (( now - start > timeout )) && {
    echo -e "\n❌ Timeout: GitLab root password file not found after $((timeout/60))m"
    exit 1
  }
done

# Vault unseal and add passwords, kv
# Ensure Vault container initialized only once
${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml exec -T vault sh -c '
  if [ ! -s /vault/config/unseal_info ]; then
    echo "[INFO] Vault not initialized, running operator init..."
    vault operator init -key-shares=1 -key-threshold=1 > /vault/config/unseal_info
  else
    echo "[INFO] Vault already initialized."
  fi
'

# Read keys safely (single values, trimmed)
Unseal_Key=$( ${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml exec -T vault \
  awk "/Unseal Key/ {print \$4; exit}" /vault/config/unseal_info | tr -d '\r\n')

Root_Token=$( ${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml exec -T vault \
  awk "/Initial Root/ {print \$4; exit}" /vault/config/unseal_info | tr -d '\r\n')

# Validate keys
if [[ -z "$Unseal_Key" || -z "$Root_Token" ]]; then
  echo "❌ Failed to parse Vault unseal or root token."
  ${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml exec -T vault cat /vault/config/unseal_info
  exit 1
fi

# Unseal Vault if needed
echo "[INFO] Unsealing Vault..."
${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml exec -T vault \
  vault operator unseal "$Unseal_Key" >/dev/null

# Login
echo "[INFO] Logging into Vault..."
${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml exec -T vault \
  vault login -no-print "$Root_Token" >/dev/null

# Copy keys locally for future reuse
mkdir -p "$VAULT_HOME/config"
${DOCKER_COMPOSE_COMMAND} -f "$CFG_HOME"/compose.yaml cp vault:/vault/config/unseal_info "$VAULT_HOME/config/unseal_info"

# Also export variables for later use
Unseal_Key=$(awk '/Unseal Key/ {print $4; exit}' "$VAULT_HOME/config/unseal_info")
Root_Token=$(awk '/Initial Root/ {print $4; exit}' "$VAULT_HOME/config/unseal_info")

echo "[INFO] Vault unsealed and ready."

# ssh routines (generate a key, create data for gitlab API, crate an ssh config and add server (fqdn & short name) to the known hosts
#[ ! -d "$HOME/.ssh" ] && { mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"; }
ssh_key="{\"title\":\"Autogenerated\",\"key\":\"$(<"$CFG_HOME"/gitlab_key.pub)\"}"
#cat <<END > "$HOME/.ssh/config"
cat <<END >> /etc/ssh/ssh_config
Host $GITLAB_NAME.$DOMAIN
  PreferredAuthentications publickey
  IdentityFile $CFG_HOME/gitlab_key
END
cat <<END >> /etc/ssh/ssh_config
Host $GITLAB_NAME
  PreferredAuthentications publickey
  IdentityFile $CFG_HOME/gitlab_key
END

ssh-keyscan -t rsa -p 2204 "$GITLAB_NAME.$DOMAIN" > "$CFG_HOME/gitlab_ssh_key"
echo "$(<"$CFG_HOME"/gitlab_ssh_key)" >> /etc/ssh/ssh_known_hosts
#echo $(<$CFG_HOME/gitlab_ssh_key) >> "$HOME/.ssh/known_hosts"
#ssh-keyscan -t rsa -p 2204 "$GITLAB_NAME.$DOMAIN" >> "$HOME/.ssh/known_hosts"

# GitLab readiness (expects JSON: {"status":"ok"})
wait_json_eq "https://${GITLAB_NAME}.${DOMAIN}/-/readiness" ".status" "ok" "GitLab"

# register & configure runner
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec gitlab-runner gitlab-runner register -n -r "$(<"$CFG_HOME"/gitlab_runner_token)" -u "https://$GITLAB_NAME.$DOMAIN" --template-config /etc/gitlab-runner/config-template.toml
sed -i "s/concurrent = 1/concurrent = 15/g" "$GITLAB_RUNNER_HOME/config.toml"

# configure Git
git config --system user.email "root@gitlab"
git config --system user.name "ITKey KeyStack"
git config --system --add safe.directory "*"

# get gitlab root user token & create a new group
pwd_data="{\"grant_type\":\"password\",\"username\":\"root\",\"password\":\"$gitlab_root_password\"}"
token=$(curl -sX POST -H "Content-Type: application/json" -d "$pwd_data" "https://$GITLAB_NAME.$DOMAIN/oauth/token"  | jq -r .access_token)

# add ssh key to gitlab (skip for root when LDAP is enabled, since root will be blocked)
if [[ $LDAP_USE != "y" ]]; then
  curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$ssh_key" "https://$GITLAB_NAME.$DOMAIN/api/v4/user/keys" | jq
fi

# default settings for Role model Keystack
if [[ $LDAP_USE == "y" ]]; then
  app_settings="{\"ci_delete_pipelines_in_seconds_limit_human_readable\":\"1 year\",\"default_artifacts_expire_in\":\"14 days\",\"first_day_of_week\":\"1\",\"session_expire_delay\":\"15\",\"suggest_pipeline_enabled\": false,\"whats_new_variant\":\"current_tier\",\"version_check_enabled\":false,\"user_show_add_ssh_key_message\": false,\"usage_ping_enabled\":false,\"update_runner_versions_enabled\":false,\"auto_devops_enabled\": false,\"archive_builds_in_human_readable\":\"1 month\",\"default_branch_protection_defaults\":{\"allowed_to_push\":[{\"access_level\":60}],\"allow_force_push\":false,\"allowed_to_merge\":[{\"access_level\":40}],\"developer_can_initial_push\":false}}"
  curl -sX PUT -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$app_settings"  "https://$GITLAB_NAME.$DOMAIN/api/v4/application/settings" | jq
fi

#add group project_k, subgroups services and deployments
grp_data_project_k="{\"name\":\"project_k\",\"path\":\"project_k\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
group_id_project_k=$(curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$grp_data_project_k" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups" | jq -r .id)
grp_data_deployments="{\"name\":\"deployments\",\"parent_id\":\"${group_id_project_k}\",\"path\":\"deployments\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
group_id_deployments=$(curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$grp_data_deployments" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups" | jq -r .id)
grp_data_services="{\"name\":\"services\",\"parent_id\":\"${group_id_project_k}\",\"path\":\"services\",\"visibility\":\"internal\",\"auto_devops_enabled\":\"false\"}"
group_id_services=$(curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" -d "$grp_data_services" "https://$GITLAB_NAME.$DOMAIN/api/v4/groups" | jq -r .id)

$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault auth enable approle"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault secrets enable -path=secret_v2 -version 2 kv"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault policy write secret_v2/deployments /vault/config/policy_secret.hcl"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault write auth/approle/role/keystack token_type=batch token_policies=secret_v2/deployments"
role_id=$($DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault read -field=role_id auth/approle/role/keystack/role-id")
secret_id=$($DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault write -f -field=secret_id auth/approle/role/keystack/secret-id")

$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/secrets/job_key value=\"$(<"$CFG_HOME"/gitlab_key)\""
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/secrets/ca.crt value=\"$(<"$CA_HOME"/cert/chain-ca.pem)\""
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c \
  "vault kv put -mount=secret_v2 deployments/$GITLAB_NAME.$DOMAIN/bifrost/rmi user=\"sundog\" password=\"dogsun\""
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault secrets enable -path installer pki"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault secrets tune -max-lease-ttl=43800h installer"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault write installer/config/ca pem_bundle=@vault/config/root.pem"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault write installer/roles/certs allowed_domains=\"$DOMAIN\" allow_subdomains=true max_ttl=17520h ttl=17520h"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml exec vault /bin/sh -c "vault write installer/config/urls issuing_certificates=\"https://$VAULT_NAME.$DOMAIN/v1/pki/ca\"  crl_distribution_points=\"https://$VAULT_NAME.$DOMAIN/v1/pki/crl\""
rm -f "$VAULT_HOME/config/root.pem"

# Hardening helpers
if [[ $LDAP_USE == "y" ]]; then
  # ---- NetBox .env + extra.py ----
  nb_env="$NETBOX_HOME/env/netbox.env"
  nb_extra_py="$NETBOX_HOME/netbox/configuration/ldap/extra.py"

  replace_in_file "LDAP-SERVER-URI"              "$LDAP_SERVER_URI"           "$nb_env"
  replace_in_file "LDAP-SERVER-PORT"             "$LDAP_SERVER_PORT"          "$nb_env"
  replace_in_file "LDAP-BIND-DN"                 "$LDAP_BIND_DN"              "$nb_env"
  replace_in_file "LDAP-BIND-PASSWORD"           "$LDAP_BIND_PASSWORD"        "$nb_env"
  replace_in_file "LDAP-USER-SEARCH-BASEDN"      "$LDAP_USER_SEARCH_BASEDN"   "$nb_env"
  replace_in_file "LDAP-GROUP-SEARCH-BASEDN"     "$LDAP_GROUP_SEARCH_BASEDN"  "$nb_env"

  replace_in_file "LDAP-READER-GROUP-DN"         "$LDAP_READER_GROUP_DN"      "$nb_extra_py"
  replace_in_file "LDAP-AUDITOR-GROUP-DN"        "$LDAP_AUDITOR_GROUP_DN"     "$nb_extra_py"
  replace_in_file "LDAP-ADMIN-GROUP-DN"          "$LDAP_ADMIN_GROUP_DN"       "$nb_extra_py"

  # Certs
  cp "certs/ldaps.pem" "$NETBOX_HOME/netbox/configuration/ldaps.pem"

  # Bring NetBox up
  $DOCKER_COMPOSE_COMMAND -f "$CFG_HOME/netbox-compose.yml" up -d
fi

target_group="{\"target_group_id\":\"$group_id_project_k\"}"
# Загрузка репозиториев в Gitlab
while IFS="=" read -r repo _branch; do
    cd "$INSTALL_DIR/project_k/$repo" || exit
    while [ "$(curl -s https://"$GITLAB_NAME"."$DOMAIN"/-/readiness | jq -r .status)"  != "ok" ]; do sleep 1; done
    # If any remote named 'origin' exists — remove it
    if git remote get-url origin >/dev/null 2>&1; then
      echo "⚠️  Existing remote 'origin' found, removing..."
      git remote remove origin || git remote rm origin || true
    fi
    git remote add origin "https://git:${token}@$GITLAB_NAME.$DOMAIN/project_k/${repo}.git" || true
    git add .
    git commit -m "Add installer" || [[ $? -eq 1 ]]
    log_info "Загрузка репозитория $repo в GitLab..."
    git push -u origin --all -o ci.skip
    git push -u origin --tags -o ci.skip
    git remote remove origin
    name=$(basename "$repo")
    gitlab_project_id=$(curl -ks -L -H "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects?search=${name}&simple=true" | jq -r '.[0].id')
    curl -ks -L -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/job_token_scope/groups_allowlist" -d "$target_group"
    if [[ $LDAP_USE == "y" ]]; then
      curl -X PUT -H "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id" \
      -d "only_allow_merge_if_pipeline_succeeds=true" \
      -d "only_allow_merge_if_all_discussions_are_resolved=true" \
      -d "container_registry_access_level=disabled" \
      -d "monitor_access_level=disabled" \
      -d "wiki_access_level=disabled" \
      -d "security_and_compliance_access_level=disabled" \
      -d "releases_access_level=disabled" \
      -d "model_registry_access_level=disabled" \
      -d "feature_flags_access_level=disabled" \
      -d "snippets_access_level=disabled" \
      -d "model_experiments_access_level=disabled" \
      -d "analytics_access_level=disabled" \
      -d "issues_access_level=disabled" \
      -d "forking_access_level=disabled" \
      -d "environments_access_level=disabled"
      if [[ $name == "region1" ]]; then
        curl -X PUT -H "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id" \
        -d "forking_access_level=enabled"
      fi
      if [[ $name == "ci" || $name == "keystack" ]]; then
        curl -X PUT -H "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id" \
        -d "builds_access_level=disabled" \
        -d "merge_requests_access_level=disabled"
      fi
      if [[ $name == "gitlab-ldap-sync" ]]; then
        curl -X POST -H "Authorization: Bearer $token" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -F "key=LDAP_URL" -F "value=ldaps://${LDAP_SERVER_URI}:${LDAP_SERVER_PORT}"
        curl -X POST -H "Authorization: Bearer $token" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -F "key=LDAP_DN" -F "value=${LDAP_BIND_DN}"
        curl -X POST -H "Authorization: Bearer $token" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -F "key=LDAP_BASE_DN" -F "value=${LDAP_USER_SEARCH_BASEDN}"
        curl -X POST -H "Authorization: Bearer $token" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -F "key=LDAP_GROUP_BASE_DN" -F "value=${LDAP_GROUP_SEARCH_BASEDN}"
        curl -X POST -H "Authorization: Bearer $token" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -F "key=GITLAB_MAINTENANCE_LDAP_GROUP" -F "value=${LDAP_ADMIN_GROUP_DN}"
        LDAP_USER_FILTER="(|(memberof=$LDAP_ADMIN_GROUP_DN)(memberof=$LDAP_AUDITOR_GROUP_DN)(memberof=$LDAP_READER_GROUP_DN))"
        curl -X POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -d "{\"key\":\"LDAP_USER_FILTER\",\"value\":\"${LDAP_USER_FILTER}\"}"
        GITLAB_GROUPS="[{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_AUDITOR_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k\", \"ldap\": \"$LDAP_READER_GROUP_DN\", \"perms\": 20},{\"gitlab\": \"project_k/deployments\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 40},{\"gitlab\": \"project_k/services\", \"ldap\": \"$LDAP_ADMIN_GROUP_DN\", \"perms\": 20}]"
        curl -X POST -H "Authorization: Bearer $token" \
        "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$gitlab_project_id/variables" \
        -F "key=GITLAB_GROUPS" -F "value=${GITLAB_GROUPS}"
      fi
    fi
done < "./keystack"

# Prereqs expected in env:
#   token, GITLAB_NAME, DOMAIN, group_id_project_k
#   NEXUS_USER, NEXUS_FQDN, NETBOX_NAME, LCM_IP, INSTALL_HOME, BASE
#   VAULT_NAME, role_id, secret_id, LDAP_USE
# NOTE: CI_REGISTRY is intentionally set to literal "$KEYSTACK_REGISTRY" (runtime expansion).

gitlab_base="https://${GITLAB_NAME}.${DOMAIN}/api/v4"
hdr=(-H "Authorization: Bearer ${token}")
curl_opts=(-sS --retry 3 --retry-connrefused --max-time 20)

upsert_var() {
  # Usage: upsert_var group|admin KEY VALUE [extra -F args...]
  local scope="$1"; shift
  local key="$1"; shift
  local value="$1"; shift
  local url
  if [[ "$scope" == "group" ]]; then
    url="${gitlab_base}/groups/${group_id_project_k}/variables"
  else
    url="${gitlab_base}/admin/ci/variables"
  fi

  # Try update (PUT). If 404, do create (POST).
  local http
  http=$(curl "${curl_opts[@]}" "${hdr[@]}" \
      -o /dev/null -w "%{http_code}" \
      -X PUT -F "key=${key}" --form-string "value=${value}" "$@" \
      "${url}/${key}" || true)

  if [[ "$http" == "200" ]]; then
    echo "Updated ${scope} variable: ${key}"
    return 0
  fi

  http=$(curl "${curl_opts[@]}" "${hdr[@]}" \
      -o /dev/null -w "%{http_code}" \
      -X POST -F "key=${key}" --form-string "value=${value}" "$@" \
      "${url}" || true)

  if [[ "$http" == "201" || "$http" == "200" ]]; then
    echo "Created ${scope} variable: ${key}"
  else
    echo "ERROR ${scope} variable ${key}: HTTP ${http}" >&2
    exit 1
  fi
}

# -------- group: project_k variables --------
upsert_var group GIT_SSL_NO_VERIFY         "true"
upsert_var group KEYSTACK_REGISTRY_USER    "${NEXUS_USER}"
upsert_var group KEYSTACK_REGISTRY         "${NEXUS_FQDN}"
upsert_var group NETBOX_URI                "https://${NETBOX_NAME}.${DOMAIN}"
# literal reference so jobs can expand it at runtime
upsert_var group CI_REGISTRY               "\$KEYSTACK_REGISTRY"
upsert_var group NEXUS_FQDN                "${NEXUS_FQDN}"
upsert_var group KEYSTACK_NEXUS            "https://${NEXUS_FQDN}"
upsert_var group NEXUS_USER                "${NEXUS_USER}"
upsert_var group LCM_IP                    "${LCM_IP}"
upsert_var group DOMAIN                    "${DOMAIN}"
upsert_var group INSTALL_HOME              "${INSTALL_HOME}"
upsert_var group BASE                      "${BASE}"

# -------- admin-level CI defaults --------
upsert_var admin ANSIBLE_FORCE_COLOR       "true"
if [[ "${LDAP_USE:-n}" == "y" ]]; then
  upsert_var admin MERGE_REQUEST_APPROVE   "true"
else
  upsert_var admin MERGE_REQUEST_APPROVE   "false"
fi

# -------- Vault configuration (group) --------
upsert_var group vault_addr        "https://${VAULT_NAME}.${DOMAIN}"
upsert_var group vault_engine      "secret_v2"
upsert_var group vault_method      "approle"
upsert_var group vault_username    "${role_id}"   -F "masked=true"
upsert_var group vault_password    "${secret_id}" -F "masked=true"
upsert_var group vault_prefix      "deployments/${GITLAB_NAME}.${DOMAIN}"
upsert_var group vault_role        "keystack"
upsert_var group vault_pki         "installer"
upsert_var group vault_role_pki    "certs"
upsert_var group vault_secman      "false"

function add_ks_admin_to_groups() {
  local user_id=$1
  # Add ks-admin to project_k group and all subgroups as Owner
  for group_id in "$group_id_project_k" "$group_id_deployments" "$group_id_services"; do
    member_result=$(curl -s -X POST -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "{\"user_id\":\"$user_id\",\"access_level\":50}" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/groups/$group_id/members")

    member_id=$(echo "$member_result" | jq -r '.id // empty')
    if [ -n "$member_id" ]; then
      echo "ks-admin added to group $group_id successfully"
    else
      echo "Warning: Could not add ks-admin to group $group_id: $(echo "$member_result" | jq -r '.message // "Unknown error"')"
    fi
  done
}

function create_ks_admin_user() {
  ks_admin_password=$(openssl rand -hex 16)

  # Check if user already exists via API
  existing_user=$(curl -s -H "Authorization: Bearer $token" "https://$GITLAB_NAME.$DOMAIN/api/v4/users?username=ks-admin" | jq -r '.[0].id // empty')

  if [ -n "$existing_user" ]; then
    # Update existing user password
    curl -s -X PUT -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "{\"password\":\"$ks_admin_password\"}" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/users/$existing_user"
    curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
      -d "$ssh_key" "https://$GITLAB_NAME.$DOMAIN/api/v4/users/$existing_user/keys" | jq
    add_ks_admin_to_groups "$existing_user"
    echo "User ks-admin password updated"
  else
    # Create new user via API
    user_data="{\"name\":\"KS Admin\",\"username\":\"ks-admin\",\"email\":\"ks-admin@example.com\",\"password\":\"$ks_admin_password\",\"admin\":true,\"skip_confirmation\":true}"
    create_result=$(curl -s -X POST -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$user_data" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/users")

    user_id=$(echo "$create_result" | jq -r '.id // empty')
    if [ -n "$user_id" ]; then
      curl -sX POST -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
        -d "$ssh_key" "https://$GITLAB_NAME.$DOMAIN/api/v4/users/$user_id/keys" | jq
      echo "User ks-admin created successfully"
      add_ks_admin_to_groups "$user_id"
    else
      echo "Error creating user ks-admin: $(echo "$create_result" | jq -r '.message // "Unknown error"')"
      exit 1
    fi
  fi
}

create_ks_admin_user

if [[ "$LDAP_USE" == "y" ]]; then

# Generate/replace PAT for ks-admin inside GitLab (capture ONLY the token)
  PAT="$(
    $DOCKER_COMPOSE_COMMAND -f "$CFG_HOME/compose.yaml" exec -T gitlab bash -lc 'set -euo pipefail; gitlab-rails runner -' <<'RUBY'
require "securerandom"

# --- Harden a couple of app settings (stderr logs) ---
begin
  settings = ApplicationSetting.current || ApplicationSetting.last || ApplicationSetting.create!
  settings.update!(signup_enabled: false, remember_me_enabled: false)
  warn "Application settings updated: signup_disabled=true, remember_me=false"
rescue => e
  warn "Failed to update application settings: #{e.class}: #{e.message}"
end

# --- Block root user (stderr logs) ---
begin
  if (root_user = User.find_by(username: "root"))
    root_user.update!(state: "blocked")
    warn "Root user has been disabled successfully"
  else
    warn "Root user not found"
  end
rescue => e
  warn "Failed to disable root user: #{e.class}: #{e.message}"
end

# --- Create/replace PAT for ks-admin and print ONLY the token to STDOUT ---
u = User.find_by!(username: "ks-admin")

if (t = u.personal_access_tokens.find_by(name: "PAT"))
  t.destroy
end

plain = SecureRandom.hex(20)
t = u.personal_access_tokens.build(
  name: "PAT",
  scopes: %w[api sudo],
  expires_at: Time.current + 1.year
)
t.set_token(plain)
t.save!

puts plain
RUBY
)"

  if [[ -z "${PAT:-}" ]]; then
    echo "❌ PAT creation error: empty output from gitlab-rails runner" >&2
    exit 1
  fi
  echo "✅ PAT issued for ks-admin"

  echo "[INFO] Writing LDAP bind secret..."
  $DOCKER_COMPOSE_COMMAND -f "$CFG_HOME/compose.yaml" exec -T gitlab /bin/bash -c "
cat <<'EOF' | gitlab-rake gitlab:ldap:secret:write
main:
  password: '$LDAP_BIND_PASSWORD'
  bind_dn: '$LDAP_BIND_DN'
EOF
"
$DOCKER_COMPOSE_COMMAND -f "$CFG_HOME"/compose.yaml restart gitlab
wait_json_eq "https://${GITLAB_NAME}.${DOMAIN}/-/readiness" ".status" "ok" "GitLab"
else
  # When LDAP is not enabled, use the root token
  PAT="$token"
fi

# remove unneeded env variables
unset SAN

# Build the KV path on the host
VAULT_PATH="deployments/${GITLAB_NAME}.${DOMAIN}/secrets/accounts"

# Read runner token from file on the host
GITLAB_RUNNER_TOKEN_CONTENT="$(<"$CFG_HOME/gitlab_runner_token")"

# NetBox API root: HTTP 200 (extend timeout if you like)
wait_http_200 "https://${NETBOX_NAME}.${DOMAIN}/api/" "NetBox" 1200

#get token for netbox - run netbox before it
netbox_pwd="{\"username\":\"admin\",\"password\":\"$netbox_admin_password\"}"
netbox_token=$(curl -sX POST -H "Content-Type: application/json" "https://$NETBOX_NAME.$DOMAIN/api/users/tokens/provision/" --data "$netbox_pwd" | jq -r .key)

# Create JSON safely with jq (handles all escaping), pipe to vault inside the container
# shellcheck disable=SC2016
jq -n \
  --arg gitlab_root_password         "$gitlab_root_password" \
  --arg gitlab_ks_admin_password     "$ks_admin_password" \
  --arg gitlab_runner_token          "$GITLAB_RUNNER_TOKEN_CONTENT" \
  --arg nexus_admin_password         "$NEXUS_PASSWORD" \
  --arg netbox_admin_password        "$netbox_admin_password" \
  --arg netbox_db_password           "$netbox_db_password" \
  --arg netbox_redis_password        "$netbox_redis_password" \
  --arg netbox_redis_cache_password  "$netbox_redis_cache_password" \
  --arg NETBOX_TOKEN                 "$netbox_token" \
  --arg GITLAB_TOKEN                 "$PAT" \
  --arg LDAP_PASSWORD                "${LDAP_BIND_PASSWORD:-}" \
  --argjson ldap_enabled             "$([[ "$LDAP_USE" == "y" ]] && echo true || echo false)" \
  '{
    gitlab_root_password:         $gitlab_root_password,
    gitlab_ks_admin_password:     $gitlab_ks_admin_password,
    gitlab_runner_token:          $gitlab_runner_token,
    nexus_admin_password:         $nexus_admin_password,
    netbox_admin_password:        $netbox_admin_password,
    netbox_db_password:           $netbox_db_password,
    netbox_redis_password:        $netbox_redis_password,
    netbox_redis_cache_password:  $netbox_redis_cache_password,
    NETBOX_TOKEN:                 $NETBOX_TOKEN,
    GITLAB_TOKEN:                 $GITLAB_TOKEN
  } | if $ldap_enabled then . + {LDAP_PASSWORD: $LDAP_PASSWORD} else . end' \
| $DOCKER_COMPOSE_COMMAND -f "$CFG_HOME/compose.yaml" exec -T \
    -e VAULT_P="$VAULT_PATH" \
    vault /bin/sh -c 'vault kv put -mount=secret_v2 "$VAULT_P" @/dev/stdin'

if [[ $LDAP_USE == "y" ]]; then
  function get_project_id() {
    PROJECT_ID=$(curl -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects" | jq ".[] | select(.name == \"gitlab-ldap-sync\") | .id")
    if [ -z "$PROJECT_ID" ]; then
      echo "Project services/gitlab-ldap-sync not found" && exit 1
    fi
  }

  get_project_id

  function create_schedule_ldap() {
    local existing_schedule
    existing_schedule=$(curl -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every day at 12AM\") | .id")
    if [ -n "$existing_schedule" ]; then
      curl -ks -X DELETE -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule"
    fi
    local schedule_id
    schedule_id=$(curl -ks -X POST -H "PRIVATE-TOKEN: $PAT" \
      --form description="Sync every day at 12AM" \
      --form ref="master" \
      --form cron="0 0 * * *" \
      --form cron_timezone="UTC" \
      --form active="true" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq .id)
    curl -ks -X POST -H "PRIVATE-TOKEN:  $PAT" --form "key=ldap" --form "value=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$schedule_id/variables"
  }

  function create_schedule_gitlab() {
    local existing_schedule
    existing_schedule=$(curl -ks -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq -r ".[] | select(.description == \"Sync every 10 minute\") | .id")
    if [ -n "$existing_schedule" ]; then
      curl -ks -X DELETE -H "PRIVATE-TOKEN: $PAT" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$existing_schedule"
    fi
    local schedule_id
    schedule_id=$(curl -ks -X POST -H "PRIVATE-TOKEN: $PAT" \
      --form description="Sync every 10 minute" \
      --form ref="master" \
      --form cron="/10 * * * *" \
      --form cron_timezone="UTC" \
      --form active="true" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules" | jq .id)
    curl -ks -X POST -H "PRIVATE-TOKEN:  $PAT" --form "key=gitlab" --form "value=true" "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/pipeline_schedules/$schedule_id/variables"
  }

  create_schedule_ldap
  create_schedule_gitlab

  trigger_pipeline() {
    local existing_trigger
    existing_trigger=$(curl -ks -H "PRIVATE-TOKEN: $PAT" \
      "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/triggers" | jq -r '.[] | select(.description == "Automated Trigger") | .token')
    if [ -z "$existing_trigger" ]; then
      existing_trigger=$(curl --silent --request POST "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/triggers" \
        --header "PRIVATE-TOKEN: $PAT" \
        --form description="Automated Trigger" | jq -r '.token')
    fi
    curl -ks -X POST "https://$GITLAB_NAME.$DOMAIN/api/v4/projects/$PROJECT_ID/trigger/pipeline" \
      --form token="$existing_trigger" \
      --form ref="master"
  }

  trigger_pipeline
fi

upload_netbox() {
    NETBOX_API_URL="https://$NETBOX_NAME.$DOMAIN/api/"
    log_info_block "Загрузка данных в Netbox"
    upload_data_netbox
}

curl_netbox() {
    local data_file=$1
    local endpoint=$2

    check_file_exists "$data_file"
    local data_json
    data_json=$(cat "$data_file")

    echo "Загрузка файла $data_file в $NETBOX_API_URL$endpoint/"

    response=$(curl -ks -L -X POST "${NETBOX_API_URL}${endpoint}/" \
        -H "Authorization: Token $netbox_token" \
        -H "Content-Type: application/json" \
        -d "$data_json" \
        --connect-timeout 10)

    # Проверка на успешность загрузки
    if [[ -z "$response" ]]; then
        exit_on_error "Error: Нет ответа от NetBox. Проверьте конечную точку API или данные."
    fi

    # Проверка формата ответа (массив или объект)
    if [[ $(echo "$response" | jq -e 'type == "array"') ]]; then
        # Обработка случая, когда в ответе массив
        if [[ "$(echo "$response" | jq length)" -gt 0 ]]; then
            echo "Success: Данные загружены в ${endpoint} из ${data_file}."
        else
            echo "Success: Данные загружены в ${endpoint}, but response is an empty array."
        fi
    elif [[ $(echo "$response" | jq -e 'type == "object"') ]]; then
        # Обработка случая, когда в ответе объект
        error_message=$(echo "$response" | jq -r '.detail // empty')
        if [[ -n "$error_message" ]]; then
            echo "Error: $error_message"
        else
            id=$(echo "$response" | jq -r '.id // empty')
            if [[ -n "$id" ]]; then
                echo "Success: Данные загружены в ${endpoint} из ${data_file} с ID $id."
            else
                echo "Success: Данные загружены в ${endpoint}, но не вернули ID."
            fi
        fi
    else
        echo "Error: Неожиданный формат ответа: $response"
    fi
}

upload_data_netbox() {
    cd "${INSTALL_DIR}"
    # Массив json файлов
    declare -a endpoints_and_files=(
        "tenancy/tenants netbox_jsons/tenants.json"
        "extras/tags netbox_jsons/tags.json"
        "dcim/site-groups netbox_jsons/site_groups.json"
        "dcim/regions netbox_jsons/regions.json"
        "dcim/manufacturers netbox_jsons/device_manufacturers.json"
        "dcim/device-types netbox_jsons/device_types.json"
        "dcim/device-roles netbox_jsons/device_roles.json"
        "dcim/sites netbox_jsons/sites.json"
        "extras/custom-field-choice-sets netbox_jsons/custom_fields_choice_sets.json"
        "extras/custom-fields netbox_jsons/custom_fields.json"
        "dcim/devices netbox_jsons/devices.json"
        "ipam/vlans netbox_jsons/vlans.json"
        "ipam/prefixes netbox_jsons/prefixes.json"
        "dcim/interfaces netbox_jsons/interfaces_bond.json"
        "dcim/interfaces netbox_jsons/interfaces.json"
        "ipam/ip-addresses netbox_jsons/ip_addresses.json"
        "extras/config-contexts netbox_jsons/config_contexts.json"
        "users/permissions netbox_jsons/permissions.json"
    )

    for entry in "${endpoints_and_files[@]}"; do
        endpoint=$(echo "$entry" | awk '{print $1}')
        file=$(echo "$entry" | awk '{print $2}')
        curl_netbox "$file" "$endpoint"
    done
}

upload_netbox

printf "\n\n\n############################################################\n"
echo "#                YOUR INSTALLATION IS READY                #"
printf "############################################################\n\n\n"

echo "LCM GitLab root password: $gitlab_root_password"
echo "LCM GitLab ks-admin password: $ks_admin_password"
echo "LCM GitLab runner token: $(<"$CFG_HOME"/gitlab_runner_token)"
echo "LCM GitLab SSH private key: $CFG_HOME/gitlab_key"
echo "LCM GitLab SSH public key: $CFG_HOME/gitlab_key.pub"
echo "LCM Nexus admin password: $NEXUS_PASSWORD"
echo "LCM Netbox admin password: $netbox_admin_password"
echo "LCM Netbox postgres password: $netbox_db_password"
echo "LCM Netbox redis password: $netbox_redis_password"
echo "LCM Netbox redis cache password: $netbox_redis_cache_password"
echo "LCM Vault Initial Root Token: $Root_Token"
echo "LCM Vault Unseal Key 1: $Unseal_Key"
echo "LCM Root CA Certificate: $CA_HOME/cert/chain-ca.pem"
echo ""
echo "Service URLs:"
echo "  GitLab:  https://${GITLAB_NAME}.${DOMAIN}"
echo "  Vault:   https://${VAULT_NAME}.${DOMAIN}"
echo "  Nexus:   https://${NEXUS_NAME}.${DOMAIN}"
echo "  Netbox:  https://${NETBOX_NAME}.${DOMAIN}"

rm -f "$VAULT_HOME/config/unseal_info"
rm -f "$VAULT_HOME/config/root.pem"
rm -f "$GITLAB_HOME/config/initial_root_password"
echo "" > "$INSTALL_DIR/netbox-docker/env/postgres.env"
echo "" > "$INSTALL_DIR/netbox-docker/env/redis-cache.env"
echo "" > "$INSTALL_DIR/netbox-docker/env/netbox.env"
echo "" > "$INSTALL_DIR/netbox-docker/env/redis.env"

# If you want to scrub it, empty the file (or remove it). Otherwise leave it.
: > "$CFG_HOME/gitlab_runner_token"
sed -i "s|DB_PASSWORD=.*|DB_PASSWORD=netbox_db_password|" "$NETBOX_HOME/env/netbox.env"
sed -i "s|REDIS_CACHE_PASSWORD=.*|REDIS_CACHE_PASSWORD=netbox_redis_cache_password|" "$NETBOX_HOME/env/netbox.env"
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=netbox_redis_password|" "$NETBOX_HOME/env/netbox.env"
sed -i "s|SUPERUSER_PASSWORD=.*|SUPERUSER_PASSWORD=netbox_admin_password|" "$NETBOX_HOME/env/netbox.env"
sed -i "s|AUTH_LDAP_BIND_PASSWORD: .*|AUTH_LDAP_BIND_PASSWORD: \"LDAP-BIND-PASSWORD\"|" "$NETBOX_HOME/env/netbox.env"
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=netbox_db_password|" "$NETBOX_HOME/env/postgres.env"
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=netbox_redis_password|" "$NETBOX_HOME/env/redis.env"
sed -i "s|REDIS_PASSWORD=.*|REDIS_PASSWORD=netbox_redis_cache_password|" "$NETBOX_HOME/env/redis-cache.env"
