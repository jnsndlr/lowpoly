#!/bin/zsh
# Records the teaser's shots with tools/teaser_capture.gd, encodes each one, and cuts
# them together in order to rough_cut.mp4.
#   tools/teaser_capture.sh --out=DIR [--seed=N] [--fps=60] [--size=1920x1080]
#                           [--only=name,name] [--first-frame] [--keep-frames]
#   tools/teaser_capture.sh --out=DIR --recut      (just encodes and cuts what's in DIR,
#                           after changing the times in its shots.txt: name in length)
# Anything else after the options goes to the game (for example --ferry-sizes=4,4,2).
set -e

godot=/Applications/Godot.app/Contents/MacOS/Godot
repo=${0:A:h:h}
out=""
seed=123
fps=60
size=1920x1080
keep=0
stills=0
recut=0
rest=()
for a in "$@"; do
	case $a in
		--out=*) out=${a#--out=} ;;
		--seed=*) seed=${a#--seed=} ;;
		--fps=*) fps=${a#--fps=} ;;
		--size=*) size=${a#--size=} ;;
		--keep-frames) keep=1 ;;
		--recut) recut=1 ;;
		--first-frame) stills=1; rest+=$a ;;
		*) rest+=$a ;;
	esac
done
[[ -n $out ]] || { echo "needs --out=DIR" >&2; exit 2; }
mkdir -p "$out"
out=${out:A}

(( recut )) || "$godot" --path "$repo" --resolution "$size" --fixed-fps "$fps" --disable-vsync \
	--script tools/teaser_capture.gd -- --seed="$seed" --out="$out" --fps="$fps" --ferry-sizes=4 "${rest[@]}"

(( stills )) && exit 0

list=$out/cut_list.txt
: > "$list"
while read -r name start len; do
	if [[ -d $out/$name ]]; then
		ffmpeg -nostdin -y -loglevel error -framerate "$fps" -start_number 1 -i "$out/$name/%05d.png" \
			-c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p "$out/$name.mp4"
		(( keep )) || rm -r "$out/$name"
	fi
	ffmpeg -nostdin -y -loglevel error -ss "$start" -t "$len" -i "$out/$name.mp4" \
		-c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p "$out/cut_$name.mp4"
	print -r -- "file '$out/cut_$name.mp4'" >> "$list"
done < "$out/shots.txt"
ffmpeg -nostdin -y -loglevel error -f concat -safe 0 -i "$list" -c copy "$out/rough_cut.mp4"
rm "$list" "$out"/cut_*.mp4
echo "rough cut: $out/rough_cut.mp4"
