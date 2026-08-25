#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo bash "$ROOT_DIR/scripts/install-deps.sh"
JOBS="${JOBS:-4}" bash "$ROOT_DIR/scripts/build-l4t.sh"

install -Dm755 "$ROOT_DIR/dist/moonlight-vulkan" \
    "$HOME/.local/bin/moonlight-nightly-vulkan"
install -Dm644 "$ROOT_DIR/build/moonlight-qt/app/res/moonlight.svg" \
    "$HOME/.local/share/icons/hicolor/scalable/apps/moonlight-nightly-vulkan.svg"

desktop_file="$HOME/.local/share/applications/moonlight-nightly-vulkan.desktop"
mkdir -p "$(dirname "$desktop_file")"
cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=Moonlight Nightly (Vulkan)
Comment=Moonlight nightly with NVV4L2 decode and Vulkan rendering
Exec=$HOME/.local/bin/moonlight-nightly-vulkan
Icon=moonlight-nightly-vulkan
Terminal=false
Categories=Game;
EOF

command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

echo "Xong. Bản stable vẫn được giữ nguyên."
echo "Mở 'Moonlight Nightly (Vulkan)' trong menu hoặc chạy:"
echo "$HOME/.local/bin/moonlight-nightly-vulkan"

