#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"

[[ $(uname -m) == aarch64 ]] || die "build-l4t.sh phải chạy native trên arm64/aarch64 (Switch-L4T/Jetson)."
need git
need ninja
need qmake6
need pkg-config
need python3
need vulkaninfo

if [[ -r /proc/device-tree/compatible ]]; then
    compatible=$(tr '\0' '\n' < /proc/device-tree/compatible)
    grep -Eqi 'nvidia,tegra(210)?' <<<"$compatible" || \
        die "Máy arm64 này không phải NVIDIA Tegra/L4T."
fi

[[ -e /dev/nvhost-nvdec ]] || \
    die "Không tìm thấy /dev/nvhost-nvdec. Hãy boot bằng kernel/BSP Switchroot L4T đúng bản."
ldconfig_output=$(ldconfig -p 2>/dev/null || true)
grep -q 'libnvbuf_utils\.so' <<<"$ldconfig_output" || \
    die "Thiếu libnvbuf_utils của NVIDIA L4T. Hãy cập nhật Switchroot BSP."
vulkan_summary=$(vulkaninfo --summary 2>&1) || \
    die "Vulkan runtime không hoạt động. Hãy kiểm tra NVIDIA L4T driver."
grep -Eqi 'NVIDIA|Tegra' <<<"$vulkan_summary" || \
    die "vulkaninfo không thấy GPU NVIDIA Tegra."

deps_prefix="$BUILD_DIR/deps/prefix"
export PKG_CONFIG_PATH="$deps_prefix/lib/pkgconfig:$deps_prefix/lib/aarch64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD_LIBRARY_PATH="$deps_prefix/lib:$deps_prefix/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"

# libplacebo hiện tại cần Meson >= 1.3. Jammy chỉ có 0.61, nên dùng venv
# cục bộ thay vì thay đổi Python/Meson của hệ điều hành.
meson_is_new_enough() {
    local version
    version=$($1 --version 2>/dev/null) || return 1
    [[ $version =~ ^([0-9]+)\.([0-9]+) ]] || return 1
    (( BASH_REMATCH[1] > 1 || (BASH_REMATCH[1] == 1 && BASH_REMATCH[2] >= 3) ))
}

meson_cmd=$(command -v meson || true)
if [[ -z "$meson_cmd" ]] || ! meson_is_new_enough "$meson_cmd"; then
    tools_venv="$BUILD_DIR/tools/venv"
    if [[ ! -x "$tools_venv/bin/meson" ]]; then
        note "Cài Meson 1.3.2 vào build/tools (không sửa hệ điều hành)"
        python3 -m venv "$tools_venv"
        "$tools_venv/bin/python" -m pip install --disable-pip-version-check 'meson==1.3.2'
    fi
    meson_cmd="$tools_venv/bin/meson"
fi
meson_is_new_enough "$meson_cmd" || die "Cần Meson >= 1.3.0."

# Dùng đúng SDL2/SDL_ttf mà pipeline L4T chính thức của Moonlight đang pin.
packaging_commit="87b7904f0bfdfc32af155c92376868e489770079"
sdl_marker="$deps_prefix/.moonlight-sdl-packaging-commit"
if [[ ! -f "$sdl_marker" ]] || [[ $(<"$sdl_marker") != "$packaging_commit" ]] || \
        [[ ! -f "$deps_prefix/lib/pkgconfig/sdl2.pc" ]] || \
        [[ ! -f "$deps_prefix/lib/pkgconfig/SDL2_ttf.pc" ]]; then
    note "Build SDL2 KMSDRM theo Moonlight L4T packaging"
    packaging_src="$BUILD_DIR/deps/moonlight-packaging"
    if [[ ! -d "$packaging_src/.git" ]]; then
        git clone https://github.com/cgutman/moonlight-packaging.git "$packaging_src"
    fi
    git -C "$packaging_src" fetch origin "$packaging_commit"
    git -C "$packaging_src" checkout --detach "$packaging_commit"
    git -C "$packaging_src" submodule sync --recursive
    git -C "$packaging_src" submodule update --init SDL2 SDL_ttf

    sdl_build="$BUILD_DIR/deps/sdl2-build"
    sdl_ttf_build="$BUILD_DIR/deps/sdl-ttf-build"
    rm -rf -- "$sdl_build" "$sdl_ttf_build"
    mkdir -p "$sdl_build" "$sdl_ttf_build"
    (cd "$sdl_build" && "$packaging_src/SDL2/configure" \
        --prefix="$deps_prefix" --libdir="$deps_prefix/lib" \
        --enable-shared --disable-static --enable-video-kmsdrm --disable-video-rpi)
    make -C "$sdl_build" -j"$JOBS"
    make -C "$sdl_build" install

    (cd "$packaging_src/SDL_ttf" && ./autogen.sh)
    (cd "$sdl_ttf_build" && "$packaging_src/SDL_ttf/configure" \
        --prefix="$deps_prefix" --libdir="$deps_prefix/lib" \
        --enable-shared --disable-static)
    make -C "$sdl_ttf_build" -j"$JOBS"
    make -C "$sdl_ttf_build" install
    printf '%s\n' "$packaging_commit" > "$sdl_marker"
fi

# Nintendo Switch dùng L4T R32 và cần fork FFmpeg có decoder NVV4L2.
# Commit này là submodule FFmpeg-l4t-new trong cgutman/moonlight-packaging.
ffmpeg_l4t_commit="93133c040cff97b99046612dac7219844a55f3b8"
ffmpeg_marker="$deps_prefix/.ffmpeg-l4t-commit"
if [[ ! -f "$ffmpeg_marker" ]] || [[ $(<"$ffmpeg_marker") != "$ffmpeg_l4t_commit" ]] || \
        [[ ! -f "$deps_prefix/lib/pkgconfig/libavcodec.pc" ]]; then
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
        --arch=aarch64 --prefix="$deps_prefix" --libdir="$deps_prefix/lib" \
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

libplacebo_commit="4d82c6898551068d4ae6a6b5538efcddc2c7cf64"
libplacebo_marker="$deps_prefix/.libplacebo-commit"
if [[ ! -f "$libplacebo_marker" ]] || [[ $(<"$libplacebo_marker") != "$libplacebo_commit" ]] || \
        [[ ! -f "$deps_prefix/lib/pkgconfig/libplacebo.pc" ]]; then
    note "Build libplacebo v7 cho L4T"
    pl_src="$BUILD_DIR/deps/libplacebo"
    pl_build="$BUILD_DIR/deps/libplacebo-build"
    if [[ ! -d "$pl_src/.git" ]]; then
        git clone https://github.com/haasn/libplacebo.git "$pl_src"
    fi
    git -C "$pl_src" fetch origin "$libplacebo_commit"
    git -C "$pl_src" checkout --detach "$libplacebo_commit"
    # Bundled Vulkan-Headers có header Vulkan 1.4 mới để compile, trong khi
    # binary vẫn chỉ yêu cầu Vulkan 1.2 mà L4T R32 hỗ trợ.
    git -C "$pl_src" submodule sync --recursive
    git -C "$pl_src" submodule update --init --recursive
    rm -rf -- "$pl_build"
    "$meson_cmd" setup "$pl_build" "$pl_src" \
        --prefix="$deps_prefix" --libdir=lib \
        -Ddefault_library=shared -Ddemos=false -Dtests=false \
        -Dvulkan=enabled -Dopengl=disabled -Dshaderc=enabled
    ninja -C "$pl_build" -j"$JOBS" install
    printf '%s\n' "$libplacebo_commit" > "$libplacebo_marker"
fi

export QMAKE_RPATHDIR="$deps_prefix/lib $deps_prefix/lib/aarch64-linux-gnu"

prepare_source
source_dir="$SOURCE_DIR"
moonlight_build="$BUILD_DIR/l4t"
[[ ${CLEAN:-0} == 1 ]] && rm -rf -- "$moonlight_build"
mkdir -p "$moonlight_build"
qmake_args=("CONFIG+=disable-libva" "CONFIG+=disable-libvdpau")
[[ ${EMBEDDED:-0} == 1 ]] && qmake_args+=("CONFIG+=embedded")

note "Configure L4T nightly (NVV4L2 decode + Vulkan render)"
qmake_log="$moonlight_build/qmake.log"
(cd "$moonlight_build" && qmake6 "${qmake_args[@]}" \
    "QMAKE_RPATHDIR=$deps_prefix/lib $deps_prefix/lib/aarch64-linux-gnu" \
    "$source_dir/moonlight-qt.pro") 2>&1 | tee "$qmake_log"
grep -Fq "FFmpeg decoder selected" "$qmake_log" || \
    die "qmake không enable FFmpeg decoder. Xem $qmake_log"
grep -Fq "Vulkan support enabled via libplacebo" "$qmake_log" || \
    die "qmake không enable Vulkan renderer. Xem $qmake_log"
grep -Fq "Wayland extensions enabled" "$qmake_log" || \
    die "qmake không enable Wayland frame pacing. Kiểm tra libwayland-dev."
if grep -Eq "VAAPI renderer selected|VDPAU renderer selected" "$qmake_log"; then
    die "L4T build đã bật nhầm VAAPI/VDPAU. Xem $qmake_log"
fi
make -C "$moonlight_build" -j"$JOBS" release

moonlight_binary="$moonlight_build/app/moonlight"
linkage_log="$moonlight_build/ldd.log"
ldd "$moonlight_binary" > "$linkage_log"
grep -F "$deps_prefix/lib/libavcodec" "$linkage_log" >/dev/null || \
    die "Binary không link FFmpeg NVV4L2 trong prefix. Xem $linkage_log"
grep -F "$deps_prefix/lib/libplacebo" "$linkage_log" >/dev/null || \
    die "Binary không link libplacebo trong prefix. Xem $linkage_log"
grep -F "$deps_prefix/lib/libSDL2" "$linkage_log" >/dev/null || \
    die "Binary không link SDL2 L4T trong prefix. Xem $linkage_log"

cat > "$DIST_DIR/moonlight-vulkan" <<EOF
#!/usr/bin/env bash
export PREFER_VULKAN=1
export VULKAN_IS_SLOW=0
export LD_LIBRARY_PATH="$deps_prefix/lib:$deps_prefix/lib/aarch64-linux-gnu:\${LD_LIBRARY_PATH:-}"
if [[ \${XDG_SESSION_TYPE:-} == wayland ]]; then
    export QT_QPA_PLATFORM="\${QT_QPA_PLATFORM:-wayland}"
fi
exec "$moonlight_binary" "\$@"
EOF
chmod +x "$DIST_DIR/moonlight-vulkan"
write_build_info l4t-aarch64
{
    printf 'ffmpeg_l4t_commit=%s\n' "$ffmpeg_l4t_commit"
    printf 'libplacebo_commit=%s\n' "$libplacebo_commit"
    printf 'moonlight_packaging_commit=%s\n' "$packaging_commit"
} >> "$DIST_DIR/build-info.txt"
note "Xong: $DIST_DIR/moonlight-vulkan"

