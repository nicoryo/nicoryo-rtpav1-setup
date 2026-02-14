#!/usr/bin/env bash
set -euo pipefail

KVS_SO="/usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstkvssink.so"
DISABLED_SO="${KVS_SO}.disabled"

usage() {
  cat <<USAGE
Usage: $0 [--restore]

Options:
  --restore  Restore previously disabled libgstkvssink.so

Notes:
  This is an optional cleanup for systems where gst-plugin-scanner prints:
    Failed to load plugin ... libgstkvssink.so: libKinesisVideoProducer.so: cannot open shared object file
USAGE
}

RESTORE=0
for arg in "$@"; do
  case "$arg" in
    --restore) RESTORE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; usage; exit 1 ;;
  esac
done

if [[ "$RESTORE" -eq 1 ]]; then
  if [[ -f "$DISABLED_SO" ]]; then
    sudo mv -f "$DISABLED_SO" "$KVS_SO"
    echo "Restored: $KVS_SO"
  else
    echo "Nothing to restore: $DISABLED_SO"
  fi
else
  if [[ -f "$KVS_SO" ]]; then
    sudo mv -f "$KVS_SO" "$DISABLED_SO"
    echo "Disabled: $KVS_SO"
  else
    echo "Not found: $KVS_SO (already absent or disabled)"
  fi
fi

rm -f "$HOME/.cache/gstreamer-1.0/registry.x86_64.bin"
echo "Cleared: ~/.cache/gstreamer-1.0/registry.x86_64.bin"
