---
id: wali-19ab3b
title: Rewrite t@t commit authorship in this repository
status: done
priority: 2
size: s
complexity: low
process: direct
owner: main
created: 2026-10-16T16:33:20Z
updated: 2026-10-17T01:08:12Z
started: 2026-10-17T01:06:10Z
completed: 2026-10-17T01:08:12Z
depends: [ops-e5b39c]
tags: []
source: git-identity-leak-2026-10-07
agent: claude-code/claude-opus-5-5
---

Rewrite this repository's t <t@t> commits (from the 2026-10-07 global-config leak; see ops-5749d9) to Keith Hughitt <keith.hughitt@gmail.com>, following the runbook ops-e5b39c. Inventory on titan 2026-10-16: 39 t@t commits on all refs, 13 unpushed on main, 2 worktree(s); remote: khughitt/wali.

## Notes

- 2026-10-17T01:06:10Z (main): started
  provenance: {"harness_session":"claude-code:c6863573-34c2-470d-b394-259f7cc75503","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-10-17T01:06:10Z (main): Direct history maintenance under ops-e5b39c's pilot procedure (as vdocs-387695). No agent session in wali on Titan or Europa; Europa has only the main checkout. Inventory: 178 commits, 39 t@t, all on main (origin/main reaches 26, pushed); legacy-click-cli (unmerged), wali-7521bb (merged, worktree on Titan WORK_ROOT, locked, clean) and annotated tag v0.1-legacy predate the window and must stay unchanged. No stash, signatures, extra headers, repo-local user.*. Remote khughitt/wali main 5f873eb236908c74701100f9c4c18ec26a7f1ce4 (lease), no remote tags. Steps: bundle --all; mirror; filter-repo --mailmap; byte-verify; citation check in every project; guarded update-ref (refuses a changed tag); attach map; test-fast; push main --force-with-lease.
- 2026-10-17T01:06:29Z (main): attached: 2026-10-16-identity-commit-map.txt (3444 bytes): Authorship rewrite map: 42 changed commit IDs (old new); resolves historical SHA references in task notes and docs without editing them
- 2026-10-17T01:08:12Z (main): done
  provenance: {"harness_session":"claude-code:c6863573-34c2-470d-b394-259f7cc75503","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-10-17T01:08:12Z (main): Rewrote 39 t@t commits to Keith Hughitt (78 identity lines, 42 hashes changed) in one filter-repo pass in a mirror outside Dropbox; verified all 180 commits byte-for-byte (only mapped parents and identities differ; every tree preserved). Swapped main in one guarded update-ref transaction; legacy-click-cli, wali-7521bb and tag v0.1-legacy unchanged (tag object identical). Rewritten SHAs cited anywhere: this task's lease note and an ops push receipt (provenance); map attached (tasks/files/wali-19ab3b/2026-10-16-identity-commit-map.txt). No test-fast recipe; just test and just check green. Pushed main with lease 5f873eb -> 59c7790 (khughitt/wali). A fresh remote mirror, Titan and Europa show 0 t@t; Europa fsck clean. Forced only past ops-e5b39c, whose pilot procedure was followed. Artifacts on Titan at WORK_ROOT/wali/identity-rewrite-20261017T010610Z.
  provenance: {"harness_session":"claude-code:c6863573-34c2-470d-b394-259f7cc75503","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
