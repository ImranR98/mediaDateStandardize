#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"/lib.sh

usage() {
    echo >&2 "Usage: $(basename $0) [-d] [path to source directory] [path to destination directory]"
    echo >&2 "Uses ExifTool to process all files in a specified directory in the following way:"
    echo >&2 "  - First, pick a date from the file's metadata. If it has a DateTimeOriginal, use that, otherwise use the oldest available date."
    echo >&2 "  - All other dates in the file's metadata are set to the chosen value."
    echo >&2 "  - The file is renamed, based on the chosen date, to the following standard format: YYYY-MM-DD-HH-MM-SS-(<original-name>).ext"
    echo >&2 "  - Copy the renamed file to a destination directory"
    echo >&2 "This is done whenever files in the dir change. Files that were already processed are left intact, and files that cannot be processed are moved to a subdirectory."
    echo >&2 "If a file could not be processed and the NTFY_URL (with an optional NTFY_TOKEN) environment variable exists, a ntfy.sh notification is triggered."
    echo >&2 ""
    echo >&2 "      -d              If this option is set, processed files are deleted from the original directory after a 60 minute wait."
    echo >&2 ""
}

# Decide whether to delete standardized files based on whether the -d option is set
DELETE=false
while getopts "d" opt; do
    case $opt in
    d) DELETE=true ;;
    \?) usage && exit 1 ;;
    esac
done
shift $((OPTIND - 1))

if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    usage
    log "One or both directory arguments is invalid" 1 1
fi

errorNotif() {
    log "$1" 1
    if [ -n "$NTFY_URL" ]; then
        curlFn="curl -s -H \"Title: Exif Standardize Error\" -d \""$1"\""
        if [ -n "$NTFY_TOKEN" ]; then
            curlFn=""$curlFn" -u :"$NTFY_TOKEN""
        fi
        curlFn=""$curlFn" "$NTFY_URL""
        eval "$curlFn"
    fi
}

while [ true ]; do
    timeout --foreground 300 inotifywait -qq -e modify,create,delete "$1"
    sleep 1
    readarray -t files < <(find "$1" -maxdepth 1 -type f)
    for file in "${files[@]}"; do
        FILE_NAME="$(basename "$file")"
        if [ "$(isLikelyStandardString "$FILE_NAME")" == false ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.pending.+')" ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.syncthing.+')" ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.stfolder$')" ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.stignore$')" ]; then
            mkdir -p "$1"/FAILED_ITEMS
            STD_OUTPUT="$(standardize "$file")"
            NEW_PATH="$(echo "$STD_OUTPUT" | grep -E '^Renamed to ' | tail -c +12)"
            if [ -z "$NEW_PATH" ]; then
                errorNotif "Failed to standardize ""$file"""
                mv "$file" "$1"/FAILED_ITEMS/"$FILE_NAME"
                continue
            fi
            NEW_NAME="$(basename "$NEW_PATH")"
            cp "$NEW_PATH" "$2"/"$NEW_NAME"
            if [ "$(sha256sum "$NEW_PATH" | awk '{print $1}')" == "$(sha256sum "$2"/"$NEW_NAME" | awk '{print $1}')" ]; then
                log "Standardized "$file""
                if [ "$DELETE" == true ]; then
                    (sleep 3600 && rm "$NEW_PATH") &
                fi
            else
                errorNotif "Failed to copy ""$file"""
                mv "$NEW_PATH" "$1"/FAILED_ITEMS/"$NEW_NAME"
            fi
        fi
    done
done
