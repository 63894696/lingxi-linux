#!/bin/bash
set -e
U=debianuser
H=/home/$U
install -d -o $U -g $U $H/.config/fcitx5

cat > $H/.config/fcitx5/profile <<'EOF'
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=prisir

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=prisir
# Layout
Layout=

[GroupOrder]
0=Default
EOF

cat > $H/.config/fcitx5/config <<'EOF'
[Hotkey]
EnumerateWithTriggerKeys=True
EnumerateSkipFirst=False

[Hotkey/TriggerKeys]
0=Control+space
1=Zenkaku_Hankaku
2=Hangul

[Hotkey/AltTriggerKeys]
0=Shift_L

[Hotkey/EnumerateForwardKeys]
0=Control+Shift_L

[Hotkey/EnumerateBackwardKeys]
0=Control+Shift_R

[Hotkey/EnumerateGroupForwardKeys]
0=Super+space

[Hotkey/EnumerateGroupBackwardKeys]
0=Shift+Super+space

[Behavior]
ActiveByDefault=False
ShareInputState=No
ShowInputMethodInformation=True
EOF

chown -R $U:$U $H/.config/fcitx5

# 必须先杀掉旧 fcitx5 再写 profile：退出时会把内存里的旧配置刷盘，
# 把刚写好的 prisir 组冲成只有 keyboard-us。
pkill -u "$U" fcitx5 2>/dev/null || true
sleep 1
# 再写一次，防止上面 kill 刷盘覆盖
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
chown $U:$U $H/.config/fcitx5/profile

cat > $H/.xinitrc <<'EOF'
#!/bin/sh
export XDG_CURRENT_DESKTOP=LXQt
export XDG_SESSION_TYPE=x11
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx
export SDL_IM_MODULE=fcitx
fcitx5 -d --verbose 2 >/tmp/fcitx5-debianuser.log 2>&1 || true
exec startlxqt
EOF
chown $U:$U $H/.xinitrc
chmod +x $H/.xinitrc

grep -q GTK_IM_MODULE=fcitx /etc/environment 2>/dev/null || cat >> /etc/environment <<'EOF'
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

# Start now in live X session (as root use runuser; no sudo on this box)
pkill -u "$U" fcitx5 2>/dev/null || true
sleep 1
runuser -u "$U" -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 2
runuser -u "$U" -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  fcitx5-remote -s prisir || true
runuser -u "$U" -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  fcitx5-remote -n || true
pgrep -a fcitx5 || echo 'fcitx5 NOT running'
echo DONE
