#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/.build}"
GST_RS_DIR="${GST_RS_DIR:-${BUILD_ROOT}/gst-plugins-rs}"
# Compatible with Ubuntu 22.04 era GStreamer. Override with GST_RS_REF if needed.
GST_RS_REF="${GST_RS_REF:-111f98cc80c8225da956e588cb0dfe79484b49f4}"

usage() {
  cat <<USAGE
Usage: $0 [--skip-apt]

Options:
  --skip-apt  Skip apt package installation
  -h, --help  Show this help
USAGE
}

SKIP_APT=0
for arg in "$@"; do
  case "$arg" in
    --skip-apt) SKIP_APT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg" >&2; usage; exit 1 ;;
  esac
done

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "ERROR: this script targets x86_64. Detected: $(uname -m)" >&2
  exit 1
fi

if [[ -f /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "ERROR: this script targets Ubuntu. Detected: ${ID:-unknown}" >&2
    exit 1
  fi
fi

if [[ "$SKIP_APT" -eq 0 ]]; then
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential pkg-config git curl ca-certificates \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav gstreamer1.0-gl gstreamer1.0-x \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev

  if apt-cache show gstreamer1.0-plugins-rs >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gstreamer1.0-plugins-rs || true
    if gst-inspect-1.0 rtpav1depay >/dev/null 2>&1; then
      echo "Installed via apt: gstreamer1.0-plugins-rs"
      echo "Check: gst-inspect-1.0 rtpav1depay"
      exit 0
    fi
  fi
fi

mkdir -p "$BUILD_ROOT"

if ! command -v rustc >/dev/null 2>&1 || ! command -v cargo >/dev/null 2>&1; then
  curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal
fi

# shellcheck source=/dev/null
source "$HOME/.cargo/env"

if [[ ! -d "$GST_RS_DIR/.git" ]]; then
  git clone https://gitlab.freedesktop.org/gstreamer/gst-plugins-rs.git "$GST_RS_DIR"
fi

git -C "$GST_RS_DIR" fetch --all --tags
git -C "$GST_RS_DIR" checkout "$GST_RS_REF"

(
  cd "$GST_RS_DIR"
  cargo build -p gst-plugin-rtp --release -j"$(nproc)"
)

PLUGIN_SO="$GST_RS_DIR/target/release/libgstrsrtp.so"
if [[ ! -f "$PLUGIN_SO" ]]; then
  echo "ERROR: plugin not found: $PLUGIN_SO" >&2
  exit 1
fi

cat > "$SCRIPT_DIR/env_rtpav1.sh" <<ENV
#!/usr/bin/env bash
export GST_PLUGIN_PATH="$GST_RS_DIR/target/release\${GST_PLUGIN_PATH:+:\$GST_PLUGIN_PATH}"
ENV
chmod +x "$SCRIPT_DIR/env_rtpav1.sh"

# shellcheck source=/dev/null
source "$SCRIPT_DIR/env_rtpav1.sh"

gst-inspect-1.0 rtpav1depay >/dev/null

echo "Setup complete"
echo "Plugin: $PLUGIN_SO"
echo "Use: source $SCRIPT_DIR/env_rtpav1.sh"
echo "Check: gst-inspect-1.0 rtpav1depay"
