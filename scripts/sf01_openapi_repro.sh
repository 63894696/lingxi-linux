#!/bin/bash
set -euo pipefail
export HOME=/home/debianuser
export XDG_RUNTIME_DIR=/run/user/1000
HELPER=/usr/lib/fcitx5/prisir/prisir_openapi
CFG=$HOME/.config/prisir/open_api.json

echo "=== STEP0 ==="
cat "$CFG"
$HELPER --status || true

echo "=== STEP1 disable+stop ==="
python3 - <<'PY'
import json
from pathlib import Path
p=Path("/home/debianuser/.config/prisir/open_api.json")
c=json.loads(p.read_text()); c["enabled"]=False; c["port"]=28111
p.write_text(json.dumps(c, ensure_ascii=False, indent=2)+"\n")
print(c)
PY
$HELPER --stop || true
sleep 0.5
$HELPER --status || true
pgrep -af prisir_openapi || echo no_proc

echo "=== STEP2 enable+start port 28111 ==="
python3 - <<'PY'
import json
from pathlib import Path
p=Path("/home/debianuser/.config/prisir/open_api.json")
c=json.loads(p.read_text()); c["enabled"]=True; c["port"]=28111
p.write_text(json.dumps(c, ensure_ascii=False, indent=2)+"\n")
print(c)
PY
$HELPER --start; echo start_exit:$?
sleep 1
$HELPER --status || true
curl -s --connect-timeout 1 http://127.0.0.1:28111/health || echo health_fail
echo
pgrep -af 'prisir_openapi' || true
tail -15 /run/user/1000/prisir_openapi.log || true
