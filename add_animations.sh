#!/usr/bin/env bash
# Copy Mixamo FBX clips into the Godot project, pre-configured as retargeted
# Animation Libraries (same settings as animations/Idle.fbx.import).
#
# Usage:  ./add_animations.sh ~/Downloads/*.fbx            (Jensen's clips -> animations/)
#         ./add_animations.sh --alice ~/Downloads/*.fbx    (Alice's clips -> animations/alice animations/,
#                                                           loaded onto her automatically; the file name
#                                                           is the animation name Gemma picks, e.g. Laugh.fbx)
#
# Clips whose name contains idle/walk/run/jog/sprint/firing/strafe are set to
# loop; everything else (jumps, deaths, reloads...) plays once.
# Files that already exist in animations/ are skipped.
set -euo pipefail

ANIM_DIR="$(cd "$(dirname "$0")" && pwd)/jensen-huang-the-game/animations"
TEMPLATE="$ANIM_DIR/Idle.fbx.import"
RES_DIR="res://animations"
if [ "${1:-}" = "--alice" ]; then
  shift
  ANIM_DIR="$ANIM_DIR/alice animations"; RES_DIR="res://animations/alice animations"
  mkdir -p "$ANIM_DIR"
fi
[ -f "$TEMPLATE" ] || { echo "Template $TEMPLATE not found"; exit 1; }
PARAMS="$(sed -n '/^\[params\]/,$p' "$TEMPLATE")"

for src in "$@"; do
  name="$(basename "$src" | sed 's/(\([0-9]*\))/ \1/')"   # "Firing(1).fbx" -> "Firing 1.fbx"
  dest="$ANIM_DIR/$name"
  if [ -e "$dest" ]; then echo "skip  $name (already in project)"; continue; fi

  loop=0
  shopt -s nocasematch
  [[ "$name" =~ idle|walk|run|jog|sprint|firing|strafe|talk|think|laugh|cry|sad ]] && loop=1
  shopt -u nocasematch

  # Write the .import first so Godot picks up these settings on its first scan.
  {
    printf '[remap]\n\nimporter="animation_library"\nimporter_version=1\ntype="AnimationLibrary"\n\n'
    printf '[deps]\n\nsource_file="%s/%s"\n\n' "$RES_DIR" "$name"
    echo "$PARAMS" | sed -E "s/\"settings\/loop_mode\": [0-9]/\"settings\/loop_mode\": $loop/"
  } > "$dest.import"
  cp "$src" "$dest"
  echo "added $name  (loop=$loop)"
done
echo "Done. Click back into the Godot editor and it will import them."
