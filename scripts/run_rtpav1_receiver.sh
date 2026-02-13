#!/usr/bin/env bash
set -euo pipefail

PORT="5004"
OUT="/tmp/rtpav1_rx.av1"
LATENCY="100"
TIMEOUT_SEC="35"

usage() {
  cat <<USAGE
Usage: $0 [--port N] [--out PATH] [--latency MS] [--timeout SEC]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --latency) LATENCY="$2"; shift 2 ;;
    --timeout) TIMEOUT_SEC="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if ! gst-inspect-1.0 rtpav1depay >/dev/null 2>&1; then
  echo "rtpav1depay not found. Run: source ./scripts/env_rtpav1.sh" >&2
  exit 1
fi

rm -f "$OUT"

timeout "${TIMEOUT_SEC}s" gst-launch-1.0 -e \
  udpsrc port="$PORT" caps="application/x-rtp,media=video,clock-rate=90000,encoding-name=AV1,payload=96" ! \
  rtpjitterbuffer latency="$LATENCY" do-lost=true post-drop-messages=true ! \
  rtpav1depay ! av1parse ! filesink location="$OUT" || true

if [[ -s "$OUT" ]]; then
  echo "Received: $OUT"
  ls -lh "$OUT"
else
  echo "No output file generated: $OUT" >&2
  exit 1
fi
