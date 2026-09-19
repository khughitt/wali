---
id: wali-8ad74b
title: Design phone wallpaper sync from the brief
status: doing
priority: 2
size: m
complexity: high
process: planned
owner: main
created: 2026-09-19T11:25:22Z
updated: 2026-09-19T12:16:19Z
started: 2026-09-19T12:13:30Z
depends: [wali-0b4022]
parent: wali-51adcc
tags: [wallpaper]
source: docs/notes/2026-09-19-phone-wallpapers-brief.md
agent: claude-code/claude-opus-5
spec: docs/specs/2026-09-19-phone-sync-design.md
---

Settle transport (Dropbox folder mirror vs. rsync to Termux over the tailnet), crop policy (from wali-0b4022), the [phone] config table on the rendering host, and the walictl phone sync mirror semantics (render missing, remove unfavorited/hidden), then a plan. Inputs: the brief (docs/notes/2026-09-19-phone-wallpapers-brief.md), the user's answers to its questions 1-2 (what the phone does with the set; whether its wallpaper source can read a Dropbox offline folder), and whether the quick-edit magick pipeline (wali-e00eb6) is the render path or a minimal magick call ships first.

## Notes

- 2026-09-19T12:03:00Z (main): brief questions 1-2 answered: auto-rotate via a folder-reading wallpaper app (Muzei lean), Dropsync mirror of a Dropbox folder. Transport fixed; design still settles crop policy, [phone] config, and mirror semantics
- 2026-09-19T12:13:30Z (main): started
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:16:19Z (phone-sync): design drafted at docs/specs/2026-09-19-phone-sync-design.md (untracked by policy: git info/exclude); waiting on user review before the plan
