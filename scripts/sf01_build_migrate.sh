#!/bin/bash
# Build migrated 0.3.0 on SF01 from synced tree and install.
set -euo pipefail
ROOT=/root/lingxi-linux
cd "$ROOT"

echo "[1] cmake addon"
cmake -B fcitx5-prisir/build -S fcitx5-prisir
cmake --build fcitx5-prisir/build -j"$(nproc)"
ls -lh fcitx5-prisir/build/prisir.so

echo "[2] engine (prefer existing WSL-built)"
SO="$ROOT/dist/libprisir_ime.so"
if [[ ! -f "$SO" ]]; then
  echo "missing $SO — upload from WSL build first" >&2
  exit 1
fi

echo "[3] pack 0.3.0"
bash scripts/pack_deb.sh \
  --addon fcitx5-prisir/build/prisir.so \
  --engine "$SO" \
  --db assets/ciku.db \
  --helpers helpers \
  --version 0.3.0 \
  --out dist/fcitx5-prisir_0.3.0_amd64.deb

echo "[4] install"
# remove old layout files that conflict (0.2.0 used libprisir.so)
dpkg -r fcitx5-prisir 2>/dev/null || true
rm -f /usr/lib/x86_64-linux-gnu/fcitx5/libprisir.so
dpkg -i dist/fcitx5-prisir_0.3.0_amd64.deb

echo "[5] restart fcitx5"
pkill -u debianuser fcitx5 2>/dev/null || true
sleep 1
: > /tmp/fcitx5-030.log
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d --verbose=2 >/tmp/fcitx5-030.log 2>&1 || true
sleep 3
pgrep -a fcitx5 || echo 'fcitx5 NOT running'
grep -E 'prisir|assert|Signal|Loaded addon prisir' /tmp/fcitx5-030.log | tail -20 || true

echo "[6] smoke"
python3 tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases prisir_ime/abi_cases.json || true

echo DONE
dpkg -l fcitx5-prisir | tail -1
