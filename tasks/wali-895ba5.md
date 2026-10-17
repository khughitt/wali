---
id: wali-895ba5
title: "Adopt the test front door: test-fast and test-one recipes"
status: todo
priority: 3
size: s
complexity: low
process: direct
created: 2026-10-17T02:02:03Z
updated: 2026-10-17T02:02:03Z
depends: []
tags: []
agent: claude-code/claude-opus-5-5
---

wali's justfile has test, check and verify but no test-fast or test-one, so the shared workflow (test-one while working, test-fast before committing, recorded through tools/tt) falls back to the full just test. Found during wali-19ab3b. Add test-fast (the pytest, zsh and Lua suites, or a fast subset) and test-one through tools/tt, as the other projects' justfiles do, and name them in AGENTS.md.
