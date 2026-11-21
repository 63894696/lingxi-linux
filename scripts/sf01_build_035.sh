#!/bin/bash
# Build + install fcitx5-prisir 0.3.5 — Apache-2.0 + privacy/terms copy.
set -euo pipefail
cd /root/lingxi-linux
ADDON_SRC="fcitx5-prisir"
echo "[1] cmake"
cmake -B "${ADDON_SRC}/build" -S "${ADDON_SRC}"
cmake --build "${ADDON_SRC}/build" -j"$(nproc)"
ENGINE=dist/libprisir_ime.so
[[ -f "$ENGINE" ]] || ENGINE=prisir_ime/target/release/libprisir_ime.so
DB=assets/ciku.db
[[ -f "$DB" ]] || DB=/usr/lib/fcitx5/prisir/ciku.db
VOICE=/usr/lib/fcitx5/prisir/voice/sensevoice-small
[[ -f "$VOICE/model.onnx" ]] || VOICE=assets/voice/sensevoice-small
echo "[2] pack 0.3.5"
bash scripts/pack_deb.sh \
  --addon "${ADDON_SRC}/build/prisir.so" \
  --engine "$ENGINE" \
  --db "$DB" \
  --voice-model "$VOICE" \
  --helpers helpers \
  --version 0.3.5 \
  --out dist/fcitx5-prisir_0.3.5_amd64.deb
echo "[3] install"
dpkg -i dist/fcitx5-prisir_0.3.5_amd64.deb
python3 tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases prisir_ime/abi_cases.json
ls -lh dist/fcitx5-prisir_0.3.5_amd64.deb
dpkg -l fcitx5-prisir | tail -1
grep -n "Apache\|灵犀拼音采用严格\|OIE-PCS" /usr/lib/fcitx5/prisir/prisir_about | head -20
test -f /usr/lib/fcitx5/prisir/LICENSE.txt
test -f /usr/share/doc/fcitx5-prisir/LICENSE.txt
head -3 /usr/lib/fcitx5/prisir/LICENSE.txt
pkill -u debianuser fcitx5 2>/dev/null || true
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  fcitx5 -d --replace || true
echo "[done] 0.3.5 installed"
