#!/bin/bash

function len {
  echo $(echo $1 | awk '{print length}')
}

function logger {
  upper=$(echo $1 | tr '[:lower:]' '[:upper:]')
  echo "${upper} $2"
}

function usage {
  echo ""
  echo "Somewhat painlessly scan docker container images using twistcli."
  echo "Usage: ${0##*/} [options]"
  echo "  -i    Specify the name of the image in the format image or image:label."
  echo "        Can be used multiple times."
  echo "  -h    Display this help message."
  echo ""
  echo "Example:"
  echo "  ${0##*/} -i <image1> -i <image2:label>"
  exit 0
}

function determine_os {
  OS=`uname`

  if [ "${OS}" == "Darwin" ]; then
    OS_INFO[0]="OS X"
    if sw_vers > /dev/null 2>&1; then
      OS_INFO[1]=$(sw_vers -productVersion)
    fi

  elif [ "${OS}" == "Linux" ]; then
    if [ -f "/etc/alpine-release" ]; then
      OS_INFO[0]="Alpine Linux"
      OS_INFO[1]=$(egrep -o "[0-9].*[0-9]" /etc/alpine-release)
    elif [ -f "/etc/debian_version" ]; then
      OS_INFO[0]="Debian Linux"
      OS_INFO[1]=$(egrep -o "[0-9].*[0-9]" /etc/debian_version)
    elif [ -f "/etc/system-release" ]; then
      if [ -f "/etc/redhat-release" ]; then
        OS_INFO[0]="Redhat Linux"
        OS_INFO[1]=$(egrep -o "[0-9].*[0-9]" /etc/redhat-release)
      else
        OS_INFO[0]="Amazon Linux"
        OS_INFO[1]=$(cat /etc/system-release-cpe | egrep -o "([0-9]+)(\.[0-9]+)+")
      fi
    fi
  else
    OS_INFO[0]="Unknown"
    OS_INFO[1]="Unknown"
  fi
}

function config_help {
  echo ""
  echo "In order to use this utility you need to have the file ${TWISTLOCK_FILE} and its contents should look like this:"
  echo "{"
  echo "  \"endpoint\": \"<<ENDPOINT-URL>>\","
  echo "  \"port\": <PORT-NUMBER>,"
  echo "  \"username\": \"<USERNAME>\","
  echo "  \"password\": \"<PASSWORD>\""
  echo "}"
}

function fetch_twistcli {
  OS=`uname`
  BINDIR=~/bin
  if [ "${OS}" == "Linux" ]; then
    DOWNLOAD_URL="https://<<DOWNLOAD-URL>"
  elif [ "${OS}" == "Darwin" ]; then
    DOWNLOAD_URL="https://<<DOWNLOAD-URL>"
  fi

  if [ ! -d "${BINDIR}" ]; then
    if ! mkdir "${BINDIR}" > /dev/null 2>&1; then
      logger "error" "Failed to create ${BINDIR}"
      exit 1
    fi
  fi

  curl -s -L -k "${DOWNLOAD_URL}" > "${BINDIR}/twistcli" -o ${BINDIR}/twistcli
  if [ $? -ne 0 ]; then
    logger "error" "Failed to download twistcli."
    exit 1
  fi
  
  chmod +x "${BINDIR}/twistcli"
}

function check_prereqs {
  JQ_FOUND=false

  determine_os

  OS_NAME="${OS_INFO[0]}"
  OS_VERSION="${OS_INFO[1]}"

  if [ "${OS}" == "Unknown" ]; then
    logger "error" "Unable to determine your operating system."
    exit 1
  fi
  
  logger "info" "Your operating system is ${OS_NAME} ${OS_VERSION}."
  
  if jq --version > /dev/null 2>&1; then
    JQ_FOUND=true
  else
    case $OS in
      "OS X")
        INSTALL_USING="brew install jq"
        ;;
      "Alpine Linux")
        INSTALL_USING="sudo apk add jq"
        ;;
      "Debian Linux")
        INSTALL_USING="sudo apt-get -y install jq"
        ;;
      "Amazon Linux")
        INSTALL_USING="sudo yum -y install jq"
        ;;
      "Redhat Linux")
        INSTALL_USING="sudo yum -y install jq"
        ;;
      "Unknown")
        logger "error" "Unable to determine your operating system."
        exit 1
        ;;
      *)
        logger "error" "Unable to determine your operating system."
        exit 1
        ;;
    esac
  fi

  if [ "${JQ_FOUND}" == false ]; then
    logger "error" "jq not found. Please install it with: \"${INSTALL_USING}\" and try again."
    exit 1
  fi

  if ! twistcli -v > /dev/null 2>&1; then
    logger "info" "twistcli not found. Attempting to download."
    fetch_twistcli
  fi
}

function scrub_and_pull_image {
  IFS=':' read -r -a bits <<< "$image_string"
  image_name="${bits[0]}"
  image_label="${bits[1]}"

  if [ $(len $image_label) -eq 0 ]; then
    image_label="latest"
  fi

  image_full="${image_name}:${image_label}"

  if [ $(docker images "${image_full}" | tail -n +2 | wc -l) -ne 1 ]; then
    logger "info" "Image \"${image_full}\" doesn't exist. Attempting to pull it."
    output=$((docker pull "${image_full}") 2>&1)
    if [ $? -ne 0 ]; then
      if echo $output | grep -q "not found"; then
        logger "error" "The image \"${image_full}\" does not exist in the registry."
      else
        logger "error" "Failed to pull \"${image_full}\": ${output}"
      fi
      exit 1
    fi
  fi
}

TWISTLOCK_FILE=~/.twistlock.json

if [ -f "${TWISTLOCK_FILE}" ]; then
  mode=$(stat -c "%a" "${TWISTLOCK_FILE}")
  if [ $mode -ne 600 ]; then
    logger "info" "${TWISTLOCK_FILE} should be mode 600, but is ${mode}. Fixing."
    chmod 600 "${TWISTLOCK_FILE}"
  fi
else
  logger "error" "Cannot find ${TWISTLOCK_FILE}. Cannot continue."
  config_help
  exit 1
fi

ENDPOINT=$(jq -r ".endpoint" ${TWISTLOCK_FILE})
if [ $(len ${ENDPOINT}) -eq 0 ] || [ "${ENDPOINT}" == null ]; then
  logger "error" "Could not find the Twistlock endpoint in ${TWISTLOCK_FILE}."
  config_help
  exit 1
fi

PORT=$(jq -r ".port" ${TWISTLOCK_FILE})
if [ $(len ${PORT}) -eq 0 ] || [ "${PORT}" == null ]; then
  logger "error" "Could not find the Twistlock port in ${TWISTLOCK_FILE}."
  config_help
  exit 1
fi

USERNAME=$(jq -r ".username" ${TWISTLOCK_FILE})
if [ $(len ${USERNAME}) -eq 0 ] || [ "${USERNAME}" == null ]; then
  logger "error" "Could not find the Twistlock username in ${TWISTLOCK_FILE}."
  config_help
  exit 1
fi

PASSWORD=$(jq -r ".password" ${TWISTLOCK_FILE})
if [ $(len ${PASSWORD}) -eq 0 ] || [ "${PASSWORD}" == null ]; then
  logger "error" "Could not find the Twistlock password in ${TWISTLOCK_FILE}."
  config_help
  exit 1
fi

if [ $# -eq 0 ]; then
  usage
fi

while getopts "hi:" opt; do
    case $opt in
        i)
          images+=("$OPTARG")
          ;;
        h)
          usage
          ;;
        *)
          usage
          ;;
    esac
done
shift $((OPTIND -1))

if [ "${#images[@]}" -eq 0 ]; then
  logger "warn" "No images specified."
  usage
fi

check_prereqs

for image_string in ${images[@]}; do
  scrub_and_pull_image

  logger "info" "scanning ${image_full}"
  twistcli images scan --address https://${ENDPOINT}:${PORT} --details --user ${USERNAME} --password ${PASSWORD} "${image_full}"
done
