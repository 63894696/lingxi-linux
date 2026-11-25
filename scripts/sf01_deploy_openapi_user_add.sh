#!/bin/bash
# 部署 Open API 造词 RPC（user_add / user_add_batch）并冒烟。
set -euo pipefail

install -m 0755 /root/lingxi-linux/helpers/prisir_openapi /usr/lib/fcitx5/prisir/prisir_openapi
install -m 0755 /root/lingxi-linux/helpers/prisir_about /usr/lib/fcitx5/prisir/prisir_about
python3 -m py_compile /usr/lib/fcitx5/prisir/prisir_openapi

python3 <<'PY'
import json, os, pwd
from pathlib import Path
u = pwd.getpwnam("debianuser")
p = Path("/home/debianuser/.config/prisir/open_api.json")
p.parent.mkdir(parents=True, exist_ok=True)
cfg = {"enabled": True, "bind": "127.0.0.1", "port": 23331}
if p.exists():
    try:
        cfg.update(json.loads(p.read_text(encoding="utf-8")))
    except Exception:
        pass
cfg["enabled"] = True
cfg.setdefault("bind", "127.0.0.1")
cfg.setdefault("port", 23331)
p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
os.chown(p, u.pw_uid, u.pw_gid)
os.chown(p.parent, u.pw_uid, u.pw_gid)
print("cfg", cfg)
PY

pkill -u debianuser -f /usr/lib/fcitx5/prisir/prisir_openapi || true
sleep 1
runuser -u debianuser -- env HOME=/home/debianuser XDG_RUNTIME_DIR=/run/user/1000 \
  /usr/lib/fcitx5/prisir/prisir_openapi --start
sleep 1

echo "=== health ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/health
echo
echo "=== user_add ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"user_add","params":{"word":"开放接口探针","pos":1},"id":1}'
echo
echo "=== user_add_batch ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"user_add_batch","params":{"words":["fcitx5","灵犀拼音","雅可比猜想"],"pos":1},"id":2}'
echo
echo "=== query lxpy ==="
runuser -u debianuser -- curl -s http://127.0.0.1:23331/rpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"query","params":{"pinyin":"lxpy"},"id":3}'
echo
echo DONE_OPENAPI_USER_ADD
