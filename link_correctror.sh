# The script for correct link from nexus web portal
# To get link from nexus:
# 1) Go nexus web portal repo
# 2) Select image
# 3) Summary -> Path -> RCM Copy link address
# To start: bash link_corrector.sh <link_from_nexus_web_portal>

[ -z $1 ] && { echo "To run the script, you need to pass a link to as an argument"; exit 1; }

sed -e "s#%2#/#g" $1 | cat -