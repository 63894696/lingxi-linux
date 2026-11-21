#!/bin/bash
# 部署常驻语音 daemon + 热键设置（需先把源码 scp 到 /root/lingxi-linux）
set -euo pipefail
ROOT=/root/lingxi-linux
cd "$ROOT"

echo "[1] apt deps (pynput + Xlib)"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq python3-pynput python3-xlib

echo "[2] install helper"
install -m 0755 helpers/prisir_voice /usr/lib/fcitx5/prisir/prisir_voice
sed -i 's/\r$//' /usr/lib/fcitx5/prisir/prisir_voice
python3 -m py_compile /usr/lib/fcitx5/prisir/prisir_voice
echo "helper OK"

echo "[3] rebuild addon"
cmake --build fcitx5-prisir/build -j"$(nproc)"
install -m 0644 fcitx5-prisir/build/prisir.so /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so
echo "addon OK"

echo "[4] stop old voice daemon"
pkill -f '/usr/lib/fcitx5/prisir/prisir_voice' 2>/dev/null || true
rm -f /run/user/1000/prisir_voice.sock /tmp/prisir-1000/prisir_voice.sock 2>/dev/null || true

echo "[5] restart fcitx5 as debianuser"
pkill -u debianuser fcitx5 2>/dev/null || true
sleep 1
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 2
pgrep -a fcitx5 || true

echo "[6] smoke: start daemon as debianuser + ping"
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  /usr/lib/fcitx5/prisir/prisir_voice --daemon >/tmp/prisir_voice_daemon.log 2>&1 &
sleep 2
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  /usr/lib/fcitx5/prisir/prisir_voice --status || true
echo "--- daemon log ---"
tail -20 /tmp/prisir_voice_daemon.log || true
echo HOTKEY_READY
