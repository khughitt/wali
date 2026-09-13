# Hidden photos

Status: draft, 2026-09-13. Task `wali-0fe239`.

## Problem

Some photos in the library should never come up as a wallpaper again, but
deleting them from the synced library is destructive and the sampler has no
negative signal today: a photo is a favorite or it is neutral. The panel needs
a one-press way to say "not this one", and the set it builds needs to be
inspectable and reversible, because a hide is one keypress away from the
favorite heart.

## Design

### Data: the ratings file

`favorites.json` (config key `favorites_file`) becomes version 2 and carries
both sets. It stays under the synced backgrounds directory, so a hide made on
one host applies everywhere.

```json
{
  "version": 2,
  "favorites": { "<id>": { "added": "<utc>" } },
  "hidden":    { "<id>": { "added": "<utc>" } }
}
```

- The `Favorites` class becomes `Ratings` with `favorites` and `hidden` maps
  and the same lock (`favorites.lock`). Its `load` accepts version 1 (no
  `hidden` key) and writes version 2 on the next save; any other version is an
  error, as today. Version 1 acceptance is a one-time upgrade path, not a
  compatibility layer to keep: remove it once both hosts have written version 2.
- A photo is in at most one set. `hide` refuses a favorite
  (`unfavorite first: <id>`) and `favorite --add` refuses a hidden photo
  (`unhide first: <id>`). Refusing rather than moving keeps an accidental hide
  from silently erasing a favorite.
- The config key and file name keep their `favorites` names. Renaming them
  means a dotfiles change on every host for no behavioural gain.

### Commands

```
walictl hide [<id>]        # hide; when <id> is the displayed photo, sample a replacement
walictl unhide <id>        # restore
walictl hidden --json      # {ok, hidden: [{id, added, path, source_path, exists}]}
```

- `hide` with no id acts on the displayed photo. When the hidden photo is the
  one on screen, the command continues as `random` (a weighted sample,
  discarding forward history) so the screen never keeps showing what was just
  hidden. Output: `hidden <id>` on one line, then the selection line `random`
  prints. Hiding another id records only.
- `hidden --json` mirrors `favorites --json` item for item, so the panel list
  and any script can render thumbnails from `path`.
- `current --json` gains `"hidden": <bool>`, true only when history replay has
  landed on a hidden photo.

### Selection

- `weights` gives hidden photos weight 0, like recent ones, so `next` at the
  end of history, `random`, and the timer never sample them. Hidden photos
  still count toward a month's `photos_per_month` denominator; the density
  boost is about the period, not about the photo.
- `earlier` and `later` step over hidden photos: they walk the library, and a
  hidden photo is out of the library for viewing purposes. The position is
  taken from the full dated order (so a hidden photo reached through history
  replay still has neighbours), then the step continues past hidden ids until
  a visible one or the library edge. The `neighbors` listing skips hidden ids
  the same way.
- History replay (`previous`, `next` while forward history exists) does not
  filter. History is what was shown; a hidden photo reached this way is why
  `current --json` reports `hidden`.

### Panel

- A ghost `eye-off` button joins the utility strip, key `x`, tooltip
  "Hide (x) · right-click: hidden list". Left-click runs `walictl hide` and
  refreshes; the hidden photo is gone from the frame in the same round trip.
  No confirmation: the list view is the undo.
- Right-click on that button opens a native context menu with one action,
  "Show hidden…", via `panel.openContextMenu` (plugin API 28; installed
  Noctalia 5.1.0 supports it, and `plugin.toml` bumps `plugin_api` to 28).
  `shift+x` opens the same view from the keyboard.
- The hidden list replaces the frame area, like help does: a `ui.scroll` of
  rows, each a 64 px thumbnail (`ui.image`, `fit = "cover"`), the display date
  and id, and a ghost "Restore" button that runs `walictl unhide <id>` and
  re-reads the list. An empty list shows "Nothing hidden". `x`, `shift+x`, or
  the help toggle leaves the view.
- When `current.hidden` is true (history replay), the caption detail line says
  `hidden` in `tertiary` and the hide button becomes a `Restore` (`eye`)
  action for that photo.

### Errors

Every failure is one line on stderr and exit 1, surfaced in the caption as
today: unknown id, refusing to hide a favorite, refusing to favorite a hidden
photo, and `unhide` of a photo that is not hidden (`not hidden: <id>`).

## Testing

- pytest: ratings round trip and version-1 upgrade; refusal in both
  directions; `hide` of the displayed photo samples and pushes history; `hide`
  of another id leaves the wallpaper alone; weights zero for hidden; earlier,
  later, and neighbors skip hidden; `current --json` reports `hidden`;
  `hidden --json` contract.
- `plugin_test.lua`: `Logic.commandFor` for `hide`, `unhide`, `hidden`;
  `validateCurrent` accepts and requires the boolean `hidden` field;
  `decodeHidden` validates the list payload; the glyph and tooltip helpers for
  the hide/restore button.
- Manual: hide from the panel, open the hidden list, restore, confirm the
  photo can be sampled again.

## Out of scope

- A global niri binding for hide (dotfiles; add when the panel path has settled).
- Filtering hidden photos out of history replay.
- Migrating `favorites_file` to a `ratings_file` name.
