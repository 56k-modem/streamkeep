#!/usr/bin/env bash
set -euo pipefail

TS_FOLDER="${TS_FOLDER:-/input}"
JPG_FOLDER="${JPG_FOLDER:-/output}"
FONT_PATH="${FONT_PATH:-/usr/share/fonts/truetype/Misc-Fixed-7x13.ttf}"
SHOW_NAME="Wubby"
SHOW_DIR="$TS_FOLDER/TV Shows/$SHOW_NAME"
CURRENT_SEASON="Season $(date +%y)"
SEASON_DIR="$SHOW_DIR/$CURRENT_SEASON"

RESCAN=false
STAY_ALIVE=false
for arg in "$@"; do
    [[ "$arg" == "--rescan" ]] && RESCAN=true
    [[ "$arg" == "--stay-alive" ]] && STAY_ALIVE=true
done

echo "[vcsi] $(date '+%F %T')  pass started"

###############################################################################
# Step 0 – purge stale JPEGs
# A JPEG is "stale" when its video file has been modified *after* the JPEG.
###############################################################################
_purge_stale_sheets() {
    local dir="$1"
    shopt -s nullglob
    for vid_path in "$dir"/*.mp4; do
        base="$(basename "$vid_path")"
        jpg_path="$JPG_FOLDER/$base.jpg"
        if [ -f "$jpg_path" ] && [ "$vid_path" -nt "$jpg_path" ]; then
            echo "[vcsi] deleting stale sheet for $base.jpg (video newer)"
            rm -v "$jpg_path"
        fi
    done
}

_purge_stale_sheets "$TS_FOLDER"
if $RESCAN; then
    for sdir in "$SHOW_DIR"/Season*/; do
        [ -d "$sdir" ] && _purge_stale_sheets "$sdir"
    done
fi

###############################################################################
# Step 1 – generate sheets; skip any JPEGs that still exist
###############################################################################
_generate_sheets() {
    local dir="$1"
    vcsi "$dir" --no-overwrite \
         -t -T sw -w 900 -g 3x5 \
         --background-color 000000 \
         --metadata-font "$FONT_PATH" \
         --metadata-font-color ffffff \
         --metadata-font-size 12 \
         --timestamp-font "$FONT_PATH" \
         --timestamp-format "{H}:{M}:{S}" \
         --ignore-errors \
         --exclude-extensions jpg \
         -o "$JPG_FOLDER"
}

_generate_sheets "$TS_FOLDER"
if $RESCAN; then
    for sdir in "$SHOW_DIR"/Season*/; do
        [ -d "$sdir" ] && _generate_sheets "$sdir"
    done
fi

echo "[vcsi] $(date '+%F %T') for jellyfin pass started"

sleep 2

###############################################################################
# Step 1b – generate 16:9 poster sheets next to the .mp4 files
# Output: VOD_filename.mp4 -> VOD_filename.jpg (alongside the .mp4)
###############################################################################
_generate_posters() {
    local dir="$1"
    shopt -s nullglob
    for vid_path in "$dir"/*.mp4; do
        base="$(basename "$vid_path")"        # e.g. VOD_filename.mp4
        poster_path="$dir/${base%.mp4}.jpg"   # e.g. VOD_filename.jpg
        gen_path="$dir/$base.jpg"             # e.g. VOD_filename.mp4.jpg (vcsi default)

        # Delete stale poster if video is newer
        if [ -f "$poster_path" ] && [ "$vid_path" -nt "$poster_path" ]; then
            echo "[vcsi] deleting stale poster for ${base%.mp4}.jpg (video newer)"
            rm -v "$poster_path"
        fi

        # Skip if poster already exists and is not stale
        if [ -f "$poster_path" ]; then
            continue
        fi

        # Generate poster (minimal, 16:9, no metadata/timestamps)
        vcsi "$vid_path" --no-overwrite \
          -w 3840 -g 5x3 \
          --background-color 000000 \
          --metadata-position hidden \
          --ignore-errors \
          --exclude-extensions jpg \
          -o "$dir"

        # Rename from "VOD_filename.mp4.jpg" to "VOD_filename.jpg"
        if [ -f "$gen_path" ]; then
            mv -v "$gen_path" "$poster_path"
            # Pad to exact 3840x2160 (centered, black bars top/bottom if needed)
            ffmpeg -hide_banner -y -i "$poster_path" -frames:v 1 -update 1 \
              -vf "scale=3840:-1,pad=3840:2160:(ow-iw)/2:(oh-ih)/2:black" \
              -q:v 2 \
              "$poster_path.tmp.jpg"
            mv -v "$poster_path.tmp.jpg" "$poster_path"
        fi
    done
}

_generate_posters "$TS_FOLDER"
if $RESCAN; then
    for sdir in "$SHOW_DIR"/Season*/; do
        [ -d "$sdir" ] && _generate_posters "$sdir"
    done
fi

###############################################################################
# Step 2 – prune orphaned JPEGs (videos deleted or moved)
###############################################################################
for jpg_path in "$JPG_FOLDER"/*.jpg; do
    base="${jpg_path##*/}"; base="${base%.jpg}"
    # Also keep sheets whose video was renamed and moved to any Season folder
    season_match=( "$SHOW_DIR"/Season*/*"$base" )
    [[ -f "$TS_FOLDER/$base" ]] || [[ -f "${season_match[0]:-}" ]] || { rm -v "$jpg_path"; }
done

###############################################################################
# Step 2b – prune orphaned 16:9 posters in $TS_FOLDER
###############################################################################
shopt -s nullglob
for jpg_path in "$TS_FOLDER"/*.jpg; do
    base="$(basename "$jpg_path" .jpg)"
    # Also keep posters whose video was renamed and moved to any Season folder
    season_match=( "$SHOW_DIR"/Season*/*"${base}.mp4" )
    [[ -f "$TS_FOLDER/$base.mp4" ]] || [[ -f "${season_match[0]:-}" ]] || { echo "[vcsi] removing orphaned poster: $jpg_path"; rm -v "$jpg_path"; }
done

###############################################################################
# Step 3 – rename and move completed VODs to current Season with Jellyfin naming
# Skips any mp4 whose .recording sentinel file still exists (still being written)
###############################################################################
mkdir -p "$SEASON_DIR"

echo "[vcsi] $(date '+%F %T') moving completed VODs to Season folders..."

# Move each completed mp4 (and its .jpg poster) from the input root to its respective Season DIR,
# sorted by modification time so multiple new VODs are numbered chronologically.
while IFS= read -r mp4; do
    [ -f "$mp4" ] || continue
    base=$(basename "$mp4" .mp4)
    # Skip if the recording sentinel still exists (stream still in progress)
    if [ -f "$TS_FOLDER/${base}.recording" ]; then
        echo "[vcsi] skipping ${base}.mp4 (recording still in progress)"
        continue
    fi

    # Derive date from the file itself to ensure correct chronological sorting
    # and handle streams that cross midnight or are processed in batches.
    fyear=$(date -r "$mp4" +%y)
    fdate=$(date -r "$mp4" +%m%d)
    fseason_dir="$SHOW_DIR/Season ${fyear}"
    mkdir -p "$fseason_dir"

    # Handle multiple streams on the same day by appending a sequence number.
    # This ensures Jellyfin sorts them chronologically even if they share a date.
    # We check the destination folder for existing .mp4 files with the same date tag.
    count=$(find "$fseason_dir" -maxdepth 1 -name "* - S${fyear}E${fdate}*" -name "*.mp4" | wc -l)
    seq_str=$(printf "%02d" $((count + 1)))
    
    new_name="${SHOW_NAME} - S${fyear}E${fdate}${seq_str} - ${base}"

    mv -- "$mp4" "$fseason_dir/${new_name}.mp4"
    echo "[vcsi] moved ${base}.mp4 -> ${new_name}.mp4"
    jpg="$TS_FOLDER/${base}.jpg"
    if [ -f "$jpg" ]; then
        mv -- "$jpg" "$fseason_dir/${new_name}.jpg"
        echo "[vcsi] moved ${base}.jpg -> ${new_name}.jpg"
    fi
    sheet="$JPG_FOLDER/${base}.mp4.jpg"
    if [ -f "$sheet" ]; then
        mv -- "$sheet" "$JPG_FOLDER/${new_name}.mp4.jpg"
        echo "[vcsi] renamed sheet ${base}.mp4.jpg -> ${new_name}.mp4.jpg"
    fi
done < <(find "$TS_FOLDER" -maxdepth 1 -name "*.mp4" -printf '%T@ %p\n' | sort -n | sed 's/^[^ ]* //')

echo "[vcsi] $(date '+%F %T') VOD move finished"

echo "[vcsi] $(date '+%F %T')  pass finished"

if $STAY_ALIVE; then
    echo "[vcsi] Entering stay-alive mode..."
    exec sleep infinity
fi
