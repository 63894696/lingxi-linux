#!/bin/bash
# Install original LingxiPinyin 0.2.0 as root (no sudo on SF01) and smoke-test.
set -euo pipefail

DEB=/root/lingxi-linux/dist/LingxiPinyin-Linux-x86_64-0.2.0_amd64.deb
ORIG0906=/root/lingxi-linux/dist/fcitx5-prisir_0.1.0_ORIGINAL-20260906_amd64.deb

echo "[1] remove current fcitx5-prisir if any"
dpkg -r fcitx5-prisir 2>/dev/null || true
# leftover files from our 0.1.0 layout
rm -f /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so || true

echo "[2] deps"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq python3-gi gir1.2-gtk-3.0 2>&1 | tail -5

echo "[3] install 0.2.0"
dpkg -i "$DEB" || apt-get install -y -f -qq
dpkg -l fcitx5-prisir | cat
echo "--- installed files ---"
ls -lh /usr/lib/x86_64-linux-gnu/fcitx5/*prisir* /usr/lib/fcitx5/prisir/libprisir_ime.so 2>&1 | head -20
cat /usr/share/fcitx5/addon/prisir.conf
cat /usr/share/fcitx5/inputmethod/prisir.conf

echo "[4] ensure debianuser profile has prisir"
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

echo "[5] restart fcitx5 as debianuser"
pkill -u $U fcitx5 2>/dev/null || true
sleep 1
: > /tmp/fcitx5-020-test.log
runuser -u $U -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d --verbose=2 >/tmp/fcitx5-020-test.log 2>&1 || true
sleep 3

echo "[6] status"
pgrep -a fcitx5 || echo 'fcitx5 NOT running'
runuser -u $U -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  fcitx5-remote -n || true
runuser -u $U -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  fcitx5-remote -s prisir || true
sleep 1
runuser -u $U -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  fcitx5-remote -n || true

echo "[7] engine smoke (ABI, independent of UI)"
python3 /root/lingxi-linux/tools/smoke_matrix.py \
  --lib /usr/lib/fcitx5/prisir/libprisir_ime.so \
  --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases /root/lingxi-linux/prisir_ime/abi_cases.json || true

echo "[8] log tail"
grep -E 'prisir|assert|Signal|abort|Loaded addon' /tmp/fcitx5-020-test.log | tail -40 || true
tail -30 /tmp/fcitx5-020-test.log || true
# also check if still alive after a few seconds
sleep 2
pgrep -a fcitx5 || echo 'fcitx5 DIED after switch'
echo DONE
echo "NOTE: no sudo on this host — use root SSH or: su -"
echo "ORIG0906 also at: $ORIG0906"
