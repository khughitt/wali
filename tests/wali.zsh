#!/usr/bin/env zsh
set -euo pipefail

repo_root=${0:A:h:h}
source "${0:A:h}/tmp_cleanup.zsh"

fail() {
  print -u2 -- "FAIL: $*"
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-wali.XXXXXX")
register_tmp_cleanup "$tmp"
mkdir -p "${tmp}/bin"

# identify -ping -format '%w %h %[orientation]\n': the stored size and the
# EXIF orientation, from IDENTIFY_SIZE
cat > "${tmp}/bin/identify" <<'EOF'
#!/usr/bin/env zsh
print -- "${IDENTIFY_SIZE:-2100 1200 TopLeft}"
EOF

cat > "${tmp}/bin/kitten" <<'EOF'
#!/usr/bin/env zsh
exit 0
EOF

cat > "${tmp}/bin/magick" <<'EOF'
#!/usr/bin/env zsh
printf '%s\0' "$@" > "$MAGICK_ARGS_FILE"
EOF

cat > "${tmp}/bin/jpegoptim" <<'EOF'
#!/usr/bin/env zsh
exit 0
EOF

cat > "${tmp}/bin/oxipng" <<'EOF'
#!/usr/bin/env zsh
exit 0
EOF

chmod +x "${tmp}/bin/identify" "${tmp}/bin/kitten" "${tmp}/bin/magick" \
  "${tmp}/bin/jpegoptim" "${tmp}/bin/oxipng"

export PATH="${tmp}/bin:${PATH}"
export MAGICK_ARGS_FILE="${tmp}/magick.args"
export WAYLAND_DISPLAY=
export WALI_FORMAT=jpg

source "${repo_root}/shell/wali.zsh"
! alias wali >/dev/null 2>&1 || fail 'non-Wayland setup must not define wali alias'

cd "$tmp"
malicious='$(touch PWNED).jpg'
source_path="${tmp}/${malicious}"
output_path="${tmp}/output file.jpg"
touch -- "$source_path"

read_magick_args() {
  args=()
  while IFS= read -r -d $'\0' arg; do
    args+=("$arg")
  done < "$MAGICK_ARGS_FILE"
}

typeset -a args
_wali_process_image "$source_path" "$output_path" upright >/dev/null
[[ ! -e "${tmp}/PWNED" ]] || fail 'wallpaper filename executed shell syntax'
read_magick_args
[[ "${args[1]}" == "$source_path" ]] || fail 'source path lost its argument boundary'
[[ "${args[-1]}" == "$output_path" ]] || fail 'output path lost its argument boundary'
[[ "${args[*]}" == "$source_path -auto-orient -resize 3440x -quality 90 $output_path" ]] || \
  fail "upright must apply the EXIF orientation and resize only: ${args[*]}"

_wali_process_image "$source_path" "$output_path" rotate -90 >/dev/null
read_magick_args
[[ "${args[*]}" == "$source_path -auto-orient -rotate -90 -resize 3440x -quality 90 $output_path" ]] || \
  fail "rotate must turn the oriented image: ${args[*]}"

rm -f "$MAGICK_ARGS_FILE"
for mode in unsupported crop rotate-crop landscape; do
  set +e
  _wali_process_image "$source_path" "$output_path" "$mode" >/dev/null 2>&1
  exit_status=$?
  set -e
  (( exit_status != 0 )) || fail "processing mode $mode should fail"
  [[ ! -e "$MAGICK_ARGS_FILE" ]] || fail "mode $mode should not invoke magick"
done

set +e
_wali_process_image "$source_path" "$output_path" rotate 45 >/dev/null 2>&1
exit_status=$?
set -e
(( exit_status != 0 )) || fail 'unsupported rotation should fail'
[[ ! -e "$MAGICK_ARGS_FILE" ]] || fail 'invalid rotation should not invoke magick'

# The displayed size: a sideways EXIF orientation swaps the stored size.
[[ "$(IDENTIFY_SIZE='4032 2268 TopLeft' _wali_oriented_size "$source_path")" == '4032 2268' ]] || \
  fail 'TopLeft must keep the stored size'
[[ "$(IDENTIFY_SIZE='4032 2268 BottomRight' _wali_oriented_size "$source_path")" == '4032 2268' ]] || \
  fail 'a 180 degree orientation must keep the stored size'
for orientation in RightTop LeftBottom LeftTop RightBottom; do
  [[ "$(IDENTIFY_SIZE="4032 2268 $orientation" _wali_oriented_size "$source_path")" == '2268 4032' ]] || \
    fail "$orientation must swap the stored size"
done

# Ingest judges portrait by the displayed size: a sensor-landscape photo
# tagged RightTop is a portrait and prompts; [u]pright keeps it upright.
mkdir -p "${tmp}/ingest/archive/2021/06" "${tmp}/ingest/wali/3440"
touch "${tmp}/ingest/archive/2021/06/PXL_20210622_004806837.jpg"
rm -f "$MAGICK_ARGS_FILE"
print u | IDENTIFY_SIZE='3840 2160 RightTop' BACKGROUND_IMG_DIR="${tmp}/ingest/archive" \
  WALI_DIR="${tmp}/ingest/wali" wali_ingest > "${tmp}/ingest.out" 2>&1
rg -q -F '[r]otate / [u]pright / [s]kip?' "${tmp}/ingest.out" || fail 'a tagged portrait must prompt'
read_magick_args
[[ "${args[*]}" == "${tmp}/ingest/archive/2021/06/PXL_20210622_004806837.jpg -auto-orient -resize 3440x -quality 90 ${tmp}/ingest/wali/3440/PXL_20210622_004806837.jpg" ]] || \
  fail "[u]pright must ingest upright: ${args[*]}"

# A landscape as displayed is ingested without a prompt.
rm -f "$MAGICK_ARGS_FILE"
print -n | IDENTIFY_SIZE='2160 3840 LeftBottom' BACKGROUND_IMG_DIR="${tmp}/ingest/archive" \
  WALI_DIR="${tmp}/ingest/other" wali_ingest > "${tmp}/ingest.out" 2>&1
! rg -q -F '[s]kip?' "${tmp}/ingest.out" || fail 'a landscape as displayed must not prompt'
read_magick_args
[[ "${args[2]}" == -auto-orient && "${args[3]}" == -resize ]] || fail "a landscape must ingest upright: ${args[*]}"

mkdir -p "${tmp}/home"
export NOCTALIA_LOG="${tmp}/noctalia.log"

cat > "${tmp}/bin/noctalia" <<'EOF'
#!/usr/bin/env zsh
print -r -- "$*" >> "$NOCTALIA_LOG"
EOF
chmod +x "${tmp}/bin/noctalia"

# wali_rotate baked a 21:9 crop into the shared library; rotation is a
# walictl recipe now.
HOME="${tmp}/home" WAYLAND_DISPLAY=wayland-1 \
  PATH="${tmp}/bin:$PATH" zsh -f -c '
    set -e
    source "$1/shell/wali.zsh"
    [[ "$WALI_BACKEND" == noctalia ]]
    [[ "$(alias wali)" == *"walictl random"* ]]
    ! typeset -f wali_print >/dev/null || exit 1
    ! alias wali_edit_current >/dev/null 2>&1 || exit 1
    ! typeset -f wali_save >/dev/null || exit 1
    ! typeset -f wali_edit_fav >/dev/null || exit 1
    ! typeset -f wali_rotate >/dev/null || exit 1
  ' zsh "$repo_root" || fail 'Noctalia setup defines the wrong helpers'

# The plugin's contract with Noctalia v5. It lived in dotfiles' setup suite
# while the plugin did; it belongs beside the plugin.
python3 - "${repo_root}/integrations/noctalia-plugin/plugin.toml" <<'PY'
import sys, tomllib

wali = tomllib.load(open(sys.argv[1], "rb"))
assert wali["id"] == "khughitt/wali-panel"
assert wali["plugin_api"] == 28
assert wali["plugin_api"] <= 28
assert wali["dependencies"] == ["walictl"]
assert wali["widget"] == [{"id": "widget", "entry": "widget.luau"}]
assert wali["panel"] == [{
    "id": "panel", "entry": "panel.luau", "width": 588, "height": 680,
    "placement": "attached", "position": "auto",
    "keyboard_focus": "exclusive",
    "capture_keys": ["h", "Left", "l", "Right", "k", "Up", "j", "Down", "r", "f", "space", "e", "y", "a", "x", "shift+x", "shift+question", "F1"],
}]
assert "setting" not in wali
PY

print -- 'wali tests passed'
