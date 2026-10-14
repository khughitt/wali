Supplemental review complete. Reviewer identity: **codex**; exact model identity remains unverifiable.

**Strengths:** Both `.worktrees/wali-b0882b/tools/cli.toml` and `.worktrees/wali-b0882b/tools/cli_surface.py` match the approved ops commit `6b007593911549afa031dc7eaeb6308f733f1529` byte-for-byte. The walictl inventory matches the live parser exactly, including both new config rows. The helper changes are provenance comments only. The documentation relocation preserves the existing discussion’s structure.

**Critical / Important / Minor findings:** None. Prior whole-change findings remain unchanged: none.

**Declined to judge:** Other CLIs’ accumulated inventory changes beyond confirming approved-source identity; their behavior belongs to their owning projects. I did not rerun the full suite—the controller reports unfiltered `just verify` passing 260 Python tests, shell and plugin tests, and clean ruff/task checks.

**Assessment: Yes.** No corrective changes required. `git diff --check` also passed.

Skipped duplicate suite execution and live desktop checks. No new material risk identified; this supplemental review made no mutations.

Ruling: Accept. Other CLI inventories are canonical approved-source copies and do not affect wali execution. No minor (deferred) findings.
