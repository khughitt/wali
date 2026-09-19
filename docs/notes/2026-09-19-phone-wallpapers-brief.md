# Phone wallpapers from favorites — brief

Scoped 2026-09-19 from `wali-448071`.

## Problem

The 687 favorited photos are desktop wallpapers; none of them reach the phone
(`amalthea`, a Pixel 8 Pro, 1344×2992 portrait). The outcome wanted: every
favorite is available on the phone as a phone-ready image — scaled and cropped
for its screen — kept in step with the favorites set without hand work, so the
phone can rotate through or pick from the same set the desktop does.

## Current behaviour and evidence

- The library `~/d/linux/backgrounds/3440/` holds 7521 photos already
  downscaled to 3440 wide (e.g. 3440×1935) by `wali_ingest` in
  `shell/wali.zsh:192`. Favorites and hidden ids are in the synced
  `favorites.json` (version 2: 687 favorites, 12 hidden).
- 686 of the 687 favorites have an archive original on titan
  (`archive_root = /mnt/storage/backgrounds`, resolved by `resolve_source`,
  `bin/walictl:217`). A 40-photo sample: 35 landscape (mostly 4032×2268, 16:9),
  5 portrait. europa has no archive (`dotfiles/wali/europa/config.toml`), so
  phone renders can only be made on titan.
- Cropping a 16:9 landscape to 9:20 portrait keeps a slice ~1020 px wide of a
  2268-tall original — about a quarter of the frame. Which quarter matters.
- Per-photo intent already exists but for the landscape output: `edits.json`
  recipes (`anchor` ∈ center/top/bottom/left/right, `rotate`, tone; spec
  `docs/specs/2026-09-13-quick-edit-design.md`). The pipeline that renders them
  is plan `docs/plans/2026-09-13-quick-edit.md`; only Task 1 (config and cache
  paths, commit `ae48131`) has landed. Tasks 2–9 (`wali-0b6bf3` … `wali-1bb717`)
  are open under `wali-608311`. `[edits] output` is one size per host.
- `~/d/linux/backgrounds/archive/phone/` is a hand-collected set of seven
  portrait wallpapers from 2023 — the last time phone backgrounds were curated,
  and not tied to favorites.
- Host recognition across projects: there is no device registry. `ops`
  `identity.toml` names projects, not machines; `ops/hosts/<hostname>/` exists
  for titan only and tracks adopted system settings (`bin/host-drift`);
  dotfiles keys per-host config by directory name (`wali/titan/`, `wali/europa/`).
  `amalthea` appears nowhere in ops, dots, mind6, or wali. On the tailnet the
  phone is `pixel-8-pro.tailc3d156.ts.net` (android, online).
- `mind6`'s mobile support is a PWA: the server binds loopback and
  `tailscale serve` proxies it to the phone (`docs/guide/local-deployment.md`
  §"Phone access over the tailnet"). It moves no files to the phone, so nothing
  there is reusable as a transport; it does establish that the tailnet is the
  standing link to the phone.
- Transports present on titan: `tailscale` (Taildrop, `tailscale file cp`,
  one-shot to the phone's Downloads), Dropbox (the library already lives under
  `~/d`). Not installed: syncthing, kdeconnect, adb, localsend. The phone runs
  Termux (dotfiles `yazi/yazi.toml` has `for = "android"` `termux-open`
  openers), so an sshd/rsync endpoint on the phone is possible but not set up.

## Constraints

- `bin/walictl` is standard-library Python; image work is `subprocess` to
  `magick`, the same pipeline the quick-edit plan builds (Task 3, `wali-e00eb6`).
- Renders need the originals, so the phone set is produced on titan only. A
  render must not be tied to the favorite toggle: ~1 s per photo would make
  `walictl favorite` slow on every host.
- The favorites file is synced; whatever is derived from it must be a mirror
  (unfavorite or hide removes the phone copy) or it drifts like `archive/phone`
  did.
- A Dropbox-held output set costs storage on every machine syncing `~/d`:
  687 × ~1–1.5 MB ≈ 1 GB, growing with favorites.
- The recipe's `anchor` is defined against the landscape output aspect; a
  top/bottom anchor says nothing about which horizontal slice a portrait crop
  should keep.

## Alternatives

**Transport**
1. *Dropbox folder* (lean): `walictl` mirrors renders into a folder under
   `~/d/linux/backgrounds/` (e.g. `amalthea/`); the Dropbox Android app marks it
   available offline; a wallpaper app on the phone reads that folder. No new
   daemon or tooling on either side; deletion propagates. Cost: ~1 GB of Dropbox
   and a phone-side wallpaper app that can source a folder.
2. *rsync over the tailnet to Termux sshd*: exact mirror, no Dropbox cost, but
   requires sshd + storage permission on the phone and the phone awake when the
   sync runs; a systemd timer would need retry.
3. *Taildrop*: works today with nothing to install, but is push-only into
   Downloads with no delete, so it cannot be a mirror; fine for a one-off batch.

**Crop policy**
1. *Center crop to 9:20* — cheapest; loses three quarters of most landscapes.
2. *Fit with blurred fill* — whole photo visible, letterboxed into a blurred
   scaled copy of itself; no per-photo intent needed. Lean for a first pass
   alongside 1, judged on a contact sheet.
3. *Per-photo horizontal anchor / focal point* — a phone-specific `anchor`
   (left/center/right) in the recipe, set from the panel; best result, most
   work, and depends on the quick-edit pipeline landing first.

**Target profile**: a `[phone]` (or `[targets.amalthea]`) table in
`config.toml` on the rendering host — `output = "1344x2992"`, `dir`, and the
crop policy — rather than a new cross-project device registry: nothing else
today needs to know about amalthea, and dotfiles already keys config per host.

**Trigger**: a `walictl phone sync` subcommand that diffs favorites against the
output folder (render missing, remove stale), run by hand or from a systemd
timer on titan beside `wali-rotate.timer`.

## Unanswered questions

1. *Answered 2026-09-19:* auto-rotate. Lean: Muzei (free, open source) with its
   "My Photos" source pointed at the local folder, dim/blur effect off; writing
   an app is not warranted while that works.
2. *Answered 2026-09-19:* yes — Dropsync on the phone mirrors the Dropbox folder
   to on-device storage (download-mirror mode propagates deletes), and the
   wallpaper app reads that local folder. Transport is settled: Dropbox folder
   mirror written by walictl on titan.
3. Is center crop or fit-with-blur acceptable for most favorites, or is a
   per-photo anchor needed from the start? Research `wali-0b4022`
   renders a sample both ways for the user to judge.
4. Should hidden photos and photos whose recipe rotates them be handled
   specially (rotate before cropping)? Falls out of the design once 3 is
   answered.
5. Does the phone set wait for the quick-edit pipeline (Task 3) or ship with its
   own minimal `magick` call? Design, after 3.

## Proposed decomposition

Goal `wali-51adcc` (todo, P2, source: this brief) owns:

- `wali-448071` — the idea, waiting on 1–3.
- `wali-0b4022` — research: render ~20 favorites' originals at
  1344×2992 as center crop and as fit-with-blur, contact sheets for review.
  Wakes `wali-448071`.
- `wali-8ad74b` — design phone wallpaper sync from this brief; depends on the
  research and on the user's answers to 1–2.
