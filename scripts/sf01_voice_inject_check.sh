#!/bin/bash
set -e
python3 -c 'import numpy,onnxruntime,sounddevice,gi; print("deps_ok")'
ls -la /usr/lib/fcitx5/prisir/prisir_voice
which xdotool
grep -nE 'resolve_target|accept_focus|已上屏|self.hide' /usr/lib/fcitx5/prisir/prisir_voice | head
test -f /usr/lib/fcitx5/prisir/voice/sensevoice-small/model.onnx && echo MODEL_OK
echo READY
