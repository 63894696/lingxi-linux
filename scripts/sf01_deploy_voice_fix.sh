#!/bin/bash
# 修复：可拖浮窗 / 去掉「语音热键」菜单 / 开机自启 / 修 daemon 崩溃
set -euo pipefail
ROOT=/root/lingxi-linux
cd "$ROOT"

echo "[1] helper"
install -m 0755 helpers/prisir_voice /usr/lib/fcitx5/prisir/prisir_voice
sed -i 's/\r$//' /usr/lib/fcitx5/prisir/prisir_voice
python3 -m py_compile /usr/lib/fcitx5/prisir/prisir_voice

echo "[2] rebuild addon (drop 语音热键 menu + autostart --start)"
cmake --build fcitx5-prisir/build -j"$(nproc)"
install -m 0644 fcitx5-prisir/build/prisir.so /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so

echo "[3] autostart desktop + user systemd"
install -m 0644 packaging/prisir-voice.desktop /etc/xdg/autostart/prisir-voice.desktop
install -d /home/debianuser/.config/systemd/user
install -m 0644 packaging/prisir-voice.service /home/debianuser/.config/systemd/user/prisir-voice.service
chown -R debianuser:debianuser /home/debianuser/.config/systemd
# enable for user session
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user daemon-reload || true
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user enable --now prisir-voice.service || true

echo "[4] restart voice daemon + fcitx"
pkill -u debianuser -f '/usr/lib/fcitx5/prisir/prisir_voice' 2>/dev/null || true
rm -f /run/user/1000/prisir_voice.sock
sleep 1
pkill -u debianuser fcitx5 2>/dev/null || true
sleep 1
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  XAUTHORITY=/home/debianuser/.Xauthority \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 3

echo "[5] ensure daemon"
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  XAUTHORITY=/home/debianuser/.Xauthority \
  /usr/lib/fcitx5/prisir/prisir_voice --start
sleep 2
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  /usr/lib/fcitx5/prisir/prisir_voice --status
pgrep -af prisir_voice || true
strings /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so | grep -aE 'prisir-voice|语音' || true
echo FIX_READY
