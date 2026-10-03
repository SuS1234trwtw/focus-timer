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

GEIST="https://raw.githubusercontent.com/vercel/geist-font/main/fonts/GeistMono/ttf"
for w in Light Regular Bold; do fetch "$GEIST/GeistMono-$w.ttf"; done

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

# Extracts exact archive paths into $DEST: unzip_fonts <zip url> <label> <path in zip>...
unzip_fonts() {
  local url="$1" label="$2"; shift 2
  local missing=0 f
  for f in "$@"; do [ -f "$DEST/${f##*/}" ] || missing=1; done
  [ "$missing" = 1 ] || return 0
  local tmp; tmp="$(mktemp -d)"
  if curl -fsSL "$url" -o "$tmp/fonts.zip"; then
    for f in "$@"; do
      unzip -j -o -q "$tmp/fonts.zip" "$f" -d "$DEST" && echo "fetched ${f##*/}" || echo "warning: ${f##*/} not in archive" >&2
    done
  else
    echo "warning: could not fetch $label" >&2
  fi
  rm -rf "$tmp"
}

# Victor Mono (Rubjerg Hansen) static TTFs from the repo's release bundle.
unzip_fonts "https://raw.githubusercontent.com/rubjo/victor-mono/master/public/VictorMonoAll.zip" "Victor Mono"   TTF/VictorMono-Light.ttf TTF/VictorMono-Regular.ttf TTF/VictorMono-Bold.ttf

# Martian Mono (Evil Martians), standard width.
unzip_fonts "https://github.com/evilmartians/mono/releases/download/v1.1.0/martian-mono-1.1.0-ttf.zip" "Martian Mono"   MartianMono-StdLt.ttf MartianMono-StdRg.ttf MartianMono-StdBd.ttf

# Commit Mono (Eigil Nikolajsen): 400 and 700 only, no light.
unzip_fonts "https://github.com/eigilnikolajsen/commit-mono/releases/download/v1.143/CommitMono-1.143.zip" "Commit Mono"   CommitMono-1.143/ttfautohint/CommitMono-400-Regular.ttf CommitMono-1.143/ttfautohint/CommitMono-700-Regular.ttf

# Monaspace Neon (GitHub Next): the static release is OTF only, so take the "frozen" TTFs.
unzip_fonts "https://github.com/githubnext/monaspace/releases/download/v1.400/monaspace-frozen-v1.400.zip" "Monaspace Neon"   "Frozen Fonts/Monaspace Neon/MonaspaceNeonFrozen-Light.ttf"   "Frozen Fonts/Monaspace Neon/MonaspaceNeonFrozen-Regular.ttf"   "Frozen Fonts/Monaspace Neon/MonaspaceNeonFrozen-Bold.ttf"

ls "$DEST"
