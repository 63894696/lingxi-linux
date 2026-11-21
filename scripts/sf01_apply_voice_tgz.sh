#!/bin/bash
set -euo pipefail
cd /tmp
tar -xzf prisir_voice_fix.tgz
# verify not truncated
grep -n 'self.on_trigger = on_trigger' helpers/prisir_voice
python3 -m py_compile helpers/prisir_voice

install -m 0755 helpers/prisir_voice /usr/lib/fcitx5/prisir/prisir_voice
cp helpers/prisir_voice /root/lingxi-linux/helpers/prisir_voice
cp fcitx5-prisir/src/prisir.cpp /root/lingxi-linux/fcitx5-prisir/src/prisir.cpp
mkdir -p /root/lingxi-linux/packaging
cp packaging/prisir-voice.desktop packaging/prisir-voice.service /root/lingxi-linux/packaging/
install -m 0644 packaging/prisir-voice.desktop /etc/xdg/autostart/prisir-voice.desktop

# rebuild addon
cmake --build /root/lingxi-linux/fcitx5-prisir/build -j"$(nproc)"
install -m 0644 /root/lingxi-linux/fcitx5-prisir/build/prisir.so /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so

# systemd unit with X env
install -d /home/debianuser/.config/systemd/user
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
chown -R debianuser:debianuser /home/debianuser/.config/systemd

# kill old
pkill -u debianuser -f /usr/lib/fcitx5/prisir/prisir_voice || true
sleep 1
rm -f /run/user/1000/prisir_voice.sock /run/user/1000/prisir_voice.lock /run/user/1000/prisir_voice.pid
rm -f /tmp/prisir-1000/prisir_voice.sock

runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user daemon-reload
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user enable prisir-voice.service
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user restart prisir-voice.service
sleep 2

# verify remote line 416
sed -n '414,417p' /usr/lib/fcitx5/prisir/prisir_voice
ls -la /run/user/1000/prisir_voice.sock || true
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 /usr/lib/fcitx5/prisir/prisir_voice --status
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 /usr/lib/fcitx5/prisir/prisir_voice --toggle
sleep 1
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 /usr/lib/fcitx5/prisir/prisir_voice --status
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 /usr/lib/fcitx5/prisir/prisir_voice --toggle
sleep 1
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 /usr/lib/fcitx5/prisir/prisir_voice --status
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user is-enabled prisir-voice.service
strings /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so | grep -a prisir-voice
echo APPLY_OK
