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

## Runbook (titan)

```bash
plan=~/d/wali/docs/notes/2026-09-24-library-repair.plan
backup=/mnt/storage/backgrounds-library-backup-2026-09-24

~/d/wali/tools/library-repair apply "$plan" --backup "$backup" --dry-run   # expect: would repair 430
~/d/wali/tools/library-repair apply "$plan" --backup "$backup"

# No original: the library file is full size and upright already; resize it.
f=~/d/linux/backgrounds/3440/PXL_20231208_121805621.jpg
cp -pn "$f" "$backup/" && magick "$f" -resize 3440x -quality 90 "jpg:$f.tmp" \
  && jpegoptim --strip-none "$f.tmp" && mv "$f.tmp" "$f"

# The 7 rotate recipes turned these photos upright; the files are upright now.
for id in PXL_20210608_145815616 PXL_20210626_151504364 PXL_20210712_141515287 PXL_20210726_164659824; do
  walictl variant reset "$id"
done
for id in PXL_20210605_113652102 PXL_20210621_234755670 PXL_20210710_132329781; do
  walictl variant apply "$id" --set anchor=bottom
done

~/d/wali/tools/library-repair audit   # expect: 0 of 7515 library files carry an EXIF rotation (414 before)
```

A dry run that reports `no archive original` or an ambiguous match: move
that line out of the plan (or give it `rotate=N`) and run again. A rerun is
safe: it re-renders from the originals and keeps the first backup.

Restore one file: `cp -p "$backup/<file>" ~/d/linux/backgrounds/3440/`.

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
