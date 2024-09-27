#!/bin/bash

# The script provide yes\no answer

[[ -z $DEBUG ]] && DEBUG="true"


yes_no_answer () {
  TS_YES_NO_INPUT=""
  while true; do
    read -p "$TS_YES_NO_QUESTION" yn
    yn=${yn:-"Yes"}
    echo $yn
    case $yn in
        [Yy]* ) export TS_YES_NO_INPUT="true"; break;;
        [Nn]* ) export TS_YES_NO_INPUT="false"; break ;;
        * ) echo "Please answer yes or no.";;
    esac
  done
  export TS_YES_NO_QUESTION="<Empty yes\no question>"
}

yes_no_answer
[ "$DEBUG" = true ] && echo -e "
  [DEBUG]
  TS_YES_NO_INPUT:   $TS_YES_NO_INPUT
"