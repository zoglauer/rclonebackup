#!/bin/bash


PROGRAMNAME="backup_tar.sh"

echo ""
echo "Launching ${PROGRAMNAME}"

help() {
  echo ""
  echo "${PROGRAMNAME}"
  echo "Copyright by Andreas Zoglauer"
  echo ""
  echo "Usage: bash ${PROGRAMNAME} [options]";
  echo ""
  echo "Options:"
  echo "  --prefix=[name]: The prefix for the backup file name (default: Backup)"
  echo "  --folder=[name]: The name of the directory to backup"
  echo "  --target=[name]: The distination where to store the backup"
  echo "  --rotations=[number]: The number of rotations to keep (minimum 2, default 2)"
  echo "  --diffs=[number]: The number of diffs to keep (minimum 2, default 5)"
  echo "  --maxratio=[percent]: The maximum size in percent a diff can of a rotation, before we start a new rotation (minium 5, maximum 50, default 10)"
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
BACKUPPREFIX="Backup"
FOLDER="NONE____NONE"
TARGET="NONE____NONE"
ROTATIONS=2
DIFFS=5
MAXRATIO=10

# Overwrite default options with user options:
for C in "${CMD[@]}"; do
  if [[ ${C} == *-f*=* ]]; then
    FOLDER=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-p*=* ]]; then
    BACKUPPREFIX=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-t*=* ]]; then
    TARGET=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-r*=* ]]; then
    ROTATIONS=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-d*=* ]]; then
    DIFFS=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-m*=* ]]; then
    MAXRATIO=`echo ${C} | awk -F"=" '{ print $2 }'`
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

type pigz >/dev/null 2>&1
if [ $? -ne 0 ]; then
  echo ""
  echo "ERROR: pigz must be installed"
  echo ""
  exit 1
fi 

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

if [[ ${TARGET} == "NONE____NONE" ]]; then
  echo ""
  echo "ERROR: You need to give a target directory where to store the backup"
  echo ""
  exit 1
fi

TARGET="${TARGET/#\~/$HOME}"
TARGET=$(realpath ${TARGET})
if [[ ! -d ${TARGET} ]]; then
  echo ""
  echo "ERROR: The directory where to store the backup does not exist: ${TARGET}"
  echo ""
  exit 1
fi

if [[ ${TARGET} == ${FOLDER}* ]]; then
  echo ""
  echo "ERROR: The target directory cannot be in the path of the folder directory"
  echo ""
  exit 1
fi

re='^[+-]?[0-9]+([.][0-9]+)?$'
if ! [[ ${ROTATIONS} =~ $re ]] ; then
  echo ""
  echo "ERROR: The given rotations are not a number: ${ROTATIONS}"
  echo ""
  exit 1
fi

if [[ ${ROTATIONS} -lt 1 ]]; then
  echo ""
  echo "ERROR: You need at least one rotations and not ${ROTATIONS}"
  echo ""
  exit 1
fi

if ! [[ ${DIFFS} =~ $re ]] ; then
  echo ""
  echo "ERROR: The given number for diffs is not a number: ${DIFFS}"
  echo ""
  exit 1
fi

if [[ ${DIFFS} -lt 2 ]]; then
  echo ""
  echo "ERROR: You need at least two diffs and not ${DIFFS}"
  echo ""
  exit 1
fi

if ! [[ ${MAXRATIO} =~ $re ]] ; then
  echo ""
  echo "ERROR: The given number for the maximum diff size is not a number: ${MAXRATIO}"
  echo ""
  exit 1
fi

if [[ ${MAXRATIO} -lt 5 ]]; then
  echo ""
  echo "ERROR: The maximum diff size should be at least 5% and not ${MAXRATIO}"
  echo ""
  exit 1
fi

if [[ ${MAXRATIO} -gt 50 ]]; then
  echo ""
  echo "ERROR: The maximum diff size should be not larger than 50% and not ${MAXRATIO}"
  echo ""
  exit 1
fi

echo ""
echo "Using this file name prefix:                                ${BACKUPPREFIX}" 
echo "Using this folder:                                          ${FOLDER}" 
echo "Using this target directory:                                ${TARGET}"
echo "Using this number of rotations:                             ${ROTATIONS}"
echo "Using this number of diffs:                                 ${DIFFS}"
echo "Using this maximum ratio between diff and rotation size:    ${MAXRATIO}"

# For testing create a new file in the folder
#mktemp -p ${FOLDER}

# Now do the actual backup

cd ${TARGET}

# Find the highest rotation
MAXROTATION="0"
for F in `ls ${BACKUPPREFIX}.* 2>/dev/null`; do
  R=$(echo $F | awk -F".rot" '{ print $2 }' | awk -F"." '{print $1 }' )
  if [[ ${R} =~ $re ]] ; then
    if [[ ${R} -gt ${MAXROTATION} ]]; then
      MAXROTATION=${R}
    fi
  fi
done


# Find the highest diff
MAXDIFF="0"
for F in `ls ${BACKUPPREFIX}.rot${MAXROTATION}.* 2>/dev/null`; do
  D=$(echo $F | awk -F".diff" '{ print $2 }' | awk -F"." '{print $1 }' )
  if [[ ${D} =~ $re ]] ; then
    if [[ ${D} -gt ${MAXDIFF} ]]; then
      MAXDIFF=${D}
    fi
  fi
done

echo ""
echo "Found maximum rotation:   ${MAXROTATION}" 
echo "Found maximum diff:       ${MAXDIFF}"

# Calculate the file size difference between the rotation and the highest diff
RATIO=0
if [[ ${MAXDIFF} -ge 1 ]]; then
  SIZEROT=$(stat --printf="%s" ${BACKUPPREFIX}.rot${MAXROTATION}.tar.gz)
  SIZEDIFF=$(stat --printf="%s" ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz)
  RATIO=$(echo "100.0 * ${SIZEDIFF} / ${SIZEROT}" | bc )
fi

# We create a new rotation when there is none, or if we have exceeded or maximum number of diffs 
if [[ ${MAXROTATION} -eq 0 ]] || [[ ${RATIO} -gt ${MAXRATIO} ]]; then

  MAXROTATION=$(( MAXROTATION + 1 ))
  
  echo ""
  echo "Creating new rotation with ID ${MAXROTATION}"
  
  tar --listed-incremental=${BACKUPPREFIX}.rot${MAXROTATION}.log --use-compress-program="pigz --best --recursive" -cf ${BACKUPPREFIX}.rot${MAXROTATION}.tar.gz ${FOLDER}
  
  if [[ $? -ne 0 ]]; then
    echo "ERROR: tar exited with an error code -- not deleting anything"
  else
    # Delete everything before the minimum rotation
    MINROTATION=$(( MAXROTATION - ROTATIONS ))
    for F in `ls ${BACKUPPREFIX}.*`; do
      R=$(echo $F | awk -F".rot" '{ print $2 }' | awk -F"." '{print $1 }' )
      if [[ ${R} =~ $re ]] ; then
        if [[ ${R} -le ${MINROTATION} ]]; then
          rm ${F}
        fi
      fi
    done
  fi

else
# We create a new diff
  LASTMAXDIFF=${MAXDIFF}
  MAXDIFF=$(( MAXDIFF + 1 ))
  
  echo ""
  echo "Creating new diff ID ${MAXDIFF} for rotation ${MAXROTATION}"

  cp ${BACKUPPREFIX}.rot${MAXROTATION}.log ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.log
  tar --listed-incremental=${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.log --use-compress-program="pigz --best --recursive" -cf ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz ${FOLDER}
  
  # Check if there is a change
  if [ ${MAXDIFF} -ge 2 ]; then
    MD5OLD=$(tar tvfz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${LASTMAXDIFF}.tar.gz | md5sum)
    MD5NEW=$(tar tvfz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz | md5sum)
    
    if [[ ${MD5OLD} == ${MD5NEW} ]]; then
      echo "No change from old diff - removing it"
      rm ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.log
      MAXDIFF=${LASTMAXDIFF}
    fi
  fi
  
  # Delete too old diffs
  if [ ${MAXDIFF} -gt ${DIFFS} ]; then
    MINDIFF=$(( MAXDIFF - DIFFS + 1 ))
    for F in `ls ${BACKUPPREFIX}.rot${MAXROTATION}.diff*.log 2>/dev/null`; do
      D=$(echo $F | awk -F".diff" '{ print $2 }' | awk -F"." '{print $1 }' )
      if [[ ${D} =~ $re ]] ; then
        if [[ ${D} -lt ${MINDIFF} ]]; then
          echo "Removing ${BACKUPPREFIX}.rot${MAXROTATION}.diff${D}"
          rm ${BACKUPPREFIX}.rot${MAXROTATION}.diff${D}.tar.gz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${D}.log
        fi
      fi
    done
  fi
fi

echo ""
echo "Done"



