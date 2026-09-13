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
- A photo is in at most one set, and every writer enforces it. `load` rejects
  a file whose sets overlap (`photo in both favorites and hidden: <id>`).
  `hide` refuses a favorite (`unfavorite first: <id>`); `favorite` with
  `--add`, and the plain toggle when it would add, refuse a hidden photo
  (`unhide first: <id>`). `import-favorites --force` keeps the existing
  `hidden` map and refuses when an imported id is hidden, listing the
  conflicts. Refusing rather than moving keeps an accidental hide from
  silently erasing a favorite.
- The config key and file name keep their `favorites` names. Renaming them
  means a dotfiles change on every host for no behavioural gain.

### Commands

```
walictl hide [<id>]        # hide; when <id> is the displayed photo, sample a replacement
walictl unhide <id>        # restore
walictl hidden --json      # {ok, hidden: [{id, added, path, source_path, exists}]}
```

- `hide` with no id acts on the displayed photo. The hide is saved first.
  When the hidden photo is the one on screen, the command then continues as
  `random` (a weighted sample, discarding forward history) so the screen does
  not keep showing what was just hidden. Output: `hidden <id>` on one line,
  then the selection line `random` prints. Hiding another id records only.
- Replacement can fail: the last visible photo was just hidden, or Noctalia
  rejects the change. The hide stays recorded; the command reports
  `hidden <id>` on stdout, then the replacement error on stderr, exit 1. The
  panel refreshes metadata after `hide` regardless of exit status, so the
  caption shows both the `hidden` state and the error.
- `hidden --json` mirrors `favorites --json` item for item, so the panel list
  and any script can render thumbnails from `path`.
- `current --json` gains `"hidden": <bool>`: membership in the hidden set,
  however the photo came to be displayed (history replay, a failed
  replacement, or a hide made on another host).

### Selection

- Hidden photos are removed from the candidate list before weighting, not
  given weight 0: `sample` falls back to a uniform draw over every candidate
  when all weights are 0 (everything recent), and that fallback must not
  surface a hidden photo. Month density is still computed over the full
  library, so hiding a photo does not change its month's boost. With no
  visible candidates the command fails (`every photo is hidden`); the
  all-recent fallback relaxes only the recency exclusion.
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
- When `current.hidden` is true, the caption detail line says
  `hidden` in `tertiary` and the hide button becomes a `Restore` (`eye`)
  action for that photo.

### Errors

Every failure is one line on stderr and exit 1, surfaced in the caption as
today: unknown id, refusing to hide a favorite, refusing to favorite a hidden
photo, and `unhide` of a photo that is not hidden (`not hidden: <id>`).

## Testing

- pytest: ratings round trip, version-1 upgrade, and overlap rejection on
  load; refusal from `hide`, `favorite --add`, the plain toggle, and
  `import-favorites --force` (which also preserves `hidden`); `hide` of the
  displayed photo samples and pushes history; `hide` of another id leaves
  the wallpaper alone; hiding the last visible photo records the hide and
  exits 1; a rejected replacement keeps the hide; hidden ids never sampled,
  including in the all-recent uniform fallback; earlier, later, and
  neighbors skip hidden; `current --json` reports `hidden` for a photo
  hidden while displayed; `hidden --json` contract.
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
