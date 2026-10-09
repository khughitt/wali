# Noctalia panel refinements — brief

## Problem

Make the wallpaper panel easier and more pleasant to use without letting a
development experiment break the installed panel. This pass covers four
unclaimed ideas sharing the Noctalia subsystem: animation (`wali-3bcef2`),
native favorite stars (`wali-24af13`), finer edit sliders (`wali-751b2c`), and
safe worktree testing (`wali-ff0d50`). All remain ideas pending evidence or
design. Ingestion-path migration (`wali-b0882b`) is outside this cluster.

## Current behaviour and evidence

- `integrations/noctalia-plugin/plugin.toml` declares API 28 and the production
  id `khughitt/wali-panel`; `tests/wali.zsh` asserts both. The plugin README
  describes hot reload and manifest reload, but gives no isolated test route.
  `wali-ff0d50` records the September 19 incident: deleting a worktree left
  the installed plugin link dangling. Its separate stale-link observations
  remain historical context, not verified current host state.
- `panel.luau` already fades the help view with frame ticks and opacity
  (`af0b328`). The favorite heart is glyph-only; click effects and hover glow
  are absent. `wali-51e601` already investigates animation feasibility; the
  earlier no-button-color finding came from API 22 and needs rechecking.
  The original mindful sources and `dots-b9ba7c` confirm colorful, subtle
  on/off effects, organic variation, and the accepted hover trigger.
- `panel.luau:sliderRow` uses recipe values as thumb coordinates and labels.
  `logic.luau` defines seven sliders: brightness, contrast, saturation and
  hue have centered defaults; blur, noise and bloom default to an endpoint.
  `deb12d9` established string-valued `onChange` callbacks and a valueless
  `onDragEnd` that requests the preview. `plugin_test.lua` checks this flow.
- `bin/walictl` owns locked, stem-keyed ratings and exports `favorites --json`.
  `cmd_favorite` writes wali ratings; it does not mirror native stars.
  The historical prerequisite `dots-59c279` is done. Native config/state
  merging, reload semantics, and the old `[[wallpaper.favorite]]` spelling
  have not been established by this pass.

## Constraints

Keep wali authoritative for ratings and recipes; preserve hidden/favorite
exclusion, original images, integer recipe ranges, pinned edit ids and
coalesced previews. The quick-edit spec supplies the intended model, but its
header still says draft: current code and callback tests establish shipped
behavior. Keep the production plugin contract and standard-library Python.
Dotfiles owns host wiring. Preserve each idea's full source body.

Experiments must use explicit worktree executables or an isolated PATH,
scratch state, and process cleanup. A dev id alone does not isolate walictl
or wallpaper changes. Live desktop use requires separate permission.
`tasks/.config.toml` declares no resource needs; if future work needs a
machine-readable desktop-review gate, propose a judgement need before using it.

## Alternatives

1. **Testing:** lean toward a separate Noctalia config/state and headless or
   nested compositor, with fake walictl. A distinct development id is a
   fallback to investigate; a health check alone catches a dangling link
   but does not provide a test route.
2. **Favorites:** lean toward a one-way native display mirror only if
   removals and native overrides can be reconciled without losing unrelated
   entries. Keeping native stars separate is the fallback. Bidirectional
   synchronization adds ownership conflicts and is not recommended.
3. **Sliders and effects:** lean toward panel-only invertible slider mapping
   with actual-value labels and the requested default-on opt-out; compare
   centered and endpoint curves before settling them. Keep recipe/CLI units.
   Reuse frame ticks for effects if API evidence supports the visual result;
   pulse versus sweep and the colorful carrier remain choices for review.

## Unanswered questions

- Can Noctalia isolate plugin discovery, IPC and state sufficiently for a
  disposable panel session? `wali-75ab89` answers this with one pilot.
- Which nodes/properties support the requested effects at API 28, and are
  CSS, SVG or shaders available? `wali-51e601` answers feasibility; the user
  judges the eventual visual candidates.
- How do native config favorites, persisted toggles, removals and reloads
  interact? Do stars follow a photo or its changing variant path?
  `wali-864e2b` traces the contract and tests scratch state.
- Which curves give useful fine control on all seven sliders, round-trip
  existing recipes, and keep exact defaults/endpoints? Where can the opt-out
  live? `wali-ae2aa9` prepares a design for user review.

## Proposed decomposition

Lane goal `wali-9a738d` owns these ideas and follow-ups. Its first milestone
is the isolated test route; other independent design/research can proceed.

- `wali-75ab89` — P2, small, mid complexity, direct research; wakes
  `wali-ff0d50`, `wali-3bcef2` and `wali-751b2c`.
- `wali-51e601` — reused P3, small, mid complexity, direct animation research;
  now depends on `wali-75ab89` for prototypes and wakes `wali-3bcef2`.
- `wali-864e2b` — P3, small, mid complexity, direct native-favorite research;
  wakes `wali-24af13`.
- `wali-ae2aa9` — P3, small, high complexity, planned slider design; preserves
  the requested opt-out and wakes `wali-751b2c` with reviewed artifacts.

Each follow-up records findings here and adds a finding note to every named
waiting idea in its completion commit, making it eligible for a later scope
pass. File implementation work only after the remaining decisions are settled.
