#!/usr/bin/env bash
set -euo pipefail
DEB=/mnt/d/Projects/lingxi-linux/dist/LingxiPinyin-Linux-x86_64-0.2.0_amd64.deb
OUT=/mnt/d/Projects/lingxi-linux/helpers
TMP=/tmp/prisir020_extract
rm -rf "$TMP"
mkdir -p "$TMP" "$OUT"
dpkg-deb -x "$DEB" "$TMP"
cp -a "$TMP"/usr/lib/fcitx5/prisir/prisir_dict "$OUT"/
cp -a "$TMP"/usr/lib/fcitx5/prisir/prisir_dict.py "$OUT"/
cp -a "$TMP"/usr/lib/fcitx5/prisir/prisir_symbols "$OUT"/
cp -a "$TMP"/usr/lib/fcitx5/prisir/prisir_about "$OUT"/
cp -a "$TMP"/usr/lib/fcitx5/prisir/prisir_handwriting "$OUT"/
cp -a "$TMP"/usr/lib/fcitx5/prisir/prisir_voice "$OUT"/
# keep models optional under assets (large) — only copy small index if needed
mkdir -p /mnt/d/Projects/lingxi-linux/assets/hand
cp -a "$TMP"/usr/lib/fcitx5/prisir/hand/char_index.json /mnt/d/Projects/lingxi-linux/assets/hand/ 2>/dev/null || true
ls -la "$OUT"
wc -l "$OUT"/*
