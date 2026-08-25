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

Chạy trực tiếp trên Switch-L4T Ubuntu 22.04/24.04 hoặc Fedora:

```bash
sudo bash ./scripts/install-deps.sh
bash ./scripts/build-l4t.sh
./dist/moonlight-vulkan
```

Trên Ubuntu L4T, nếu FFmpeg hoặc `libplacebo-dev` của hệ thống quá cũ,
script build bản tương thích vào prefix nội bộ trong `build/deps`. Không dùng
`CONFIG+=vulkanslow/gpuslow`, vì hai option này cố tình hạ ưu tiên Vulkan.

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
