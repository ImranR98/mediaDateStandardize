#!/usr/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"/lib.sh

# ===============
# MediaDateStandardize
# ===============
# Uses ExifTool to process all files in a specified directory in the following way:
# - First, pick a date from the file's metadata. If it has a DateTimeOriginal, use that, otherwise use the oldest available date.
#     - Or use the filename if the user opted to do that.
# - All other dates in the file's metadata are set to the chosen value.
# - The file is renamed, based on the chosen date, to the following standard format: YYYY-MM-DD-HH-MM-SS-(<original-name>).ext
# ===============================================================================================================================

# Usage function
usage() {
    echo >&2 "Usage: $(basename $0) [-n] [path to directory]"
    echo >&2 "Uses ExifTool to process all files in a specified directory in the following way:"
    echo >&2 "  - First, pick a date from the file's metadata. If it has a DateTimeOriginal, use that, otherwise use the oldest available date."
    echo >&2 "  - All other dates in the file's metadata are set to the chosen value."
    echo >&2 "  - The file is renamed, based on the chosen date, to the following standard format: YYYY-MM-DD-HH-MM-SS-(<original-name>).ext"
    echo >&2 ""
    echo >&2 "      -n              If this option is set, a date will be extracted from the file name instead if possible."
    echo >&2 ""
}

# Decide what command to use based on whether the -n option is set
COMMAND="standardize"
while getopts "n" opt; do
    case $opt in
    n) COMMAND="standardizeWithFName" ;;
    \?) usage && exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Validate the arguments
if [ ! $# -eq 1 ]; then
    usage
    log "Incorrect number of arguments" 1 1
fi
if [ ! -d "$1" ]; then
    usage
    log "No valid target directory provided" 1 1
fi

# Ensure ExifTool and FFmpeg are installed
ensureCommands exiftool ffmpeg

# Run the function in parallel on all target files
processFilesInDirInParallel "$1" "$COMMAND"

log "Done!"