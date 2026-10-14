---
id: wali-b5e7a2
title: Identify the cause of grey panel image previews
status: todo
priority: 2
size: s
complexity: mid
process: direct
created: 2026-10-14T01:00:09Z
updated: 2026-10-14T01:00:09Z
depends: [wali-75ab89]
parent: wali-9a738d
tags: [noctalia]
source: docs/notes/2026-10-13-panel-preview-positioning-brief.md
agent: codex
---

Question: When the panel shows a grey rectangle, is its image path missing/unreadable, its panel state stale, or Noctalia failing to load a valid image? The capture says closing and reopening usually restores the image; it does not identify the affected view.
Where to start: docs/notes/2026-10-13-panel-preview-positioning-brief.md; integrations/noctalia-plugin/panel.luau (frame, refresh/finishCurrent, onOpen, finishPreview), plugin_test.lua's mocked ui.image, and bin/walictl (cmd_variant_preview, prune_previews). Read mindful:thought:07db296e4a1c44e4ada9be93f80e2f05 without changing the stored source.
Bound: After wali-75ab89 establishes isolation, use scratch state and explicit worktree walictl paths. Exercise one source image, one saved variant and one edit preview through open/navigation/help/edit transitions, with at most ten reopen cycles or 30 minutes of reproduction attempts. Record the Noctalia version, affected view, path existence/readability and relevant callback order at a failure and after reopening. If evidence points to Noctalia, search upstream open/closed issues and PRs, default/development branches and changelog before reproducing or patching that upstream defect. No fix implementation, production-link changes, cache clearing on the host or blind retry workaround.
Expected result: Record a reproduction and evidence-backed ownership/root-cause recommendation, or a precise inconclusive result and the evidence still needed, on this task and in the brief. Identify the smallest regression check and fix handoff only if the cause is established. Existing mocked image tests alone cannot verify real image loading. Any unavoidable live desktop capture needs separate host-use permission.
Ideas it wakes: On completion, run `tasks note wali-630361 --no-reviewed "<finding>"`, before this result's branch merges.
