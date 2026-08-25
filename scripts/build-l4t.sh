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

if ! pkg-config --atleast-version=6.1 libavcodec; then
    note "Build FFmpeg Moonlight fork cho L4T (FFmpeg hệ thống < 6.1)"
    ff_src="$BUILD_DIR/deps/ffmpeg"
    ff_build="$BUILD_DIR/deps/ffmpeg-build"
    if [[ ! -d "$ff_src/.git" ]]; then
        git clone https://github.com/cgutman/FFmpeg.git "$ff_src"
    fi
    git -C "$ff_src" fetch origin
    # Cùng commit FFmpeg với manifest Flathub đã đối chiếu.
    git -C "$ff_src" checkout --detach d17de7e33f1332cc2fb3f5afab9ed4f29699c5a0
    rm -rf -- "$ff_build"
    mkdir -p "$ff_build"
    (cd "$ff_build" && "$ff_src/configure" \
        --prefix="$deps_prefix" --enable-shared --disable-static \
        --disable-programs --disable-doc --enable-pic --enable-libdrm \
        --enable-decoder=h264_v4l2m2m \
        --enable-decoder=hevc_v4l2m2m)
    make -C "$ff_build" -j"$JOBS"
    make -C "$ff_build" install
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
