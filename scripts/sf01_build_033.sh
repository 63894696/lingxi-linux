#!/bin/bash
# Build + install fcitx5-prisir 0.3.3 — full single package (lexicon + SenseVoice).
set -euo pipefail
cd /root/lingxi-linux

ADDON_SRC="fcitx5-prisir"
echo "[1] cmake addon"
cmake -B "${ADDON_SRC}/build" -S "${ADDON_SRC}"
cmake --build "${ADDON_SRC}/build" -j"$(nproc)"

ENGINE=dist/libprisir_ime.so
if [[ ! -f "$ENGINE" ]]; then
  ENGINE=prisir_ime/target/release/libprisir_ime.so
fi
[[ -f "$ENGINE" ]] || { echo "missing engine so" >&2; exit 2; }

DB=assets/ciku.db
[[ -f "$DB" ]] || DB=/usr/lib/fcitx5/prisir/ciku.db

VOICE=assets/voice/sensevoice-small
[[ -f "$VOICE/model.onnx" ]] || VOICE=/usr/lib/fcitx5/prisir/voice/sensevoice-small
[[ -f "$VOICE/model.onnx" ]] || { echo "missing SenseVoice model" >&2; exit 2; }

echo "[2] pack 0.3.3 (full: db + voice model)"
bash scripts/pack_deb.sh \
  --addon "${ADDON_SRC}/build/prisir.so" \
  --engine "$ENGINE" \
  --db "$DB" \
  --voice-model "$VOICE" \
  --helpers helpers \
  --version 0.3.3 \
  --out dist/fcitx5-prisir_0.3.3_amd64.deb

echo "[3] install"
dpkg -r fcitx5-prisir 2>/dev/null || true
dpkg -i dist/fcitx5-prisir_0.3.3_amd64.deb
test -f /usr/lib/fcitx5/prisir/ciku.db && echo CIKU_OK
test -f /usr/lib/fcitx5/prisir/voice/sensevoice-small/model.onnx && echo VOICE_MODEL_OK
ls -lh /usr/lib/fcitx5/prisir/voice/sensevoice-small/

echo "[4] restart fcitx5"
pkill -u debianuser fcitx5 2>/dev/null || true
sleep 1
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 2
pgrep -a fcitx5 || true

echo "[5] engine smoke"
python3 tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases prisir_ime/abi_cases.json

echo DONE
dpkg -l fcitx5-prisir | tail -1
ls -lh dist/fcitx5-prisir_0.3.3_amd64.deb
