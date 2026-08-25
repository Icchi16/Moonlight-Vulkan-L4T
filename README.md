# Moonlight Qt nightly + Vulkan renderer

Bộ script này build `master` (nightly) của
[moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt)
và buộc Moonlight ưu tiên Vulkan renderer bằng `PREFER_VULKAN=1`.
Không có fork renderer riêng: Vulkan/libplacebo đã nằm trong upstream, nhờ vậy
có thể theo nightly mà chỉ duy trì lớp build/packaging nhỏ này.

> `PREFER_VULKAN=1` chỉ có tác dụng khi binary được compile với
> libplacebo >= 7.349.0 và FFmpeg >= 6.1. Script sẽ dừng nếu qmake không
> báo `Vulkan support enabled via libplacebo`.

## Cách dùng

### Build + cài đặt chỉ bằng một command

Fedora:

```bash
bash ./scripts/bootstrap-fedora.sh
```

Bazzite:

```bash
bash ./scripts/bootstrap-bazzite.sh
```

Switch-L4T/Jetson arm64:

```bash
bash ./scripts/bootstrap-l4t.sh
```

Ba script bootstrap tự cài build tool/dependency, build nightly, và cài
kết quả. Bazzite dùng `org.flatpak.Builder`, không layer RPM và không
yêu cầu reboot.

### Bazzite / Fedora x86_64 (khuyến nghị: Flatpak)

```bash
bash ./scripts/build-flatpak.sh
flatpak install --user --reinstall ./dist/moonlight-nightly-vulkan.flatpak
flatpak run com.moonlight_stream.Moonlight
```

Script lấy manifest Flathub hiện tại (gồm FFmpeg và libplacebo đúng bản),
thay source Moonlight bằng commit nightly mới nhất, và thêm
`PREFER_VULKAN=1`. Đây là lối phù hợp với Bazzite immutable.

### Fedora workstation (native)

```bash
sudo bash ./scripts/install-deps.sh
bash ./scripts/build-native.sh
./dist/moonlight-vulkan
```

### Switchroot / Switch-L4T arm64

Script cài bản nightly song song, không xóa hoặc ghi đè bản `moonlight-qt`
stable do L4T Megascript cài. Chạy trực tiếp trên Switchroot Ubuntu
22.04/24.04:

```bash
bash ./scripts/bootstrap-l4t.sh
```

Sau khi build, mở **Moonlight Nightly (Vulkan)** trong menu ứng dụng hoặc chạy
`~/.local/bin/moonlight-nightly-vulkan`. Lần build đầu sẽ lâu vì script build
dependency L4T; các lần sau dùng lại cache trong `build/deps`.

Nếu màn hình đăng nhập cho chọn session, ưu tiên **Plasma (Wayland)** hoặc
**Ubuntu on Wayland**. Launcher sẽ dùng Qt Wayland native khi session hiện tại
là Wayland; nó không ép Wayland khi bạn đang đăng nhập X11.

Trên Switch-L4T, script luôn dùng FFmpeg 6.1.1 NVV4L2 của Switchroot
(`h264_nvv4l2`/`hevc_nvv4l2`) để giữ hardware decoding trên Tegra, và
build libplacebo Vulkan vào prefix nội bộ trong `build/deps`. SDL2/SDL_ttf
được pin theo Moonlight L4T packaging và SDL2 được build với KMSDRM. Script
không dùng `CONFIG+=vkslow/gpuslow`, đồng thời tắt VAAPI/VDPAU cho binary L4T
để không probe nhầm renderer desktop.

Nightly mang các thay đổi UI, protocol và bugfix mới nhất từ `master`.
Nintendo Switch vẫn dùng H.264/HEVC NVV4L2; AV1 không có hardware decode trên
Tegra X1 nên không được bật chỉ vì dùng bản nightly.

## Pin commit để build lại đúng một bản

Mặc định script resolve `master` thành SHA và ghi SHA vào
`dist/build-info.txt`. Có thể build lại SHA/tag cụ thể:

```bash
MOONLIGHT_REF=7cf8b46 bash ./scripts/build-native.sh
MOONLIGHT_REF=v6.1.0 bash ./scripts/build-flatpak.sh
```

Các biến hữu ích:

- `JOBS=4`: giới hạn luồng compile (nên dùng 4 trên Switch).
- `CLEAN=1`: xóa build tree của target trước khi build.
- `EMBEDDED=1`: thêm `CONFIG+=embedded` cho L4T.
- `MOONLIGHT_REPO=URL`: dùng fork khác, nếu cần.

## Kiểm tra renderer khi chạy

Bật performance overlay trong Moonlight và xem log terminal. Dòng log phải có
`Vulkan rendering device chosen`/`libplacebo`; không nên chỉ có EGL/VDPAU.
Có thể tắt ép Vulkan tạm thời để so sánh:

```bash
PREFER_VULKAN=0 ./build/moonlight-qt/app/moonlight
```

Vulkan renderer không tự động đồng nghĩa với Vulkan Video decoding.
Renderer có thể nhận frame từ VAAPI/NVDEC/V4L2; decoder thực tế phụ thuộc
driver, FFmpeg và GPU. Hãy so sánh `Average decoding time`, `Average rendering
time` và `Frames dropped by network` trước khi kết luận latency giảm.

Trên Switchroot, log stream phải có decoder `h264_nvv4l2` hoặc
`hevc_nvv4l2` và dòng `Using Vulkan renderer`. Nếu không có `nvv4l2`, không
nên benchmark latency vì Moonlight có thể đang decode bằng CPU.

