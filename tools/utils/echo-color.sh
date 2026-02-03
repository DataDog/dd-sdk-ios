#!/bin/zsh

# Usage:
# ./tools/utils/echo-color.sh [OPTION] "message" [additional_message]
# This script renders colored output for different types of log messages.
# It supports info, error, warning, success messages, and titles, each with distinctive coloring.

# Options:
#   --info   Display info message in light blue.
#   --err    Display the message as an error in red.
#   --warn   Display the message as a warning in yellow.
#   --succ   Display the message as a success in green.
#   --title  Display the message in a purple title box.
#   --subtitle  Display the message in a blue title box with "➔" prefix.
#   --subtitle2  Display the message in a light blue title box with "➔ ➔" prefix.

# Arguments:
#   "message"            Mandatory first argument; content varies based on the chosen option.
#   [additional_message] Optional second argument for --err, --warn, and --succ, not used with --title.

RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
RESET="\e[0m"
BOLD="\e[1m"
PURPLE="\e[35m"
BLUE='\033[34m'
BLUE_LIGHT='\033[36m'

echo_info() {
  echo "${BLUE_LIGHT}$1${RESET} $2"
}

echo_err() {
  echo "${RED}$1${RESET} $2"
}

echo_warn() {
  echo "${YELLOW}$1${RESET} $2"
}

echo_succ() {
  echo "${GREEN}$1${RESET} $2"
}

# Usage:
# echo_box COLOR text
echo_box() {
  echo ""
  local COLOR=$1
  local text=$2
  local len=$((${#text}+2))
  local separator=$(printf '.%.0s' {1..$len})
  echo -e " ${COLOR}${separator}${RESET}"
  echo -e "${COLOR}┌$(printf '\u2500%.0s' $(seq 1 $len))┐${RESET}"
  echo -e "${COLOR}│ ${BOLD}$text${RESET}${COLOR} │${RESET}"
  echo -e "${COLOR}└$(printf '\u2500%.0s' $(seq 1 $len))┘${RESET}"
}

echo_title() {
  echo_box "$PURPLE" "$1"
}

echo_subtitle() {
  echo_box $BLUE "➔ $1"
}

echo_subtitle2() {
  echo_box $BLUE_LIGHT "➔ ➔ $1"
}

case "$1" in
    --info)
        echo_info "$2" "$3"
        ;;
    --err)
        echo_err "$2" "$3"
        ;;
    --warn)
        echo_warn "$2" "$3"
        ;;
    --succ)
        echo_succ "$2" "$3"
        ;;
    --title)
        echo_title "$2"
        ;;
    --subtitle)
        echo_subtitle "$2"
        ;;
    --subtitle2)
        echo_subtitle2 "$2"
        ;;
    *)
        ;;
esac
