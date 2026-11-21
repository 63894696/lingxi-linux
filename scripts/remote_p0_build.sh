#!/usr/bin/env bash
# P0 build+install on the Linux debug host.
# Expects tree at $HOME/lingxi-linux (or LINGXI_ROOT).
set -euo pipefail

ROOT="${LINGXI_ROOT:-$HOME/lingxi-linux}"
cd "$ROOT"

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
# shellcheck disable=SC1091
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"

echo "[1/5] cargo build --release (prisir_ime)"
# 3–4GB RAM: avoid peak OOM from full LTO+parallel codegen
export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-1}"
(
  cd prisir_ime
  # Override release LTO for this machine if needed
  if [[ "${LINGXI_NO_LTO:-1}" == "1" ]]; then
    mkdir -p .cargo
    cat > .cargo/config.toml <<'EOF'
[profile.release]
lto = false
codegen-units = 16
EOF
  fi
  cargo build --release
)

SO="$ROOT/prisir_ime/target/release/libprisir_ime.so"
[[ -f "$SO" ]] || { echo "missing $SO" >&2; exit 1; }
echo "  engine: $(du -h "$SO" | cut -f1)"

echo "[2/5] cmake build fcitx5 addon"
cmake -B fcitx5-prisir/build -S fcitx5-prisir
cmake --build fcitx5-prisir/build -j"$(nproc)"
ADDON="$ROOT/fcitx5-prisir/build/prisir.so"
[[ -f "$ADDON" ]] || { echo "missing $ADDON" >&2; exit 1; }

DB="$ROOT/assets/ciku.db"
[[ -f "$DB" ]] || { echo "missing $DB — sync assets/ciku.db first" >&2; exit 1; }

echo "[3/5] pack .deb"
bash scripts/pack_deb.sh --addon "$ADDON" --engine "$SO" --db "$DB" --out "$ROOT/dist/fcitx5-prisir_0.1.0_amd64.deb"

echo "[4/5] dpkg install"
dpkg -i "$ROOT/dist/fcitx5-prisir_0.1.0_amd64.deb"

echo "[5/5] smoke_matrix"
python3 "$ROOT/tools/smoke_matrix.py" --lib /usr/lib/fcitx5/prisir/libprisir_ime.so --db /usr/lib/fcitx5/prisir/ciku.db \
  --cases "$ROOT/prisir_ime/abi_cases.json"

echo "P0 done. Add「灵犀拼音」in fcitx5 config if needed: fcitx5-configtool"
fcitx5-remote -r 2>/dev/null || true
ls -la /usr/lib/fcitx5/prisir/ /usr/lib/x86_64-linux-gnu/fcitx5/prisir.so
