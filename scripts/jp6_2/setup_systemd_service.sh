#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

ACTION="install"
MODE="sender"   # sender | receiver
SERVICE_NAME="nicoryo-rtpav1"
RUN_USER="${SUDO_USER:-${USER}}"
RUN_GROUP="video"

SENDER_HOST="127.0.0.1"
SENDER_PORT="5004"
SENDER_SECONDS="0"
SENDER_BITRATE="4000000"

RECV_PORT="5004"
RECV_OUT="/var/tmp/nicoryo-rtpav1-rx.av1"
RECV_LATENCY="100"
RECV_TIMEOUT="0"

usage() {
  cat <<USAGE
Usage: $0 [install|uninstall|status] [options]

Actions:
  install      Install and start systemd service (default)
  uninstall    Stop/disable and remove service files
  status       Show service status

Options:
  --mode MODE          sender | receiver (default: sender)
  --name NAME          service name (default: nicoryo-rtpav1)
  --user USER          run user (default: current user)
  --group GROUP        run group (default: video)

  --host IP            sender host (default: 127.0.0.1)
  --port N             sender/receiver RTP port (default: 5004)
  --seconds N          sender seconds (0 = infinite, default: 0)
  --bitrate BPS        sender bitrate (default: 4000000)

  --out PATH           receiver output path (default: /var/tmp/nicoryo-rtpav1-rx.av1)
  --latency MS         receiver jitterbuffer latency (default: 100)
  --timeout SEC        receiver timeout (0 = infinite, default: 0)

  -h, --help           show this help
USAGE
}

if [[ $# -gt 0 ]]; then
  case "$1" in
    install|uninstall|status)
      ACTION="$1"
      shift
      ;;
  esac
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --name) SERVICE_NAME="$2"; shift 2 ;;
    --user) RUN_USER="$2"; shift 2 ;;
    --group) RUN_GROUP="$2"; shift 2 ;;
    --host) SENDER_HOST="$2"; shift 2 ;;
    --port) SENDER_PORT="$2"; RECV_PORT="$2"; shift 2 ;;
    --seconds) SENDER_SECONDS="$2"; shift 2 ;;
    --bitrate) SENDER_BITRATE="$2"; shift 2 ;;
    --out) RECV_OUT="$2"; shift 2 ;;
    --latency) RECV_LATENCY="$2"; shift 2 ;;
    --timeout) RECV_TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ "$MODE" != "sender" && "$MODE" != "receiver" ]]; then
  echo "Invalid --mode: $MODE (sender|receiver)" >&2
  exit 1
fi

if [[ $EUID -ne 0 ]]; then
  SUDO="sudo"
else
  SUDO=""
fi

UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_PATH="/etc/default/${SERVICE_NAME}"

install_service() {
  if [[ ! -f "${SCRIPT_DIR}/env_rtpav1.sh" ]]; then
    echo "ERROR: ${SCRIPT_DIR}/env_rtpav1.sh not found." >&2
    echo "Run ./scripts/jp6_2/setup_rtpav1_local.sh first." >&2
    exit 1
  fi

  $SUDO tee "$ENV_PATH" >/dev/null <<ENV
MODE=${MODE}
SENDER_HOST=${SENDER_HOST}
SENDER_PORT=${SENDER_PORT}
SENDER_SECONDS=${SENDER_SECONDS}
SENDER_BITRATE=${SENDER_BITRATE}
RECV_PORT=${RECV_PORT}
RECV_OUT=${RECV_OUT}
RECV_LATENCY=${RECV_LATENCY}
RECV_TIMEOUT=${RECV_TIMEOUT}
ENV
  $SUDO chmod 0644 "$ENV_PATH"

  $SUDO tee "$UNIT_PATH" >/dev/null <<UNIT
[Unit]
Description=nicoryo RTP AV1 (${MODE})
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
SupplementaryGroups=video render
WorkingDirectory=${REPO_ROOT}
Environment=PYTHONUNBUFFERED=1
EnvironmentFile=-${ENV_PATH}
ExecStart=/bin/bash -lc 'set -euo pipefail; source "${SCRIPT_DIR}/env_rtpav1.sh"; if [[ "\${MODE}" == "receiver" ]]; then exec "${SCRIPT_DIR}/run_rtpav1_receiver.sh" --port "\${RECV_PORT}" --out "\${RECV_OUT}" --latency "\${RECV_LATENCY}" --timeout "\${RECV_TIMEOUT}"; else exec "${SCRIPT_DIR}/run_rtpav1_sender.sh" --host "\${SENDER_HOST}" --port "\${SENDER_PORT}" --seconds "\${SENDER_SECONDS}" --bitrate "\${SENDER_BITRATE}"; fi'
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT

  $SUDO systemctl daemon-reload
  $SUDO systemctl enable --now "${SERVICE_NAME}.service"

  echo "Installed: ${SERVICE_NAME}.service"
  echo "Unit: ${UNIT_PATH}"
  echo "Env : ${ENV_PATH}"
  $SUDO systemctl --no-pager --full status "${SERVICE_NAME}.service" || true
}

uninstall_service() {
  $SUDO systemctl disable --now "${SERVICE_NAME}.service" || true
  $SUDO rm -f "$UNIT_PATH"
  $SUDO rm -f "$ENV_PATH"
  $SUDO systemctl daemon-reload
  echo "Removed: ${SERVICE_NAME}.service"
}

show_status() {
  $SUDO systemctl --no-pager --full status "${SERVICE_NAME}.service"
}

case "$ACTION" in
  install) install_service ;;
  uninstall) uninstall_service ;;
  status) show_status ;;
  *) echo "Unknown action: $ACTION" >&2; exit 1 ;;
esac
