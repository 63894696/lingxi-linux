#!/bin/bash
set -e
python3 <<'PY'
from pathlib import Path
import os, pwd
p = Path("/home/debianuser/.config/prisir/voice.json")
p.parent.mkdir(parents=True, exist_ok=True)
p.write_text('{\n  "hotkey": "alt_r"\n}\n', encoding="utf-8")
u = pwd.getpwnam("debianuser")
os.chown(p, u.pw_uid, u.pw_gid)
os.chown(p.parent, u.pw_uid, u.pw_gid)
print(p.read_text())
PY
strings /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so | grep -aE '语音|prisir-voice' || true
runuser -u debianuser -- env XDG_RUNTIME_DIR=/run/user/1000 \
  /usr/lib/fcitx5/prisir/prisir_voice --status || true
