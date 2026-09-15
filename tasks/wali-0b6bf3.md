---
id: wali-0b6bf3
title: "Task 2: Recipe model and EditsStore"
status: done
priority: 2
size: s
complexity: low
process: planned
owner: quick-edit-recipes
created: 2026-09-13T17:59:09Z
updated: 2026-09-15T10:25:59Z
started: 2026-09-15T09:53:31Z
completed: 2026-09-15T09:57:47Z
depends: [wali-eea384]
parent: wali-608311
tags: [wallpaper]
plan: docs/plans/2026-09-13-quick-edit.md
step: "Task 2: Recipe model and `EditsStore`"
---

## Notes

- 2026-09-15T09:53:47Z (quick-edit-recipes): process=planned: reusing the committed spec and plan, same as Task 1
- 2026-09-15T09:57:47Z (quick-edit-recipes): recipe validation, --set parsing, canonical form, EditsStore
- 2026-09-15T10:25:59Z (quick-edit-recipes): review fixes: import-favorites validates imported ids before saving (a bad stem no longer bricks the favorites file), and EditsStore.load drops all-default recipes so get() returns None — the plan's snippet kept them; code deviates deliberately
