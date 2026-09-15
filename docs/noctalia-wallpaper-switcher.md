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
| `<edits_file>` | Per-photo edit recipes (`edits.json`), synced beside favorites; optional |
| `$XDG_CACHE_HOME/wali/variants/<id>/<key>/` | One rendered variant per recipe/output/source key, per host |
| `$XDG_CACHE_HOME/wali/preview/<id>/` | Downscaled previews for the panel's edit mode |
| `$XDG_STATE_HOME/wali/history.json` | Per-host history with a cursor |
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
walictl variant show [<id>] --json          # effective recipe and cached variant path
walictl variant preview [<id>] --set k=v..  # 560px preview of the settings; prints its path
walictl variant apply [<id>] --set k=v..    # replace the recipe, render, show it when displayed
walictl variant reset [<id>]                # drop the recipe and its renders
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

Quick edits are recipes: `rotate` (0/90/180/270), `brightness`, `contrast`
(-100..100), `saturation` (0..200), `hue` (-180..180), `blur` (0..20), `noise`,
`bloom` (0..100), and `anchor` (center/top/bottom/left/right, a crop to the
output aspect from that edge; needs `[edits] output = "WxH"` in the host
config). Set `edits_file` to turn them on:

```toml
edits_file = "~/d/linux/backgrounds/edits.json"

[edits]
output = "3440x1440"
```

`walictl` renders a recipe with `magick` into a per-host cache the first time
the photo is selected there; each distinct recipe, output size, or library
file gets its own keyed path, because Noctalia ignores a wallpaper change to
the path it already shows. Stale renders are removed only after a wallpaper
change succeeds. `apply` and `reset` re-set the wallpaper when the photo is
on screen and rewrite its history entry's path, so history keeps one entry
per photo.

Design: `docs/specs/2026-09-07-wallpaper-management-redesign-design.md` in the dotfiles repo, where the redesign was done.
