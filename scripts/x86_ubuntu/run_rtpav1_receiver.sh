#!/usr/bin/env bash
set -euo pipefail

PORT="5504"
PAYLOAD="97"
LATENCY="100"
DECODER="auto"
SYNC="false"
SINK="autovideosink"

usage() {
  cat <<USAGE
Usage: $0 [--port N] [--payload N] [--latency MS] [--decoder auto|av1dec|avdec_av1] [--sink NAME] [--sync true|false]

Notes:
  - decoder=auto is preferred and selects av1dec first, then avdec_av1.
  - Before running, source ./scripts/x86_ubuntu/env_rtpav1.sh
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PORT="$2"; shift 2 ;;
    --payload) PAYLOAD="$2"; shift 2 ;;
    --latency) LATENCY="$2"; shift 2 ;;
    --decoder) DECODER="$2"; shift 2 ;;
    --sink) SINK="$2"; shift 2 ;;
    --sync) SYNC="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if ! gst-inspect-1.0 rtpav1depay >/dev/null 2>&1; then
  echo "ERROR: rtpav1depay not found. Run: source ./scripts/x86_ubuntu/env_rtpav1.sh" >&2
  exit 1
fi

select_decoder() {
  case "$DECODER" in
    av1dec|avdec_av1)
      if gst-inspect-1.0 "$DECODER" >/dev/null 2>&1; then
        echo "$DECODER"
        return 0
      fi
      echo "ERROR: requested decoder not found: $DECODER" >&2
      exit 1
      ;;
    auto)
      if gst-inspect-1.0 av1dec >/dev/null 2>&1; then
        echo "av1dec"
        return 0
      fi
      if gst-inspect-1.0 avdec_av1 >/dev/null 2>&1; then
        echo "avdec_av1"
        return 0
      fi
      echo "ERROR: no AV1 decoder found (tried: av1dec, avdec_av1)" >&2
      exit 1
      ;;
    *)
      echo "ERROR: invalid --decoder: $DECODER" >&2
      exit 1
      ;;
  esac
}

DECODER_ELEM="$(select_decoder)"
echo "Using decoder: $DECODER_ELEM"

exec gst-launch-1.0 -v \
  udpsrc port="$PORT" caps="application/x-rtp,media=video,encoding-name=AV1,payload=$PAYLOAD,clock-rate=90000" ! \
  rtpjitterbuffer latency="$LATENCY" ! \
  rtpav1depay ! av1parse ! "$DECODER_ELEM" ! videoconvert ! "$SINK" sync="$SYNC"
