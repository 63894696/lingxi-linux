#!/bin/bash
# Build + install fcitx5-prisir 0.3.2 on SF01 (voice pseudo-stream + OpenAPI).
set -euo pipefail
cd /root/lingxi-linux

echo "[1] cmake addon"
cmake -B fcitx5-prisir/build -S fcitx5-prisir
cmake --build fcitx5-prisir/build -j"$(nproc)"

ENGINE=dist/libprisir_ime.so
if [[ ! -f "$ENGINE" ]]; then
  ENGINE=prisir_ime/target/release/libprisir_ime.so
fi
[[ -f "$ENGINE" ]] || { echo "missing engine so" >&2; exit 2; }

DB=assets/ciku.db
[[ -f "$DB" ]] || DB=/usr/lib/fcitx5/prisir/ciku.db
[[ -f "$DB" ]] || { echo "missing ciku.db" >&2; exit 2; }

echo "[2] pack 0.3.2"
bash scripts/pack_deb.sh \
  --addon fcitx5-prisir/build/prisir.so \
  --engine "$ENGINE" \
  --db "$DB" \
  --helpers helpers \
  --version 0.3.2 \
  --out dist/fcitx5-prisir_0.3.2_amd64.deb

echo "[3] install"
dpkg -r fcitx5-prisir 2>/dev/null || true
rm -f /usr/lib/x86_64-linux-gnu/fcitx5/libprisir.so
dpkg -i dist/fcitx5-prisir_0.3.2_amd64.deb
ls /usr/lib/fcitx5/prisir/ | head
test -f /etc/xdg/autostart/prisir-voice.desktop && echo AUTOSTART_VOICE_OK
test -f /usr/lib/systemd/user/prisir-voice.service && echo UNIT_VOICE_OK

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
ls -la dist/fcitx5-prisir_0.3.2_amd64.deb
