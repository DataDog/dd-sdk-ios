#!/bin/zsh

# Usage:
# ./tools/utils/echo_color.sh [OPTION] "message" [additional_message]
# This script renders colored output for different types of log messages.
# It supports error, warning, success messages, and titles, each with distinctive coloring.

# Options:
#   --err    Display the message as an error in red.
#   --warn   Display the message as a warning in yellow.
#   --succ   Display the message as a success in green.
#   --title  Display the message in a purple title box.

# Arguments:
#   "message"            Mandatory first argument; content varies based on the chosen option.
#   [additional_message] Optional second argument for --err, --warn, and --succ, not used with --title.

RED="\e[31m"
YELLOW="\e[33m"
GREEN="\e[32m"
RESET="\e[0m"
BOLD="\e[1m"
PURPLE="\e[35m"

echo_err() {
  echo "${RED}$1${RESET} $2"
}

echo_warn() {
  echo "${YELLOW}$1${RESET} $2"
}

echo_succ() {
  echo "${GREEN}$1${RESET} $2"
}

echo_title() {
  echo ""
  local len=$((${#1}+2))
  local separator=$(printf '.%.0s' {1..$len})
  echo -e " ${PURPLE}${separator}${RESET}"
  echo -e "${PURPLE}┌$(printf '%*s' $len | tr ' ' '─')┐${RESET}"
  echo -e "${PURPLE}│ ${BOLD}$1${RESET}${PURPLE} │${RESET}"
  echo -e "${PURPLE}└$(printf '%*s' $len | tr ' ' '─')┘${RESET}"
}

case "$1" in
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
    *)
        ;;
esac
