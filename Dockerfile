FROM ubuntu
RUN apt update
RUN apt install -y curl exiftool inotify-tools file
VOLUME /source
VOLUME /destination
ENV NTFY_URL=
ENV NTFY_TOKEN=
COPY . .
ENTRYPOINT bash ./mediaDateStandardizeCopyLoop.sh /source /destination

# docker build -t media-date-standardize-copy-loop .
# docker run -v ~/Pictures:/source -v ~/Downloads:/destination --user 1000 \
#   -e NTFY_URL="https://ntfy.sh/topic" -e NTFY_TOKEN="ntfy_token" \
#   media-date-standardize-copy-loop
# docker tag media-date-standardize-copy-loop imranrdev/media-date-standardize-copy-loop