#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sudo bash "$ROOT_DIR/scripts/install-deps.sh"
JOBS="${JOBS:-4}" bash "$ROOT_DIR/scripts/build-l4t.sh"
echo "Xong. Chạy: $ROOT_DIR/dist/moonlight-vulkan"
