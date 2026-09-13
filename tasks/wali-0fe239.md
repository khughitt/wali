---
id: wali-0fe239
title: "Wali panel: downvote/hide button with a reviewable hidden list"
status: done
priority: 2
size: m
complexity: mid
created: 2026-09-13T16:33:37Z
updated: 2026-09-13T20:53:06Z
completed: 2026-09-13T20:53:06Z
depends: []
tags: [noctalia, wallpaper]
spec: docs/specs/2026-09-13-hidden-photos-design.md
plan: docs/plans/2026-09-13-hidden-photos.md
---

Add a button to the wali panel to downvote or hide the current image so it stops being sampled. Hidden images must be recoverable: provide a way to list what has been hidden and remove an entry (walictl subcommand and/or a panel view) so an accidental hide is not permanent. Decide whether this is a rating threshold on the existing per-image ratings or a separate hidden set.

## Notes

- 2026-09-13T16:50:03Z (panel-scope): Scoped 2026-09-13: spec at docs/specs/2026-09-13-hidden-photos-design.md; ratings file v2 with a hidden map, hide/unhide/hidden commands, panel hide button + hidden list view.
- 2026-09-13T20:53:06Z (panel-scope): hidden photos landed on panel-scope: ratings v2 with a hidden set, hide/unhide/hidden commands, sampler and neighbour exclusion, panel hide button, context menu, and hidden list; reviewed on the rendered panel
