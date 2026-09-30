#!/usr/bin/env bash
# Downloads JetBrains Mono (SIL Open Font License 1.1) from the official JetBrains repo.
# Run from the repo root before `xcodegen generate`. The app falls back to the system
# monospaced font if these are missing.
set -euo pipefail

DEST="FocusTimer/Resources/Fonts"
BASE="https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/fonts/ttf"
mkdir -p "$DEST"

for weight in Light Regular Bold; do
  file="JetBrainsMono-$weight.ttf"
  if [ ! -f "$DEST/$file" ]; then
    curl -fsSL "$BASE/$file" -o "$DEST/$file"
    echo "fetched $file"
  fi
done
