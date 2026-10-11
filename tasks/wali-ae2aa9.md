---
id: wali-ae2aa9
title: Design fine-control slider mapping from the panel brief
status: todo
priority: 3
size: s
complexity: high
process: planned
created: 2026-10-09T11:56:10Z
updated: 2026-10-11T15:44:20Z
depends: []
parent: wali-9a738d
tags: [noctalia]
source: docs/notes/2026-10-09-noctalia-panel-refinements-brief.md
agent: codex
---

Produce a reviewable design for wali-751b2c from docs/notes/2026-10-09-noctalia-panel-refinements-brief.md. Preserve the source request: nonlinear mapping enabled by default with an opt-out. Settle the curve for centered defaults and endpoint defaults, thumb-to-value and value-to-thumb mappings, integer rounding, existing-recipe round trips, actual-value labels, exact default/endpoints, and where the opt-out is stored.

Where to look: integrations/noctalia-plugin/logic.luau (sliders, recipeDefaults), panel.luau (sliderRow, onChange, onDragEnd), plugin_test.lua (slider and coalesced-preview tests), bin/walictl's recipe limits, and docs/specs/2026-09-13-quick-edit-design.md. The spec header still says draft; current behavior and deb12d9 establish the callback contract.

Lean: panel-only coordinate mapping, with a UI-local opt-out if the host supports it; preserve recipe values/ranges and CLI semantics. Review two labelled candidate curves before choosing; include all seven controls and round-trip checks. Do not implement the panel change. Request permission separately if a later rendered review needs the live desktop.

Done: written design reviewed by the user, followed by a reviewed implementation plan under the normal planned process; record findings in the brief. On completion, run tasks note on wali-751b2c with the settled design and artifact paths, before the result's branch merges.
