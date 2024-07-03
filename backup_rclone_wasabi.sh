#!/bin/bash

# Since rclone can explode in memory size and take down the whole machine, limit the memory usage to
# 16 GB of memory usage
ulimit -m 16777216


PROGRAMNAME="backup_rclone_wasabi.sh"
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
BACKUPHOMEDESTINATION=""
TIMEOUT=21
SIZECHECK="TRUE"
FILTERFILES="FALSE"
VERBOSE="FALSE"
# Docker has too many small files for backup to gogole drive -- we always need to exclude it
EXCLUDES="docker/ users/simy/"

# Overwrite default options with user options:
for C in "${CMD[@]}"; do
  if [[ ${C} == *-n*=* ]]; then
    NAME=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-b*=* ]]; then
    BACKUPHOMEDESTINATION=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-t*=* ]]; then
    TIMEOUT=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-do-size-c* ]]; then
    SIZECHECK="TRUE"
  elif [[ ${C} == *-v* ]]; then
    VERBOSE="TRUE"
  elif [[ ${C} == *-f* ]]; then
    FILTERFILES="TRUE"
  elif [[ ${C} == *-no-size-c* ]]; then
    SIZECHECK="FALSE"
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
RCLONECONFIG=$(dirname "$0")/rclone_wasabi.conf

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
echo "INFO [${NAME}]: Started backup script for ${NAME} to Wasabi @ $(date)" 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}

if [[ ${TIMEOUT} -ge 2 ]]; then
  echo "INFO [${NAME}]: Timeout for rclone: ${TIMEOUT} hours" 2>&1 | tee -a ${LOG}
else 
  TIMEOUT="21"
  echo "WARNING [${NAME}]: Timeout for rclone needs to be 2 hours at a minimum. Using the default, ${TIMEOUT} hours." 2>&1 | tee -a ${LOG}
fi

echo "INFO [${NAME}]: Checking if we got a name of a raid" 2>&1 | tee -a ${LOG}
if [[ ${NAME} == "" ]]; then
  echo "ERROR [${NAME}]: You need to provide a directory name at the command line" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [${NAME}]: Checking if the raid directory exists" 2>&1 | tee -a ${LOG}
if [ ! -d ${RAIDDIR} ]; then
  echo "ERROR [${NAME}]: The raid director ${RAIDDIR} does not exist" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [${NAME}]: Checking if the conf file exists" 2>&1 | tee -a ${LOG}
if [ ! -f ${RCLONECONFIG} ]; then
  echo "ERROR [${NAME}]: The rclone conf file \"${RCLONECONFIG}\" is not in the start directory" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [${NAME}]: Checking if this script is still running"  2>&1 | tee -a ${LOG}
STATUS=$(ps -efww | grep -w -E "root.*bin.*${PROGRAMNAME}.*${NAME}" | grep -v "grep" | grep -v "sudo" | grep -v "timeout" | grep -v ${PARENTPID})
if [[ ${STATUS} != "" ]]; then
  echo "ERROR [${NAME}]: ${PROGRAMNAME} still running for ${NAME}" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [${NAME}]: Checking if rclone is still running"  2>&1 | tee -a ${LOG}
if [[ $(ps -Af | grep "[ ]rclone" | grep "${NAME}") != "" ]]; then
  echo "ERROR [${NAME}]: rclone still running for ${NAME}"  2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [${NAME}]: Checking if the volume is mounted" 2>&1 | tee -a ${LOG}
if [[ $(grep ${RAIDDIR} /proc/mounts) == "" ]]; then
  echo "ERROR [${NAME}]: Raid not mounted" 2>&1 | tee -a ${LOG}
  exit 1
fi

echo "INFO [${NAME}]: Checking if mount point exists" 2>&1 | tee -a ${LOG}
MOUNTPOINT=$(findmnt -rn -o TARGET | grep "/volumes/${NAME}")
if [[ ${MOUNTPOINT} == "" ]]; then
  echo "ERROR [${NAME}]: Mount point not found" 2>&1 | tee -a ${LOG}
  exit 1
fi

# Second, that everything is OK with it if it is an mdadm raid:

#if [[ ${MOUNTPOINT} == md* ]]; then 
#  echo "INFO: Checking if the raid is not degraded" 2>&1 | tee -a ${LOG}
#  if grep -A1 ${MOUNTPOINT} /proc/mdstat | tail -n 1 | awk '{print $NF }' | grep _ > /dev/null; then 
#    echo "ERROR: Failed disks, not syncing" 2>&1 | tee -a ${LOG}
#    exit 1
#  fi
#fi

echo "INFO [${NAME}]: Checking if \"du\" triggers any failures" 2>&1 | tee -a ${LOG}
du -s ${RAIDDIR}/${USERDIR} 2>&1 > /dev/null
if [ "$?" != "0" ]; then
  echo "ERROR [${NAME}]: Unable to read directory size via du or executing du triggered errors" 2>&1 | tee -a ${LOG}
   exit 1
fi


echo " " 2>&1 | tee -a ${LOG} 
echo "INFO [${NAME}]: All tests passed! " 2>&1 | tee -a ${LOG}

if [[ ${BACKUPHOMEDESTINATION} != "" ]]; then 

  echo " " 2>&1 | tee -a ${LOG} 
  echo "INFO [${NAME}]: Starting backup of home directories @ $(date) ...  " 2>&1 | tee -a ${LOG}

  if [[ ! -d ${RAIDDIR}/${BACKUPHOMEDESTINATION} ]]; then
    mkdir ${RAIDDIR}/${BACKUPHOMEDESTINATION}
  fi

  for D in `find /home -maxdepth 1 -mindepth 1 -type d`; do
    if [[ ${D} != *"lost+found"* ]]; then
      echo "INFO [${NAME}]: Starting backup of ${D} @ $(date) ...  " 2>&1 | tee -a ${LOG}
      PREFIX="Backup.$(basename ${D})"
      bash $(dirname "$0")/backup_tar.sh -p="${PREFIX}" -f="${D}" -a="${RAIDDIR}/${BACKUPHOMEDESTINATION}" -r=1 -d=5 2>&1 | tee -a ${LOG}
    fi
  done
fi

echo " " 2>&1 | tee -a ${LOG} 
#echo "INFO: Starting backup @ $(date) ...  " 2>&1 | tee -a ${LOG}
EXCLUDE=""
for E in ${EXCLUDES}; do
  echo "INFO [${NAME}]: Excluded from backup: ${E}" 2>&1 | tee -a ${LOG}
  EXCLUDE+="--exclude ${E} "
done
echo " " 2>&1 | tee -a ${LOG}

BACKUPBASE=backup-${NAME}-encrypted
BACKUPDIR=${BACKUPBASE}:latest
BACKUPDIFFDIR=${BACKUPBASE}:latest-diff-$(date +%Y-%m-%d--%H-%M-%S)
FILTER=" "
if [[ ${FILTERFILES} == TRUE ]]; then
  FILTER="--filter-from $(dirname "$0")/rclone_filter.txt "
fi
# In case the directory does not exist make it, otherwise this does nothing
rclone --config ${RCLONECONFIG} mkdir ${BACKUPDIR}

# Check size before
if [[ ${SIZECHECK} == "TRUE" ]]; then
  echo "INFO [${NAME}]: Starting to calculate initial size of remote directory @ $(date) ... " 2>&1 | tee -a ${LOG}
  SIZEBEFOREORIG=$(timeout 2h rclone --config ${RCLONECONFIG} ${FILTER} --fast-list size ${BACKUPDIR})
  SIZEBEFORE=$(echo "${SIZEBEFOREORIG}" | awk -F\( '{print $2}' | awk -F"byte|Byte" '{ print $1 }' | tail -1)
  echo "INFO [${NAME}]: Size of remote directory before rclone: ${SIZEBEFORE}" 2>&1 | tee -a ${LOG}
else
  echo "INFO [${NAME}]: Not performing any size checks" 2>&1 | tee -a ${LOG}
fi
echo " " 2>&1 | tee -a ${LOG}

# 2022/2/12: Copy links as .rclonelink to avoid dangling links
OPTIONS="--config ${RCLONECONFIG} -P --stats 1m -l --fast-list --transfers=2 --check-first --backup-dir ${BACKUPDIFFDIR} ${FILTER} ${EXCLUDE} sync ${RAIDDIR} ${BACKUPDIR}"
# 2024/6/20: Wasabi transfer speed up
OPTIONS="--config ${RCLONECONFIG} -P --stats 1m -l --fast-list --transfers=32 --checkers=32 --backup-dir ${BACKUPDIFFDIR} ${FILTER} ${EXCLUDE} sync ${RAIDDIR} ${BACKUPDIR}"
# Limit server side copy size:
OPTIONS="--config ${RCLONECONFIG} -P --stats 1m -l --fast-list --transfers=32 --checkers=32 --s3-copy-cutoff 2000M --backup-dir ${BACKUPDIFFDIR} ${FILTER} ${EXCLUDE} sync ${RAIDDIR} ${BACKUPDIR}"
if [[ ${VERBOSE} == "FALSE" ]]; then
  OPTIONS="--stats-one-line ${OPTIONS}"
fi
echo "INFO [${NAME}]: rclone options: ${OPTIONS}" 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}

#time rclone --dry-run ${OPTIONS} 2>&1 | tee -a ${LOG}

echo "INFO [${NAME}]: Starting rclone @ $(date) ... " 2>&1 | tee -a ${LOG}
RCLONEOUTPUT=$(timeout ${TIMEOUT}h rclone ${OPTIONS} 2>&1 | tee -a ${LOG})
RCLONEEXITCODE=$?

echo "INFO [${NAME}]: rclone exited with code ${RCLONEEXITCODE} @ $(date)" 2>&1 | tee -a ${LOG}
echo " " 2>&1 | tee -a ${LOG}

# Do some error processing
if [[ ${RCLONEEXITCODE} != 0 ]]; then
  echo "ERROR [${NAME}]: rclone exited with non-zero code ${RCLONEEXITCODE}" 2>&1 | tee -a ${LOG}
fi
if [[ ${RCLONEOUTPUT} == *"Failed to copy"* ]]; then
  echo "ERROR [${NAME}]: Some files failed to copy" 2>&1 | tee -a ${LOG}
fi


echo "INFO [${NAME}]: Checking for duplicates  @ $(date) ... " 2>&1 | tee -a ${LOG}
if grep -q "Duplicate object found" ${LOG}; then
  echo "INFO [${NAME}]: Duplicates found and keeping only newest... " 2>&1 | tee -a ${LOG}
  timeout 6h rclone --config ${RCLONECONFIG} -L --fast-list dedupe --dedupe-mode newest ${BACKUPDIR} 2>&1 | tee -a ${LOG}
fi
echo " " 2>&1 | tee -a ${LOG}


if [[ ${SIZECHECK} == "TRUE" ]]; then
  echo "INFO [${NAME}]: Starting to calculate final size of remote directory @ $(date) ... " 2>&1 | tee -a ${LOG}
  SIZEAFTERORIG=$(timeout 2h rclone --config ${RCLONECONFIG} ${FILTER} --fast-list size ${BACKUPDIR} 2>&1)

  echo "INFO [${NAME}]: Unformatted size output: ${SIZEAFTERORIG}" 2>&1 | tee -a ${LOG}
  SIZEAFTER=$(echo "${SIZEAFTERORIG}" | awk -F\( '{print $2}' | awk -F"byte|Byte" '{ print $1 }' | tail -1)
  echo "INFO [${NAME}]: Size of remote directory after rclone: ${SIZEAFTER}" 2>&1 | tee -a ${LOG}
  DIFFERENCE=$(echo "${SIZEAFTER} ${SIZEBEFORE}" | awk '{ byte =($1 - $2)/1024/1024/1024; print byte " GB" }')
  echo "INFO [${NAME}]: Size difference: ${DIFFERENCE}" 2>&1 | tee -a ${LOG}

  echo "INFO [${NAME}]: Checking used local space again for comparison @ $(date) ... " 2>&1 | tee -a ${LOG}
  echo "INFO [${NAME}]: $(du -s -B1 ${RAIDDIR}/.)" 2>&1 | tee -a ${LOG}
fi


echo " " 2>&1 | tee -a ${LOG}
echo "INFO [${NAME}]: Checking to cleanup old diffs @$(date) ... " 2>&1 | tee -a ${LOG}

LIST=$(rclone --config ${RCLONECONFIG} lsd ${BACKUPBASE}: 2>&1)
DIRS=$(echo "${LIST}" | awk '{ print $5 }')

TOBEDELETED=""
NINETYDAYSAGO=$(date --date="90 days ago" +%s)
for D in ${DIRS}; do
  echo "${D}" 2>&1 | tee -a ${LOG}
  if [[ ${D} == latest-diff-* ]]; then
    TESTDATE=$(date --date="$(echo "${D}" | awk -F'[-]'  '{ printf "%s-%s-%s %s:%s:%s", $3, $4, $5, $7, $8, $9 }')" +%s)
    if (( ${TESTDATE} < ${NINETYDAYSAGO} )); then
      TOBEDELETED+="${D} "
    fi
  fi
done


for D in ${TOBEDELETED}; do
  echo "INFO [${NAME}]: Deleting ${D} ... " 2>&1 | tee -a ${LOG}
  rclone --config ${RCLONECONFIG} purge ${BACKUPBASE}:${D} 2>&1 | tee -a ${LOG}
done

echo " " 2>&1 | tee -a ${LOG}
echo "INFO [${NAME}]: Done @ $(date)! " 2>&1 | tee -a ${LOG}

exit 0

