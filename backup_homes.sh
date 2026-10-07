#!/bin/bash

PROGRAMNAME="backup_homes.sh"

set -o pipefail

help() {
  echo ""
  echo "${PROGRAMNAME}";
  echo "Copyright by Andreas Zoglauer"
  echo ""
  echo "Usage: bash ${PROGRAMNAME} [options]";
  echo ""
  echo "Options:"
  echo "  --name=[name]: The name of the raid to clone -- it  is assumed it mounted under /volumes"
  echo "  --backuphomes=[destination]: If set, backup all home directories to [destination], which needs to be on the raid (top level)"
  echo ""
}


# Store command line as array
CMD=( "$@" )

# Check for help
for C in "${CMD[@]}"; do
  if [[ ${C} == "-h" ]] || [[ ${C} == "--help" ]]; then
    echo ""
    help
    exit 0
  fi
done

# Default options
NAME=""
BACKUPHOMEDESTINATION="backups"
EXCLUDES="docker simy lost+found"

# Scan all options
for C in "${CMD[@]}"; do
  if [[ ${C} == --name=* ]] || [[ ${C} == -n=* ]]; then
    NAME="${C#*=}"
  elif [[ ${C} == --backuphomes=* ]] || [[ ${C} == -b=* ]]; then
    BACKUPHOMEDESTINATION="${C#*=}"
  elif [[ ${C} == "--help" ]] || [[ ${C} == "-h" ]]; then
    echo ""
    help
    exit 0
  else
    echo ""
    echo "ERROR: Unknown command line option: ${C}"
    echo "       See \"${PROGRAMNAME} --help\" for a list of options"
    exit 1
  fi
done

# We need root to write the logrotate config, the log file, and to read all home directories
if [[ ${EUID} -ne 0 ]]; then
  echo ""
  echo "ERROR: ${PROGRAMNAME} must be run as root"
  exit 1
fi

RAIDDIR="/volumes/${NAME}"

# Setup the backup facility - default is going to /var/log/backups
if [[ ! -f /etc/logrotate.d/backups ]]; then
  echo "/var/log/backups { " >> /etc/logrotate.d/backups
  echo "  rotate 5 " >> /etc/logrotate.d/backups
  echo "  weekly " >> /etc/logrotate.d/backups
  echo "  compress " >> /etc/logrotate.d/backups
  echo "  missingok " >> /etc/logrotate.d/backups
  echo "  notifempty " >> /etc/logrotate.d/backups
  echo "}" >> /etc/logrotate.d/backups
fi
LOG="/var/log/backups"

# We do not want to sync if we are not mounted or have any other problem -- since that might remove all remote data

echo " " 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}
echo "INFO [home backups]: Started backup script for home-directories to ${NAME} @ $(date)" 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}

echo "INFO [home-backups]: Checking if we got a name of a raid" 2>&1 | tee -a ${LOG}
if [[ ${NAME} == "" ]]; then
  echo "ERROR [home-backups]: You need to provide a raid name at the command line" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [home-backups]: Checking if the raid directory exists" 2>&1 | tee -a ${LOG}
if [ ! -d ${RAIDDIR} ]; then
  echo "ERROR [home-backups]: The raid director ${RAIDDIR} does not exist" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [home-backups]: Checking if this script is still running"  2>&1 | tee -a ${LOG}
LOCKFILE="/var/lock/backup_homes_${NAME}.lock"
exec 9>${LOCKFILE}
flock -n 9
if [[ $? -ne 0 ]]; then
  echo "ERROR [home-backups]: ${PROGRAMNAME} still running for ${NAME}" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [home-backups]: Checking if the volume is mounted" 2>&1 | tee -a ${LOG}
if ! mountpoint -q "${RAIDDIR}"; then
  echo "ERROR [home-backups]: Raid not mounted" 2>&1 | tee -a ${LOG}
  exit 1
fi


echo " " 2>&1 | tee -a ${LOG} 
echo "INFO [home-backups]: All tests passed! " 2>&1 | tee -a ${LOG}

echo " " 2>&1 | tee -a ${LOG} 
echo "INFO [home-backups]: Starting backup of home directories @ $(date) ...  " 2>&1 | tee -a ${LOG}


DESTINATION="${RAIDDIR}/${BACKUPHOMEDESTINATION}/${HOSTNAME}"
if [[ ! -d ${DESTINATION} ]]; then
  mkdir -p "${DESTINATION}"
  if [[ $? -ne 0 ]]; then
    echo "ERROR [home-backups]: Could not create ${DESTINATION}" 2>&1 | tee -a ${LOG}
    exit 1
  fi
fi


FAILED=""
for D in `find /home -maxdepth 1 -mindepth 1 -type d`; do
  HOMENAME=$(basename ${D})

  EXCLUDED="FALSE"
  for E in ${EXCLUDES}; do
    if [[ ${HOMENAME} == "${E}" ]]; then
      EXCLUDED="TRUE"
    fi
  done


  if [[ ${EXCLUDED} == "FALSE" ]]; then
    echo "INFO [home-backups]: Starting backup of ${D} @ $(date) ... " 2>&1 | tee -a ${LOG}
    bash "$(dirname "$0")"/backup_rsync.sh --f="${D}" -a="${DESTINATION}/" 2>&1 | tee -a ${LOG}
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
      echo "ERROR [home-backups]: Backup of ${D} failed" 2>&1 | tee -a ${LOG}
      FAILED="${FAILED} ${D}"
    fi
  fi
done


echo " " 2>&1 | tee -a ${LOG}
if [[ ${FAILED} != "" ]]; then
  echo "ERROR [home-backups]: The following backups failed:${FAILED} @ $(date)" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [home-backups]: Done @ $(date)! " 2>&1 | tee -a ${LOG}

exit 0




