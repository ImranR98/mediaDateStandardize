# Media Date Standardize

Shell scripts that use [ExifTool](https://exiftool.org/) to "standardize" the Exif dates and file names of all media files (images, videos, and audio) in a directory. This means doing the following:
1. Finding the `DateTimeOriginal` of the file or, if that does not exist, the oldest available Exif date.
2. Changing all Exif dates to that date.
3. Renaming the file to the following format: `YYYY-MM-DD-HH-MM-SS-(<original-name>).ext`

2 main scripts:
- `mediaDateStandardize.sh` to standardize the files in a directory.
- `mediaDateStandardizeCopyLoop.sh` to continuously standardize files in a directory and copy the standardized versions to a destination directory.
  - This can optionally notify the user via [ntfy.sh](https://ntfy.sh/) when there is a failure to standardize a file.
  - It can also optionally delete the files from the original directory.
  - A Dockerfile is provided for simple deployment of this script.