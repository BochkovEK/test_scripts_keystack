#!/bin/bash

# The script provide yes\no answer

[[ -z $TS_DEBUG ]] && TS_DEBUG="sosa"
[[ -z $TS_YES_NO_QUESTION ]] && TS_YES_NO_QUESTION="<Empty yes/no question>[yes]"

#echo $TS_DEBUG
#echo $TS_YES_NO_QUESTION
yes_no_answer () {
  while true; do
    read -p "$TS_YES_NO_QUESTION" yn
    yn=${yn:-"Yes"}
#    echo $yn
    case $yn in
        [Yy]* ) echo "true"; break;;
        [Nn]* ) echo "false"; break ;;
        * ) echo "Please answer yes or no.";;
    esac
  done
#  export TS_YES_NO_QUESTION='<Empty yes/no question>'
}

echo $TS_DEBUG
yes_no_answer
[ "$TS_DEBUG" = true ] && echo -e "
  [TS_DEBUG]
  TS_YES_NO_QUESTION:   $TS_YES_NO_QUESTION
"