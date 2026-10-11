---
id: wali-75ab89
title: Establish an isolated Noctalia panel test route for worktrees
status: todo
priority: 2
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

Question: Can a worktree panel run in an isolated Noctalia configuration/compositor with its own walictl PATH and state, and if not, does a separate development plugin id provide a safe fallback?
Where to start: docs/notes/2026-10-09-noctalia-panel-refinements-brief.md; integrations/noctalia-plugin/plugin.toml, panel.luau, widget.luau and README.md; tests/wali.zsh's production-id assertions; the current Noctalia launch/plugin-discovery documentation.
Bound: inspect supported launch and configuration isolation, then exercise one disposable panel load/reload/unload in a headless or nested session with fake walictl and scratch XDG state. Do not change the installed plugin link, production id, host configuration, wallpaper, or ratings. Seek separate host-use permission if an unavoidable fallback opens live desktop windows. Track and clean up every child process.
Expected result: record a recommended route, exact launch and cleanup commands, how walictl resolves on PATH, and checks that the production link and state remain intact. Verify disposal leaves no dangling development link or child process. Record limits or unavailable tooling rather than declaring the route supported without evidence; update the brief and identify any implementation follow-up.
Ideas it wakes: on completion, run tasks note on wali-ff0d50, wali-3bcef2 and wali-751b2c with the isolation finding, before the result's branch merges.
