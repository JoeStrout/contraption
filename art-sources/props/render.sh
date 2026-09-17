#!/bin/sh
# Render the prop sprite strips.  Any arguments are passed on to make_props.py,
# e.g.  ./render.sh --only scissors --engine eevee --samples 16
set -e
here=$(cd "$(dirname "$0")" && pwd)
BLENDER=${BLENDER:-/Applications/3rd-Party/Blender.app/Contents/MacOS/Blender}
[ -x "$BLENDER" ] || { echo "set BLENDER to your Blender executable" >&2; exit 1; }
exec "$BLENDER" -b --factory-startup -P "$here/make_props.py" -- "$@"
