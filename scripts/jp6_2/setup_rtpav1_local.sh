#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-${REPO_ROOT}/.build}"
GST_RS_DIR="${GST_RS_DIR:-${BUILD_ROOT}/gst-plugins-rs}"
GST_RS_REF="${GST_RS_REF:-111f98cc80c8225da956e588cb0dfe79484b49f4}"
WITH_APT=0

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/common_jp62.sh"

usage() {
  cat <<USAGE
Usage: $0 [--with-apt]

Options:
  --with-apt   Install required apt packages (requires sudo)
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --with-apt) WITH_APT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown arg: $arg"; usage; exit 1 ;;
  esac
done

require_jp62

if [[ "$WITH_APT" -eq 1 ]]; then
  sudo apt-get update
  sudo apt-get install -y \
    nvidia-l4t-gstreamer \
    build-essential pkg-config git curl ca-certificates \
    libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
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

cargo -C "$GST_RS_DIR" build -p gst-plugin-rtp --release -j"$(nproc)"

PLUGIN_SO="$GST_RS_DIR/target/release/libgstrsrtp.so"
if [[ ! -f "$PLUGIN_SO" ]]; then
  echo "ERROR: plugin not found: $PLUGIN_SO" >&2
  exit 1
fi

cat > "$REPO_ROOT/scripts/jp6_2/env_rtpav1.sh" <<ENV
#!/usr/bin/env bash
export GST_PLUGIN_PATH="$GST_RS_DIR/target/release\${GST_PLUGIN_PATH:+:\$GST_PLUGIN_PATH}"
ENV
chmod +x "$REPO_ROOT/scripts/jp6_2/env_rtpav1.sh"

# shellcheck source=/dev/null
source "$REPO_ROOT/scripts/jp6_2/env_rtpav1.sh"
gst-inspect-1.0 rtpav1pay >/dev/null

echo "Setup complete"
echo "Plugin: $PLUGIN_SO"
echo "Use: source $REPO_ROOT/scripts/jp6_2/env_rtpav1.sh"
