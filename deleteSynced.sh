#!/bin/bash

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"/lib.sh

usage() {
    echo >&2 "Usage: $(basename $0) [path to source directory] [path to destination directory]"
    echo >&2 "Deletes all files in the source directory that exist in the destination directory (by file name and hash)."
    echo >&2 ""
}

if [ ! -d "$1" ] || [ ! -d "$2" ]; then
    usage
    log "One or both directory arguments is invalid" 1 1
fi

readarray -t files < <(find "$1" -maxdepth 1 -type f)
for file in "${files[@]}"; do
    NEW_PATH="$2"/"$(basename "$file")"
    if [ -f "$NEW_PATH" ] && [ "$(sha256sum "$NEW_PATH" | awk '{print $1}')" == "$(sha256sum "$file" | awk '{print $1}')" ]; then
        rm "$file"
    fi
done
