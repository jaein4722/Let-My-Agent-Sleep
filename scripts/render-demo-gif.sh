#!/usr/bin/env bash
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"$ROOT/site/demo.gif"}
TMPDIR_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/lmas-demo.XXXXXX")

cleanup() {
  rm -rf "$TMPDIR_ROOT"
}
trap cleanup EXIT

command -v magick >/dev/null 2>&1 || {
  printf 'ImageMagick magick command is required\n' >&2
  exit 1
}

FONT=${LMAS_DEMO_FONT:-/System/Library/Fonts/HelveticaNeue.ttc}
[ -f "$FONT" ] || FONT=${LMAS_DEMO_FONT:-/System/Library/Fonts/Supplemental/Arial.ttf}

escape_xml() {
  printf '%s' "$1" \
    | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

line() {
  local y color text
  y=$1
  color=$2
  text=$3
  printf '<text x="64" y="%s" fill="%s" font-family="Menlo, SFMono-Regular, monospace" font-size="18">%s</text>\n' "$y" "$color" "$(escape_xml "$text")"
}

render_frame() {
  local frame title accent lines
  frame=$1
  title=$2
  accent=$3
  shift 3
  lines=$(
    local y=168
    for text in "$@"; do
      line "$y" "#c8d1ea" "$text"
      y=$((y + 30))
    done
  )

  cat > "$TMPDIR_ROOT/frame-$frame.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="780" height="420" viewBox="0 0 780 420">
  <rect width="780" height="420" fill="#070a14"/>
  <circle cx="680" cy="74" r="96" fill="#113949" opacity="0.78"/>
  <circle cx="628" cy="344" r="122" fill="#123a29" opacity="0.72"/>
  <circle cx="520" cy="212" r="84" fill="#58d68d" opacity="0.9"/>
  <path d="M590 118 L520 238 H594 L566 318 L668 178 H592 L628 118 Z" fill="#4dd6e0" opacity="0.95"/>
  <text x="44" y="58" fill="#4dd6e0" font-family="Menlo, SFMono-Regular, monospace" font-size="18" letter-spacing="4">LMAS</text>
  <text x="44" y="96" fill="#e6eaf5" font-family="Helvetica Neue, Arial, sans-serif" font-size="32" font-weight="700">Start long jobs. Stop the loop.</text>
  <rect x="44" y="122" width="522" height="206" rx="10" fill="#0d1324" stroke="#1c2745"/>
  <circle cx="70" cy="144" r="5" fill="#f07a7a"/>
  <circle cx="90" cy="144" r="5" fill="#f0b45a"/>
  <circle cx="110" cy="144" r="5" fill="#58d68d"/>
  <text x="136" y="150" fill="$accent" font-family="Menlo, SFMono-Regular, monospace" font-size="15">$(escape_xml "$title")</text>
  $lines
  <text x="44" y="370" fill="#9aa6c4" font-family="Helvetica Neue, Arial, sans-serif" font-size="20">One handoff. One wake-up. Same supported session.</text>
</svg>
EOF

  magick -font "$FONT" "$TMPDIR_ROOT/frame-$frame.svg" "$TMPDIR_ROOT/frame-$frame.png"
}

render_frame 0 "agent starts a real command" "#4dd6e0" \
  "\$ lmas_start \"python train.py --config exp.yaml\"" \
  "wrapping command with tmux watcher..."

render_frame 1 "LMAS_HANDOFF v1" "#f0b45a" \
  "run_id: lmas_20260709T115238+0900_88226" \
  "status: STARTED" \
  "agent stops here. no polling."

render_frame 2 "session sleeping" "#58d68d" \
  "17 hours later..." \
  "no tail loops" \
  "no repeated continue turns"

render_frame 3 "LMAS_COMPLETION_EVENT v1" "#58d68d" \
  "run_id: lmas_20260709T115238+0900_88226" \
  "status: SUCCEEDED" \
  "stdout, stderr, metadata, artifacts recorded"

render_frame 4 "same session continues" "#4dd6e0" \
  "agent inspects logs once" \
  "summarizes metrics" \
  "starts the next useful step"

magick -delay 120 "$TMPDIR_ROOT/frame-0.png" \
  -delay 140 "$TMPDIR_ROOT/frame-1.png" \
  -delay 180 "$TMPDIR_ROOT/frame-2.png" \
  -delay 140 "$TMPDIR_ROOT/frame-3.png" \
  -delay 170 "$TMPDIR_ROOT/frame-4.png" \
  -loop 0 "$OUT"

printf '%s\n' "$OUT"
