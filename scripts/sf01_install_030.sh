#!/bin/bash
set -euo pipefail
cd /root/lingxi-linux

DEB=dist/fcitx5-prisir_0.3.0_amd64.deb
ls -lh "$DEB"
dpkg-deb -c "$DEB" | head -40

echo "[1] remove 0.2.0"
dpkg -r fcitx5-prisir 2>/dev/null || true
rm -f /usr/lib/x86_64-linux-gnu/fcitx5/libprisir.so
rm -f /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so

echo "[2] install 0.3.0"
dpkg -i "$DEB" || apt-get install -y -f -qq
dpkg -l fcitx5-prisir | cat
ls -lh /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so /usr/lib/fcitx5/prisir/
ls /usr/lib/fcitx5/prisir/
cat /usr/share/fcitx5/addon/prisir.conf

echo "[3] ensure profile"
U=debianuser
H=/home/$U
install -d -o $U -g $U $H/.config/fcitx5
cat > $H/.config/fcitx5/profile <<'EOF'
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=prisir

[Groups/0/Items/0]
Name=keyboard-us
Layout=

[Groups/0/Items/1]
Name=prisir
Layout=

[GroupOrder]
0=Default
EOF
chown -R $U:$U $H/.config/fcitx5

echo "[4] restart fcitx5"
pkill -u $U fcitx5 2>/dev/null || true
sleep 1
: > /tmp/fcitx5-030.log
runuser -u $U -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d --verbose=2 >/tmp/fcitx5-030.log 2>&1 || true
sleep 3
pgrep -a fcitx5 || echo 'fcitx5 NOT running'
grep -E 'Loaded addon prisir|assert|Signal No|abort' /tmp/fcitx5-030.log || true
tail -15 /tmp/fcitx5-030.log

echo "[5] smoke_matrix"
python3 tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases prisir_ime/abi_cases.json

echo DONE
