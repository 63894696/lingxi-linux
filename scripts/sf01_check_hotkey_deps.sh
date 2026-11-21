#!/bin/bash
set -e
python3 - <<'PY'
miss=[]
for m in ("pynput","Xlib","gi"):
    try:
        __import__(m if m!="Xlib" else "Xlib")
        print(m, "OK")
    except Exception as e:
        print(m, "MISS", e)
        miss.append(m)
print("MISS_LIST", ",".join(miss) if miss else "none")
PY
echo "DISPLAY=${DISPLAY:-unset}"
# session type (X11 vs wayland)
loginctl list-sessions --no-legend 2>/dev/null | head -5 || true
who
ps aux | grep -E 'Xorg|wayland|gnome-session|lightdm|sddm' | grep -v grep | head -8
pip3 show pynput 2>/dev/null | head -3 || true
