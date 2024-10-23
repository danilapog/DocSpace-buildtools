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

function resize_fedora_disk() {
  # Print current disk layout
  echo "Current disk layout:"
  lsblk

  # Install required tools if they are not available
  if ! command -v parted &> /dev/null; then
    echo "parted not found, installing..."
    sudo dnf install -y parted
  fi

  if ! command -v growpart &> /dev/null; then
    echo "growpart not found, installing..."
    sudo dnf install -y cloud-utils-growpart
  fi

  # Fix GPT table to use all available space if needed
  echo "Fixing GPT to use all available space..."
  echo -e "fix\n" | sudo parted /dev/sda

  # Use growpart to resize the partition /dev/sda2
  echo "Resizing partition /dev/sda2 using growpart..."
  sudo growpart /dev/sda 2

  # Check the filesystem type before resizing
  FSTYPE=$(df -T | grep '/$' | awk '{print $2}')

  # Resize the filesystem based on the filesystem type (xfs or ext4)
  if [ "$FSTYPE" == "xfs" ]; then
    echo "Resizing XFS filesystem on /dev/sda2..."
    sudo xfs_growfs /
  elif [ "$FSTYPE" == "ext4" ]; then
    echo "Resizing ext4 filesystem on /dev/sda2..."
   sudo resize2fs /dev/sda2
  else
   echo "Unsupported filesystem type: $FSTYPE"
    exit 1
  fi

  # Print the new disk layout
  echo "Disk layout after resizing:"
  lsblk

  # Verify new available space
  echo "Filesystem after resizing:"
  df -h /
}

function prepare_vm() {
  echo "inside prepare_vm function"
  if [ -f /etc/os-release ]; then
    source /etc/os-release
    case $ID in
      ubuntu)
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
          ;;

      debian)
          [ "$VERSION_CODENAME" == "bookworm" ] && apt-get update -y && apt install -y curl gnupg
          apt-get remove postfix -y && echo "${COLOR_GREEN}☑ PREPAVE_VM: Postfix was removed${COLOR_RESET}"
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-deb
          ;;

      fedora)
          echo "THIS IS FEDORA"
          [ $(hostnamectl | grep "Operating System" | awk '{print $5}') == "40" ] && resize_fedora_disk 
          ;;

      centos)
          [ "$VERSION_ID" == "8" ] && sed -i 's|^mirrorlist=|#&|; s|^#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|' /etc/yum.repos.d/CentOS-*
          [[ "${TEST_REPO_ENABLE}" == 'true' ]] && add-repo-rpm
          yum -y install centos*-release 
          ;;

      *)
          echo "${COLOR_RED}Failed to determine Linux dist${COLOR_RESET}"; exit 1
          ;;
    esac
  else
      echo "${COLOR_RED}File /etc/os-release doesn't exist${COLOR_RESET}"; exit 1
  fi
}

main() {
  hostnamectl
  echo ${VERSION}
  [ $(hostnamectl | grep "Operating System" | awk '{print $5}') == "40" ] && echo "THIS IS FEDORA40"
  prepare_vm
}

main
