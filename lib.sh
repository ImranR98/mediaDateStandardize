#!/usr/bin/bash

# Note: Most of these do not validate their arguments

# Log function - Prints the provided string (not validated) with a log level and date prefix.
# If $2 is 1, redirects to stderr with a 'WARN' prefix. If $3 is 1, redirects to stderr with an 'ERRR' prefix and exits with code 1
log() {
    if [ "$2" == 1 ] && [ "$3" == 1 ]; then
        echo -e "ERRR: $(date): "$1"" >&2
        exit 1
    elif [ "$2" == 1 ]; then
        echo -e "WARN: $(date): "$1"" >&2
    else
        echo -e "INFO: $(date): "$1""
    fi
}

# Takes any number of arguments and ensures they are all available as commands on the system
ensureCommands() {
    COMMS=("$@")
    for COMM in "${COMMS[@]}"; do
        if [ -z "$(which $COMM)" ]; then
            log 'The following command is not available: '"$COMM" 1 1
        fi
    done
}

# Takes 2 arguments (neither validated): A path to a directory and a command string
# Then runs the command for each file in the directory (passing the file path as an argument)
# Commands are run in parallel based on the available number of CPU cores
processFilesInDirInParallel() {
    COMMAND="$2"

    # Get real path of target directory
    TARGET_DIR="$(realpath "$1")"

    # Number of CPU cores is used to split task into that many processes
    NUMBER_SPLITS="$(grep -c ^processor /proc/cpuinfo)"

    # Grab the list of files in the target directory
    FILES="$(find "$TARGET_DIR" -type f)"

    # Work out number of files to be processed by each task
    NUM_FILES="$(echo "$FILES" | wc -l)"
    ((NUM_FILES_PER_TASK = (NUM_FILES + NUMBER_SPLITS - 1) / NUMBER_SPLITS))

    # Split the data and store results in separate files in a temporary directory
    TEMP_DIR=$(mktemp -d)
    CURRENT_DIR=$(cd $(dirname "${BASH_SOURCE[0]}") >/dev/null 2>&1 && pwd)
    cd ${TEMP_DIR}
    echo "$FILES" | split --lines=${NUM_FILES_PER_TASK}
    cd ${CURRENT_DIR}

    # Define a nested function to process the file lists
    processFilesInListSequentially() {
        OLDIFS="$IFS"
        IFS=$'\n'
        read -d '\n' -a FILES <"$1"
        IFS="$OLDIFS"
        for file in "${FILES[@]}"; do
            eval ""$2" '"$file"'"
        done
    }

    # Process each file list in the temporary directory in a new process
    for file in "$TEMP_DIR"/*; do
        processFilesInListSequentially "$file" "$COMMAND" &
    done
    # Wait for all processing to end, then clean up the temp. dir.
    wait
    rm -r "$TEMP_DIR"
}

# Takes a file path (not validated) and uses ExifTool to return a datetime string for the file - either its DateTimeOriginal or, if that is unavailable, the oldest date found in the metadata
findRealExifDate() {
    FILE="$1"
    # Figure out what date to use (valid DateTimeOriginal if available, else the oldest valid date available)
    DATE_TO_USE=''
    DTO="$(exiftool -m -q "$FILE" -datetimeoriginal -api LargeFileSupport=1 | awk -F ': ' '{print $2}' | grep -v 0000 | grep -v -e "[0-9][0-9][0-9][0-9]:[0-9][0-9]$")"           # DateTimeOriginal
    OD="$(exiftool -m -q "$FILE" -api LargeFileSupport=1 | grep Date | grep -v 0000 | grep -v -e "[0-9][0-9][0-9][0-9]:[0-9][0-9]$" | awk -F ': ' '{print $2}' | sort | head -1)" # Oldest date
    # if [ ! -z "$(echo "$DTO" | grep -e "^0000")" ] || [ ! -z "$(echo "$DTO" | grep -e "[0-9][0-9][0-9][0-9]:[0-9][0-9]$")" ]; then DTO=''; fi
    # if [ ! -z "$(echo "$OD" | grep -e "^0000")" ] || [ ! -z "$(echo "$OD" | grep -e "[0-9][0-9][0-9][0-9]:[0-9][0-9]$")" ]; then OD=''; fi
    if [ ! -z "$DTO" ]; then
        DATE_TO_USE="$DTO"
    elif [ ! -z "$OD" ]; then
        DATE_TO_USE="$OD"
    fi
    # Print the date found (or nothing)
    echo "$DATE_TO_USE"
}

# Takes 2 arguments (neither validated): A path to a file and an ExifTool datetime string
# Uses ExifTool to change all dates in the file's metadata to the provided value
setExifDates() {
    # If, for some reason, the time is missing, add a time of 12 AM
    DATA="$2"
    if [ "$(echo "$DATA" | awk -F ':' '{print NF}')" == 3 ]; then
        DATA="$DATA"' 00:00:00'
    fi
    exiftool -m -q "-DateTimeOriginal = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-CreateDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-MediaCreateDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-TrackCreateDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    # exiftool -m -q "-FileCreateDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1 # Win/Mac only
    exiftool -m -q "-ModifyDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-MediaModifyDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-TrackModifyDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-FileModifyDate = ${DATA}" "${1}" -overwrite_original -api LargeFileSupport=1
}

# Takes a path to a file (not validated), uses ExifTool to find the file's DateTimeOriginal tag, and renames the file accordingly (leaving the original name in appended brackets)
# For MP4 files following a specific naming format, the MediaCreateDate is used instead (workaround for videos from Pixel phones)
# If no date is found, the file is skipped (warning shown)
renameFileByDateTimeOriginal() {
    DATE="$(exiftool -m -q "$1" -datetimeoriginal -api LargeFileSupport=1 | awk -F ': ' '{print $2}' | tr ': ' - | head -c 19)"
    NAM="$(basename "$1")"
    if [ -z "$DATE" ] && [ ! -z "$(echo "$NAM" | grep -e '^PXL_' | grep -ie '\.mp4$')" ]; then
        DATE="$(exiftool -m -q "$1" -mediacreatedate -api LargeFileSupport=1 | awk -F ': ' '{print $2}' | tr ': ' - | head -c 19)" # Pixel exception workaround
    fi
    if [ ! -z "$DATE" ]; then
        DIR="$(dirname "$1")"
        EXT="${NAM##*.}"
        NAM="${NAM%.*}"
        FINAL_NAME="$DIR"/"$DATE-(""$NAM"").$EXT"
        mv "$1" "$DIR"/"$DATE-(""$NAM"").$EXT"
        echo Renamed to "$FINAL_NAME"
    else
        log 'File not renamed: '"$1" 1
    fi
}

# Takes a string (presumably a file name) and outputs true or false depending on whether the string seems to be a standardized file name
isLikelyStandardString() {
    if [ -n "$(echo "$1" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-\(.+')" ]; then
        echo true
    else
        echo false
    fi
}

isFileMedia() {
    type="$(file -b --mime-type "$1")"
    if [[ "$type" =~ ^(image|video|audio)/ ]] || [[ "$type" == "application/octet-stream" ]]; then
        echo true
    else
        echo false
    fi
}

# Define the function to run on the batch of target files
standardize() {
    if [ "$(isFileMedia "$1")" == false ]; then
        log 'File is not a media file: '"$1" 1
    else
        DATE="$(findRealExifDate "$1")"
        if [ -z "$DATE" ]; then
            log 'No date found for file: '"$1" 1
        else
            setExifDates "$1" "$DATE"
            renameFileByDateTimeOriginal "$1"
        fi
    fi
}

# Run the standardize function, but first change the file Exif dates according to the file name first
standardizeWithFName() {
    exiftool -m -q "-FileName > DateTimeOriginal" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-FileName > CreateDate" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-FileName > MediaCreateDate" "${1}" -overwrite_original -api LargeFileSupport=1
    exiftool -m -q "-FileName > TrackCreateDate" "${1}" -overwrite_original -api LargeFileSupport=1
    standardize "$1"
}
