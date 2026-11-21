#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq libportaudio2 portaudio19-dev xdotool
python3 - <<'PY'
import numpy, onnxruntime, sounddevice
print('deps OK')
import json
from pathlib import Path
p = Path('/usr/lib/fcitx5/prisir/voice/sensevoice-small')
print('model files:', list(p.glob('*')))
s = onnxruntime.InferenceSession(str(p/'model.onnx'), providers=['CPUExecutionProvider'])
toks = json.loads((p/'tokens.json').read_text(encoding='utf-8'))
print('model OK', [i.name for i in s.get_inputs()], 'tokens', len(toks))
PY
echo DONE
