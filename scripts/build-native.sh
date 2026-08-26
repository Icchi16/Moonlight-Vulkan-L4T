#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"

need qmake6
need make
need pkg-config

prepare_source
source_dir="$SOURCE_DIR"
moonlight_build="$BUILD_DIR/native"
[[ ${CLEAN:-0} == 1 ]] && rm -rf -- "$moonlight_build"
mkdir -p "$moonlight_build"

pkg-config --atleast-version=6.1 libavcodec || die "Cần FFmpeg/libavcodec >= 6.1 để build Vulkan renderer."
pkg-config --atleast-version=7.349.0 libplacebo || die "Cần libplacebo >= 7.349.0. Trên L4T hãy dùng build-l4t.sh."

note "Configure native build với Vulkan/libplacebo"
qmake_log="$moonlight_build/qmake.log"
(cd "$moonlight_build" && qmake6 "$source_dir/moonlight-qt.pro") 2>&1 | tee "$qmake_log"
grep -Fq "Vulkan support enabled via libplacebo" "$qmake_log" || \
    die "qmake không enable Vulkan renderer. Xem $qmake_log"

note "Compile Moonlight ($JOBS jobs)"
make -C "$moonlight_build" -j"$JOBS" release

cat > "$DIST_DIR/moonlight-vulkan" <<EOF
#!/usr/bin/env bash
export PREFER_VULKAN=1
exec "$moonlight_build/app/moonlight" "\$@"
EOF
chmod +x "$DIST_DIR/moonlight-vulkan"
write_build_info native
note "Xong: $DIST_DIR/moonlight-vulkan"
