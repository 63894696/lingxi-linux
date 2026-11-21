#!/bin/bash
set -euo pipefail
cd /tmp
tar -xzf prisir_openapi_fix.tgz

python3 -m py_compile helpers/prisir_openapi helpers/prisir_openapi_ui helpers/prisir_about

install -m 0755 helpers/prisir_openapi /usr/lib/fcitx5/prisir/prisir_openapi
install -m 0755 helpers/prisir_openapi_ui /usr/lib/fcitx5/prisir/prisir_openapi_ui
install -m 0755 helpers/prisir_about /usr/lib/fcitx5/prisir/prisir_about
cp helpers/prisir_openapi helpers/prisir_openapi_ui helpers/prisir_about /root/lingxi-linux/helpers/
cp fcitx5-prisir/src/prisir.cpp /root/lingxi-linux/fcitx5-prisir/src/prisir.cpp
mkdir -p /root/lingxi-linux/packaging
cp packaging/* /root/lingxi-linux/packaging/ 2>/dev/null || true

install -m 0644 packaging/prisir-openapi.desktop /etc/xdg/autostart/prisir-openapi.desktop
install -d /home/debianuser/.config/systemd/user
install -m 0644 packaging/prisir-openapi.service /home/debianuser/.config/systemd/user/prisir-openapi.service
chown -R debianuser:debianuser /home/debianuser/.config/systemd

cmake --build /root/lingxi-linux/fcitx5-prisir/build -j"$(nproc)"
install -m 0644 /root/lingxi-linux/fcitx5-prisir/build/prisir.so /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so

# enable config for smoke (user can turn off in UI)
python3 - <<'PY'
from pathlib import Path
import json, os, pwd
p = Path("/home/debianuser/.config/prisir/open_api.json")
p.parent.mkdir(parents=True, exist_ok=True)
cfg = {"enabled": True, "port": 23331, "bind": "127.0.0.1"}
p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
u = pwd.getpwnam("debianuser")
os.chown(p, u.pw_uid, u.pw_gid)
os.chown(p.parent, u.pw_uid, u.pw_gid)
print("wrote", p)
PY

pkill -u debianuser -f /usr/lib/fcitx5/prisir/prisir_openapi || true
sleep 1

runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 HOME=/home/debianuser \
  systemctl --user daemon-reload
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 HOME=/home/debianuser \
  systemctl --user enable prisir-openapi.service
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 HOME=/home/debianuser \
  /usr/lib/fcitx5/prisir/prisir_openapi --start
sleep 1

echo "=== health ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/health || true
echo
echo "=== query ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"query","params":{"pinyin":"nihao"},"id":1}' || true
echo
echo "=== classify ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"classify","params":{"input":"hello"},"id":2}' || true
echo
echo "=== sentences ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"sentences","params":{"input":"nihaoshijie","k":3},"id":3}' || true
echo
echo "=== status rpc ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"status","id":4}' || true
echo
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 HOME=/home/debianuser \
  /usr/lib/fcitx5/prisir/prisir_openapi --status

# restart fcitx to pick up --start on load
pkill -u debianuser fcitx5 || true
sleep 1
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  XAUTHORITY=/home/debianuser/.Xauthority \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 2
pgrep -a fcitx5 || true
curl -s http://127.0.0.1:23331/health || true
echo
echo OPENAPI_READY
