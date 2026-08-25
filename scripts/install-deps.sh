#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Chạy script này bằng sudo: sudo $0" >&2
    exit 1
fi

source /etc/os-release
case "${ID:-}" in
    fedora|bazzite)
        if [[ ${ID:-} == bazzite ]]; then
            echo "Bazzite là immutable: hãy dùng scripts/build-flatpak.sh (không layer toolchain vào OS)." >&2
            exit 2
        fi
        dnf install -y git gcc-c++ make pkgconf-pkg-config \
            qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel \
            openssl-devel SDL2-devel SDL2_ttf-devel ffmpeg-devel \
            libva-devel libvdpau-devel opus-devel pulseaudio-libs-devel \
            alsa-lib-devel libdrm-devel libplacebo-devel vulkan-loader-devel \
            shaderc-devel meson ninja-build python3-jinja2 glslang-devel nasm yasm
        ;;
    ubuntu|debian)
        apt-get update
        apt-get install -y git build-essential pkg-config qmake6 \
            qt6-base-dev qt6-declarative-dev libqt6svg6-dev qt6-wayland \
            qml6-module-qtquick-controls qml6-module-qtquick-templates \
            qml6-module-qtquick-layouts qml6-module-qtqml-workerscript \
            qml6-module-qtquick-window qml6-module-qtquick \
            libegl1-mesa-dev libgl1-mesa-dev libopus-dev libsdl2-dev \
            libsdl2-ttf-dev libssl-dev libavcodec-dev libavformat-dev \
            libswscale-dev libva-dev libvdpau-dev libxkbcommon-dev \
            wayland-protocols libdrm-dev libvulkan-dev libplacebo-dev \
            meson ninja-build python3-jinja2 glslang-dev libshaderc-dev nasm yasm
        ;;
    *)
        echo "Distro '${ID:-unknown}' chưa được hỗ trợ." >&2
        exit 2
        ;;
esac
