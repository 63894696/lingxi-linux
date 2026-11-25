#!/bin/bash
# 部署「灵犀造词」：helper + 状态区菜单，打包 0.3.7 并重装。
set -euo pipefail
ROOT=/root/lingxi-linux
cd "$ROOT"

echo "[1] syntax"
python3 -m py_compile helpers/prisir_quick_add
grep -n 'prisir-quick-add\|灵犀造词\|prisir_quick_add' fcitx5-prisir/src/prisir.cpp | head -20
grep -F prisir_quick_add scripts/pack_deb.sh

echo "[2] cmake rebuild addon"
cmake -B fcitx5-prisir/build -S fcitx5-prisir
cmake --build fcitx5-prisir/build -j"$(nproc)"
strings fcitx5-prisir/build/prisir.so | grep -E 'prisir-quick-add|prisir_quick_add'

echo "[3] pack 0.3.7"
ENGINE=dist/libprisir_ime.so
[[ -f "$ENGINE" ]] || ENGINE=/usr/lib/fcitx5/prisir/libprisir_ime.so
DB=assets/ciku.db
[[ -f "$DB" ]] || DB=/usr/lib/fcitx5/prisir/ciku.db
VOICE=/usr/lib/fcitx5/prisir/voice/sensevoice-small
bash scripts/pack_deb.sh \
  --addon fcitx5-prisir/build/prisir.so \
  --engine "$ENGINE" \
  --db "$DB" \
  --voice-model "$VOICE" \
  --helpers helpers \
  --version 0.3.7 \
  --out dist/fcitx5-prisir_0.3.7_amd64.deb

echo "[4] install"
dpkg -i dist/fcitx5-prisir_0.3.7_amd64.deb
install -m 0755 helpers/prisir_quick_add /usr/lib/fcitx5/prisir/prisir_quick_add
test -x /usr/lib/fcitx5/prisir/prisir_quick_add
ls -lh /usr/lib/fcitx5/prisir/prisir_quick_add

echo "[5] engine FFI smoke (user_add_pos / auto_code)"
python3 - <<'PY'
import ctypes, os, tempfile
from ctypes import c_void_p, c_char_p, c_int, c_int64
lib = ctypes.CDLL('/usr/lib/fcitx5/prisir/libprisir_ime.so')
lib.prisir_ime_load.restype = c_void_p
lib.prisir_ime_load.argtypes = [c_char_p, c_int]
lib.prisir_ime_free.argtypes = [c_void_p]
lib.prisir_ime_free_string.argtypes = [c_void_p]
lib.prisir_ime_auto_code.restype = c_void_p
lib.prisir_ime_auto_code.argtypes = [c_void_p, c_char_p]
lib.prisir_ime_word_pinyin.restype = c_void_p
lib.prisir_ime_word_pinyin.argtypes = [c_void_p, c_char_p]
lib.prisir_ime_user_add_pos.restype = c_int
lib.prisir_ime_user_add_pos.argtypes = [c_void_p, c_char_p, c_char_p, c_int64]
h = lib.prisir_ime_load(b'/usr/lib/fcitx5/prisir/ciku.db', 0)
assert h, 'load failed'
def take(p):
    if not p: return ''
    s = ctypes.string_at(p).decode()
    lib.prisir_ime_free_string(p)
    return s
ac = take(lib.prisir_ime_auto_code(h, '北京大学'.encode()))
wp = take(lib.prisir_ime_word_pinyin(h, '北京大学'.encode()))
print('auto_code=', ac, 'word_pinyin=', wp)
assert ac and wp, (ac, wp)
# 写一条可识别的测试词到用户库（不影响主库）
ok = lib.prisir_ime_user_add_pos(h, b'lxzcsmoketest', '灵犀造词探针'.encode(), c_int64(1))
print('user_add_pos=', ok)
assert ok == 1
lib.prisir_ime_free(h)
print('OK FFI')
PY

echo "[6] restart fcitx5"
pkill -9 -u debianuser fcitx5 2>/dev/null || true
sleep 2
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
  fcitx5 -d --replace >/tmp/fcitx5-quickadd.log 2>&1 || true
sleep 2
grep -F 'Loaded addon prisir' /tmp/fcitx5-quickadd.log || cat /tmp/fcitx5-quickadd.log | tail -40
runuser -u debianuser -- env DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 \
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus fcitx5-remote -s prisir || true
echo DONE_QUICK_ADD_0.3.7
