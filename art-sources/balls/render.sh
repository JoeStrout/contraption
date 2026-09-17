#!/bin/sh
# Render the ball sprite sheets.  Any arguments are passed on to make_balls.py,
# e.g.  ./render.sh --only ball-star --frames 16 --engine eevee
set -e
here=$(cd "$(dirname "$0")" && pwd)
BLENDER=${BLENDER:-/Applications/3rd-Party/Blender.app/Contents/MacOS/Blender}
[ -x "$BLENDER" ] || { echo "set BLENDER to your Blender executable" >&2; exit 1; }
exec "$BLENDER" -b --factory-startup -P "$here/make_balls.py" -- "$@"
