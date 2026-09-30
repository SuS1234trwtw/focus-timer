#!/usr/bin/env bash
# Downloads the bundled terminal fonts (all SIL Open Font License, Ubuntu Font Licence,
# or Apache) into FocusTimer/Resources/Fonts. Run from the repo root before `xcodegen generate`.
# The app registers whatever it finds at launch and falls back to SF Mono for anything missing,
# so a failed download degrades gracefully instead of breaking the build.
set -uo pipefail

DEST="FocusTimer/Resources/Fonts"
mkdir -p "$DEST"

fetch() {  # fetch <url> [file name]
  local url="$1" name="${2:-${1##*/}}"
  [ -f "$DEST/$name" ] && return 0
  if curl -fsSL "$url" -o "$DEST/$name"; then echo "fetched $name"; else echo "warning: could not fetch $name" >&2; rm -f "$DEST/$name"; fi
}

JB="https://raw.githubusercontent.com/JetBrains/JetBrainsMono/master/fonts/ttf"
for w in Light Regular Bold; do fetch "$JB/JetBrainsMono-$w.ttf"; done

G="https://raw.githubusercontent.com/google/fonts/main"
for w in Light Regular Bold; do fetch "$G/ofl/ibmplexmono/IBMPlexMono-$w.ttf"; done
for w in Regular Bold; do fetch "$G/ofl/spacemono/SpaceMono-$w.ttf"; done
for w in Regular Bold; do fetch "$G/ufl/ubuntumono/UbuntuMono-$w.ttf"; done
for w in Regular Bold; do fetch "$G/ofl/anonymouspro/AnonymousPro-$w.ttf"; done
for w in Regular Bold; do fetch "$G/ofl/firamono/FiraMono-$w.ttf"; done
fetch "$G/ofl/vt323/VT323-Regular.ttf"
fetch "$G/ofl/sharetechmono/ShareTechMono-Regular.ttf"

SCP="https://raw.githubusercontent.com/adobe-fonts/source-code-pro/release/TTF"
for w in Light Regular Bold; do fetch "$SCP/SourceCodePro-$w.ttf"; done

NOTO="https://raw.githubusercontent.com/notofonts/notofonts.github.io/main/fonts/NotoSansMono/hinted/ttf"
for w in Light Regular Bold; do fetch "$NOTO/NotoSansMono-$w.ttf"; done

# DejaVu Sans Mono (the classic Linux terminal font) ships as a release zip.
if [ ! -f "$DEST/DejaVuSansMono.ttf" ]; then
  DEJAVU="https://github.com/dejavu-fonts/dejavu-fonts/releases/download/version_2_37/dejavu-fonts-ttf-2.37.zip"
  TMP="$(mktemp -d)"
  if curl -fsSL "$DEJAVU" -o "$TMP/dejavu.zip"; then
    for f in DejaVuSansMono DejaVuSansMono-Bold; do
      unzip -j -o -q "$TMP/dejavu.zip" "*ttf/$f.ttf" -d "$DEST" && echo "fetched $f.ttf" \
        || echo "warning: $f.ttf not in archive" >&2
    done
  else
    echo "warning: could not fetch DejaVu" >&2
  fi
  rm -rf "$TMP"
fi

# Cascadia Mono (Windows Terminal's font) ships as a release zip.
if [ ! -f "$DEST/CascadiaMono-Regular.ttf" ]; then
  CASCADIA="https://github.com/microsoft/cascadia-code/releases/download/v2407.24/CascadiaCode-2407.24.zip"
  TMP="$(mktemp -d)"
  if curl -fsSL "$CASCADIA" -o "$TMP/cascadia.zip"; then
    for w in Light Regular Bold; do
      unzip -j -o -q "$TMP/cascadia.zip" "*static/CascadiaMono-$w.ttf" -d "$DEST" && echo "fetched CascadiaMono-$w.ttf" \
        || echo "warning: CascadiaMono-$w.ttf not in archive" >&2
    done
  else
    echo "warning: could not fetch Cascadia Code" >&2
  fi
  rm -rf "$TMP"
fi

ls "$DEST"
