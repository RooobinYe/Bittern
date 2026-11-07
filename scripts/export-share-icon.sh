#!/bin/bash
# 从 Bittern/AppIcon.icon 导出分享面板用的图标 ShareIcon.imageset（浅色和深色各一套）。
#
# App 图标不能用 UIImage(named:) 读取，分享面板顶部又不会自动显示 App 图标，
# 所以另存一张普通图片给 SharePreview 的 icon 用。改了 AppIcon.icon 之后重新运行。
#
# 用法: bash scripts/export-share-icon.sh
set -euo pipefail

cd "$(dirname "$0")/.."

ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
OUT=Bittern/Assets.xcassets/ShareIcon.imageset

mkdir -p "$OUT"
for rendition in Default Dark; do
  for scale in 2 3; do
    "$ICTOOL" Bittern/AppIcon.icon --export-image \
      --output-file "$OUT/ShareIcon-$rendition@${scale}x.png" \
      --platform iOS --rendition "$rendition" \
      --width 64 --height 64 --scale "$scale" >/dev/null
  done
done

cat > "$OUT/Contents.json" <<'JSON'
{
  "images" : [
    {
      "filename" : "ShareIcon-Default@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "ShareIcon-Dark@2x.png",
      "idiom" : "universal",
      "scale" : "2x"
    },
    {
      "filename" : "ShareIcon-Default@3x.png",
      "idiom" : "universal",
      "scale" : "3x"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "ShareIcon-Dark@3x.png",
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
