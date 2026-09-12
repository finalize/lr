#!/bin/sh
# アイコンを作り直してアセットカタログに入れる。
#
# 1024 の PNG を1枚描いて、あとは sips で縮小するだけ。デザインツールは使わない。
# グラデーションは元にした画像から採った色を make-icon.swift に直接書いてある。
set -e
cd "$(dirname "$0")/.."

out=LR/Assets.xcassets/AppIcon.appiconset
color=${1:-white}      # white | dark
weight=${2:-bold}      # medium | semibold | bold | heavy

swift Icon/make-icon.swift "$out/icon_1024.png" "$color" 0.82 "$weight"
for s in 512 256 128 64 32 16; do
  sips -Z $s "$out/icon_1024.png" --out "$out/icon_$s.png" >/dev/null
done
echo "作った: $out"
