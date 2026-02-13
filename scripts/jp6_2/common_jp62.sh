#!/usr/bin/env bash
set -euo pipefail

require_jp62() {
  if [[ "${SKIP_JP62_CHECK:-0}" == "1" ]]; then
    return 0
  fi

  if [[ ! -f /etc/nv_tegra_release ]]; then
    echo "ERROR: /etc/nv_tegra_release not found. This script targets Jetson JP6.2 (L4T R36.4.x)." >&2
    exit 1
  fi

  local rel
  rel="$(cat /etc/nv_tegra_release)"

  # JP6.2 on Jetson Linux is L4T R36.4.x
  if [[ "$rel" != *"R36 (release), REVISION: 4."* ]]; then
    echo "ERROR: Unsupported Jetson release." >&2
    echo "Detected: $rel" >&2
    echo "Required: JP6.2 (L4T R36.4.x). Set SKIP_JP62_CHECK=1 to override." >&2
    exit 1
  fi
}
