---
id: wali-1bb717
title: "Task 9: Host config and manual verification"
status: doing
priority: 2
size: xs
complexity: low
process: planned
owner: quick-edit-recipes
created: 2026-09-13T17:59:09Z
updated: 2026-09-17T15:47:56Z
started: 2026-09-16T00:53:42Z
depends: [wali-8c3853, wali-4a1724]
parent: wali-608311
tags: [noctalia]
plan: docs/plans/2026-09-13-quick-edit.md
step: "Task 9: Host config and manual verification"
---

## Notes

- 2026-09-16T00:56:12Z (quick-edit-recipes): parked (waiting on user, review): titan configured (edits_file, output 3440x1440; europa 1920x1200) and the branch loaded: plugin relinked to the worktree, ~/bin/walictl shimmed, plugin re-enabled. Judge the edit-mode layout, slider heights, and preview latency on the rendered panel
- 2026-09-16T02:34:48Z (quick-edit-recipes): review found: Noctalia marshals callback and frame-tick args as strings; slider drags and the help fade errored on string arithmetic and the host disabled the panel. Fixed with tonumber at both boundaries (9c36665), panel re-enabled
- 2026-09-16T09:18:53Z (quick-edit-recipes): second root cause from live debugging: slider onDragEnd carries no value (empty string; the C++ signal is void) — values stream through onChange. Sliders now track the draft in onChange and request the preview on drag end; harness mirrors the contract
- 2026-09-16T23:55:39Z (quick-edit-recipes): 'crash' root cause: apply's full-size render takes 15-20s (bloom ~9s + blur ~5s at 3440px) with every control disabled by the busy gate and no feedback. Fixed with a progress caption during apply/reset. Also: noise->blur ordering left black blocks at preview scale (magick cache quirk); noise now renders last. Panel height 680 so edit mode never scrolls
- 2026-09-17T14:18:37Z (quick-edit-recipes): Confirmed Apply is killed by the panel-wide 10s deadline; full ImageMagick renders take up to 22s. Adding an Apply-only 30s deadline and native loader feedback.
- 2026-09-17T14:18:51Z (quick-edit-recipes): User approved the bounded regression fix: Apply-only 30s panel deadline plus the native loader during Apply.
- 2026-09-17T14:21:52Z (quick-edit-recipes): parked (waiting on user, review): Open Quick Edit, make a multi-adjustment recipe, and confirm Apply shows a loader and completes within 30 seconds.
- 2026-09-17T15:45:19Z (quick-edit-recipes): Manual verification found two follow-ups: noise is not visibly effective, and slider numeric values need immediate display updates while Apply waits for drag release.
- 2026-09-17T15:47:56Z (quick-edit-recipes): Fixed preview-noise attenuation (noise strength no longer scales with preview dimensions) and immediate slider value redraw; preview still begins only on drag release. Full verification and focused review passed.
- 2026-09-17T15:47:56Z (quick-edit-recipes): parked (waiting on user, review): In Quick Edit, set Noise to a high value and confirm the preview visibly gains grain; drag a slider and confirm its number tracks immediately while the preview changes on release.
