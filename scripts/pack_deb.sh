#!/usr/bin/env bash
# Pack fcitx5-prisir .deb from built artifacts.
# Usage (on Linux):
#   bash scripts/pack_deb.sh \
#     --addon build/prisir.so \
#     --engine prisir_ime/target/release/libprisir_ime.so \
#     --db /path/to/ciku.db \
#     --out dist/fcitx5-prisir_0.1.0_amd64.deb
set -euo pipefail

VERSION="${VERSION:-0.3.6}"
# 0.3.6: 九键 T9 长音节优先展开（修 caidan→菜单）；Apache-2.0 + SenseVoice
ADDON=""
ENGINE=""
DB=""
OUT=""
HELPERS=""
VOICE_MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --addon) ADDON="$2"; shift 2 ;;
    --engine) ENGINE="$2"; shift 2 ;;
    --db) DB="$2"; shift 2 ;;
    --helpers) HELPERS="$2"; shift 2 ;;
    --voice-model) VOICE_MODEL="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$ADDON" && -f "$ADDON" ]] || { echo "need --addon prisir.so" >&2; exit 2; }
[[ -n "$ENGINE" && -f "$ENGINE" ]] || { echo "need --engine libprisir_ime.so" >&2; exit 2; }
[[ -n "$DB" && -f "$DB" ]] || { echo "need --db ciku.db" >&2; exit 2; }
OUT="${OUT:-dist/fcitx5-prisir_${VERSION}_amd64.deb}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPERS="${HELPERS:-$ROOT/helpers}"
# SenseVoice：必须进包，装完即可听写（与 Win 同款目录布局）
if [[ -z "$VOICE_MODEL" ]]; then
  for cand in \
    "$ROOT/assets/voice/sensevoice-small" \
    "$ROOT/voice/sensevoice-small" \
    /usr/lib/fcitx5/prisir/voice/sensevoice-small
  do
    if [[ -f "$cand/model.onnx" && -f "$cand/tokens.json" ]]; then
      VOICE_MODEL="$cand"
      break
    fi
  done
fi
[[ -n "$VOICE_MODEL" && -f "$VOICE_MODEL/model.onnx" && -f "$VOICE_MODEL/tokens.json" ]] \
  || { echo "need SenseVoice model dir (--voice-model with model.onnx+tokens.json)" >&2; exit 2; }

STAGE="$(mktemp -d /tmp/fcitx5-prisir-deb.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p \
  "$STAGE/DEBIAN" \
  "$STAGE/usr/lib/x86_64-linux-gnu/fcitx5" \
  "$STAGE/usr/lib/fcitx5/prisir" \
  "$STAGE/usr/share/fcitx5/addon" \
  "$STAGE/usr/share/fcitx5/inputmethod"

install -m 0644 "$ADDON" "$STAGE/usr/lib/x86_64-linux-gnu/fcitx5/prisir.so"
install -m 0644 "$ENGINE" "$STAGE/usr/lib/fcitx5/prisir/libprisir_ime.so"
install -m 0644 "$DB" "$STAGE/usr/lib/fcitx5/prisir/ciku.db"
install -m 0644 "$ROOT/fcitx5-prisir/prisir.conf.in" "$STAGE/usr/share/fcitx5/addon/prisir.conf"
install -m 0644 "$ROOT/fcitx5-prisir/prisir-inputmethod.conf" "$STAGE/usr/share/fcitx5/inputmethod/prisir.conf"
# Apache License 2.0
mkdir -p "$STAGE/usr/share/doc/fcitx5-prisir"
if [[ -f "$ROOT/LICENSE.txt" ]]; then
  install -m 0644 "$ROOT/LICENSE.txt" "$STAGE/usr/share/doc/fcitx5-prisir/LICENSE.txt"
  install -m 0644 "$ROOT/LICENSE.txt" "$STAGE/usr/lib/fcitx5/prisir/LICENSE.txt"
elif [[ -f "$ROOT/packaging/LICENSE.txt" ]]; then
  install -m 0644 "$ROOT/packaging/LICENSE.txt" "$STAGE/usr/share/doc/fcitx5-prisir/LICENSE.txt"
  install -m 0644 "$ROOT/packaging/LICENSE.txt" "$STAGE/usr/lib/fcitx5/prisir/LICENSE.txt"
fi

# helpers：词库/造词/符号/语音/关于/开放API。不打包手写/AI。
for h in prisir_dict prisir_dict.py prisir_quick_add prisir_symbols prisir_about prisir_voice prisir_openapi prisir_openapi_ui; do
  if [[ -f "$HELPERS/$h" ]]; then
    install -m 0755 "$HELPERS/$h" "$STAGE/usr/lib/fcitx5/prisir/$h"
  fi
done
# 语音模型（装完即用）
mkdir -p "$STAGE/usr/lib/fcitx5/prisir/voice/sensevoice-small"
install -m 0644 "$VOICE_MODEL/model.onnx" "$STAGE/usr/lib/fcitx5/prisir/voice/sensevoice-small/model.onnx"
install -m 0644 "$VOICE_MODEL/tokens.json" "$STAGE/usr/lib/fcitx5/prisir/voice/sensevoice-small/tokens.json"
if [[ -f "$VOICE_MODEL/config.yaml" ]]; then
  install -m 0644 "$VOICE_MODEL/config.yaml" "$STAGE/usr/lib/fcitx5/prisir/voice/sensevoice-small/config.yaml"
fi
echo "[pack] voice-model=$(du -h "$VOICE_MODEL/model.onnx" | cut -f1) from $VOICE_MODEL"

# 自启：xdg autostart + user systemd 单元模板
mkdir -p \
  "$STAGE/etc/xdg/autostart" \
  "$STAGE/usr/lib/systemd/user" \
  "$STAGE/usr/share/prisir/packaging"
for d in prisir-voice.desktop prisir-openapi.desktop; do
  if [[ -f "$ROOT/packaging/$d" ]]; then
    install -m 0644 "$ROOT/packaging/$d" "$STAGE/etc/xdg/autostart/$d"
    install -m 0644 "$ROOT/packaging/$d" "$STAGE/usr/share/prisir/packaging/$d"
  fi
done
for s in prisir-voice.service prisir-openapi.service; do
  if [[ -f "$ROOT/packaging/$s" ]]; then
    install -m 0644 "$ROOT/packaging/$s" "$STAGE/usr/lib/systemd/user/$s"
    install -m 0644 "$ROOT/packaging/$s" "$STAGE/usr/share/prisir/packaging/$s"
  fi
done

SIZE_KB=$(du -sk "$STAGE" | cut -f1)
cat > "$STAGE/DEBIAN/control" <<EOF
Package: fcitx5-prisir
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Depends: fcitx5-modules, libfcitx5core7 | libfcitx5core2 | libfcitx5core1, libc6, python3, python3-gi, gir1.2-gtk-3.0
Recommends: python3-numpy, python3-onnxruntime, python3-sounddevice, xdotool
Maintainer: BabelSpan <dev@babelspan.com>
Installed-Size: ${SIZE_KB}
Description: Lingxi Pinyin (fcitx5) — full offline package
 Core IME + full lexicon + SenseVoice model + Open API.
 Install once; voice dictation works without a second download.
 No handwriting (Win Ink vs ONNX) or AI assistant tray.
EOF
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
# 语音/OpenAPI：把 user unit 落到常见登录用户（debianuser / 当前 SUDO_USER）
_install_user_units() {
  u="$1"
  home=$(getent passwd "$u" | cut -d: -f6)
  [ -n "$home" ] || return 0
  uid=$(id -u "$u" 2>/dev/null) || return 0
  mkdir -p "$home/.config/systemd/user"
  for s in prisir-voice.service prisir-openapi.service; do
    if [ -f "/usr/lib/systemd/user/$s" ]; then
      install -m 0644 "/usr/lib/systemd/user/$s" "$home/.config/systemd/user/$s"
      chown "$u:$u" "$home/.config/systemd/user/$s" 2>/dev/null || true
    fi
  done
  if [ -d "/run/user/$uid" ]; then
    runuser -u "$u" -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user daemon-reload 2>/dev/null || true
    runuser -u "$u" -- env XDG_RUNTIME_DIR="/run/user/$uid" systemctl --user enable prisir-voice.service 2>/dev/null || true
  fi
}
for cand in debianuser "${SUDO_USER:-}" ; do
  [ -n "$cand" ] || continue
  id "$cand" >/dev/null 2>&1 && _install_user_units "$cand"
done
if command -v fcitx5-remote >/dev/null 2>&1; then
  fcitx5-remote -r || true
fi
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

mkdir -p "$(dirname "$OUT")"
dpkg-deb --build "$STAGE" "$OUT"
echo "built $OUT ($(du -h "$OUT" | cut -f1))"
