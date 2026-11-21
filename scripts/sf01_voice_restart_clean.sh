#!/bin/bash
set -euo pipefail
# 清掉所有旧 daemon，用新脚本 + systemd 拉起唯一实例
pkill -u debianuser -f '/usr/lib/fcitx5/prisir/prisir_voice' 2>/dev/null || true
sleep 1
pkill -9 -u debianuser -f '/usr/lib/fcitx5/prisir/prisir_voice' 2>/dev/null || true
rm -f /run/user/1000/prisir_voice.sock /run/user/1000/prisir_voice.lock /run/user/1000/prisir_voice.pid
rm -f /run/user/1000/prisir_voice_daemon.log

# systemd user unit：带上 X 环境
cat > /home/debianuser/.config/systemd/user/prisir-voice.service <<'EOF'
[Unit]
Description=Lingxi voice dictation daemon
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 -u /usr/lib/fcitx5/prisir/prisir_voice --daemon
Restart=on-failure
RestartSec=2
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/debianuser/.Xauthority
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
Environment=GTK_IM_MODULE=fcitx
Environment=QT_IM_MODULE=fcitx
Environment=XMODIFIERS=@im=fcitx

[Install]
WantedBy=default.target
EOF
chown debianuser:debianuser /home/debianuser/.config/systemd/user/prisir-voice.service

runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user daemon-reload
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user restart prisir-voice.service
sleep 5
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  systemctl --user status prisir-voice.service --no-pager | head -20
echo "--- status ---"
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  /usr/lib/fcitx5/prisir/prisir_voice --status || true
echo "--- procs ---"
pgrep -af prisir_voice || true
echo "--- log ---"
tail -30 /run/user/1000/prisir_voice_daemon.log 2>/dev/null || \
  journalctl --user -u prisir-voice.service -n 30 --no-pager 2>/dev/null || \
  runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
    journalctl --user -u prisir-voice.service -n 30 --no-pager || true
echo CLEAN_OK
