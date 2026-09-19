---
id: wali-8ad74b
title: Design phone wallpaper sync from the brief
status: done
priority: 2
size: m
complexity: high
process: planned
owner: phone-sync
created: 2026-09-19T11:25:22Z
updated: 2026-09-19T17:16:05Z
started: 2026-09-19T12:13:30Z
completed: 2026-09-19T17:16:05Z
depends: [wali-0b4022]
parent: wali-51adcc
tags: [wallpaper]
source: docs/notes/2026-09-19-phone-wallpapers-brief.md
agent: claude-code/claude-opus-5
spec: docs/specs/2026-09-19-phone-sync-design.md
plan: docs/plans/2026-09-19-phone-sync.md
---

Settle transport (Dropbox folder mirror vs. rsync to Termux over the tailnet), crop policy (from wali-0b4022), the [phone] config table on the rendering host, and the walictl phone sync mirror semantics (render missing, remove unfavorited/hidden), then a plan. Inputs: the brief (docs/notes/2026-09-19-phone-wallpapers-brief.md), the user's answers to its questions 1-2 (what the phone does with the set; whether its wallpaper source can read a Dropbox offline folder), and whether the quick-edit magick pipeline (wali-e00eb6) is the render path or a minimal magick call ships first.

## Notes

- 2026-09-19T12:03:00Z (main): brief questions 1-2 answered: auto-rotate via a folder-reading wallpaper app (Muzei lean), Dropsync mirror of a Dropbox folder. Transport fixed; design still settles crop policy, [phone] config, and mirror semantics
- 2026-09-19T12:13:30Z (main): started
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:16:19Z (phone-sync): design drafted at docs/specs/2026-09-19-phone-sync-design.md (untracked by policy: git info/exclude); waiting on user review before the plan
- 2026-09-19T12:16:19Z (phone-sync): parked (waiting on user, review): review the design spec; on approval, invoke writing-plans for the implementation plan
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:30:56Z (phone-sync): resumed
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:30:56Z (phone-sync): review round 1: 4 findings taken — ratings file must exist (missing ≠ empty), a state-dir manifest records source identity + output (fallback→original and output changes re-render), dotfiles wiring is an explicit dots piece (per-unit ln_s, titan-only enable), .nomedia created in the Dropbox folder since download mirror deletes device-only files
- 2026-09-19T12:30:56Z (phone-sync): parked (waiting on user, review): re-review the revised spec; on approval, writing-plans
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:35:49Z (phone-sync): resumed
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:35:49Z (phone-sync): review round 2: spec approved for planning with two clarifications applied — ratings must fail on the read itself (Ratings.load required=True, no exists() pre-check); manifest guarantee is recovery on mismatch, not atomicity, with interruption tests between the two writes
- 2026-09-19T12:42:33Z (phone-sync): plan drafted at docs/plans/2026-09-19-phone-sync.md (untracked by policy), six step children wali-59e9ad→756c72→3f1e03→7f84a5→2f951f→4e5921 chained by dep; dots-edcbef holds the dotfiles wiring and gates the goal and Task 6
- 2026-09-19T12:42:33Z (phone-sync): parked (waiting on user, review): review the implementation plan; on approval, execute Tasks 1-5 in .worktrees/phone-sync (subagent-driven), then Task 6 on titan
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:48:16Z (phone-sync): resumed
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:48:16Z (phone-sync): plan review round 1: 5 findings taken — Task 6 no longer touches ~/bin/walictl (it and dotfiles bin/walictl are the quick-edit review shim today) and enables the timer only after the serving checkout has phone; dotfiles excluded from both scans; temporaries are <id>.jpg.tmp written as jpg:<path> so no id can collide; dry-run validates dir type; manifest load also survives invalid UTF-8. Spec updated to match
- 2026-09-19T12:48:16Z (phone-sync): parked (waiting on user, review): re-review the revised plan; on approval execute Tasks 1-5 in .worktrees/phone-sync
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:56:13Z (phone-sync): resumed
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T12:56:13Z (phone-sync): plan review round 2: temporary is target.stem + .jpg.tmp (name+suffix doubled .jpg); timer activation now requires dots-edcbef landed, setup.sh --only systemd to create the links, and ~/bin/walictl itself passing phone sync --dry-run with no substitute path
- 2026-09-19T12:56:13Z (phone-sync): parked (waiting on user, review): re-review the plan's Task 3 tmp naming and Task 6 activation; on approval execute Tasks 1-5 in .worktrees/phone-sync
  provenance: {"harness_session":"claude-code:fa1ebf0a-db9b-4904-8ab3-9cdbaae58690","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T13:06:19Z (phone-sync): resumed
  provenance: {"harness_session":"claude-code:f80a968e-fd50-4a48-8930-8977cd5cb9f0","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T13:06:19Z (phone-sync): plan approved; executing Tasks 1-5 in .worktrees/phone-sync
- 2026-09-19T13:20:34Z (phone-sync): Tasks 1-5 committed on phone-sync (24332ff..07d3c44); dots-edcbef merged into dotfiles main (94b53b2); first titan sync running via the worktree executable
- 2026-09-19T17:16:05Z (main): done
  provenance: {"harness_session":"claude-code:f80a968e-fd50-4a48-8930-8977cd5cb9f0","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-19T17:16:05Z (main): design, plan, and six steps landed: walictl phone sync merged (dfb5f2f), timer live on titan
  provenance: {"harness_session":"claude-code:f80a968e-fd50-4a48-8930-8977cd5cb9f0","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
