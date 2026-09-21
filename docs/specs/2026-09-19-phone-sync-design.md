# Phone wallpaper sync — design

Status: draft, 2026-09-19. Task `wali-8ad74b` under goal `wali-51adcc`.
Brief: `docs/notes/2026-09-19-phone-wallpapers-brief.md` (evidence and the
decisions already taken).

## Goal

Every favorited photo is available on the phone (`amalthea`, a Pixel 8 Pro,
1344×2992) as a phone-ready render, and the phone's set tracks the favorites
set without hand work: favoriting adds a render, unfavoriting or hiding
removes it.

## Decisions carried in from the brief

- Transport is a folder under Dropbox. `walictl` on titan mirrors renders into
  it; Dropsync on the phone mirrors that folder to on-device storage; Muzei's
  "My Photos" source rotates through the local folder. Nothing new is
  installed on titan.
- Crop is a center crop to the phone aspect, judged on contact sheets
  (`wali-0b4022`). A per-photo horizontal anchor is a later opt-in.
- Renders come from the archive originals, so the sync runs on titan; europa
  has no archive and no `[phone]` table.

## Shape

One new command, `walictl phone sync`, that makes the output folder equal
to the favorites set: render what is missing or stale, delete what is no
longer a favorite, touch nothing else. A systemd timer runs it nightly. A
small manifest in the state dir records which source each render was made
from, so a better source or a new output size re-renders on its own.

Rendering is one `magick` invocation per photo, deliberately independent of
the quick-edit pipeline (`docs/specs/2026-09-13-quick-edit-design.md`, plan
tasks 2–9 still open): the phone crop needs the original's full height, while
that pipeline reads the 3440-wide library file by design and renders into a
keyed per-host cache. When the pipeline lands, recipe rotation and tone can
be folded into the phone render (§Later); nothing here blocks or is blocked
by it.

## Configuration

A `[phone]` table in `config.toml`, on the host that renders:

```toml
[phone]
dir = "~/d/linux/backgrounds/amalthea"   # the mirrored folder; walictl owns its *.jpg
output = "1344x2992"                     # the phone's screen, WIDTHxHEIGHT
```

- `PhoneConfig(dir: Path, output: tuple[int, int])`; `Config.phone:
  PhoneConfig | None`. Both keys are required inside the table; `dir` goes
  through `_expand`, `output` through the existing `parse_output`.
- Errors follow the `[edits]` wording: `config key phone.dir must be a
  non-empty string`, `config key phone.output must be WIDTHxHEIGHT`, and a
  missing key `config key phone.<key> is required`. Any `phone` command with
  no table: `config table [phone] is required` (exit 1). Nothing else in
  `walictl` reads the table.
- One target only. A second device is a second table when it exists, not a
  `[targets.<name>]` scheme now.

## The command

```
walictl phone sync [--dry-run] [--force] [--json]
```

Under a `phone.lock` in the state dir (the `locked` helper; no other lock is
taken, so there is no ordering to respect), the command:

1. Requires the ratings file to be read: the load itself fails with
   `favorites file not found: <path>` (exit 1) when `read_json` returns
   `None`, before anything is touched — `Ratings.load(path, required=True)`,
   not an `exists()` check ahead of today's load, which would leave a window
   in which the file vanishes between the check and the read. `Ratings.load`
   reads a missing file as an empty set, which for every other command is
   right and for a mirror would delete every render and push the deletions
   to the phone. A file that is present and holds no favorites empties the
   folder: that is the explicit case. The wanted set is `favorite_ids()`;
   hidden photos are disjoint from favorites already.
2. Creates `dir` if missing (`mkdir -p`) and an empty `dir/.nomedia` if
   missing, so the phone's gallery ignores the folder; it lives in the
   Dropbox source because Dropsync's download mirror deletes device-only
   files. A `dir` that exists and is not a directory is `phone.dir is not a
   directory: <path>`.
3. Removes every non-dotfile `*.jpg.tmp` left in `dir` by an interrupted
   run — its own temporaries, and only those.
4. Lists the non-dotfile `dir/*.jpg`. Every render whose stem is not in the
   wanted set is removed. Anything else in `dir` — other extensions,
   `.nomedia`, any dotfile (a `.private.jpg` included), subdirectories — is
   never touched or listed in the summary. The folder's non-dotfile `*.jpg`
   are owned by `walictl`; the docs say so. An existing non-directory at
   `dir` is `phone.dir is not a directory: <path>` in both modes, checked
   before anything is created.
5. For each wanted id in sorted order, chooses the source: `resolve_source`
   (the archive original) when present, else the library file from
   `scan_library`. An id in neither is skipped with `missing from library`
   on stderr — the ratings file is synced and may name a photo this host has
   not received — and counted in the summary; it does not fail the run.
6. A render is current when `dir/<id>.jpg` exists and the manifest entry
   for the id matches the source identity and the output size
   (§Manifest). A render made from the library fallback becomes stale the
   moment the original appears, because the source path changes; a changed
   `output` makes every render stale. `--force` treats every render as stale
   regardless (a new ImageMagick, a quality change). A stale or missing
   render is produced (§Rendering).
7. Prints one line, `rendered N, removed M, kept K, skipped S`, or with
   `--json` an object `{"ok": true, "rendered": [ids], "removed": [ids],
   "kept": K, "skipped": [{"id": …, "reason": …}]}`. `--dry-run` computes and
   reports the same plan and renders and removes nothing.

A `magick` failure stops the run at that photo: `magick failed: <stderr>`
on stderr, exit 1, the renders already produced and the removals already
made stay (each is independently correct and already in the manifest), the
partial summary is not printed. A missing `magick` is `magick command not
found` before any work.

## Manifest

`$XDG_STATE_HOME/wali/phone.json`, written with `write_json_atomic` under
the same `phone.lock`:

```json
{"version": 1, "renders": {"<id>": {"source": "<path>", "size": 4021337,
                                    "mtime_ns": 1718000000000000000,
                                    "output": "1344x2992"}}}
```

- The source identity is the path rendered from (the original or the
  library file), its size, and its mtime in nanoseconds — the same three
  facts the quick-edit cache keys on, kept readable instead of hashed.
- An entry is written after each successful rename and removed after each
  removal. The image and the manifest are two writes, so an interruption
  between them leaves them disagreeing; the guarantee is recovery, not
  atomicity: any disagreement — an entry without a file, a file without an
  entry, an entry whose identity no longer matches — is a stale render and
  is rebuilt on the next run. A missing or malformed manifest is the same
  case at whole-file scale: read as empty, every render stale, the next run
    rebuilds both (`read_json` already reports invalid JSON or a non-object;
  invalid UTF-8 raises `UnicodeError` and is the same case; the command warns
  and proceeds rather than failing, since the folder is the truth and the
  manifest a record of it). The tests interrupt between the two writes
  in both orders and show the next run converging.
- `--dry-run` reads the manifest and never writes it.

## Rendering

One process per photo:

```
magick <source> -auto-orient -strip \
       -resize WxH^ -gravity center -extent WxH \
       -quality 88 jpg:<dir>/<id>.jpg.tmp
```

then `os.replace` to `<dir>/<id>.jpg`. `-auto-orient` applies the EXIF
rotation the originals carry; `-strip` drops EXIF and GPS from files that
leave the machine; `^` scales to cover, `-extent` crops centred. The
temporary lives in `dir` so the rename is atomic on the same filesystem. Its
name is `<id>.jpg.tmp`, never `<id>.tmp.jpg`: a photo id may itself end in
`.tmp`, and a published render's suffix is always `.jpg`, so a `.tmp` suffix
can never collide with one; the `jpg:` prefix tells the encoder the format
the extension no longer does. Dropbox may transiently see the temporary; it
is removed by the rename or by step 3 of the next run.

The 3440-wide library file is the fallback source for a favorite without an
original (1 of 687 today). A 9:20 crop of a 3440×1935 file is 871×1935,
upscaled ×1.5 — soft but whole. Preferring the original is the one place this
diverges from the quick-edit pipeline, and the reason is the portrait crop.

Cost: 686 originals at roughly a second each on the first run; incremental
runs render only new favorites. The command is safe to run at any time and
idempotent.

## Timer

`systemd/wali-phone-sync.service` (oneshot, `%h/bin/walictl phone sync`)
and `systemd/wali-phone-sync.timer` (`OnCalendar=daily`, `Persistent=true`,
`AccuracySec=1h`). Dotfiles links units one by one in
`setup_systemd_user_units` (`setup.sh:763` links the two rotation units) and
enables `wali-rotate.timer` on every host under `ENABLE_USER_TIMERS`; the
phone timer must not join that block, since only titan has a `[phone]`
table. The dotfiles piece of this work, one `dots` task depended on by the
goal: two `ln_s` lines for the new units, the matching fixture and
assertions in `tests/setup_and_health.zsh`, the `[phone]` table in
`wali/titan/config.toml`, and a documented one-off
`systemctl --user enable --now wali-phone-sync.timer` on titan. On a host
without the table the service would exit 1 with the config error, which is
why it is linked everywhere and enabled only there.

## Phone side (manual, documented)

- Dropsync: a folder pair from the Dropbox folder to a local folder, method
    *download mirror*, so deletions propagate. Excluding `*.jpg.tmp` in the
  pair avoids copying a transient. Download mirror deletes files that exist
  only on the device, which is why `.nomedia` comes from the Dropbox side
  (the command creates it) rather than being placed on the phone.
- `.nomedia` keeps the renders out of the gallery; Muzei reads the folder
  through the document picker and ignores it.
- Muzei: source *My Photos*, the local folder, rotation interval to taste,
  and the dim/blur effects set to 0 — the renders are already the wallpaper.

## Errors

Every failure is one line on stderr and exit 1, through the existing `main`
handler. Config errors happen before the lock; `magick command not found`
before any render; a render failure stops the run as described. The
command never removes a render it did not decide to remove, and never
writes outside `dir`.

## Testing

- `tests/test_walictl.py`, with the existing `env` fixture: a `phone_env`
  helper writes the `[phone]` table into the config, and a `magick` stub on
  `PATH` records its argv and writes a file at the last argument. (The
  quick-edit plan's Task 3 introduces its own stub; when both exist they are
  one fixture.) Covered: config parsing and each error message; the wanted
  set (favorites in, hidden out, missing-from-library skipped); a missing
  ratings file fails before any mutation while a present empty one empties
  the folder; source preference (original over library file, library
  fallback); the fallback-then-original transition re-renders; a changed
  `output` re-renders; a changed source size or mtime re-renders; render
  argv; `--force`; removal of stale renders and of leftover temporaries,
  with their manifest entries; a missing or malformed manifest rebuilds;
    `.nomedia` created once and never removed; dotfiles (including
  `.private.jpg` and `.private.jpg.tmp`), other extensions, and
  subdirectories untouched; a favorite whose id ends in `.tmp` keeps its
  render; a non-directory at `dir` rejected on `--dry-run` too;
  `--dry-run` writes neither renders nor manifest; `--json` shape; `magick`
  failure stops with the partial state and manifest consistent; the lock
  is held.
- One real-ImageMagick test, skipped when `magick` is absent: a generated
  landscape and a generated portrait source both render to exactly
  `1344x2992` (checked with `magick identify`).
- Manual: `phone sync` on titan through the branch's own executable
  (`~/bin/walictl` is another review's shim while quick-edit is in review),
  then Dropsync and Muzei on the phone showing the set. The timer is enabled
  only once the shim the unit runs resolves to a `walictl` with `phone`.
- `just verify` before every commit.

## Documentation

- `docs/noctalia-wallpaper-switcher.md`: the `[phone]` table in the config
  section, `walictl phone sync` in the command list, `phone.json` in the
  files table, the timer in the ownership table, and a short "Phone" section
  with the Dropsync/Muzei steps and the titan-only enable.
- `README.md`: the two units in the `systemd/` row.

## Out of scope

- Recipes (`rotate`, tone, `anchor`) in phone renders, and a phone-specific
  horizontal anchor.
- More than one target device; running the sync anywhere but titan.
- Any transport other than the Dropbox folder (rsync/Termux, Taildrop).


## Later

When the quick-edit pipeline lands, the phone render can take the recipe's
`rotate` and tone operations ahead of its own crop, and a `phone_anchor`
(left/center/right) in the recipe can replace `-gravity center`. Both are
additive to this design: the command, folder, and mirror semantics stay.
