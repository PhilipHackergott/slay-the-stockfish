#!/bin/bash
# Build the chess pieces (the six standard pieces and the fairy set, AO baked), verify the glb contract,
# render previews, review sheets and portraits.
#   tools/blender/pieces/build_all.sh                      everything
#   tools/blender/pieces/build_all.sh --only knight,amazon  just those ids: build, verify, portraits
#   tools/blender/pieces/build_all.sh --set standard       the six only (lineup, anim strips, portraits)
#   --no-ao skips the AO bake (white "ao" attribute); REVIEW=1 adds the fairy review sheets to --only runs
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

ONLY="" SET="all"
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
	case "${args[i]}" in
	--only) ONLY="${args[i + 1]:-}" ;;
	--set) SET="${args[i + 1]:-}" ;;
	esac
done
FAIRY_SHEETS=fairy,families,board,fairy_anim

run 3600 build_pieces.py "$@"
if [[ -n "$ONLY" ]]; then
	run 1800 verify_pieces.py --only "$ONLY"
	run 1800 render_previews.py --what portraits --pieces "$ONLY" --samples "$SAMPLES"
	if [[ "${REVIEW:-0}" == 1 ]]; then
		run 3600 render_previews.py --what "$FAIRY_SHEETS" --samples "$SAMPLES"
	fi
else
	run 1800 verify_pieces.py --set "$SET"
	case "$SET" in
	standard) run 3600 render_previews.py --what lineup,anim,portraits --pieces king,queen,rook,bishop,knight,pawn \
		--samples "$SAMPLES" ;;
	fairy) run 3600 render_previews.py --what "portraits,$FAIRY_SHEETS" --samples "$SAMPLES" ;;
	*) run 3600 render_previews.py --what "lineup,anim,portraits,$FAIRY_SHEETS" --samples "$SAMPLES" ;;
	esac
fi
echo "BUILD_ALL OK"
