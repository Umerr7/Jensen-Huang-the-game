#!/usr/bin/env bash
# Copy Mixamo FBX clips into the Godot project, pre-configured as retargeted
# Animation Libraries (same settings as animations/Idle.fbx.import).
#
# Usage:  ./add_animations.sh ~/Downloads/*.fbx
#
# Clips whose name contains idle/walk/run/jog/sprint/firing/strafe are set to
# loop; everything else (jumps, deaths, reloads...) plays once.
# Files that already exist in animations/ are skipped.
set -euo pipefail

ANIM_DIR="$(cd "$(dirname "$0")" && pwd)/jensen-huang-the-game/animations"
TEMPLATE="$ANIM_DIR/Idle.fbx.import"
[ -f "$TEMPLATE" ] || { echo "Template $TEMPLATE not found"; exit 1; }
PARAMS="$(sed -n '/^\[params\]/,$p' "$TEMPLATE")"

for src in "$@"; do
  name="$(basename "$src" | sed 's/(\([0-9]*\))/ \1/')"   # "Firing(1).fbx" -> "Firing 1.fbx"
  dest="$ANIM_DIR/$name"
  if [ -e "$dest" ]; then echo "skip  $name (already in project)"; continue; fi

  loop=0
  shopt -s nocasematch
  [[ "$name" =~ idle|walk|run|jog|sprint|firing|strafe ]] && loop=1
  shopt -u nocasematch

  # Write the .import first so Godot picks up these settings on its first scan.
  {
    printf '[remap]\n\nimporter="animation_library"\nimporter_version=1\ntype="AnimationLibrary"\n\n'
    printf '[deps]\n\nsource_file="res://animations/%s"\n\n' "$name"
    echo "$PARAMS" | sed -E "s/\"settings\/loop_mode\": [0-9]/\"settings\/loop_mode\": $loop/"
  } > "$dest.import"
  cp "$src" "$dest"
  echo "added $name  (loop=$loop)"
done
echo "Done. Click back into the Godot editor and it will import them."
