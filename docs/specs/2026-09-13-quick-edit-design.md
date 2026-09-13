# Quick edit: per-photo variants from a synced recipe

Status: draft, 2026-09-13. Task `wali-608311`. Extends the variant mechanism
from the dotfiles spec `2026-09-07-wallpaper-management-redesign-design.md`.

## Problem

A photo that almost works as a wallpaper usually needs one small change: a
rotation, a lift in brightness, a little desaturation, or the crop anchored
to its top edge instead of Noctalia's center crop. Opening GIMP for that is
too heavy, and today nothing writes the variants `walictl` already knows how to
prefer. The edit should be tried before it is committed, survive wallpaper
cycles, follow the photo to the other host, and never touch the original.

## Design

### Recipe, not pixels, is what syncs

Each edited photo has a recipe: the ordered set of adjustments to apply to its
library file. Recipes live in one synced JSON file; rendered pixels are a
per-host cache derived from the recipe and that host's screen shape.

`edits.json` beside `favorites.json`, config key `edits_file`. It is optional:
when unset, recipes are off, no render step runs, and navigation behaves as
today; the `variant` commands fail with `config key edits_file is required`.

```json
{
  "version": 1,
  "edits": {
    "<id>": {
      "rotate": 90, "brightness": 10, "contrast": 0, "saturation": 80,
      "hue": 0, "blur": 0, "noise": 0, "bloom": 0, "anchor": "top",
      "updated": "<utc>"
    }
  }
}
```

Only keys that differ from their default are stored. A recipe with no
non-default keys is removed. Fields, defaults, and ranges:

| key | default | range | magick |
|---|---|---|---|
| `rotate` | 0 | 0, 90, 180, 270 | `-rotate N` |
| `brightness` | 0 | -100..100 | `-brightness-contrast B×C` |
| `contrast` | 0 | -100..100 | (same flag) |
| `saturation` | 100 | 0..200 | `-modulate 100,S,H` |
| `hue` | 0 | -180..180 | (same flag; H = 100 + hue/1.8) |
| `blur` | 0 | 0..20 | `-blur 0xN` |
| `noise` | 0 | 0..100 | `-attenuate N/100 +noise Gaussian` |
| `bloom` | 0 | 0..100 | screen-blend of a `-blur 0x25` copy at N% |
| `anchor` | `center` | center, top, bottom, left, right | crop to the output aspect from that edge |

Operations apply in table order: rotate first, then tone, then blur, noise,
bloom, then the crop. `chroma` from the task body is dropped: on photographs
it is indistinguishable from `saturation`. `anchor = center` stores nothing
and leaves the crop to Noctalia. A `zoom` factor is out of scope.

Values outside a range, unknown keys, and non-integers are errors at the
command line; the recipe file is validated on load like the ratings file and
rejected whole on a malformed entry.

### Rendering

`walictl` stays standard-library Python; it shells out to `magick`
(ImageMagick 7, on both hosts). A missing `magick` is
`magick command not found`, like GIMP today.

- Source is the library file for the id (3440 wide), never the archive original.
- Output: `$XDG_CACHE_HOME/wali/variants/<id>.jpg` with a sidecar
  `<id>.recipe` holding the SHA-256 of the canonical recipe JSON, the output
  size, and the source identity (library path, size, mtime), so replacing a
  library file invalidates its render. The `variants_dir` config key is
  removed; the cache is the only variant location and `resolve_variant`
  reads it.
- A render is current when the sidecar hash matches; otherwise it is stale
  and rerendered. A recipe removed from `edits.json` means the cache pair is
  deleted on the next touch.
- Publication is atomic and serialised: renders happen under a
  `variants.lock` in the state dir (the existing `locked` helper), `magick`
  writes to a temporary file in the cache dir, and only a successful render
  is renamed over `<id>.jpg`, then the sidecar written with
  `write_json_atomic`. A failed render leaves the previous pair untouched,
  so a stale-but-good variant keeps displaying until a render succeeds.
- The crop needs the output size: config `[edits] output = "3440x1440"`,
  per host. An `anchor` other than `center` with no `output` set is
  `config key edits.output is required for anchor` at apply time. The crop
  box is computed in Python from `magick identify -format %wx%h` on the
  rotated intermediate (or from the source size, swapped for 90/270), so
  the geometry passed to `-crop` is exact rather than gravity-and-extent
  guesswork.
- Trigger: `display_path` (sampling, `earlier`, `later`) and `replay_path`
  (history replay) call `ensure_variant(id)` before returning, so a stale or
  missing render on this host is produced the first time the photo is
  selected here. `replay_path` resolves from the id, not the recorded entry
  path: the variant when a recipe exists, else the library file, so a reset
  never replays a deleted cache path. `current` never renders. A render
  failure fails the selection command with magick's stderr; the wallpaper is
  left as it was.
- `apply` and `reset` change the displayed file's path without changing the
  photo, and `reconcile` compares paths. Both therefore update the current
  history entry's `path` under the history lock (after setting the
  wallpaper) instead of pushing, so the next navigation neither records a
  duplicate `observed` entry nor discards forward history.

### Commands

```
walictl variant show [<id>] --json            # {ok, id, recipe: {...} | null, variant_path}
walictl variant preview [<id>] --set k=v ...  # render a 560px-wide preview; print its path
walictl variant apply [<id>] --set k=v ...    # replace the recipe, render, re-set the wallpaper if current
walictl variant reset [<id>]                  # remove the recipe and cache, re-set the wallpaper if current
```

- `<id>` defaults to the displayed photo.
- `--set` is repeated; the given set *is* the recipe (`apply` replaces, it
  does not merge). Passing a default value clears that key.
- `preview` writes `$XDG_CACHE_HOME/wali/preview/<id>.<hash8>.jpg` and
  deletes other previews for that id. The changing file name is deliberate:
  `ui.image` may cache by path. The source is resized to 560 px wide *before*
  the operations so the round trip is fast enough for a slider, and the
  pipeline is made representative of the full render at that scale: the
  pixel-unit parameters (`blur` sigma, the bloom blur radius, and the noise
  attenuation) are multiplied by the resize factor (560 / source width after
  rotation), and the preview is cropped to the output aspect from the anchor
  whenever `edits.output` is set, including `center`, so the preview shows
  what Noctalia's crop will show. Without `edits.output` the preview is
  uncropped, as the full render is.
- `apply` order: render to the cache first, then save the recipe, then re-set
  the wallpaper through Noctalia when the photo is displayed. A render
  failure saves nothing; a rejected wallpaper change leaves the recipe and
  cache in place (the next selection uses them) and reports the error.
  `reset` removes the recipe, deletes the cache pair, and re-sets the
  library file when the photo is displayed. History is not pushed by either
  (the photo did not change; see Rendering). `reset` on a photo without a
  recipe is `no recipe: <id>`.
- `walictl edit` keeps opening GIMP.

### Panel: edit mode

- A ghost `adjustments` button in the utility strip, key `a`, toggles edit
  mode; `a` again or Cancel leaves it, discarding unapplied changes. Entering
  pins the session to the displayed photo's id, runs `variant show --json`
  for it, and seeds the controls; a photo without a recipe starts at
  defaults. Every `preview`, `apply`, and `reset` from the session passes
  that id explicitly: the timer and the global bindings can change the
  wallpaper while the panel is open, and the edit must not land on whatever
  is displayed by then. Each session carries a generation number; a preview
  callback whose generation is not the current one is dropped, so Cancel or
  reopening on another photo cannot paint a stale preview into the frame.
- Layout in edit mode: the frame shrinks to 200 px (`fit = "contain"`) and
  shows the latest preview, or the current photo until the first preview
  lands; below it a `ui.scroll` holds one row per slider (label, `ui.slider`
  `controlSize = "sm"`, value), a row of rotate buttons (0/90/180/270 as
  `selected` toggles) and anchor buttons (center/top/bottom/left/right), and
  a final row with `Reset` (destructive variant, enabled when a recipe
  exists), `Cancel`, and `Apply` (primary). Exact heights are a review item on
  the rendered panel; the panel entry height in `plugin.toml` may grow if the
  scroll is too cramped.
- Every `onDragEnd` and every rotate/anchor click runs `variant preview` with
  the full current control state; the frame path updates when it returns.
  Requests are serialised through the existing `busy` gate: a change made
  while a preview runs is remembered and sent once, after the running one
  returns, so sliders never queue up stale renders.
- `Apply` runs `variant apply` with the same `--set` list, then refreshes
  `current` and leaves edit mode. `Reset` runs `variant reset`, then the same.
- The caption's existing `variant` tag reads as the "edited" indicator; no new
  caption state.
- Navigation keys are ignored in edit mode; `capture_keys` adds `a`.

### Errors

Command failures show in the caption detail line as today. A preview failure
leaves the last good preview in the frame. Apply failures leave edit mode
open so the controls are not lost.

## Testing

- pytest with a stub `magick` on `PATH` that records its argv and copies the
  input to the output: recipe validation and canonical hashing; the argv
  built for each key and for the crop box for every anchor at both landscape
  and portrait sources; the preview scaling of pixel-unit parameters and its
  crop; `ensure_variant` renders when missing, skips when the hash matches,
  rerenders when stale or when the source changed, and deletes the pair when
  the recipe is gone; a failed render leaves the previous pair; navigation
  with `edits_file` unset never invokes the stub; `apply` and `reset` re-set
  the wallpaper only when the photo is current and rewrite the history
  entry's path rather than pushing; `preview` prunes older previews; every
  config error message.
- One pytest against the real `magick`, skipped when it is not on `PATH`:
  render a generated landscape image with rotate 90, an anchor, blur, and
  bloom at full size and as a preview, and assert the preview equals the
  full render downscaled to preview size within a small mean absolute
  difference. The argv stub cannot catch a visual mismatch; this can.
- `plugin_test.lua`: control state to `--set` arguments and back from a
  `variant show` payload; the slider table (key, range, step, label);
  the pending-preview coalescing helper; payload validation for
  `variant show` and `variant preview`.
- Manual: rotate and anchor a portrait photo, apply, cycle away and back,
  check the variant persists; on the second host, select the same photo and
  confirm it renders there with that host's output size.

## Out of scope

- `zoom` / rescale and free-form crop.
- Chroma as a separate control.
- Editing the archive original; `walictl edit` (GIMP) remains the route for that.
- Batch re-rendering the cache when `edits.output` changes; stale sidecars
  handle it lazily.
