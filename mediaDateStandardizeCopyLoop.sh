#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"/lib.sh

usage() {
    echo >&2 "Usage: $(basename $0) [-d] [path to source directory] [path to destination directory]"
    echo >&2 "Uses ExifTool to process all files in a specified directory in the following way:"
    echo >&2 "  - First, pick a date from the file's metadata. If it has a DateTimeOriginal, use that, otherwise use the oldest available date."
    echo >&2 "  - All other dates in the file's metadata are set to the chosen value."
    echo >&2 "  - The file is renamed, based on the chosen date, to the following standard format: YYYY-MM-DD-HH-MM-SS-(<original-name>).ext"
    echo >&2 "  - Copy the modified file to a destination directory, leaving the original as-is"
    echo >&2 "This is done whenever files in the dir change."
    echo >&2 "If a file could not be processed and the NTFY_URL (with an optional NTFY_TOKEN) environment variable exists, a ntfy.sh notification is triggered."
    echo >&2 ""
    echo >&2 "      -d              If this option is set, processed files are moved instead of copied from the original directory."
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

notif() {
    PRIORITY=default
    if [ "$2" = low ]; then
        PRIORITY=low
    elif [ "$2" = high ]; then
        PRIORITY=high
    fi
    if [ "$PRIORITY" = low ]; then
        log "$1"
    else
        log "$1" 1
    fi
    if [ -n "$NTFY_URL" ]; then
        curlFn="curl -s -H \"Priority: $PRIORITY\" -H \"Title: Exif Standardize\" -d \"$1\""
        if [ -n "$NTFY_TOKEN" ]; then
            curlFn="$curlFn -u :$NTFY_TOKEN"
        fi
        curlFn="$curlFn $NTFY_URL"
        eval "$curlFn"
    fi
}

TEMP_PROCESSING_DIR="$(mktemp -d)"
trap "rm -rf \"$TEMP_PROCESSING_DIR\"" EXIT

while [ true ]; do
    timeout --foreground 300 inotifywait -qq -e modify,create,delete "$1"
    sleep 1
    readarray -t files < <(find "$1" -maxdepth 1 -type f)
    for file in "${files[@]}"; do
        FILE_NAME="$(basename "$file")"
        if [ -n "$(getStandardizedIfExists "$FILE_NAME" "$2")" ]; then
            echo "Already synced: $file"
            continue
        fi
        rsync -t "$file" "$TEMP_PROCESSING_DIR"/
        TEMP_PATH="$TEMP_PROCESSING_DIR"/"$FILE_NAME"
        if [ "$(isLikelyStandardString "$FILE_NAME")" == false ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.pending.+')" ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.syncthing.+')" ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.stfolder$')" ] &&
            [ -z "$(echo "$FILE_NAME" | grep -E '^\.stignore$')" ]; then
            STD_OUTPUT="$(standardize "$TEMP_PATH")"
            NEW_PATH="$(echo "$STD_OUTPUT" | grep -E '^Renamed to ' | tail -c +12)"
            if [ -z "$NEW_PATH" ]; then
                notif "Failed to standardize $FILE_NAME"
                continue
            fi
            NEW_NAME="$(basename "$NEW_PATH")"
            mv "$NEW_PATH" "$2"/"$NEW_NAME"
            if [ "$(sha256sum "$2"/"$NEW_NAME" | awk '{print $1}')" == "$(sha256sum "$2"/"$NEW_NAME" | awk '{print $1}')" ]; then
                notif "Standardized $FILE_NAME" low
                if [ "$DELETE" == true ]; then
                    (rm "$file") &
                fi
            else
                notif "Failed to move $TEMP_PATH to $2." high
            fi
        fi
    done
done
