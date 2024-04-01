# The script for correct link from nexus web portal and upload file from link to $HOME dir
# To get link from nexus:
# 1) Go nexus web portal repo
# 2) Select image
# 3) Summary -> Path -> RCM Copy link address
# To start: bash link_corrector.sh <link_from_nexus_web_portal>

[ -z $1 ] && { echo "To run the script, you need to pass a link to as an argument"; exit 1; }

echo $1 | sed -e "s#%2F#/#g" | tee /tmp/link_to_wget.txt
cat /tmp/link_to_wget.txt | wget - -o $HOME/