---
id: wali-273c6f
title: Design draggable wallpaper positioning from the panel brief
status: todo
priority: 3
size: s
complexity: high
process: planned
created: 2026-10-14T01:00:09Z
updated: 2026-10-14T01:00:09Z
depends: [wali-75ab89]
parent: wali-9a738d
tags: [noctalia]
source: docs/notes/2026-10-13-panel-preview-positioning-brief.md
agent: codex
---

Why: The capture prefers dragging a wallpaper within a screen outline to adding more anchor buttons, and explicitly asks about corner placement. Current recipes allow only center/top/bottom/left/right; this is an extension of completed quick-edit work wali-608311.
Done: Prepare a design spec and implementation plan for separate user reviews, with a visual mockup the user can judge. Establish the supported pointer/drag contract for the declared plugin API, the geometry information the panel needs, and how a draft position is persisted and rendered consistently for preview/full-size/phone output. Compare continuous crop offsets with snapping to edge/corner anchors; lean toward continuous positioning within the existing fill-screen crop, with no zoom or blank borders. Explain that the largest output-aspect crop has spare space on at most one axis, so corner choices can coincide with edge choices. If true two-axis placement would require zoom or letterboxing, surface that scope decision in the design rather than quietly adding it. Define clamping, rotation, differing source/output aspects, unavailable output size, existing recipe interpretation, Apply/Cancel/Reset and a keyboard-accessible equivalent. Preserve originals, pinned edit ids and coalesced previews. Trace the API first; after wali-75ab89, use an isolated prototype only if required by the reviewed plan, never the installed plugin link. Record a blocked feasibility finding rather than inventing unsupported UI capabilities. On completion, update the brief and run `tasks note wali-b07541 --no-reviewed "<reviewed design finding>"` before the branch merges. Implementation of the feature is outside this design task.
Where to look: docs/notes/2026-10-13-panel-preview-positioning-brief.md; integrations/noctalia-plugin/panel.luau (frame, choiceRow, editControls), logic.luau (anchors, recipeKeys, defaults, variant commands), plugin_test.lua; bin/walictl (_check_recipe_value, validate_recipe, parse_settings, crop_box, magick_argv, render_key, phone rendering); tests/test_walictl.py's crop and preview parity checks; docs/specs/2026-09-13-quick-edit-design.md and docs/noctalia-wallpaper-switcher.md. The shipped code is authoritative where the older draft spec disagrees.
