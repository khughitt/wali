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

# All config and image operations use scratch paths, including favorite writes.
export XDG_CONFIG_HOME="${tmp}/config"
export XDG_STATE_HOME="${tmp}/state"
export XDG_CACHE_HOME="${tmp}/cache"
export FD_ARGS_FILE="${tmp}/fd.args" GIMP_ARGS_FILE="${tmp}/gimp.args"
export ACTION_LOG="${tmp}/actions"
wallpapers="${tmp}/library ; \$(touch PWNED)"
archive="${tmp}/archive [originals]"
photo=PXL_20210622_004806837
mkdir -p "$wallpapers" "$archive/2021/06" "$XDG_CONFIG_HOME/wali"
touch "$archive/2021/06/$photo.jpg"

write_config() {
  python3 - "$XDG_CONFIG_HOME/wali/config.toml" "$wallpapers" "${1:-$archive}" <<'PYCONFIG'
import json, sys
from pathlib import Path
config, wallpaper, archive = sys.argv[1:]
text = f"wallpaper_dir = {json.dumps(wallpaper)}\nfavorites_file = {json.dumps(str(Path(config).parent / 'favorites.json'))}\n"
if archive != "absent":
    text += f"archive_root = {json.dumps(archive)}\n"
Path(config).write_text(text)
PYCONFIG
}

walictl() {
  if [[ "$1" == config ]]; then
    case "${WALICTL_TEST_FAILURE:-}" in
      command) print -u2 -- 'config command failed'; return 7 ;;
      json) print -r -- 'not json'; return ;;
      fields) print -r -- '{"wallpaper_dir": 3, "archive_root": null}'; return ;;
    esac
  else
    print -r -- "$*" >> "$ACTION_LOG"
  fi
  "$repo_root/bin/walictl" "$@"
}

cat > "${tmp}/bin/fd" <<'EOF'
#!/usr/bin/env zsh
printf '%s\0' "$@" > "$FD_ARGS_FILE"
print -r -- "$2/PXL_20210622_004806837.jpg"
EOF
cat > "${tmp}/bin/fzf" <<'EOF'
#!/usr/bin/env zsh
cat
EOF
chmod +x "${tmp}/bin/fd" "${tmp}/bin/fzf"
function /bin/gimp {
  printf '%s\0' "$@" > "$GIMP_ARGS_FILE"
}

# Ingest judges portrait by its displayed size, using the final directory.
unset WALI_DIR BACKGROUND_IMG_DIR
write_config
rm -f "$MAGICK_ARGS_FILE"
print u | IDENTIFY_SIZE='3840 2160 RightTop' wali_ingest > "${tmp}/ingest.out" 2>&1
rg -q -F '[r]otate / [u]pright / [s]kip?' "${tmp}/ingest.out" || fail 'a tagged portrait must prompt'
read_magick_args
[[ "${args[*]}" == "$archive/2021/06/$photo.jpg -auto-orient -resize 3440x -quality 90 $wallpapers/$photo.jpg" ]] || \
  fail "[u]pright must ingest into the configured library: ${args[*]}"

# A config changed after sourcing takes effect; conflicting old vars are ignored.
export WALI_DIR="${tmp}/wrong-library" BACKGROUND_IMG_DIR="${tmp}/wrong-archive"
wallpapers="${tmp}/other library"
mkdir -p "$wallpapers"
write_config
rm -f "$MAGICK_ARGS_FILE"
print -n | IDENTIFY_SIZE='2160 3840 LeftBottom' wali_ingest > "${tmp}/ingest.out" 2>&1
! rg -q -F '[s]kip?' "${tmp}/ingest.out" || fail 'a landscape as displayed must not prompt'
read_magick_args
[[ "${args[-1]}" == "$wallpapers/$photo.jpg" ]] || fail 'ingest cached an old config'
[[ "${args[2]}" == -auto-orient && "${args[3]}" == -resize ]] || fail "a landscape must ingest upright: ${args[*]}"

for old_vars in unset conflicting; do
  if [[ "$old_vars" == unset ]]; then
    unset WALI_DIR BACKGROUND_IMG_DIR
  else
    export WALI_DIR="${tmp}/wrong-library" BACKGROUND_IMG_DIR="${tmp}/wrong-archive"
  fi
  wallpapers="${tmp}/library ; \$(touch PWNED)"
  write_config absent
  touch "$wallpapers/$photo.jpg"
  # Reprocessing uses its explicit source, with no archive_root required.
  rm -f "$MAGICK_ARGS_FILE"
  print u | IDENTIFY_SIZE='2160 3840 TopLeft' wali_reprocess "$archive" >/dev/null 2>&1
  read_magick_args
  [[ "${args[1]}" == "$archive/2021/06/$photo.jpg" && "${args[-1]}" == "$wallpapers/$photo.jpg" ]] || \
    fail 'reprocess lost the explicit source or configured target'
  touch "$wallpapers/$photo.jpg"
  wali_search "$photo"
  args=()
  while IFS= read -r -d $'\0' arg; do args+=("$arg"); done < "$FD_ARGS_FILE"
  [[ "${args[2]}" == "$wallpapers" ]] || fail 'search lost the configured directory boundary'
  python3 - "$XDG_CONFIG_HOME/wali/favorites.json" "$photo" <<'PYFAVORITE'
import json, sys
assert sys.argv[2] in json.load(open(sys.argv[1]))["favorites"]
PYFAVORITE
  wali_edit_search "$photo" >/dev/null
  args=()
  while IFS= read -r -d $'\0' arg; do args+=("$arg"); done < "$GIMP_ARGS_FILE"
  [[ "${args[1]}" == "$wallpapers/$photo.jpg" && ${#args} == 1 ]] || fail 'edit-search lost the image boundary'
done
[[ ! -e "$tmp/PWNED" ]] || fail 'configured path executed shell syntax'

assert_no_actions() {
  [[ ! -e "$MAGICK_ARGS_FILE" && ! -e "$FD_ARGS_FILE" && ! -e "$GIMP_ARGS_FILE" && ! -e "$ACTION_LOG" ]] || \
    fail 'config failure reached processing, search, favorite or GIMP'
  ! rg -q -F '[s]kip?' "$tmp/failure.out" || fail 'config failure prompted'
}

for invalid in missing toml type command json fields; do
  write_config
  unset WALICTL_TEST_FAILURE
  case "$invalid" in
    missing) rm "$XDG_CONFIG_HOME/wali/config.toml" ;;
    toml) print -r -- '[' > "$XDG_CONFIG_HOME/wali/config.toml" ;;
    type) print -r -- 'wallpaper_dir = 3\nfavorites_file = "~/f"' > "$XDG_CONFIG_HOME/wali/config.toml" ;;
    *) export WALICTL_TEST_FAILURE="$invalid" ;;
  esac
  for consumer in wali_ingest wali_reprocess wali_search wali_edit_search; do
    rm -f "$MAGICK_ARGS_FILE" "$FD_ARGS_FILE" "$GIMP_ARGS_FILE" "$ACTION_LOG"
    if "$consumer" "$archive" > "$tmp/failure.out" 2>&1; then
      fail "$consumer accepted $invalid config"
    fi
    [[ -s "$tmp/failure.out" ]] || fail "$consumer failed silently"
    assert_no_actions
  done
done
unset WALICTL_TEST_FAILURE

for invalid_archive in absent "$tmp/nonexistent" "$source_path"; do
  write_config "$invalid_archive"
  rm -f "$MAGICK_ARGS_FILE" "$FD_ARGS_FILE" "$GIMP_ARGS_FILE" "$ACTION_LOG"
  if wali_ingest > "$tmp/failure.out" 2>&1; then fail 'ingest accepted an unavailable archive'; fi
  rg -q 'archive_root' "$tmp/failure.out" || fail 'ingest must explain the archive config failure'
  assert_no_actions
done

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
