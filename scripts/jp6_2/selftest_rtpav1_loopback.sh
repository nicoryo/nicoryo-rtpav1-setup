#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_jp62.sh"

PORT="5200"
SECONDS="20"
OUT="/tmp/rtpav1_loopback_rx.av1"

usage() {
  cat <<USAGE
Usage: $0 [--seconds N] [--port N] [--out PATH]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --seconds) SECONDS="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

require_jp62

"$SCRIPT_DIR/run_rtpav1_receiver.sh" --port "$PORT" --out "$OUT" --timeout "$((SECONDS + 10))" &
RX_PID=$!

sleep 1
"$SCRIPT_DIR/run_rtpav1_sender.sh" --host 127.0.0.1 --port "$PORT" --seconds "$SECONDS"

wait "$RX_PID"

gst-launch-1.0 -e filesrc location="$OUT" ! av1parse ! av1dec ! fakesink sync=false

echo "Loopback self-test passed: $OUT"
