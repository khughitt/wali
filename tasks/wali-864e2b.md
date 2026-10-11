---
id: wali-864e2b
title: Determine whether native Noctalia stars can mirror wali favorites safely
status: todo
priority: 3
size: s
complexity: mid
process: direct
created: 2026-10-09T11:56:10Z
updated: 2026-10-11T15:44:20Z
depends: []
parent: wali-9a738d
tags: [noctalia]
source: docs/notes/2026-10-09-noctalia-panel-refinements-brief.md
agent: codex
---

Question: How do the current Noctalia native grid's config-declared favorites, persisted star toggles and config reload interact, and can wali remain the authoritative favorite store?
Where to start: docs/notes/2026-10-09-noctalia-panel-refinements-brief.md; bin/walictl's cmd_favorites, _rating_items and Ratings; docs/noctalia-wallpaper-switcher.md; current upstream documentation and implementation for wallpaper favorites and config/state merging. dots-59c279 is complete; the old [[wallpaper.favorite]] spelling is a hypothesis to verify.
Bound: trace the native favorite contract and, where possible, run one scratch-state add/remove/reload cycle, including a native toggle and a variant path change. Record whether favorites identify photos or display paths. Do not alter live Noctalia config/state or implement a synchronizer.
Expected result: a small behavior table covering precedence, removals, reloads and variant identity, plus a recommendation for one-way mirror, another supported route, or retaining separate native stars. Name how stale native overrides would be handled without losing unrelated entries; update this task and the brief.
Ideas it wakes: on completion, run tasks note on wali-24af13 with the finding, before the result's branch merges.
