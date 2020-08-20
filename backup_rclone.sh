#!/bin/bash

PROGRAMNAME="backup_rclone.sh"

help() {
  echo ""
  echo "${PROGRAMNAME}";
  echo "Copyright by Andreas Zoglauer"
  echo ""
  echo "Usage: bash ${PROGRAMNAME} [options]";
  echo ""
  echo "Options:"
  echo "  --name=[name]: The name of the directory to clone"
  echo "  --backuphomes=[destination]: If set backup the home directories to [destination], which needs to be on the raid (top level)"
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
BACKUPHOMEDESTINATION=""

# Overwrite default options with user options:
for C in "${CMD[@]}"; do
  if [[ ${C} == *-n*=* ]]; then
    NAME=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-b*=* ]]; then
    BACKUPHOMEDESTINATION=`echo ${C} | awk -F"=" '{ print $2 }'`
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
RCLONECONFIG=$(dirname "$0")/rclone.conf
LOG="/tmp/Backup_$(basename ${RAIDDIR})_$(date +%Y%m%d_%H%M%S).log"

# We do not want to sync if we are not mounted or have any other problem -- since that might remove all remote data

echo "INFO: Started backup script for ${NAME} @ $(date)" 2>&1 | tee -a ${LOG}

echo "INFO: Checking if we have a good name" 2>&1 | tee -a ${LOG}
if [[ ${NAME} == "" ]]; then
  echo "ERROR: You need to provide a directory name at the command line" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO: Checking if the raid directory exists:" 2>&1 | tee -a ${LOG}
if [ ! -d ${RAIDDIR} ]; then
  echo "ERROR: The raid director ${RAIDDIR} does not exist" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO: Checking if the rclone.conf file exists" 2>&1 | tee -a ${LOG}
if [ ! -f ${RCLONECONFIG} ]; then
  echo "ERROR: There is no rclone.conf file in the start directory" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO: Checking if this script is still running"  2>&1 | tee -a ${LOG}
ps -efww | grep -w "[b]ackup_rclone.sh" | grep -v $$ | grep -v "sudo"
Status=`ps -efww | grep -w "[b]ackup_rclone.sh" | grep -v $$ | grep -v "sudo" | awk -vpid=$$ '$2 != pid { print $2 }'`
if [ ! -z "${Status}" ]; then
  echo "ERROR: ${PROGRAMNAME} still running"  2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO: Checking if rclone is still running"  2>&1 | tee -a ${LOG}
if [[ $(ps -Af | grep "[ ]rclone") != "" ]]; then
  echo "ERROR: rclone still running"  2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO: Running \"du\" to trigger any failures" 2>&1 | tee -a ${LOG}
du -s ${RAIDDIR}/${USERDIR} 2>&1 | tee -a ${LOG}
if [ "$?" != "0" ]; then
  echo "ERROR: Unable to read directory size via du" 2>&1 | tee -a ${LOG}
  exit 1 
fi

echo "INFO: Checking if the volume is mounted" 2>&1 | tee -a ${LOG}
if ! grep -qs "${RAIDDIR}" /proc/mounts; then
  echo "ERROR: Raid not mounted" 2>&1 | tee -a ${LOG}
  exit 1
fi

MOUNTPOINT=$(findmnt -n -o SOURCE --target "${RAIDDIR}")
MOUNTPOINT=$(basename ${MOUNTPOINT})

if [[ ${MOUNTPOINT} == "" ]]; then
  echo "ERROR: Mount point not found" 2>&1 | tee -a ${LOG}
  exit 1
fi

# Second, that everything is OK with it if it is an mdadm raid:

if [[ ${MOUNTPOINT} == md* ]]; then 
  echo "INFO: Checking if the raid is not degraded" 2>&1 | tee -a ${LOG}
  if grep -A1 ${MOUNTPOINT} /proc/mdstat | tail -n 1 | awk '{print $NF }' | grep _ > /dev/null; then 
    echo "ERROR: Failed disks, not syncing" 2>&1 | tee -a ${LOG}
    exit 1
  fi
fi

echo " " 2>&1 | tee -a ${LOG} 
echo "INFO: All tests passed! " 2>&1 | tee -a ${LOG}

if [[ ${BACKUPHOMEDESTINATION} != "" ]]; then 

  echo " " 2>&1 | tee -a ${LOG} 
  echo "INFO: Starting backup of home directories @ $(date) ...  " 2>&1 | tee -a ${LOG}

  if [[ ! -d ${RAIDDIR}/${BACKUPHOMEDESTINATION} ]]; then
    mkdir ${RAIDDIR}/${BACKUPHOMEDESTINATION}
  fi

  for D in `find /home -maxdepth 1 -mindepth 1 -type d`; do
    if [[ ${D} != *"lost+found"* ]]; then
      echo "INFO: Starting backup of ${D} @ $(date) ...  " 2>&1 | tee -a ${LOG}
      PREFIX="Backup.$(basename ${D})"
      bash $(dirname "$0")/backup_tar.sh -p="${PREFIX}" -f="${D}" -t="${RAIDDIR}/${BACKUPHOMEDESTINATION}" -r=1 -d=5 2>&1 | tee -a ${LOG}
    fi
  done
fi

echo " " 2>&1 | tee -a ${LOG} 
echo "INFO: Starting rclone @ $(date) ...  " 2>&1 | tee -a ${LOG}
BACKUPDIR=${NAME}encrypted:latest
BACKUPDIFFDIR=${NAME}encrypted:latest-diff-$(date +%Y-%m-%d--%H-%M-%S)
rclone --config ${RCLONECONFIG} mkdir ${BACKUPDIR}
rclone --config ${RCLONECONFIG} --drive-stop-on-upload-limit -P --stats 1m --stats-one-line -L --fast-list --transfers=5 --checkers=40 --tpslimit=10 --drive-chunk-size=64M --max-backlog 999999 --backup-dir ${BACKUPDIFFDIR} sync ${RAIDDIR} ${BACKUPDIR} 2>&1 | tee -a ${LOG}


echo "INFO: Checking for duplicates  @ $(date) ... " 2>&1 | tee -a ${LOG}
if grep -q "Duplicate object found" ${LOG}; then
  echo "INFO: Duplicates found and keeping only newest... " 2>&1 | tee -a ${LOG}
  rclone --config ${RCLONECONFIG} -L --fast-list dedupe --dedupe-mode newest ${BACKUPDIR} 2>&1 | tee -a ${LOG}
fi


echo "INFO: Starting to calculate size of remote directory @ $(date) ... " 2>&1 | tee -a ${LOG}
rclone --config ${RCLONECONFIG} --fast-list size ${BACKUPDIR} 2>&1 | tee -a ${LOG}


echo "INFO: Checking used local space again for comparison @ $(date) ... " 2>&1 | tee -a ${LOG}
du -s -B1 ${RAIDDIR}/. 2>&1 | tee -a ${LOG}


echo " " 2>&1 | tee -a ${LOG}
echo "INFO: Done @ $(date)! " 2>&1 | tee -a ${LOG}

exit 0

