#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/lib/common.sh"

need git
need flatpak
need python3

if command -v flatpak-builder >/dev/null 2>&1; then
    flatpak_builder=(flatpak-builder)
elif flatpak info --user org.flatpak.Builder >/dev/null 2>&1; then
    # Bazzite/immutable OS: dùng flatpak-builder đóng gói trong org.flatpak.Builder.
    flatpak_builder=(flatpak run --filesystem="$ROOT_DIR" \
        --filesystem=xdg-data/flatpak --command=flatpak-builder org.flatpak.Builder)
else
    die "Thiếu flatpak-builder. Trên Bazzite, cài org.flatpak.Builder từ Flathub."
fi

flatpak_work="$BUILD_DIR/flatpak"
manifest_repo="$flatpak_work/manifest"
[[ ${CLEAN:-0} == 1 ]] && rm -rf -- "$flatpak_work"
mkdir -p "$flatpak_work" "$DIST_DIR"

if [[ ! -d "$manifest_repo/.git" ]]; then
    git clone https://github.com/flathub/com.moonlight_stream.Moonlight.git "$manifest_repo"
else
    git -C "$manifest_repo" pull --ff-only
fi

need git
MOONLIGHT_SHA="$(git ls-remote "$MOONLIGHT_REPO" "$MOONLIGHT_REF" | awk 'NR==1 {print $1}')"
if [[ -z "$MOONLIGHT_SHA" ]]; then
    # Tags/short SHA không phải lúc nào cũng khớp ls-remote theo tên.
    resolve_dir="$flatpak_work/source-resolve"
    [[ -d "$resolve_dir/.git" ]] || git clone --filter=blob:none "$MOONLIGHT_REPO" "$resolve_dir"
    git -C "$resolve_dir" fetch --tags origin
    MOONLIGHT_SHA="$(git -C "$resolve_dir" rev-parse "$MOONLIGHT_REF^{commit}")"
fi
export MOONLIGHT_SHA MOONLIGHT_REPO

base_manifest="$manifest_repo/com.moonlight_stream.Moonlight.json"
manifest="$manifest_repo/com.moonlight_stream.Moonlight.NightlyVulkan.json"
cp "$base_manifest" "$manifest"

# Chỉ thay source Moonlight và environment; dependencies/patch từ Flathub được giữ nguyên.
python3 - "$manifest" <<'PY'
import json, os, sys
p = sys.argv[1]
with open(p, encoding="utf-8") as f:
    data = json.load(f)
args = data.setdefault("finish-args", [])
if "--env=PREFER_VULKAN=1" not in args:
    args.append("--env=PREFER_VULKAN=1")
moonlight = next(m for m in data["modules"] if m["name"] == "moonlight")
# Các patch trong manifest nhắm vào release stable cũ; nightly master đã chứa
# các fix đó và patch lại sẽ fail hoặc tạo thay đổi kép.
moonlight["sources"] = [s for s in moonlight["sources"] if s.get("type") != "patch"]
src = next(s for s in moonlight["sources"] if s.get("type") == "git" and "moonlight-qt" in s.get("url", ""))
src.clear()
src.update({
    "type": "git",
    "url": os.environ["MOONLIGHT_REPO"],
    "commit": os.environ["MOONLIGHT_SHA"],
    "disable-shallow-clone": True,
})
with open(p, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

runtime="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["runtime"])' "$manifest")"
runtime_version="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["runtime-version"])' "$manifest")"
sdk="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["sdk"])' "$manifest")"
flatpak install --user -y flathub "$runtime//$runtime_version" "$sdk//$runtime_version"

note "Build Flatpak Moonlight $MOONLIGHT_SHA + PREFER_VULKAN=1"
"${flatpak_builder[@]}" --user --force-clean --install-deps-from=flathub \
    --repo="$flatpak_work/repo" "$flatpak_work/build-dir" "$manifest"
flatpak build-bundle "$flatpak_work/repo" "$DIST_DIR/moonlight-nightly-vulkan.flatpak" \
    com.moonlight_stream.Moonlight
write_build_info flatpak
note "Xong: $DIST_DIR/moonlight-nightly-vulkan.flatpak"
