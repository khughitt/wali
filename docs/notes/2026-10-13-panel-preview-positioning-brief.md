# Panel preview reliability and wallpaper positioning brief

## Problem

Keep the panel's photo visible reliably and make wallpaper placement visual.
The shared capture, `mindful:thought:07db296e4a1c44e4ada9be93f80e2f05`, reports
intermittent grey previews that usually recover after reopening, and prefers
dragging nested screen/wallpaper rectangles over adding placement buttons.
`wali-630361` and `wali-b07541` remain ideas until diagnosis and design
establish their implementation handoffs.

## Current behaviour and evidence

At checkout `2fc0827`, `integrations/noctalia-plugin/panel.luau:frame` shows
`state.current.path` in photo mode and the latest preview path in edit mode.
`onOpen` clears edit/help state and refreshes current metadata. Preview
callbacks reject expired edit generations and coalesce pending changes.
`bin/walictl:cmd_variant_preview` publishes a keyed JPEG atomically, then
`prune_previews` removes that photo's other previews. These are investigation
points, not established causes of the grey rectangle. The capture does not
identify which view fails. `plugin_test.lua` replaces `ui.image` with a table
constructor, so its path assertions do not exercise Noctalia's image loader.

Quick-edit work `wali-608311` is done. Python and Luau recipes currently
accept only center/top/bottom/left/right anchors. `bin/walictl:crop_box` fits
the largest output-aspect rectangle inside the rotated source; at least one
dimension fills the source. Thus only one axis can move, or neither for equal
aspects. Within this geometry, a corner duplicates an edge position.
`tests/test_walictl.py` checks crop coordinates and preview/full-render parity.
The current edit preview is already cropped and is not an uncropped placement
canvas. No continuous-position recipe or panel drag control currently exists.

## Constraints

Preserve original photos, existing recipes, pinned edit ids, preview
coalescing and Apply/Cancel/Reset semantics. Keep preview and full-render
placement consistent, and account for the separate phone output aspect.
`bin/walictl` stays standard-library Python. The older quick-edit spec is
still labelled draft; shipped code establishes current behavior.

Reuse lane `wali-9a738d` and isolated-test research `wali-75ab89`; do not
create another test-route task or repoint the installed plugin/CLI links.
Runtime checks use scratch state and explicit worktree executables. Live
desktop use requires separate permission. No shared needs are declared in
`tasks/.config.toml`. A suspected upstream defect requires the upstream
search before its reproduction or patch; publishing remains separately gated.

## Alternatives

1. **Preview reliability:** diagnose path availability, callback/state order
   and real image loading before changing behavior. Reopening, clearing
   caches or retrying blindly lacks a demonstrated cause and regression check.
2. **Continuous crop placement:** current lean for the requested drag
   interaction, without zoom or blank borders. Requires a persisted position,
   geometry for the uncropped source, and a keyboard-accessible equivalent.
3. **Snapped anchors:** smaller recipe change, but supports only fixed
   positions. Adding corners alone cannot provide continuous repositioning.
   Genuine movement on both axes would require a separate zoom/letterboxing
   decision; it is not included by default.

## Unanswered questions

- Which view fails, does its path remain readable, and what changes on
  reopening? `wali-b5e7a2` diagnoses this with bounded isolated reproduction.
- Does the declared plugin API support the required drag coordinates and
  layout? How should geometry, persisted position and existing anchors
  interact? `wali-273c6f` traces the API and prepares a reviewed design.
- Does the crop-only interaction match the requested placement experience?
  The user judges the design's visual mockup; any zoom/border expansion stays
  an explicit scope decision.

## Proposed decomposition

Associate both ideas and follow-ups with existing lane `wali-9a738d`.

- `wali-b5e7a2` — P2, small, mid complexity, direct diagnosis; depends on
  `wali-75ab89` and wakes `wali-630361`. Return a demonstrated cause and
  regression-check recommendation, or a precise inconclusive result.
- `wali-273c6f` — P3, small, high complexity, planned positioning design;
  depends on `wali-75ab89` and wakes `wali-b07541`. Produce a design spec and
  implementation plan for separate reviews, including a visual mockup.

Each idea depends on its named follow-up. Completion records the finding here
and uses `tasks note <idea> --no-reviewed "<finding>"` before that result's
branch merges, so a later scope pass can reconsider it. Neither implementation
is authorized by this brief alone.
