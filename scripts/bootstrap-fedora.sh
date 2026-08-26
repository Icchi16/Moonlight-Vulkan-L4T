#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo dnf install -y git python3 flatpak flatpak-builder
flatpak remote-add --user --if-not-exists flathub \
    https://flathub.org/repo/flathub.flatpakrepo
bash "$ROOT_DIR/scripts/build-flatpak.sh"
flatpak install --user -y --reinstall \
    "$ROOT_DIR/dist/moonlight-nightly-vulkan.flatpak"
echo "Xong. Chạy: flatpak run com.moonlight_stream.Moonlight"
