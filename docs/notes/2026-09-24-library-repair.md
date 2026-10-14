# Library repair: EXIF orientation and baked crops

2026-09-24. Goal `wali-732fcd`. Plan: `2026-09-24-library-repair.plan`
(beside this note). Tool: `tools/library-repair`.

## Evidence

A pass over the 7515 library photos in `~/d/linux/backgrounds/3440/`:

| Files | Stored as | Displays in Noctalia |
|---|---|---|
| 95 | 3440×1935, EXIF orientation 3 | upside down |
| 307 + 7 | 3440×1935, EXIF orientation 6 / 8 | a portrait, sideways |
| 14 + 5 | 3440×1474 / 3440×1473 (orientation 1 / 6) | as `wali_rotate` rotated it, cropped to 21:9 |
| 2 + 1 | 8160×4590 jpg, 4032×2268 webp | never resized |

- Noctalia's JPEG decoder ignores the EXIF orientation flag. Every
  `rotate: 90` recipe in `edits.json` (7) is on an orientation-6 file, and
  auto-oriented contact sheets of samples show the flag is right: scenes come
  out upright.
- `wali_ingest` never applied the flag (`magick` without `-auto-orient`,
  `jpegoptim --strip-none` kept it) and judged portraits by stored size, so a
  portrait stored sensor-landscape was ingested without a prompt.
- `wali_rotate` rotated the original, cropped it to 21:9 and overwrote the
  library file. On titan that crop is what Noctalia's fill does anyway; on
  europa (16:10) and any other screen it loses picture.
- Titan's archive has originals for 7504 of the 7521 library ids. Its
  originals are 4032×2268, 8160×4590, 3840×2160 and their portraits; 451 carry
  orientation 3, 6 or 8.

The fix for new photos is in `shell/wali.zsh`: ingest applies the orientation
and writes orientation 1, and the crop modes and `wali_rotate` are gone.

## Plan

430 entries, every one re-rendered from its archive original, full-frame,
3440 wide, orientation 1:

- 95 orientation-3 files: `upright`.
- 314 sideways portraits: 275 scenes `upright` (3440×6116; the desktop shows
  a strip), 39 close-ups `keep` (still sideways, flag cleared). Close-up means
  ground cover, lichen, rock, driftwood, a flower seen from above: no
  up-direction. When unsure: upright.
- 19 cropped files: `keep` (the rotation `wali_rotate` chose, without the
  crop).
- 2 unresized files: `keep`. The third, `PXL_20231208_121805621`, has no
  archive original (the dry run found it); its library file is 8160×4590 with
  orientation 1, so the runbook resizes it in place.

`keep` finds the rotation of the original's stored pixels that matches the
file as it displays today. On 14 library photos × 4 rotations with 21:9 crops
it chose right in 56 of 56 cases, best score ≤ 0.009 against a runner-up
≥ 0.14; an ambiguous match stops the run before anything is written.

## Current rollout status

Read-only checks on titan, 2026-10-14, at checkout `4c1ce3a`:

- `tools/library-repair audit` exited 0: **0 of 7515 library files carry an
  EXIF rotation**. The backup directory below contains all 430 plan ids.
- Sampled files are already repaired: `PXL_20210710_144322511` is
  3440×1935 TopLeft; `PXL_20210608_145815616` and
  `PXL_20210605_113652102` are 3440×6116 TopLeft. The audit and samples do
  not establish that every old baked crop was removed; verify all planned
  files' full-frame geometry against their originals before declaring that
  part complete.
- All seven recipes listed below still contain `rotate: 90`; the last three
  also contain `anchor: bottom`. Their sampled sources are now upright, so
  the old rotations no longer correct the source orientation.
- `PXL_20231208_121805621` remains 8160×4590 TopLeft and has no backup in
  that directory. Its separate resize remains outstanding.

`wali-657e57` now covers verification of the existing repairs, the separate
resize and the seven recipe corrections. **Do not replay all 430 entries
merely because the task is still open.** Revalidate files, originals, backups
and recipes, and run a disposable pilot before any extended operation.
Changing the live shared library or recipes requires the user to run the
reviewed commands or explicitly approve applying them.

## Runbook (titan)

The batch commands below describe the original repair. After the current-state
checks above, use them only for entries demonstrated to still need repair.
Do not silently remove unresolved entries or widen the plan. Preserve the
original 430-entry plan as the record of the completed batch.

```bash
plan=~/d/wali/docs/notes/2026-09-24-library-repair.plan
backup=/mnt/storage/backgrounds-library-backup-2026-09-24

~/d/wali/tools/library-repair apply "$plan" --backup "$backup" --dry-run   # expect: would repair 430
~/d/wali/tools/library-repair apply "$plan" --backup "$backup"

# No original: the library file is full size and upright already; resize it.
f=~/d/linux/backgrounds/3440/PXL_20231208_121805621.jpg
cp -pn "$f" "$backup/" && magick "$f" -resize 3440x -quality 90 "jpg:$f.tmp" \
  && jpegoptim --strip-none "$f.tmp" && mv "$f.tmp" "$f"

# Only use these recipe commands after checking the current sources and recipes.
# The first four must have rotate=90 only; the last three must also have anchor=bottom.
# If there are other adjustments, preserve them when replacing the recipe instead.
for id in PXL_20210608_145815616 PXL_20210626_151504364 PXL_20210712_141515287 PXL_20210726_164659824; do
  walictl variant reset "$id"
done
for id in PXL_20210605_113652102 PXL_20210621_234755670 PXL_20210710_132329781; do
  walictl variant apply "$id" --set anchor=bottom
done

~/d/wali/tools/library-repair audit   # require zero flagged files; 7515 was the original library count
```

A dry run that reports `no archive original` or an ambiguous match stops the
rollout for investigation. Resolve the source or review an explicit rotation
before changing the plan. A rerun keeps the first backup, but still overwrites
the current library file, so first confirm no newer edit would be lost.

Check where `walictl` resolves on `PATH` before the recipe step. Back up the
current recipe state and re-read it immediately before writes: `variant reset`
removes the entire recipe, and `variant apply` replaces it. Never drop a newer
adjustment while removing the obsolete rotation. Run worktree code through its
explicit path; do not repoint the shared launcher.

Restore one file: `cp -p "$backup/<file>" ~/d/linux/backgrounds/3440/`.

Before closing `wali-657e57`, record the final zero-orientation audit,
full-frame/3440px checks for the 430 planned files and the separate resize,
the seven recipe results, and backup/restore locations. Refresh this status
section with the observed result. Unhiding photos and refreshing the live
desktop are separate decisions.

## After

- Dropbox carries the 431 files to every host; the library grows by about
  1 GB (upright portraits are 3440×6116). Variant renders re-key on the new
  source; phone renders come from the originals and do not change.
- 8 of the 12 hidden photos are sideways portraits in this plan (4 with a
  rotate recipe): `PXL_20210605_113652102`, `PXL_20210618_111545166`,
  `PXL_20210621_234755670`, `PXL_20210626_151213536`,
  `PXL_20210626_151504364`, `PXL_20210710_132329781`,
  `PXL_20210716_135524816`, `PXL_20210724_132551288`. Upright, some may be
  worth `walictl unhide`.
- A wallpaper on screen during the run keeps its old pixels until the next
  change: Noctalia ignores a change to the path it already shows.
