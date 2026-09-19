# Wallpaper selection with walictl

Noctalia v5 displays wallpapers and derives colors. `bin/walictl` decides which
photo is shown, remembers what was shown, and keeps favorites. The Wali Panel
plugin (`khughitt/wali-panel`) is a view over `walictl current --json`.

## Ownership

| Concern | Owner |
|---|---|
| Display, palette, templates, hooks | Noctalia |
| Next photo, history, favorites, config | `walictl` |
| Timed rotation | `systemd/wali-rotate.timer` running `walictl next` |
| Phone renders of favorites | `systemd/wali-phone-sync.timer` running `walictl phone sync` on titan |
| Changes made in Noctalia's own panel | `wallpaper_changed` hook running `walictl observe` |
| Per-wallpaper glass deltas | prism |

Before giving the systemd timer ownership, remove `enabled` from
`[wallpaper.automation]` in
`${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/settings.toml` if present, then run
`noctalia msg config-reload`. Noctalia state settings override tracked config, so
verify the exported effective config has wallpaper automation disabled.

## Files

| Path | Purpose |
|---|---|
| `$XDG_CONFIG_HOME/wali/config.toml` | Per-host config, linked by dotfiles' setup.sh from its `wali/<hostname>/config.toml` |
| `<favorites_file>` | Favorites and hidden photos keyed by photo id (version 2), synced with the backgrounds directory |
| `$XDG_STATE_HOME/wali/history.json` | Per-host history with a cursor |
| `$XDG_STATE_HOME/wali/phone.json` | Which source each phone render was made from; rebuilt when missing |
| `<phone.dir>` | The mirrored phone folder under Dropbox; `walictl` owns every `*.jpg` in it |
| `bin/walictl` | The CLI |
| `tests/test_walictl.py` | Tests |

## Commands

```
walictl current --json      # id, date, path, source_path, variant_path, favorite, hidden, history
walictl next                # forward in history, else a weighted sample
walictl previous            # back in history
walictl earlier             # previous photo by capture time
walictl later               # next photo by capture time
walictl random              # a weighted sample
walictl favorite            # toggle the current photo; --add/--remove [<id>]
walictl favorites --json
walictl hide [<id>]         # hide from sampling; when it is displayed, sample a replacement
walictl unhide <id>         # restore a hidden photo
walictl hidden --json       # hidden photos, same item shape as favorites
walictl neighbors --json    # capture-time neighbours, for mind6; --count must be non-negative
walictl edit                # GIMP on the original, else on the display file
walictl observe             # hook entry point
walictl import-favorites <favorites.txt>
walictl phone sync          # mirror favorites into [phone] dir; --dry-run, --force, --json
```

`Super+N` toggles the Wali Panel. Inside it, `h/l` or Left/Right walks history
(the label beside Next shows the position, `cursor/length`); `k/j` or Up/Down
selects the earlier/later photo by capture time. `f` or Space toggles
favorite, `x` hides (or restores) the photo, `shift+x` opens the hidden list,
`e` edits, `y` copies the source path (display path if no source exists),
`r` or a click on the photo samples, `?` or `F1` toggles help, and Escape
closes the panel.

Without opening the panel, `Super+Alt+Left/Right` runs previous/next,
`Super+Alt+R` samples, and `Super+Alt+F` toggles favorite. Each reports the photo
or command error through `notify-send` (provided by `libnotify`).

`earlier` and `later` share the ordering used by `neighbors`: capture date,
then photo id to order shots within the day. They prefer variants, append a
history entry after Noctalia accepts the selection, and discard forward history.
They fail at either end of the library or when the current photo is undated or
absent from the library; they do not wrap or sample.

Sampling weights: favorites weigh `1 + favorite_boost`, months weigh
`1 + period_boost * favorite density`, and the last `exclude_recent` shown
photos weigh 0. `exclude_recent` must be a non-negative integer; both boosts
must be finite non-negative numbers, and an overflowing total weight is an
error. History records selections Noctalia accepted; only the default
(all-monitor) wallpaper is tracked.

Hidden photos live beside favorites in the same synced file (version 2, with
`favorites` and `hidden` maps); a photo is in at most one set, and `hide`,
`favorite`, and `import-favorites` refuse to move one across without an
explicit `unhide` or `--remove`. Hidden photos are never sampled, `earlier`,
`later`, and `neighbors` step over them, and history replay does not filter
them: `current --json` reports `hidden` so a replayed hidden photo is visible
as such. `hide` records first and then replaces the displayed photo; if no
visible photo remains or Noctalia rejects the change, the hide stands and the
command exits 1. Update `walictl` on every host before the first favorite or
hide write after this lands: a version 1 `walictl` refuses the version 2
file.

## Phone

Favorites reach the phone as centre-cropped renders at the phone's size.
`walictl phone sync` needs a `[phone]` table on the rendering host (titan,
which has the archive originals):

```toml
[phone]
dir = "~/d/linux/backgrounds/amalthea"   # under Dropbox; walictl owns its *.jpg
output = "1344x2992"                     # the phone's screen
```

Each run renders favorites that are missing or stale (a new source, a
changed output size, or `--force`), removes renders of photos that are no
longer favorites, and leaves everything else in the folder alone. It creates
an empty `.nomedia` there so the phone's gallery ignores the renders. A
favorite this host has not received is skipped with a warning. The ratings
file must exist: a missing file is an error, not an empty set, so a sync can
never empty the phone by accident. `phone.json` in the state dir records the
source of each render; a missing or malformed manifest is rebuilt on the next
run. `--dry-run` reports the plan and changes nothing.

`wali-phone-sync.timer` runs the sync daily. Dotfiles links the units on
every host; enable the timer on titan only:
`systemctl --user enable --now wali-phone-sync.timer`.

On the phone: Dropsync mirrors the Dropbox folder to a local one such as
`Pictures/amalthea` (method *download mirror*, so deletions propagate; keep
hidden files included so `.nomedia` comes along — Dropsync cannot exclude by
pattern, and a `*.jpg.tmp` caught mid-render is deleted on the next pass).
Muzei's *My Photos* source, given that folder with *Add a folder*, rotates
through it with its blur, dim, and grey effects at 0 — the renders are
already the wallpaper.

Design: `docs/specs/2026-09-07-wallpaper-management-redesign-design.md` in the dotfiles repo, where the redesign was done.
