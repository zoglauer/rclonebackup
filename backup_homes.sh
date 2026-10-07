#!/bin/bash

PROGRAMNAME="backup_homes.sh"
CURRENTPID=$$
PARENTPID=$(ps -o ppid= -p ${CURRENTPID})

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
  echo "  --timeout=[hours]: Set a timeout in hours, default is 22 hours"
  echo "  --do-size-check / --no-size-check: Check for remote size"
  echo "  --filter: Filter standard files (sim, tra, evta, rsp)"
  echo "  --verbose: Verbose output"
  echo ""
  echo "Assumptions:"
  echo "(1) rclone is installed"
  echo "(2) The raid is mounted under /volumes/<NAME> where <NAME> is supplied at the command line"
  echo "(3) The rclone.conf file has been copied into this directory"
  echo "(4) The name of the target remote is <NAME>encrypted, where name is the name of the mounted directory supplied at the command line"  
}


# Store command line as array
CMD=( "$@" )

# Check for help
for C in "${CMD[@]}"; do
  if [[ ${C} == *-h* ]]; then
    echo ""
    help
    exit 0
  fi
done

# Default options
NAME=""
BACKUPHOMEDESTINATION="backups"
VERBOSE="FALSE"
# Docker has too many small files for backup -- we always need to exclude it
EXCLUDES="docker/ users/simy/"

# Overwrite default options with user options:
for C in "${CMD[@]}"; do
  if [[ ${C} == *-n*=* ]]; then
    NAME=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-b*=* ]]; then
    BACKUPHOMEDESTINATION=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-v* ]]; then
    VERBOSE="TRUE"
  elif [[ ${C} == *-h* ]]; then
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
STATUS=$(ps -efww | grep -w -E "root.*bin.*${PROGRAMNAME}.*${NAME}" | grep -v "grep" | grep -v "sudo" | grep -v "timeout" | grep -v ${PARENTPID})
if [[ ${STATUS} != "" ]]; then
  echo "ERROR [home-backups]: ${PROGRAMNAME} still running for ${NAME}" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [home-backups]: Checking if the volume is mounted" 2>&1 | tee -a ${LOG}
if [[ $(grep ${RAIDDIR} /proc/mounts) == "" ]]; then
  echo "ERROR [home-backups]: Raid not mounted" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [home-backups]: Checking if mount point exists" 2>&1 | tee -a ${LOG}
MOUNTPOINT=$(findmnt -rn -o TARGET | grep "/volumes/${NAME}")
if [[ ${MOUNTPOINT} == "" ]]; then
  echo "ERROR [home-backups]: Mount point not found" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo " " 2>&1 | tee -a ${LOG} 
echo "INFO [home-backups]: All tests passed! " 2>&1 | tee -a ${LOG}

echo " " 2>&1 | tee -a ${LOG} 
echo "INFO [home-backups]: Starting backup of home directories @ $(date) ...  " 2>&1 | tee -a ${LOG}

if [[ ! -d ${RAIDDIR}/${BACKUPHOMEDESTINATION} ]]; then
  mkdir ${RAIDDIR}/${BACKUPHOMEDESTINATION}
fi

if [[ ! -d ${RAIDDIR}/${BACKUPHOMEDESTINATION}/${HOSTNAME} ]]; then
  mkdir ${RAIDDIR}/${BACKUPHOMEDESTINATION}/${HOSTNAME}
fi


for D in `find /home -maxdepth 1 -mindepth 1 -type d`; do
  if [[ ${D} != *"lost+found"* ]] && [[ ${D} != *"simy"* ]]; then
    echo "INFO [home-backups]: Starting backup of ${D} @ $(date) ...  " 2>&1 | tee -a ${LOG}
    bash $(dirname "$0")/backup_rsync.sh --f="${D}" -a="${RAIDDIR}/${BACKUPHOMEDESTINATION}/${HOSTNAME}/" 2>&1 | tee -a ${LOG}
  fi
done

echo " " 2>&1 | tee -a ${LOG}
echo "INFO [home-backups]: Done @ $(date)! " 2>&1 | tee -a ${LOG}

exit 0

