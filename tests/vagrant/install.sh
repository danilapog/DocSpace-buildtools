#!/bin/bash

set -e

while [ "$1" != "" ]; do
    case $1 in
      -ds | --download-scripts )
        if [ "$2" != "" ]; then
          DOWNLOAD_SCRIPTS=$2
          shift
        fi
      ;;

      -arg | --arguments )
          if [ "$2" != "" ]; then
            ARGUMENTS=$2
            shift
          fi
      ;;

      -li | --local-install )
          if [ "$2" != "" ]; then
            LOCAL_INSTALL=$2
            shift
          fi
      ;;

      -tr | --test-repo )
          if [ "$2" != "" ]; then
            TEST_REPO_ENABLE=$2
            shift
          fi
      ;;
    esac
    shift
done

export TERM=xterm-256color^M

function common::get_colors() {
    export LINE_SEPARATOR="-----------------------------------------"
    export COLOR_BLUE=$'\e[34m' COLOR_GREEN=$'\e[32m' COLOR_RED=$'\e[31m' COLOR_RESET=$'\e[0m' COLOR_YELLOW=$'\e[33m'
}

#############################################################################################
# Checking available resources for a virtual machine
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
#############################################################################################
function check_hw() {
    echo "----------------------------------"
    echo "----------------------------------"
    echo "${COLOR_RED} $(lsblk) ${COLOR_RESET}"
    echo "----------------------------------"
    echo "----------------------------------"
    echo "${COLOR_RED} $(free -h) ${COLOR_RESET}"
    echo "----------------------------------"
    echo "----------------------------------"
    echo "${COLOR_RED} $(nproc) ${COLOR_RESET}"
    echo "----------------------------------"
    echo "----------------------------------"
    echo "${COLOR_RED} $(df -h) ${COLOR_RESET}"
}

function resize() {
  sudo parted /dev/sda print free
  sudo parted /dev/sda resizepart 2 100%

  sudo lvextend -l +100%FREE /dev/disk/root
  sudo xfs_growfs /dev/disk/root
}

main() {
  check_hw
  resize
  check_hw
}

main
