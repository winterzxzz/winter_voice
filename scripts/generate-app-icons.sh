#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_icon="$repository_root/WinterVoice/Resources/AppIconSource/WinterVoiceAppIcon.png"
icon_set="$repository_root/WinterVoice/Resources/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$source_icon" ]; then
  echo "Missing source icon: $source_icon" >&2
  exit 1
fi

mkdir -p "$icon_set"

resize_icon() {
  pixels=$1
  output=$2
  sips --resampleHeightWidth "$pixels" "$pixels" "$source_icon" \
    --out "$icon_set/$output" >/dev/null
}

resize_icon 16 icon_16x16.png
resize_icon 32 icon_16x16@2x.png
resize_icon 32 icon_32x32.png
resize_icon 64 icon_32x32@2x.png
resize_icon 128 icon_128x128.png
resize_icon 256 icon_128x128@2x.png
resize_icon 256 icon_256x256.png
resize_icon 512 icon_256x256@2x.png
resize_icon 512 icon_512x512.png
resize_icon 1024 icon_512x512@2x.png
