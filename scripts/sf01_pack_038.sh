#!/bin/bash
# 打包 fcitx5-prisir 0.3.8：灵犀造词 + OpenAPI user_add/batch + 新引擎。
set -euo pipefail
ROOT=/root/lingxi-linux
cd "$ROOT"

# 确保 helpers / addon / engine 都是最新
test -f helpers/prisir_quick_add
test -f helpers/prisir_openapi
grep -q user_add_batch helpers/prisir_openapi
grep -q prisir_quick_add scripts/pack_deb.sh
grep -q prisir-quick-add fcitx5-prisir/src/prisir.cpp
test -f dist/libprisir_ime.so
nm -D dist/libprisir_ime.so | grep -q prisir_ime_user_add_pos

echo "[1] rebuild addon"
cmake -B fcitx5-prisir/build -S fcitx5-prisir
cmake --build fcitx5-prisir/build -j"$(nproc)"

ENGINE=dist/libprisir_ime.so
DB=assets/ciku.db
[[ -f "$DB" ]] || DB=/usr/lib/fcitx5/prisir/ciku.db
VOICE=/usr/lib/fcitx5/prisir/voice/sensevoice-small
OUT=dist/fcitx5-prisir_0.3.8_amd64.deb

echo "[2] pack $OUT"
bash scripts/pack_deb.sh \
  --addon fcitx5-prisir/build/prisir.so \
  --engine "$ENGINE" \
  --db "$DB" \
  --voice-model "$VOICE" \
  --helpers helpers \
  --version 0.3.8 \
  --out "$OUT"

ls -lh --full-time "$OUT"
# 校验包内关键文件
tmpdir=$(mktemp -d)
dpkg-deb -x "$OUT" "$tmpdir"
test -x "$tmpdir/usr/lib/fcitx5/prisir/prisir_quick_add"
grep -q user_add_batch "$tmpdir/usr/lib/fcitx5/prisir/prisir_openapi"
nm -D "$tmpdir/usr/lib/fcitx5/prisir/libprisir_ime.so" | grep -E 'user_add_pos|auto_code'
strings "$tmpdir/usr/lib/x86_64-linux-gnu/fcitx5/prisir.so" | grep -E 'prisir-quick-add|prisir_quick_add'
rm -rf "$tmpdir"

echo "[3] install locally"
dpkg -i "$OUT"
echo DONE_PACK_0.3.8
