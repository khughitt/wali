---
id: wali-2f6e26
title: Conform walictl to the shared CLI vocabulary
status: doing
priority: 2
size: s
complexity: low
process: direct
owner: main
created: 2026-09-20T11:30:32Z
updated: 2026-09-20T13:11:12Z
started: 2026-09-20T13:11:12Z
depends: []
tags: [cli, cross-project]
agent: claude-code/claude-opus-5
---

Adopt the shared CLI vocabulary: vendor tools/cli.toml (and tools/cli_surface.py), make the parser conform, add the conformance test. The steps are Task 3 in the ops plan docs/plans/2026-09-20-cli-conventions.md (spec docs/specs/2026-09-20-cli-conventions-design.md). Waits for the ops table task ops-c9ecf0 to land on ops main; the ops step ops-e3b23d tracks this piece.

## Notes

- 2026-09-20T13:11:12Z (main): started
  provenance: {"harness_session":"claude-code:20e55bde-4aed-4a6f-993d-b44b058f509f","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
