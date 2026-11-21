#!/usr/bin/env bash
# Build libprisir_ime.so inside WSL; write to lingxi-linux/dist/
set -euo pipefail

SRC="/mnt/d/Projects/lingxi-android/prisir_ime"
OUT="/mnt/d/Projects/lingxi-linux/dist"
BUILD="/tmp/prisir_ime_build"

mkdir -p "$OUT" "$BUILD"
rsync -a --delete \
  --exclude target --exclude .git --exclude __pycache__ \
  "$SRC"/ "$BUILD"/

cd "$BUILD"
mkdir -p .cargo
cat > .cargo/config.toml <<'EOF'
[profile.release]
lto = false
codegen-units = 16
EOF

echo "[build] cargo release in $BUILD"
cargo build --release
ls -lh target/release/libprisir_ime.so
cp -f target/release/libprisir_ime.so "$OUT/libprisir_ime.so"
file "$OUT/libprisir_ime.so"
echo "OK -> $OUT/libprisir_ime.so"
