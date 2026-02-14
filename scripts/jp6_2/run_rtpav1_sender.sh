#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_jp62.sh"

HOST="127.0.0.1"
PORT="5004"
SECONDS="30"
BITRATE="4000000"
WIDTH="1280"
HEIGHT="720"
FPS="30"

usage() {
  cat <<USAGE
Usage: $0 [--host IP] [--port N] [--seconds N] [--bitrate BPS]

Notes:
  --seconds 0 で無期限送信
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --seconds) SECONDS="$2"; shift 2 ;;
    --bitrate) BITRATE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

require_jp62

if ! gst-inspect-1.0 rtpav1pay >/dev/null 2>&1; then
  echo "rtpav1pay not found. Run: source ./scripts/jp6_2/env_rtpav1.sh" >&2
  exit 1
fi

if [[ "$SECONDS" -eq 0 ]]; then
  gst-launch-1.0 -e \
    videotestsrc is-live=true pattern=ball ! \
    "video/x-raw,format=I420,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1" ! \
    nvvidconv ! "video/x-raw(memory:NVMM),format=NV12" ! \
    nvv4l2av1enc bitrate="$BITRATE" iframeinterval=30 idrinterval=30 ! \
    av1parse ! rtpav1pay pt=96 mtu=1200 ! \
    udpsink host="$HOST" port="$PORT" sync=false async=false
else
  NUM_BUFFERS=$((SECONDS * FPS))
  gst-launch-1.0 -e \
    videotestsrc is-live=true num-buffers="$NUM_BUFFERS" pattern=ball ! \
    "video/x-raw,format=I420,width=${WIDTH},height=${HEIGHT},framerate=${FPS}/1" ! \
    nvvidconv ! "video/x-raw(memory:NVMM),format=NV12" ! \
    nvv4l2av1enc bitrate="$BITRATE" iframeinterval=30 idrinterval=30 ! \
    av1parse ! rtpav1pay pt=96 mtu=1200 ! \
    udpsink host="$HOST" port="$PORT" sync=false async=false
fi
