#!/bin/bash


PROGRAMNAME="backup_rsync.sh"

echo ""
echo "INFO: Launching rsync-based backup"

help() {
  echo ""
  echo "${PROGRAMNAME}"
  echo "Copyright by Andreas Zoglauer"
  echo ""
  echo "Usage: bash ${PROGRAMNAME} [options]";
  echo ""
  echo "Options:"
  echo "  --folder=[name]: The directory which to backup"
  echo "  --archive=[name]: The directory where to store the backup"
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

# Default options:
FOLDER="NONE____NONE"
ARCHIVE="NONE____NONE"

# Overwrite default options with user options:
for C in "${CMD[@]}"; do
  if [[ ${C} == --folder=* ]] || [[ ${C} == --f=* ]] || [[ ${C} == -f=* ]]; then
    FOLDER="${C#*=}"
  elif [[ ${C} == --archive=* ]] || [[ ${C} == --a=* ]] || [[ ${C} == -a=* ]]; then
    ARCHIVE="${C#*=}"
  elif [[ ${C} == "--help" ]] || [[ ${C} == "-h" ]]; then
    echo ""
    help
    exit 0
  else
    echo ""
    echo "ERROR [backup_rsync]: Unknown command line option: ${C}"
    echo "       See \"${PROGRAMNAME} --help\" for a list of options"
    exit 1
  fi
done

# Sanity checks

if [[ ${FOLDER} == "NONE____NONE" ]]; then
  echo ""
  echo "ERROR [backup_rsync]: You need to give a folder to backup"
  echo ""
  exit 1
fi

FOLDER="${FOLDER/#\~/$HOME}"
FOLDER=$(realpath ${FOLDER})
if [[ ! -d ${FOLDER} ]]; then
  echo ""
  echo "ERROR [backup_rsync]: The directory to backup does not exist: ${FOLDER}"
  echo ""
  exit 1
fi

if [[ ${ARCHIVE} == "NONE____NONE" ]]; then
  echo ""
  echo "ERROR [backup_rsync]: You need to give a ARCHIVE directory where to store the backup"
  echo ""
  exit 1
fi

ARCHIVE="${ARCHIVE/#\~/$HOME}"
ARCHIVE=$(realpath ${ARCHIVE})
if [[ ! -d ${ARCHIVE} ]]; then
  echo ""
  echo "ERROR [backup_rsync]: The directory where to store the backup does not exist: ${ARCHIVE}"
  echo ""
  exit 1
fi

if [[ ${ARCHIVE} == ${FOLDER}* ]]; then
  echo ""
  echo "ERROR [backup_rsync]: The ARCHIVE directory cannot be in the path of the folder directory"
  echo ""
  exit 1
fi

TESTFILE="${ARCHIVE}/.backup_chown_test"
touch "${TESTFILE}" 2>/dev/null
if [[ $? -ne 0 ]]; then
  echo ""
  echo "ERROR [backup_rsync]: Cannot write to the archive directory: ${ARCHIVE}"
  echo ""
  exit 1
fi

chown 12345:12345 "${TESTFILE}" 2>/dev/null
if [[ $? -eq 0 ]]; then
  RSYNCOPTIONS="-ah"
else
  RSYNCOPTIONS="-ah --no-owner --no-group --no-devices --chmod=Du+rwx"
  echo "INFO [backup_rsync]: Archive does not allow preserving ownership and thus data is saved without ownership info"
fi
rm -f "${TESTFILE}"


echo ""
echo "INFO [backup_rsync]: Using this folder: ${FOLDER}" 
echo "INFO [backup_rsync]: Using this archive directory: ${ARCHIVE}"

# Now do the actual backup
echo "INFO [backup_rsync]: Switching to directory ${FOLDER}"
cd ${FOLDER}

echo "INFO [backup_rsync]: Starting rsync and watchdog"
RSYNC_TIMEOUT=600
rsync ${RSYNCOPTIONS} --timeout=${RSYNC_TIMEOUT} --delete  --exclude=".cache" --exclude=".gvfs" --exclude=".local/share/Trash" --exclude=".thumbnails" ${FOLDER} ${ARCHIVE}/ &
RSYNC_PID=$!

# Watchdog: 
IDLE_TIME=0
MAX_IDLE_TIME=600
CHECK_INTERVAL=10
LAST_TOTAL_IO_AMOUNT=""
while kill -0 ${RSYNC_PID} 2>/dev/null; do
  sleep ${CHECKINTERVAL}

  # get all rsync PIDs
  PIDS="${RSYNC_PID}"
  for P in $(pgrep -P ${RSYNC_PID}); do
    PIDS="${PIDS} ${P} $(pgrep -P ${P})"  # child and its children
  done

  TOTAL_IO_AMOUNT=0
  for P in ${PIDS}; do
    IO=$(awk '/^(rchar|wchar):/ { s += $2 } END { print s+0 }' /proc/${P}/io 2>/dev/null)
    if [[ ${IO} != "" ]]; then
      TOTAL_IO_AMOUNT=$(( TOTAL_IO_AMOUNT + IO ))
    fi
  done

  if [[ ${TOTAL_IO_AMOUNT} == "${LAST_TOTAL_IO_AMOUNT}" ]]; then
    IDLE_TIME=$(( IDLE_TIME + CHECK_INTERVAL ))
  else
    IDLE_TIME=0
  fi
  LAST_TOTAL_IO_AMOUNT=${TOTAL_IO_AMOUNT}

  if [[ ${IDLE_TIME} -ge ${MAX_IDLE_TIME} ]]; then
    echo "ERROR [backup_rsync]: rsync did not have any I/O for ${RSYNC_TIMEOUT} seconds and subsequently killed"
    kill -9 ${PIDS} 2>/dev/null
    break
  fi
done

wait ${RSYNC_PID}
RSYNC_STATUS=$?


if [[ ${RSYNC_STATUS} -eq 30 ]]; then
  echo "ERROR [backup_rsync]: rsync had no data transferred for ${MAX_IDLE_TIME} seconds and timed out"
  exit ${RSYNC_STATUS}
fi
if [[ ${RSYNC_STATUS} -eq 137 ]]; then
  echo "ERROR [backup_rsync]: rsync was hanging and killed by the watchdog"
  exit ${RSYNC_STATUS}
fi
if [[ ${RSYNC_STATUS} -ne 0 ]] && [[ ${RSYNC_STATUS} -ne 24 ]]; then
  echo "ERROR [backup_rsync]: rsync failed with exit code ${RSYNCSTATUS}"
  exit ${RSYNC_STATUS}
fi

echo "INFO [backup_rsync]: DONE"
echo ""
echo ""

exit 0

