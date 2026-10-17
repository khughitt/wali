---
id: wali-19ab3b
title: Rewrite t@t commit authorship in this repository
status: doing
priority: 2
size: s
complexity: low
process: direct
owner: main
created: 2026-10-16T16:33:20Z
updated: 2026-10-17T01:06:11Z
started: 2026-10-17T01:06:10Z
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
