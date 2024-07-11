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
  if [[ ${C} == *-h* ]]; then
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
  if [[ ${C} == *-f*=* ]]; then
    FOLDER=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-a*=* ]]; then
    ARCHIVE=`echo ${C} | awk -F"=" '{ print $2 }'`
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

# Sanity checks

if [[ ${FOLDER} == "NONE____NONE" ]]; then
  echo ""
  echo "ERROR: You need to give a folder to backup"
  echo ""
  exit 1
fi

FOLDER="${FOLDER/#\~/$HOME}"
FOLDER=$(realpath ${FOLDER})
if [[ ! -d ${FOLDER} ]]; then
  echo ""
  echo "ERROR: The directory to backup does not exist: ${FOLDER}"
  echo ""
  exit 1
fi

if [[ ${ARCHIVE} == "NONE____NONE" ]]; then
  echo ""
  echo "ERROR: You need to give a ARCHIVE directory where to store the backup"
  echo ""
  exit 1
fi

ARCHIVE="${ARCHIVE/#\~/$HOME}"
ARCHIVE=$(realpath ${ARCHIVE})
if [[ ! -d ${ARCHIVE} ]]; then
  echo ""
  echo "ERROR: The directory where to store the backup does not exist: ${ARCHIVE}"
  echo ""
  exit 1
fi

if [[ ${ARCHIVE} == ${FOLDER}* ]]; then
  echo ""
  echo "ERROR: The ARCHIVE directory cannot be in the path of the folder directory"
  echo ""
  exit 1
fi

echo ""
echo "INFO: Using this folder:                                          ${FOLDER}" 
echo "INFO: Using this archive directory:                               ${ARCHIVE}"

# For testing create a new file in the folder
#mktemp -p ${FOLDER}

# Now do the actual backup
BACKUPPREFIX=${ARCHIVE}/${BACKUPPREFIX}

echo "INFO: Switching to directory ${FOLDER}"
cd ${FOLDER}

echo "INFO: Starting rsync"
#rsync -ah --delete --info=progress2 ${FOLDER}/ ${ARCHIVE}/
rsync -ah --delete  --exclude=".cache" --exclude=".gvfs" --exclude=".local/share/Trash" --exclude=".thumbnails" ${FOLDER} ${ARCHIVE}/

echo "INFO: DONE"
echo ""
echo ""


