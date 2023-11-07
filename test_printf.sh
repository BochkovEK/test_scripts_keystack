#Colors
green=$(tput setaf 2)
red=$(tput setaf 1)
orange=$(tput setaf 3)
violet=$(tput setaf 5)
normal=$(tput sgr0)

echo "test"
printf "%s\n" "${green}Project \"project_name\" does not exist${normal}"
