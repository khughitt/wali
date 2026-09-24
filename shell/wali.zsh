#
# wallpaper switcher
# wraps pywal + chooses a random image from a specified dir
# supports X11 (feh), Wayland (swww), and Noctalia
# https://github.com/khughitt/wali
#

# skip for ubuntu and macOS hosts
if [ -f /etc/lsb-release ] && grep -q Ubuntu /etc/lsb-release; then
  return
fi
if [[ "$(uname)" == "Darwin" ]]; then
  return
fi

# detect display server / wallpaper backend
# priority: noctalia > swww > feh
if [ -n "$WAYLAND_DISPLAY" ] && command -v noctalia > /dev/null 2>&1; then
  WALI_BACKEND="noctalia"
elif [ -n "$WAYLAND_DISPLAY" ] && command -v swww > /dev/null 2>&1; then
  WALI_BACKEND="swww"
else
  WALI_BACKEND="feh"
fi

# output format for wali_ingest (jpg or png)
# set WALI_FORMAT before sourcing this file to override
: "${WALI_FORMAT:=jpg}"

# kitty image previews
# https://github.com/junegunn/fzf/issues/3228#issuecomment-1730781875
KITTY_PREVIEW_CMD='kitten icat \
    --clear \
    --transfer-mode=memory \
    --stdin=no \
    --place=${FZF_PREVIEW_COLUMNS}x${FZF_PREVIEW_LINES}@20x1 {}\
    > /dev/tty'

# wallpaper switcher
# The swww and feh backends have no switcher any more: the click CLI they ran
# is on the legacy-click-cli branch, not on main.
if [ "$WALI_BACKEND" = "noctalia" ]; then
  alias wali="walictl random"
fi

# set wallpaper to a specific image
function wali_set {
  local img="$1"

  if [ -z "$img" ]; then
    echo "Usage: wali_set <image-path>"
    return 1
  fi

  if [ "$WALI_BACKEND" = "noctalia" ]; then
    noctalia msg wallpaper-set "$img"
  elif [ "$WALI_BACKEND" = "swww" ]; then
    wal -i "$img" -n
    swww img "$img" \
      --transition-type wipe \
      --transition-duration 2 \
      --transition-fps 60
  else
    wal -i "$img" -n
    feh --bg-fill "$img"
  fi
}

function _wali_current_wallpaper {
  case "$WALI_BACKEND" in
    noctalia)
      noctalia msg wallpaper-get
      ;;
    swww)
      swww query | grep --color=never -oP 'image: \K.*' | head -n1
      ;;
    feh)
      /bin/cat ~/.fehbg | \
        /bin/grep --color=never -Eo "[\/a-z0-9]+PXL.*\.(jpg|png)"
      ;;
  esac
}

# find an image by name and add it to the favorites
function wali_search {
  local target
  target=$(fd "$1" "$WALI_DIR/3440" | grep --color='none' "$1" | fzf -1 --exact --preview=$KITTY_PREVIEW_CMD)
  [ -n "$target" ] && walictl favorite --add "${${target:t}%.*}"
}

# find an image by name and open it in gimp
function wali_edit_search {
  target=$(fd "$1" "$WALI_DIR/3440" | \
    grep --color='none' "$1" | \
    fzf -1 --exact --preview=$KITTY_PREVIEW_CMD)

  [ ! -z "$target" ] && echo "Opening $target.." && /bin/gimp "$target"
}

# create png palette based on wal colors
function wali_pal {
  source ~/.cache/wal/colors.sh

  magick -size 64x64 xc:"$color1" xc:"$color2" xc:"$color3" xc:"$color4" xc:"$color5" xc:"$color6" +append /tmp/a.png
  magick -size 64x64 xc:"$color1" xc:"$color2" xc:"$color3" xc:"$color4" xc:"$color5" xc:"$color6" +append /tmp/b.png
  magick -append /tmp/a.png /tmp/b.png ~/.cache/wal/palette.png
}

# reload pywal colors in running applications
function wali_reload {
  if [ "$WALI_BACKEND" = "swww" ]; then
    # reload waybar with new colors
    killall waybar 2>/dev/null
    ~/.config/waybar/launch.sh &
  fi

  # reload kitty colors
  killall -SIGUSR1 kitty 2>/dev/null

  echo "Reloaded colors"
}

# process a single image into 3440px-wide wallpaper
# usage: _wali_process_image <source> <outfile> <mode> [angle]
# modes: upright (orient + resize), rotate (orient + rotate + resize)
# angle: rotation degrees (default: 90). use -90 for left, 90 for right
#
# The EXIF orientation is applied first and the output is written upright
# (orientation 1): Noctalia ignores the flag, so an unapplied one shows the
# photo sideways or upside down. Crops are per-host recipes in walictl, never
# baked into the shared library.
function _wali_process_image {
  local src="$1" outfile="$2" mode="$3" angle="${4:-90}"
  local -a cmd

  case "$mode" in
    upright)
      ;;
    rotate)
      case "$angle" in
        -180|-90|90|180) ;;
        *) print -u2 -- "Unsupported rotation angle: $angle"; return 1 ;;
      esac
      ;;
    *)
      print -u2 -- "Unsupported wallpaper processing mode: $mode"
      return 1
      ;;
  esac

  cmd=(magick "$src" -auto-orient)
  if [ "$mode" = rotate ]; then
    cmd+=(-rotate "$angle")
  fi

  cmd+=(-resize 3440x)
  if [ "$WALI_FORMAT" = "jpg" ]; then
    cmd+=(-quality 90)
  fi
  cmd+=("$outfile")

  printf '%q ' "${cmd[@]}"
  printf '\n'
  command "${cmd[@]}" || return

  if [ "$WALI_FORMAT" = "jpg" ]; then
    jpegoptim --strip-none "$outfile"
  else
    oxipng -o 4 "$outfile"
  fi
}

# the size a photo displays at: "<width> <height>" after its EXIF orientation
function _wali_oriented_size {
  local w h orientation
  read -r w h orientation < <(identify -ping -format '%w %h %[orientation]\n' "$1")
  case "$orientation" in
    LeftTop|RightTop|RightBottom|LeftBottom) print -- "$h $w" ;;
    *) print -- "$w $h" ;;
  esac
}

# ask how to ingest a portrait; prints the mode, or nothing to skip. The
# preview and the prompt go to stderr: stdout is the answer.
function _wali_portrait_mode {
  local src="$1" w="$2" h="$3" choice
  kitten icat --clear --transfer-mode=memory --stdin=no "$src" >&2
  print -u2 -- "\n$(basename "$src") (${w}x${h})"
  print -u2 -n -- "[r]otate / [u]pright / [s]kip? "
  read -r choice
  case "$choice" in
    r) print -- rotate ;;
    u) print -- upright ;;
  esac
}

# image ingestion
function wali_ingest {
  local x fname outfile w h mode
  for x in $BACKGROUND_IMG_DIR/*/*/*.jpg; do
    fname=${x##*/}
    outfile="$WALI_DIR/3440/${fname%.jpg}.$WALI_FORMAT"
    [ -e "$outfile" ] && continue

    read -r w h < <(_wali_oriented_size "$x")
    mode=upright
    if [ "$h" -gt "$w" ]; then
      mode=$(_wali_portrait_mode "$x" "$w" "$h")
    fi
    if [ -z "$mode" ]; then
      echo "Skipping $fname"
      continue
    fi
    _wali_process_image "$x" "$outfile" "$mode"
  done
}

# reprocess portrait images that already have processed versions
function wali_reprocess {
  local src_path="${1:?Usage: wali_reprocess <source_path>}"
  local x fname outfile w h mode

  if [ ! -d "$src_path" ]; then
    echo "Directory not found: $src_path"
    return 1
  fi

  for x in "$src_path"/**/*.jpg; do
    [ -f "$x" ] || continue

    fname=${x##*/}
    outfile="$WALI_DIR/3440/${fname%.jpg}.$WALI_FORMAT"

    # only reprocess files that already have a processed version
    [ -e "$outfile" ] || continue

    # only prompt for portrait images
    read -r w h < <(_wali_oriented_size "$x")
    [ "$h" -gt "$w" ] || continue

    mode=$(_wali_portrait_mode "$x" "$w" "$h")
    if [ -z "$mode" ]; then
      echo "Skipping $fname"
      continue
    fi
    rm "$outfile"
    _wali_process_image "$x" "$outfile" "$mode"
  done
}

# vi:filetype=zsh
