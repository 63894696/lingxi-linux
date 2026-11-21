#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq python3-pip python3-venv xdotool 2>&1 | tail -8
python3 -m pip install --break-system-packages -q numpy onnxruntime sounddevice
python3 -c 'import numpy,onnxruntime,sounddevice; print("deps OK")'
mkdir -p /usr/lib/fcitx5/prisir/voice/sensevoice-small
ls -lh /usr/lib/fcitx5/prisir/voice/sensevoice-small/ || true
# quick model load smoke if present
if [[ -f /usr/lib/fcitx5/prisir/voice/sensevoice-small/model.onnx ]]; then
  python3 - <<'PY'
from pathlib import Path
import json, onnxruntime as ort
p = Path('/usr/lib/fcitx5/prisir/voice/sensevoice-small')
s = ort.InferenceSession(str(p/'model.onnx'), providers=['CPUExecutionProvider'])
toks = json.loads((p/'tokens.json').read_text())
print('model OK inputs', [i.name for i in s.get_inputs()], 'tokens', len(toks))
PY
fi
echo DONE
