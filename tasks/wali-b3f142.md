---
id: wali-b3f142
title: "Panel: grouped key-chip help view with fade, space toggles favorite"
status: done
priority: 2
size: s
complexity: low
process: direct
owner: main
created: 2026-09-15T00:46:29Z
updated: 2026-09-15T01:25:11Z
started: 2026-09-15T00:46:52Z
completed: 2026-09-15T01:25:11Z
depends: []
tags: [noctalia]
agent: crush
---

Help view redesign: two grouped columns (Navigate / Act + Panel) of tertiary-tinted key chips with on_surface_variant section headers, replacing space-padded monospace rows that overflow the 304px frame. No overlay/z-stack exists in the panel UI API, so help keeps replacing the frame; a 120ms opacity fade (out, swap, in) via onFrameTick + panel.setNeedsFrameTick smooths the toggle. Space joins f as a favorite toggle (capture_keys + onKey), seeding 'toggle mark' for the cross-project key vocabulary. Tooltips, README, docs/noctalia-wallpaper-switcher.md, and the tests/wali.zsh capture_keys assertion updated.

## Notes

- 2026-09-15T00:59:22Z (panel-help-polish): landed: grouped key-chip help (Navigate/Act/Panel, tertiary chips) + 120ms out/in frame fade via onFrameTick; space=favorite in capture_keys+onKey; docs+manifest assertion updated; just verify green. Chord name confirmed against noctalia v5.0.1 plugin_panel.cpp: manifest strings arrive verbatim, exact-modifier match.
- 2026-09-15T00:59:22Z (panel-help-polish): parked (waiting on agent, review): review the help view + fade live (noctalia msg plugins disable/enable khughitt/wali-panel to reload the manifest), then commit the worktree
- 2026-09-15T01:25:11Z (panel-help-polish): help regrouped into tinted key chips (Navigate/Act/Panel) fitting the frame; 120ms out/in fade on view swaps; space toggles favorite alongside f
