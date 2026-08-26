#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
MOONLIGHT_REPO="${MOONLIGHT_REPO:-https://github.com/moonlight-stream/moonlight-qt.git}"
MOONLIGHT_REF="${MOONLIGHT_REF:-master}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '\n==> %s\n' "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "Thiếu lệnh '$1'. Chạy scripts/install-deps.sh trước."; }

prepare_source() {
    local source_dir="$BUILD_DIR/moonlight-qt"
    need git
    mkdir -p "$BUILD_DIR" "$DIST_DIR"
    if [[ ! -d "$source_dir/.git" ]]; then
        note "Clone Moonlight Qt"
        git clone --recursive "$MOONLIGHT_REPO" "$source_dir"
    fi
    note "Cập nhật source và checkout $MOONLIGHT_REF"
    git -C "$source_dir" fetch --tags origin
    local resolved_ref="$MOONLIGHT_REF"
    if git -C "$source_dir" rev-parse --verify --quiet "origin/$MOONLIGHT_REF^{commit}" >/dev/null; then
        resolved_ref="origin/$MOONLIGHT_REF"
    fi
    git -C "$source_dir" checkout --detach "$resolved_ref"
    git -C "$source_dir" submodule update --init --recursive
    MOONLIGHT_SHA="$(git -C "$source_dir" rev-parse HEAD)"
    SOURCE_DIR="$source_dir"
    export MOONLIGHT_SHA SOURCE_DIR
}

write_build_info() {
    local target="$1"
    local output="${2:-$DIST_DIR/build-info.txt}"
    {
        printf 'target=%s\n' "$target"
        printf 'repository=%s\n' "$MOONLIGHT_REPO"
        printf 'requested_ref=%s\n' "$MOONLIGHT_REF"
        printf 'commit=%s\n' "$MOONLIGHT_SHA"
        printf 'built_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'renderer=PREFER_VULKAN=1 (libplacebo)\n'
    } > "$output"
}
