#!/bin/bash
# Build + install fcitx5-prisir 0.3.4 — scrubbed lexicon + full SenseVoice.
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
echo "[2] pack 0.3.4"
bash scripts/pack_deb.sh \
  --addon "${ADDON_SRC}/build/prisir.so" \
  --engine "$ENGINE" \
  --db "$DB" \
  --voice-model "$VOICE" \
  --helpers helpers \
  --version 0.3.4 \
  --out dist/fcitx5-prisir_0.3.4_amd64.deb
echo "[3] install"
dpkg -i dist/fcitx5-prisir_0.3.4_amd64.deb
python3 tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases prisir_ime/abi_cases.json
ls -lh dist/fcitx5-prisir_0.3.4_amd64.deb
dpkg -l fcitx5-prisir | tail -1
