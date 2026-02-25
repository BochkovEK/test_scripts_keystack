#!/usr/bin/env bash

set -u

echo "Looking for failed/inactive/dead units containing 'health'..."

ids=$(sudo systemctl list-units --all --state=failed,inactive,dead \
      | grep -i health \
      | sed -E 's/^([a-zA-Z0-9]+)-.*$/\1/' \
      | sort -u)

if [[ -z "$ids" ]]; then
    echo "Nothing found."
    exit 0
fi

echo
echo "Found IDs:"
printf '%s\n' "$ids"
echo

read -p "Stop, disable and reset-failed all matching units? (y/N): " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

for id in $ids; do
    echo "----------------------------------------"
    echo "Processing ID: $id"

    echo "→ Stopping services/timers..."
    sudo systemctl stop "${id}"-*.service "${id}"-*.timer 2>/dev/null || true

    echo "→ Disabling services/timers..."
    sudo systemctl disable --now "${id}"-*.service "${id}"-*.timer 2>/dev/null || true

    echo "→ Resetting failed state..."
    sudo systemctl reset-failed "${id}"-* 2>/dev/null || true

    echo "Done with $id"
done

echo
echo "All operations completed."