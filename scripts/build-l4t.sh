#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"

[[ $(uname -m) == aarch64 ]] || die "build-l4t.sh phải chạy native trên arm64/aarch64 (Switch-L4T/Jetson)."
need git
need meson
need ninja
need qmake6
need pkg-config

deps_prefix="$BUILD_DIR/deps/prefix"
export PKG_CONFIG_PATH="$deps_prefix/lib/aarch64-linux-gnu/pkgconfig:$deps_prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$deps_prefix/lib/aarch64-linux-gnu:$deps_prefix/lib:${LD_LIBRARY_PATH:-}"

# Nintendo Switch dùng L4T R32 và cần fork FFmpeg có decoder NVV4L2.
# Commit này là submodule FFmpeg-l4t-new trong cgutman/moonlight-packaging.
ffmpeg_l4t_commit="93133c040cff97b99046612dac7219844a55f3b8"
ffmpeg_marker="$deps_prefix/.ffmpeg-l4t-commit"
if [[ ! -f "$ffmpeg_marker" ]] || [[ $(<"$ffmpeg_marker") != "$ffmpeg_l4t_commit" ]]; then
    [[ -e /dev/nvhost-nvdec ]] || \
        die "Không tìm thấy /dev/nvhost-nvdec. Hãy boot bằng kernel/BSP Switchroot L4T đúng bản."
    ldconfig -p 2>/dev/null | grep -q 'libnvbuf_utils\.so' || \
        die "Thiếu libnvbuf_utils của NVIDIA L4T. Hãy cập nhật Switchroot BSP."

    note "Build FFmpeg 6.1.1 NVV4L2 dành riêng cho Switchroot L4T"
    ff_src="$BUILD_DIR/deps/ffmpeg"
    ff_build="$BUILD_DIR/deps/ffmpeg-build"
    if [[ ! -d "$ff_src/.git" ]]; then
        git clone https://github.com/theofficialgman/FFmpeg.git "$ff_src"
    fi
    git -C "$ff_src" remote set-url origin https://github.com/theofficialgman/FFmpeg.git
    git -C "$ff_src" fetch origin 6.1.1-nvv4l2
    git -C "$ff_src" checkout --detach "$ffmpeg_l4t_commit"
    rm -rf -- "$ff_build"
    mkdir -p "$ff_build"
    (cd "$ff_build" && "$ff_src/configure" \
        --arch=aarch64 --prefix="$deps_prefix" \
        --fatal-warnings --enable-pic --enable-shared --disable-static \
        --disable-all --disable-vulkan --enable-avcodec --enable-swscale \
        --enable-libdrm --extra-cflags=-I/usr/include/libdrm \
        --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=vp9 \
        --enable-decoder=h264_v4l2m2m \
        --enable-decoder=hevc_v4l2m2m \
        --enable-nvv4l2 \
        --enable-decoder=h264_nvv4l2 \
        --enable-decoder=hevc_nvv4l2)
    grep -q '#define CONFIG_H264_NVV4L2_DECODER 1' "$ff_build/config.h" || \
        die "FFmpeg configure không enable h264_nvv4l2. Kiểm tra libv4l-dev và Switchroot BSP."
    grep -q '#define CONFIG_HEVC_NVV4L2_DECODER 1' "$ff_build/config.h" || \
        die "FFmpeg configure không enable hevc_nvv4l2."
    make -C "$ff_build" -j"$JOBS"
    make -C "$ff_build" install
    printf '%s\n' "$ffmpeg_l4t_commit" > "$ffmpeg_marker"
fi

if ! PKG_CONFIG_PATH="$deps_prefix/lib/aarch64-linux-gnu/pkgconfig:$deps_prefix/lib/pkgconfig:${PKG_CONFIG_PATH:-}" \
        pkg-config --atleast-version=7.349.0 libplacebo; then
    note "Build libplacebo v7 cho L4T"
    pl_src="$BUILD_DIR/deps/libplacebo"
    pl_build="$BUILD_DIR/deps/libplacebo-build"
    if [[ ! -d "$pl_src/.git" ]]; then
        git clone https://github.com/haasn/libplacebo.git "$pl_src"
    fi
    git -C "$pl_src" fetch --tags origin
    # Commit đang dùng trong manifest Flathub; pin để build có thể lặp lại.
    git -C "$pl_src" checkout --detach 4d82c6898551068d4ae6a6b5538efcddc2c7cf64
    rm -rf -- "$pl_build"
    meson setup "$pl_build" "$pl_src" --prefix="$deps_prefix" \
        -Ddemos=false -Dvulkan=enabled -Dopengl=disabled -Dshaderc=enabled
    ninja -C "$pl_build" -j"$JOBS" install
fi

export QMAKE_RPATHDIR="$deps_prefix/lib/aarch64-linux-gnu $deps_prefix/lib"

prepare_source
source_dir="$SOURCE_DIR"
moonlight_build="$BUILD_DIR/l4t"
[[ ${CLEAN:-0} == 1 ]] && rm -rf -- "$moonlight_build"
mkdir -p "$moonlight_build"
qmake_args=()
[[ ${EMBEDDED:-0} == 1 ]] && qmake_args+=("CONFIG+=embedded")

note "Configure L4T build (Vulkan được ưu tiên, không dùng vulkanslow/gpuslow)"
qmake_log="$moonlight_build/qmake.log"
(cd "$moonlight_build" && qmake6 "${qmake_args[@]}" \
    "QMAKE_RPATHDIR=$deps_prefix/lib/aarch64-linux-gnu $deps_prefix/lib" \
    "$source_dir/moonlight-qt.pro") 2>&1 | tee "$qmake_log"
grep -Fq "Vulkan support enabled via libplacebo" "$qmake_log" || \
    die "qmake không enable Vulkan renderer. Xem $qmake_log"
make -C "$moonlight_build" -j"$JOBS" release

cat > "$DIST_DIR/moonlight-vulkan" <<EOF
#!/usr/bin/env bash
export PREFER_VULKAN=1
export LD_LIBRARY_PATH="$deps_prefix/lib/aarch64-linux-gnu:$deps_prefix/lib:\${LD_LIBRARY_PATH:-}"
exec "$moonlight_build/app/moonlight" "\$@"
EOF
chmod +x "$DIST_DIR/moonlight-vulkan"
write_build_info l4t-aarch64
note "Xong: $DIST_DIR/moonlight-vulkan"
