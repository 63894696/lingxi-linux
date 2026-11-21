#!/bin/bash
set -euo pipefail
cd /root/lingxi-linux

echo "[1] cmake"
cmake -B fcitx5-prisir/build -S fcitx5-prisir
cmake --build fcitx5-prisir/build -j"$(nproc)"

echo "[2] pack 0.3.1"
bash scripts/pack_deb.sh \
  --addon fcitx5-prisir/build/prisir.so \
  --engine dist/libprisir_ime.so \
  --db assets/ciku.db \
  --helpers helpers \
  --version 0.3.1 \
  --out dist/fcitx5-prisir_0.3.1_amd64.deb

echo "[3] install"
dpkg -r fcitx5-prisir 2>/dev/null || true
rm -f /usr/lib/x86_64-linux-gnu/fcitx5/libprisir.so
dpkg -i dist/fcitx5-prisir_0.3.1_amd64.deb
ls /usr/lib/fcitx5/prisir/

echo "[4] restart fcitx5"
pkill -u debianuser fcitx5 2>/dev/null || true
sleep 1
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 2
pgrep -a fcitx5 || true

echo "[5] openapi smoke (force)"
pkill -f prisir_openapi 2>/dev/null || true
python3 /usr/lib/fcitx5/prisir/prisir_openapi --force &
OPID=$!
sleep 1
curl -s http://127.0.0.1:23331/health || true
echo
curl -s http://127.0.0.1:23331/rpc -d '{"method":"query","params":{"pinyin":"nihao"},"id":1}' || true
echo
kill $OPID 2>/dev/null || true

echo "[6] engine smoke"
python3 tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases prisir_ime/abi_cases.json

echo DONE
dpkg -l fcitx5-prisir | tail -1
