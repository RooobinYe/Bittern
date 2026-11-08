#!/bin/bash
# 从 Bittern/AppIcon.icon 导出分享面板用的图标 ShareIcon.imageset。
#
# App 图标不能用 UIImage(named:) 读取，分享面板顶部又不会自动显示 App 图标，
# 所以另存一张普通图片给 SharePreview 的 icon 用。改了 AppIcon.icon 之后重新运行。
# 只导出浅色版：系统 App 在分享面板里也始终显示浅色图标，不随深色模式和主屏幕图标风格变化。
# 导出 128pt，是分享面板顶部图标位（约 63pt）的两倍：面板把它认为太小的图标缩小后放在白色底板上，
# 64pt 正好卡在临界值，模拟器里撑满，真机上却落到了白底板。
#
# 用法: bash scripts/export-share-icon.sh
set -euo pipefail

cd "$(dirname "$0")/.."

ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
OUT=Bittern/Assets.xcassets/ShareIcon.imageset

rm -f "$OUT"/*.png
mkdir -p "$OUT"
for scale in 2 3; do
  "$ICTOOL" Bittern/AppIcon.icon --export-image \
    --output-file "$OUT/ShareIcon@${scale}x.png" \
    --platform iOS --rendition Default \
    --width 128 --height 128 --scale "$scale" >/dev/null
done

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "ShareIcon@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "ShareIcon@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

echo "Exported $OUT"
