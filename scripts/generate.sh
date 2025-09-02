#!/usr/bin/env bash
# gif_to_sprite.sh
# Bouw 6x3 spritesheets @3 vanuit een animated GIF (URL of lokaal pad) + manifest.json.
# - Veilig downloaden (github blob -> raw, header check)
# - Coalesce (IM) + ffmpeg fallback
# - Frames normaliseren en samplen/opvullen tot 18
# - LARGE: 480x480 cell (2880x1440)  -> sprite@3x.png
# - SMALL: **minder frames (default 3x3=9)** + **kleinere cellen (default 48x48)** -> sprite_small@3x.png
# - SMALL agressief geoptimaliseerd (mik <~4KB)
# - FPS automatisch, GEKLEMD naar [1..2]
# - 2e argument: als pad => outputdir; anders => packnaam (id/name) en outputdir = out_<naam>

set -euo pipefail

### — Defaults — ###
ID_DEFAULT="com.perrello.pet.gengar"
NAME_DEFAULT="Gengar"
DEFAULT_FPS="${DEFAULT_FPS:-2.0}"       # wordt alsnog geklemd naar [1..2]
SCALE=3

# LARGE grid
COLS=6
ROWS=3
CELL_W=480
CELL_H=480
SPRITE_NAME="sprite@3x.png"

# SMALL grid — minder frames + kleinere cell
SMALL_COLS="${SMALL_COLS:-3}"      # minder kolommen (default 3)
SMALL_ROWS="${SMALL_ROWS:-3}"      # minder rijen    (default 3)
SMALL_CELL_W="${SMALL_CELL_W:-48}" # 16pt @3x
SMALL_CELL_H="${SMALL_CELL_H:-48}"
SMALL_SPRITE="sprite_small@3x.png"

TOTAL_CELLS=$((COLS*ROWS))  # 18
SHEET_W=$((COLS*CELL_W))    # 2880
SHEET_H=$((ROWS*CELL_H))    # 1440
SMALL_TOTAL_CELLS=$((SMALL_COLS*SMALL_ROWS))

### — CLI — ###
SRC="${1:-}"
ARG2="${2:-}"   # kan packnaam of outputpath zijn

if [[ -z "${SRC}" ]]; then
  echo "Gebruik: $0 <gif-pad-of-URL> [packnaam|outputdir]"
  echo "Voorbeelden:"
  echo "  $0 https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/shiny/94.gif out"
  echo "  $0 shiny.gif gengar    # pack id/name 'gengar', output in out_gengar/"
  echo "  $0 shiny.gif ./builds/gengar   # outputdir expliciet"
  exit 1
fi

# Beslis hoe ARG2 wordt gebruikt: pad => OUT_DIR, anders packnaam
is_path_like=false
if [[ -n "$ARG2" ]]; then
  if [[ "$ARG2" == */* || -e "$ARG2" ]]; then
    is_path_like=true
  fi
fi

if $is_path_like; then
  OUT_DIR="$ARG2"
  PACKNAME="demo"
else
  PACKNAME="${ARG2:-pet}"
  OUT_DIR="out_${PACKNAME}"
fi

# ID/NAME op basis van PACKNAME, tenzij expliciet via env aangepast
ID="${ID:-com.example.pet.${PACKNAME}}"
NAME="${NAME:-${PACKNAME}}"

mkdir -p "$OUT_DIR"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

### — Detecteer ImageMagick binaries — ###
CMD_MAGICK=""
CMD_IDENTIFY=""
CMD_MONTAGE=""

if command -v magick >/dev/null 2>&1; then
  CMD_MAGICK="magick"
  CMD_IDENTIFY="magick identify"
  CMD_MONTAGE="magick montage"
else
  for b in convert identify montage; do
    command -v "$b" >/dev/null 2>&1 || { echo "❌ Vereiste tool ontbreekt: $b"; exit 1; }
  done
  CMD_MAGICK="convert"
  CMD_IDENTIFY="identify"
  CMD_MONTAGE="montage"
fi

have_ffmpeg()   { command -v ffmpeg   >/dev/null 2>&1; }
have_pngquant() { command -v pngquant >/dev/null 2>&1; }
have_oxipng()   { command -v oxipng   >/dev/null 2>&1; }
have_zopfli()   { command -v zopflipng >/dev/null 2>&1; }

echo "🔧 Werkmap:  $WORK"
echo "📤 Uitvoer:  $OUT_DIR"
echo "📦 Pack:     $PACKNAME   (ID=$ID, Name=$NAME)"
echo "🧩 LARGE grid: ${COLS}x${ROWS}, cel=${CELL_W}x${CELL_H}, sheet=${SHEET_W}x${SHEET_H} @${SCALE}x"
echo "🧩 SMALL grid: ${SMALL_COLS}x${SMALL_ROWS}, cel=${SMALL_CELL_W}x${SMALL_CELL_H}"

### — 1) Haal bron binnen (URL of lokaal) + valideer header — ###
GIF_IN="$WORK/input.gif"

download_and_validate() {
  local url="$1"
  local out="$2"
  if [[ "$url" =~ ^https?://github.com/.*/blob/ ]]; then
    url="$(sed -E 's#https?://github.com/#https://raw.githubusercontent.com/#; s#/blob/#/#' <<<"$url")"
  fi
  echo "🌐 Downloaden: $url"
  curl -fsSL -H "User-Agent: curl" "$url" -o "$out"
  if head -c 512 "$out" | tr -d '\000' | grep -qiE '<!DOCTYPE|<html'; then
    echo "❌ URL leverde HTML (geen raw GIF)."; return 1
  fi
  if ! head -c 6 "$out" | grep -qE '^GIF8(7|9)a'; then
    echo "❌ Bestandsheader is geen GIF (verwacht GIF87a/GIF89a)."; return 1
  fi
}

if [[ "$SRC" =~ ^https?:// ]]; then
  download_and_validate "$SRC" "$GIF_IN" || exit 1
else
  cp "$SRC" "$GIF_IN"
  if ! head -c 6 "$GIF_IN" | grep -qE '^GIF8(7|9)a'; then
    echo "❌ Lokaal bestand lijkt geen GIF (header mismatch)."
    exit 1
  fi
fi

### — 2) Coalesce alle frames — ###
FRAMES_DIR="$WORK/frames_raw"
mkdir -p "$FRAMES_DIR"
echo "🧪 Frames coalescen…"

coalesce_ok=true
if ! $CMD_MAGICK "$GIF_IN" -coalesce "$FRAMES_DIR/%05d.png" 2>/dev/null; then
  echo "⚠️  Coalesce vanaf bestand faalde; probeer stdin-pipe…"
  if ! curl -fsSL "$([[ "$SRC" =~ ^https?:// ]] && echo "$SRC" || echo "file://$GIF_IN")" \
      | $CMD_MAGICK gif:- -coalesce "$FRAMES_DIR/%05d.png" 2>/dev/null; then
    echo "⚠️  Coalesce via stdin faalde."
    coalesce_ok=false
  fi
fi

if ! $coalesce_ok; then
  if have_ffmpeg; then
    echo "🎬 Fallback: ffmpeg → PNG frames…"
    ffmpeg -v error -y -i "$GIF_IN" "$FRAMES_DIR/%05d.png"
  else
    echo "❌ Kan geen frames extraheren (ImageMagick coalesce en ffmpeg niet beschikbaar/geslaagd)."
    exit 1
  fi
fi

shopt -s nullglob
if ! ls "$FRAMES_DIR"/*.png >/dev/null 2>&1; then
  echo "❌ Geen frames aangemaakt."
  exit 1
fi

### — 3) FPS uit GIF delays en klemmen naar [1..2] — ###
echo "⏱️  FPS bepalen…"
DELAYS_CS=$($CMD_IDENTIFY -format "%T\n" "$GIF_IN" 2>/dev/null || true)
FPS="$DEFAULT_FPS"
if [[ -n "$DELAYS_CS" ]]; then
  avg_cs=$(awk 'BEGIN{c=0;s=0}{if($1>0){s+=$1;c++}}END{if(c>0){printf "%.6f", s/c}else{print "nan"}}' <<<"$DELAYS_CS")
  if [[ "$avg_cs" != "nan" && "$avg_cs" != "" ]]; then
    FPS=$(awk -v cs="$avg_cs" 'BEGIN{printf "%.6f", 100.0/cs}')
  fi
fi
# Klem naar 1..2
FPS=$(awk -v f="$FPS" 'BEGIN{ if (f<1.0) f=1.0; if (f>2.0) f=2.0; printf "%.6f", f }')
echo "🎞️  FPS (geklemd) = $FPS"

### — 4) Normaliseer frames naar 480x480 canvas — ###
NORM_DIR="$WORK/frames_norm"
mkdir -p "$NORM_DIR"
echo "🖼️  Normaliseren naar ${CELL_W}x${CELL_H}…"

idx=0
for f in "$FRAMES_DIR"/*.png; do
  printf -v out "%s/%05d.png" "$NORM_DIR" "$idx"
  $CMD_MAGICK "$f" -alpha on -background none \
    -resize "${CELL_W}x${CELL_H}" \
    -gravity center -extent "${CELL_W}x${CELL_H}" \
    "$out"
  ((idx++))
done
TOTAL_FRAMES=$idx
echo "🔢 Totaal ruwe frames: $TOTAL_FRAMES"
if (( TOTAL_FRAMES == 0 )); then
  echo "❌ Geen frames na normalisatie."
  exit 1
fi

### — 5) Selecteer exact 18 frames (sample of opvul) — ###
SEL_DIR="$WORK/frames_sel"
mkdir -p "$SEL_DIR"

if (( TOTAL_FRAMES >= TOTAL_CELLS )); then
  echo "📉 Samplen naar $TOTAL_CELLS frames…"
  for ((i=0; i<TOTAL_CELLS; i++)); do
    src_index=$(awk -v n="$TOTAL_FRAMES" -v m="$TOTAL_CELLS" -v i="$i" 'BEGIN{
      idx = int((i*(n-1.0)/(m-1.0)) + 0.5);
      if (idx < 0) idx=0;
      if (idx > n-1) idx=n-1;
      print idx;
    }')
    printf -v src "%s/%05d.png" "$NORM_DIR" "$src_index"
    printf -v dst "%s/%05d.png" "$SEL_DIR" "$i"
    cp "$src" "$dst"
  done
else
  echo "🧩 Opvullen tot $TOTAL_CELLS frames…"
  i=0
  for f in "$NORM_DIR"/*.png; do
    printf -v dst "%s/%05d.png" "$SEL_DIR" "$i"; cp "$f" "$dst"; ((i++))
  done
  last=$((i-1))
  while (( i < TOTAL_CELLS )); do
    printf -v from "%s/%05d.png" "$SEL_DIR" "$last"
    printf -v dst  "%s/%05d.png" "$SEL_DIR" "$i"
    cp "$from" "$dst"; ((i++))
  done
fi

### — 6) LARGE spritesheet — ###
echo "🧵 LARGE sheet bouwen…"
$CMD_MONTAGE "$SEL_DIR"/*.png \
  -tile "${COLS}x${ROWS}" \
  -geometry "${CELL_W}x${CELL_H}+0+0" \
  -background none \
  "$OUT_DIR/$SPRITE_NAME"

### — 7) SMALL spritesheet — **minder frames + kleinere cellen** ###
echo "🧵 SMALL sheet bouwen (${SMALL_CELL_W}x${SMALL_CELL_H} per cel, ${SMALL_COLS}x${SMALL_ROWS} = ${SMALL_TOTAL_CELLS} frames)…"

# Kies SMALL_TOTAL_CELLS frames door sampling uit de genormaliseerde reeks
SMALL_SEL_DIR="$WORK/frames_small_sel"; mkdir -p "$SMALL_SEL_DIR"
for ((i=0; i<SMALL_TOTAL_CELLS; i++)); do
  # sample indices over het volledige bereik van TOTAL_FRAMES
  sidx=$(awk -v n="$TOTAL_FRAMES" -v m="$SMALL_TOTAL_CELLS" -v i="$i" 'BEGIN{
    idx = int((i*(n-1.0)/(m-1.0)) + 0.5);
    if (idx < 0) idx=0; if (idx > n-1) idx=n-1; print idx;
  }')
  printf -v src "%s/%05d.png" "$NORM_DIR" "$sidx"
  printf -v dst "%s/%05d.png" "$SMALL_SEL_DIR" "$i"
  cp "$src" "$dst"
done

# Downscale & montage
SMALL_TMP="$WORK/small_scaled"; mkdir -p "$SMALL_TMP"
for f in "$SMALL_SEL_DIR"/*.png; do
  base="$(basename "$f")"
  $CMD_MAGICK "$f" -alpha on -background none \
    -resize "${SMALL_CELL_W}x${SMALL_CELL_H}" \
    -gravity center -extent "${SMALL_CELL_W}x${SMALL_CELL_H}" \
    "$SMALL_TMP/$base"
done

$CMD_MONTAGE "$SMALL_TMP"/*.png \
  -tile "${SMALL_COLS}x${SMALL_ROWS}" \
  -geometry "${SMALL_CELL_W}x${SMALL_CELL_H}+0+0" \
  -background none \
  "$OUT_DIR/$SMALL_SPRITE"

# Optimaliseer SMALL agressief
echo "🪚 SMALL optimaliseren…"
# Forceer indexed palette ook zonder pngquant
$CMD_MAGICK "$OUT_DIR/$SMALL_SPRITE" \
  -strip -alpha on -define png:compression-level=9 -define png:compression-filter=5 \
  +dither -colors 8 -type Palette \
  "$OUT_DIR/$SMALL_SPRITE"

if have_pngquant; then
  pngquant --force --output "$OUT_DIR/$SMALL_SPRITE" --strip --speed 1 \
           --skip-if-larger --quality 40-95 8 "$OUT_DIR/$SMALL_SPRITE" || true
fi
if have_oxipng; then
  oxipng -o4 --strip all "$OUT_DIR/$SMALL_SPRITE" >/dev/null 2>&1 || true
fi
if have_zopfli; then
  zopflipng -y "$OUT_DIR/$SMALL_SPRITE" "$OUT_DIR/$SMALL_SPRITE" >/dev/null 2>&1 || true
fi

### — 8) manifest.json schrijven (beide varianten) — ###
echo "🗂️  manifest.json schrijven…"
cat > "$OUT_DIR/manifest.json" <<JSON
{
  "id": "${ID}",
  "name": "${NAME}",
  "variants": [
    {
      "scale": ${SCALE},
      "cols": ${COLS},
      "rows": ${ROWS},
      "cellPx": { "w": ${CELL_W}, "h": ${CELL_H} },
      "sprite": "${SPRITE_NAME}"
    },
    {
      "scale": ${SCALE},
      "cols": ${SMALL_COLS},
      "rows": ${SMALL_ROWS},
      "cellPx": { "w": ${SMALL_CELL_W}, "h": ${SMALL_CELL_H} },
      "sprite": "${SMALL_SPRITE}"
    }
  ],
  "fps": ${FPS}
}
JSON

echo "✅ Klaar!"
echo "   LARGE : $OUT_DIR/$SPRITE_NAME (${SHEET_W}x${SHEET_H})"
echo "   SMALL : $OUT_DIR/$SMALL_SPRITE ($((SMALL_COLS*SMALL_CELL_W))x$((SMALL_ROWS*SMALL_CELL_H)))"
echo "   Manifest: $OUT_DIR/manifest.json"
if command -v du >/dev/null 2>&1; then
  echo "— bestandsgroottes —"
  du -h "$OUT_DIR/"*
fi
