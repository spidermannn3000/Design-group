#!/usr/bin/env bash
# Checks that the firmware draws exactly what the phone app shows.
# Needs g++ and the Dart SDK. Run from anywhere:  front-module/test_native/check.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
nav="$here/../../phone/navigation"
out="$(mktemp -d)"
(cd "$nav" && dart run tool/export_screens.dart "$out" >/dev/null)
g++ -std=c++17 -O2 -Wall -Wextra -o "$out/render" "$here/render.cpp" "$here/../src/screen.cpp"
"$out/render" < "$out/packets.txt" > "$out/cpp.txt"
screens=$(grep -c '^== ' "$out/dart.txt")
if diff -q "$out/dart.txt" "$out/cpp.txt" >/dev/null; then
  echo "OK: all $screens screens match pixel for pixel"
else
  echo "MISMATCH between phone and firmware drawings:"
  diff "$out/dart.txt" "$out/cpp.txt" | grep -m 20 '^[<>] ==' || true
  diff "$out/dart.txt" "$out/cpp.txt" | head -40
  exit 1
fi
