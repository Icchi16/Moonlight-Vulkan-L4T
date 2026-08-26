# Moonlight Qt nightly + mspeedo Vulkan latency patch

Bộ script này build `master` (nightly) của
[moonlight-stream/moonlight-qt](https://github.com/moonlight-stream/moonlight-qt)
và buộc Moonlight ưu tiên Vulkan renderer bằng `PREFER_VULKAN=1`. Bản Flatpak
và Switchroot mặc định áp dụng port của
[mspeedo commit `180f234`](https://github.com/mspeedo/moonlight-qt/commit/180f234dcae109afda1124346958a6eac16ab214)
để giảm hàng đợi render/present trên Vulkan.

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
thay source Moonlight bằng commit nightly mới nhất, thêm patch mspeedo,
`PREFER_VULKAN=1` và `LIBVA_DRIVER_NAME=invalid` để ưu tiên Vulkan Video thay
vì VAAPI. Đây là lối phù hợp với Bazzite immutable. Bundle dùng app ID chính
thức nên sẽ thay thế Moonlight trong cùng scope cài đặt.

### Fedora workstation (native)

```bash
sudo bash ./scripts/install-deps.sh
bash ./scripts/build-native.sh
./dist/moonlight-vulkan
```

### Switchroot / Switch-L4T arm64

Script này chỉ build/cài bản nightly Vulkan; nó không build hoặc cài bản
Moonlight stable của L4T Megascript. Chạy trực tiếp trên Switchroot Ubuntu
22.04/24.04. Nếu chưa clone repository:

```bash
sudo apt update && sudo apt install -y git
git clone https://github.com/Icchi16/Moonlight-Vulkan-L4T.git
cd Moonlight-Vulkan-L4T
bash ./scripts/bootstrap-l4t.sh
```

Nếu đã clone repository:

```bash
git pull --ff-only
bash ./scripts/bootstrap-l4t.sh
```

Sau khi build, mở **Moonlight Nightly (Vulkan)** trong menu ứng dụng hoặc chạy
`~/.local/bin/moonlight-nightly-vulkan`. Lần build đầu sẽ lâu vì script build
dependency L4T; các lần sau dùng lại cache trong `build/deps`.

Nếu màn hình đăng nhập cho chọn session, ưu tiên **Plasma (Wayland)** hoặc
**Ubuntu on Wayland**. Launcher sẽ dùng Qt Wayland native khi session hiện tại
là Wayland; nó không ép Wayland khi bạn đang đăng nhập X11.

Với màn hình trong của Switch, nên test trước với V-Sync bật. Có thể tắt V-Sync
để đo latency thấp hơn, nhưng chế độ này có thể gây tearing vì màn hình không
phải VRR.

Port L4T giữ bước chờ queued-present của upstream khi Vulkan dùng FIFO/V-Sync.
Việc chờ diễn ra trước khi Moonlight chọn frame mới nhất, thay vì chặn bên trong
`renderFrame()` sau khi frame đã được chọn. Với V-Sync tắt và present mode
Immediate/Mailbox/FIFO-relaxed, tuning VRR của mspeedo vẫn được giữ nguyên.

Trên Switch-L4T, script luôn dùng FFmpeg 6.1.1 NVV4L2 của Switchroot
(`h264_nvv4l2`/`hevc_nvv4l2`) để giữ hardware decoding trên Tegra, và
build libplacebo Vulkan vào prefix nội bộ trong `build/deps`. SDL2/SDL_ttf
được pin theo Moonlight L4T packaging và SDL2 được build với KMSDRM. Script
không dùng `CONFIG+=vkslow/gpuslow`, đồng thời tắt VAAPI/VDPAU cho binary L4T
để không probe nhầm renderer desktop. Patch mspeedo giống bản Bazzite cũng
được áp dụng, nhưng không đặt `LIBVA_DRIVER_NAME=invalid`: L4T cần giữ decoder
NVV4L2, không dùng Vulkan Video/VAAPI để decode.

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
- `MSPEEDO_PATCH=0`: build L4T không có latency patch FIFO-safe để so sánh A/B.
- `MOONLIGHT_REPO=URL`: dùng fork khác, nếu cần.

## Kiểm tra renderer khi chạy

Bật performance overlay trong Moonlight và xem log terminal. Dòng log phải có
`Vulkan rendering device chosen`/`libplacebo`; không nên chỉ có EGL/VDPAU.
Có thể tắt ép Vulkan tạm thời để so sánh:

```bash
PREFER_VULKAN=0 ./build/moonlight-qt/app/moonlight
```

Bản Flatpak đặt `LIBVA_DRIVER_NAME=invalid` để VAAPI khởi tạo thất bại và thử
Vulkan Video. Switchroot không dùng policy này: decoder phải là NVV4L2 và
libplacebo Vulkan chỉ đảm nhiệm render. Hãy so sánh `Average decoding time`,
`Average rendering time` và `Frames dropped by network` trước khi kết luận.

Trên Switchroot, log stream phải có decoder `h264_nvv4l2` hoặc
`hevc_nvv4l2` và dòng `Vulkan rendering device chosen`. Nếu không có
`nvv4l2`, không nên benchmark latency vì Moonlight có thể đang decode bằng CPU.
