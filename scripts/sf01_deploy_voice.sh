#!/bin/bash
set -euo pipefail
cd /root/lingxi-linux
tar -xzf dist/fcitx5_src.tgz -C fcitx5-prisir
tar -xzf dist/helpers.tgz -C helpers
cmake --build fcitx5-prisir/build -j"$(nproc)"
install -m 0644 fcitx5-prisir/build/prisir.so /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so
for h in prisir_dict prisir_dict.py prisir_quick_add prisir_symbols prisir_about prisir_voice prisir_openapi prisir_openapi_ui; do
  if [[ -f "helpers/$h" ]]; then
    install -m 0755 "helpers/$h" "/usr/lib/fcitx5/prisir/$h"
  fi
done
sed -i 's/\r$//' /usr/lib/fcitx5/prisir/prisir_* 2>/dev/null || true
pkill -u debianuser fcitx5 2>/dev/null || true
sleep 1
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d
sleep 2
pgrep -a fcitx5 || true
ls /usr/lib/fcitx5/prisir/
ls /usr/lib/fcitx5/prisir/voice/sensevoice-small/
echo VOICE_READY
