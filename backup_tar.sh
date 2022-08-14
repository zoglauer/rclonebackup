#!/bin/bash


PROGRAMNAME="backup_tar.sh"

echo ""
echo "INFO: Launching tar-based backup"

help() {
  echo ""
  echo "${PROGRAMNAME}"
  echo "Copyright by Andreas Zoglauer"
  echo ""
  echo "Usage: bash ${PROGRAMNAME} [options]";
  echo ""
  echo "Options:"
  echo "  --prefix=[name]: The prefix for the backup file name (default: Backup)"
  echo "  --folder=[name]: The directory which to backup"
  echo "  --archive=[name]: The directory where to store the backup"
  echo "  --rotations=[number]: The number of rotations to keep (minimum 2, default 2)"
  echo "  --diffs=[number]: The number of diffs to keep (minimum 2, default 5)"
  echo "  --maxratio=[percent]: The maximum size in percent a diff can have compared to the latest rotation, before we start a new rotation (minium 5, maximum 50, default 10)"
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
ARCHIVE="NONE____NONE"
ROTATIONS=2
DIFFS=5
MAXRATIO=5
AGELIMIT=90 # days

# Overwrite default options with user options:
for C in "${CMD[@]}"; do
  if [[ ${C} == *-f*=* ]]; then
    FOLDER=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-p*=* ]]; then
    BACKUPPREFIX=`echo ${C} | awk -F"=" '{ print $2 }'`
  elif [[ ${C} == *-a*=* ]]; then
    ARCHIVE=`echo ${C} | awk -F"=" '{ print $2 }'`
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
echo "INFO: Using this file name prefix:                                ${BACKUPPREFIX}" 
echo "INFO: Using this folder:                                          ${FOLDER}" 
echo "INFO: Using this archive directory:                               ${ARCHIVE}"
echo "INFO: Using this number of rotations:                             ${ROTATIONS}"
echo "INFO: Using this number of diffs:                                 ${DIFFS}"
echo "INFO: Using this maximum ratio between diff and rotation size:    ${MAXRATIO}"
echo "INFO: Using this age limit of rotations:                          ${AGELIMIT}"
echo ""

# For testing create a new file in the folder
#mktemp -p ${FOLDER}

# Now do the actual backup
BACKUPPREFIX=${ARCHIVE}/${BACKUPPREFIX}

echo "INFO: Switching to directory ${FOLDER}"
echo ""
cd ${FOLDER}

# Find the highest rotation
MAXROTATION="0"
for F in `ls ${BACKUPPREFIX}.rot*.tar.gz 2>/dev/null`; do
  R=$(echo $F | awk -F".rot" '{ print $2 }' | awk -F"." '{print $1 }' )
  if [[ ${R} =~ $re ]] ; then
    if [[ ${R} -gt ${MAXROTATION} ]]; then
      MAXROTATION=${R}
    fi
  fi
done
echo "INFO: Found maximum rotation:   ${MAXROTATION}"


# Find the highest diff
MAXDIFF="0"
for F in `ls ${BACKUPPREFIX}.rot${MAXROTATION}.diff*.tar.gz 2>/dev/null`; do
  D=$(echo $F | awk -F".diff" '{ print $2 }' | awk -F"." '{print $1 }' )
  if [[ ${D} =~ $re ]] ; then
    if [[ ${D} -gt ${MAXDIFF} ]]; then
      MAXDIFF=${D}
    fi
  fi
done
echo "INFO: Found maximum diff:       ${MAXDIFF}"



# Calculate the file size difference between the rotation and the highest diff
RATIO=0
if [ ${MAXDIFF} -ge 1 ]; then
  SIZEROT=$(stat --printf="%s" ${BACKUPPREFIX}.rot${MAXROTATION}.tar.gz)
  SIZEDIFF=$(stat --printf="%s" ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz)
  RATIO=$(echo "100.0 * ${SIZEDIFF} / ${SIZEROT}" | bc )
  echo "INFO: Size rotation:            ${SIZEROT}"
  echo "INFO: Size maximum diff:        ${SIZEDIFF}"
  echo "INFO: Found ratio diff/rot:     ${RATIO}"
fi


# Calculate the age of the rotation
AGE=0
if [ ${MAXROTATION} -ge 1 ]; then
  AGE=$((($(date +%s) - $(date +%s -r "${BACKUPPREFIX}.rot${MAXROTATION}.tar.gz")) / 86400))
  echo "INFO: Found rotation age:       ${AGE}"
fi
echo ""


# Find recently changed virtualbox files:
EXCLUDE=""
MAXTIME=300

readarray -t files <<<"$( find "${FOLDER}" -type f -name '*.vdi' -exec realpath --relative-to "${FOLDER}" {} \; )"

if [ ${#files[@]} -gt 0 ]; then
  if [[ ${files[0]} != "" ]]; then  # no file found fills first with empty  
    for file in "${files[@]}"; do 
      if [ $(expr $(date +%s) - $( stat "${FOLDER}/${file}" -c %Y ) ) -le ${MAXTIME} ]; then 
        echo "WARNING: This file is open and will likely not be stored correctly: ${FOLDER}/${file}"; EXCLUDE=" --exclude='${file}'"; 
      fi; 
    done;
  fi
fi


# We create a new rotation when there is none, or if we have exceeded or maximum number of diffs, or if the rotation is older than 14 days 
NEEDROTATION="FALSE"
if [ ${MAXROTATION} -eq 0 ]; then
  echo "INFO: Require new rotation since there is none."
  NEEDROTATION="TRUE"
elif [ ${RATIO} -gt ${MAXRATIO} ]; then
  echo "INFO: Require new rotation since the file size ratio is larger than the threshold"
  NEEDROTATION="TRUE"
elif [ ${MAXDIFF} -ge 100 ]; then
  echo "INFO: Require new rotation since we exceeded the maximum number of allowed diffs"
  NEEDROTATION="TRUE"
elif [ ${AGE} -gt ${AGELIMIT} ]; then
  echo "INFO: Require new rotation since the main rotation is more than ${AGELIMIT} days old"
  NEEDROTATION="TRUE"
fi


TARERROR="FALSE"
if [[ ${NEEDROTATION} == "TRUE" ]]; then

  MAXROTATION=$(( MAXROTATION + 1 ))
  
  echo ""
  echo "INFO: Creating new rotation with ID ${MAXROTATION}"
 

  #COMMAND="tar ${EXCLUDE} --listed-incremental=${BACKUPPREFIX}.rot${MAXROTATION}.log --use-compress-program='pigz --best --recursive' -cf ${BACKUPPREFIX}.rot${MAXROTATION}.tar.gz ${EXCLUDE} ."
  COMMAND="tar --listed-incremental=${BACKUPPREFIX}.rot${MAXROTATION}.log --use-compress-program=pigz -cf ${BACKUPPREFIX}.rot${MAXROTATION}.tar.gz ."
  echo " "
  echo "INFO: Executing: ${COMMAND}"
  echo ""
  ANSWER=$(${COMMAND} 2>&1)
  
  if [[ $? -eq 0 ]]; then
    TARERROR="FALSE"
    echo "INFO: Success"
    echo "" 
  elif [[ $? -eq 1 ]]; then
    TARERROR="FALSE"
    echo "WARNING: Some files changed during tar creation, those will be in undetermined state."
    echo ""
    echo "--- tar output ---"
    echo "${ANSWER}"
    echo "------------------"
    echo ""
  else
    TARERROR="TRUE"
    echo "ERROR: tar exited with an error code -- not deleting anything"
    echo ""
    echo "--- tar output ---"
    echo "${ANSWER}"
    echo "------------------"
    echo ""
  fi

else
# We create a new diff
  LASTMAXDIFF=${MAXDIFF}
  MAXDIFF=$(( MAXDIFF + 1 ))
  
  echo ""
  echo "INFO: Creating new diff ID ${MAXDIFF} for rotation ${MAXROTATION}"

  cp ${BACKUPPREFIX}.rot${MAXROTATION}.log ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.log
  
  COMMAND="tar --listed-incremental=${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.log --use-compress-program=pigz -cf ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz ."
  echo " "
  echo "INFO: Executing: ${COMMAND}"
  echo ""
  ANSWER=$(${COMMAND} 2>&1)
  
  if [[ $? -eq 0 ]]; then
    TARERROR="FALSE"
    echo "INFO: Success"
    echo "" 
  elif [[ $? -eq 1 ]]; then
    TARERROR="FALSE"
    echo "WARNING: Some files changed during tar creation, those will be in undetermined state."
    echo ""
    echo "--- tar output ---"
    echo "${ANSWER}"
    echo "------------------"
    echo ""
  else
    TARERROR="TRUE"
    echo "ERROR: tar exited with an error code -- not deleting anything"
    echo ""
    echo "--- tar output ---"
    echo "${ANSWER}"
    echo "------------------"
    echo ""
  fi
    
  # Check if there is a change
  if [ ${MAXDIFF} -ge 2 ]; then
    echo "INFO: Checking if there is a difference to the previous diff"
    MD5OLD=$(tar tfz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${LASTMAXDIFF}.tar.gz | md5sum)
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Unable to calculate checksum for ${BACKUPPREFIX}.rot${MAXROTATION}.diff${LASTMAXDIFF}.tar.gz"
    fi
    MD5NEW=$(tar tfz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz | md5sum)
    if [[ $? -ne 0 ]]; then
      echo "ERROR: Unable to calculate checksum for ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz"
    fi
        
    if [[ ${MD5OLD} == ${MD5NEW} ]]; then
      echo "INFO: No change from previous diff ID ${LASTMAXDIFF}. Removing the new diff ID ${MAXDIFF}"
      rm ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.tar.gz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${MAXDIFF}.log
      MAXDIFF=${LASTMAXDIFF}
    fi
  fi
  
fi

# Check for deletes:
if [[ ${TARERROR} == "FALSE" ]]; then
  # Delete everything before the minimum rotation
  echo "INFO: Checking if we can delete old rotations"
  MINROTATION=$(( MAXROTATION - ROTATIONS ))
  for F in `ls ${BACKUPPREFIX}.*`; do
    R=$(echo $F | awk -F".rot" '{ print $2 }' | awk -F"." '{print $1 }' )
    if [[ ${R} =~ $re ]] ; then
      if [[ ${R} -le ${MINROTATION} ]]; then
        echo "INFO: Removing rotation ${F}"
        rm ${F}
      fi
    fi
  done
  
  # Delete too old diffs
  echo "INFO: Checking if we can delete old diffs"
  if [ ${MAXDIFF} -gt ${DIFFS} ]; then
    MINDIFF=$(( MAXDIFF - DIFFS + 1 ))
    for F in `ls ${BACKUPPREFIX}.rot${MAXROTATION}.diff*.log 2>/dev/null`; do
      D=$(echo $F | awk -F".diff" '{ print $2 }' | awk -F"." '{print $1 }' )
      if [[ ${D} =~ $re ]] ; then
        if [[ ${D} -lt ${MINDIFF} ]]; then
          echo "INFO: Removing diff ${BACKUPPREFIX}.rot${MAXROTATION}.diff${D}"
          rm ${BACKUPPREFIX}.rot${MAXROTATION}.diff${D}.tar.gz ${BACKUPPREFIX}.rot${MAXROTATION}.diff${D}.log
        fi
      fi
    done
  fi  
else 
  echo "WARNING: Not deleting any files due to errors during tar"
fi

echo ""
echo "INFO: DONE"
echo ""
echo ""


