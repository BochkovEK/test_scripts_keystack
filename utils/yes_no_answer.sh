#!/bin/bash

# The script provide yes\no answer

[[ -z $DEBUG ]] && DEBUG="false"
[[ -z $TS_YES_NO_QUESTION ]] && TS_YES_NO_QUESTION="foo"


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

echo $DEBUG
yes_no_answer
[ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  TS_YES_NO_QUESTION:   $TS_YES_NO_QUESTION
"