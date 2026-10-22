#!/bin/bash
# Rebuild the six chess pieces (AO baked), verify the glb contract, render previews and portraits.
#   tools/blender/pieces/build_all.sh            full run
#   tools/blender/pieces/build_all.sh --no-ao    skip the AO bake (white "ao" attribute)
set -euo pipefail
cd "$(dirname "$0")/../../.."
B="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
SAMPLES="${SAMPLES:-64}"

run() {
	local secs=$1 script=$2
	shift 2
	perl -e 'alarm shift; exec @ARGV' "$secs" "$B" --background --factory-startup --python-exit-code 1 \
		--python "tools/blender/pieces/$script" -- "$@"
}

run 1800 build_pieces.py "$@"
run 600 verify_pieces.py
run 3600 render_previews.py --what lineup,anim,portraits --samples "$SAMPLES"
echo "BUILD_ALL OK"
