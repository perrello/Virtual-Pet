#!/usr/bin/env bash
# gif_to_sprite.sh
# Bouw een 6x3 spritesheet @3 (2880x1440) + manifest.json vanuit een animated GIF (URL of lokaal pad).
# Werkt met ImageMagick 7 (magick) of 6 (convert/identify/montage).
# Optionele fallback: ffmpeg voor frame-extractie als coalesce faalt.

set -euo pipefail

### — App/manifest instellingen — ###
ID="${ID:-com.example.pet.demo}"
NAME="${NAME:-Demo}"
DEFAULT_FPS="${DEFAULT_FPS:-2.0}"

SCALE=3
COLS=6
ROWS=3
CELL_W=480
CELL_H=480
SPRITE_NAME="sprite@3x.png"

TOTAL_CELLS=$((COLS*ROWS))  # 18
SHEET_W=$((COLS*CELL_W))    # 2880
SHEET_H=$((ROWS*CELL_H))    # 1440

### — CLI — ###
SRC="${1:-}"
OUT_DIR="${2:-out}"
if [[ -z "${SRC}" ]]; then
  echo "Gebruik: $0 <gif-pad-of-URL> [out-dir]"
  echo "Voorbeeld:"
  echo "  $0 https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/shiny/94.gif out"
  exit 1
fi

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
  # montage is ook subtool van magick; gebruik die voor compat
  CMD_MONTAGE="magick montage"
else
  # IM6
  for b in convert identify montage; do
    command -v "$b" >/dev/null 2>&1 || { echo "❌ Vereiste tool ontbreekt: $b"; exit 1; }
  done
  CMD_MAGICK="convert"
  CMD_IDENTIFY="identify"
  CMD_MONTAGE="montage"
fi

have_ffmpeg() { command -v ffmpeg >/dev/null 2>&1; }

echo "🔧 Werkmap:  $WORK"
echo "📤 Uitvoer:  $OUT_DIR"
echo "🧩 Grid:     ${COLS}x${ROWS}, cel=${CELL_W}x${CELL_H}, sheet=${SHEET_W}x${SHEET_H} @${SCALE}x"

### — 1) Haal bron binnen (URL of lokaal) + valideer header — ###
GIF_IN="$WORK/input.gif"

download_and_validate() {
  local url="$1"
  local out="$2"

  # GitHub blob → raw
  if [[ "$url" =~ ^https?://github.com/.*/blob/ ]]; then
    url="$(sed -E 's#https?://github.com/#https://raw.githubusercontent.com/#; s#/blob/#/#' <<<"$url")"
  fi

  echo "🌐 Downloaden: $url"
  curl -fsSL -H "User-Agent: curl" "$url" -o "$out"

  # Check op HTML (404/landing)
  if head -c 512 "$out" | tr -d '\000' | grep -qiE '<!DOCTYPE|<html'; then
    echo "❌ URL leverde HTML (geen raw GIF). Controleer de link."
    return 1
  fi

  # GIF header check
  if ! head -c 6 "$out" | grep -qE '^GIF8(7|9)a'; then
    echo "❌ Bestandsheader is geen GIF (verwacht GIF87a/GIF89a)."
    return 1
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

### — 3) Bepaal FPS uit GIF delays (centiseconds) — ###
echo "⏱️  FPS bepalen…"
DELAYS_CS=$($CMD_IDENTIFY -format "%T\n" "$GIF_IN" 2>/dev/null || true)
FPS="$DEFAULT_FPS"
if [[ -n "$DELAYS_CS" ]]; then
  avg_cs=$(awk 'BEGIN{c=0;s=0}{if($1>0){s+=$1;c++}}END{if(c>0){printf "%.6f", s/c}else{print "nan"}}' <<<"$DELAYS_CS")
  if [[ "$avg_cs" != "nan" && "$avg_cs" != "" ]]; then
    FPS=$(awk -v cs="$avg_cs" 'BEGIN{printf "%.6f", 100.0/cs}')
  fi
fi
echo "🎞️  FPS = $FPS"

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
  # i in [0..17] → idx = round(i*(n-1)/(m-1))
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

### — 6) Montage naar spritesheet — ###
echo "🧵 Spritesheet bouwen…"
$CMD_MONTAGE "$SEL_DIR"/*.png \
  -tile "${COLS}x${ROWS}" \
  -geometry "${CELL_W}x${CELL_H}+0+0" \
  -background none \
  "$OUT_DIR/$SPRITE_NAME"

### — 7) manifest.json schrijven — ###
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
    }
  ],
  "fps": ${FPS}
}
JSON

echo "✅ Klaar!"
echo "   Spritesheet: $OUT_DIR/$SPRITE_NAME (${SHEET_W}x${SHEET_H})"
echo "   Manifest:    $OUT_DIR/manifest.json"
