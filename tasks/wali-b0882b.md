---
id: wali-b0882b
title: Move wali ingestion functions off WALI_DIR/BACKGROUND_IMG_DIR env vars
status: doing
priority: 2
size: m
complexity: mid
process: direct
owner: wali-b0882b
created: 2026-09-12T09:35:40Z
updated: 2026-10-14T10:40:40Z
started: 2026-10-14T10:31:05Z
depends: []
tags: [wallpaper]
source: dots-5760ef
---

Why: walictl and the shell helpers currently disagree about where the same wallpaper library and archive live. The CLI validates XDG_CONFIG_HOME/wali/config.toml, while wali_ingest, wali_reprocess, wali_search and wali_edit_search still use WALI_DIR/3440 or BACKGROUND_IMG_DIR. Those environment variables can point ingestion and search at a different library.
Done: Add one read-only `walictl config show` command using the existing load_config/config_path and CLI output/error conventions. Its --json output is exactly one object with resolved absolute string wallpaper_dir and string-or-null archive_root; pretty output labels those same two fields. No config writes, wallpaper selection, Noctalia IPC, generic getters, env-var fallback or extra dependencies. Extend the parser, dispatch, help/completion and the walictl rows in tools/cli.toml, following the existing surface tests.
Use one small shared shell reader of that command in all four helpers; decode JSON without eval and preserve quoted path boundaries. Treat wallpaper_dir as the final directory: never append /3440. wali_ingest reads archive_root's existing year/month JPEG layout and fails clearly before prompting or writing when it is absent or not a directory. wali_reprocess retains its explicit source-directory argument and targets the configured wallpaper_dir. Search/edit-search require only wallpaper_dir, so absence of optional archive_root does not disable them. Propagate config/command/decoding failures before any filesystem or favorite/GIMP action. Resolve settings on invocation so a freshly sourced shell does not cache stale paths. Keep WALI_FORMAT, orientation/portrait handling, 3440px rendering, and the other wallpaper backends' behavior.
Update tests/wali.zsh's two env-based ingestion fixtures and add scratch-only checks for all four consumers: unset and deliberately conflicting old vars, a wallpaper_dir with no 3440 suffix, spaces/shell metacharacters in paths, missing/invalid config and missing optional archive_root. Extend tests/test_walictl.py and tests/test_cli_surface.py for the two-field contract, XDG/tilde/symlink expansion, help/completion/output modes and no daemon access. Update docs/noctalia-wallpaper-switcher.md and shell helper usage documentation. Verify through the project's just front door; never run ingestion or reprocessing against live files as a test.
Where to look: bin/walictl (Config, load_config, _expand, COMMANDS, build_parser, main); shell/wali.zsh (the four helpers); tests/wali.zsh, tests/test_walictl.py, tests/test_cli_surface.py and tools/cli.toml. No separate TOML parser is needed.

Original capture (preserved): The walictl runtime reads ~/.config/wali/config.toml, but wali_ingest/wali_reprocess and wali_search/wali_edit_search in shell/wali still read WALI_DIR or BACKGROUND_IMG_DIR. Make these consumers use the same configured wallpaper/archive paths. wali_rotate already reads source_path and path from one walictl current --json payload and needs no further migration. Scope a minimal shared config interface when implementing; do not change the other wallpaper backends incidentally.
Historical correction: 6f09934 removed wali_rotate and the baked-crop modes; the original capture's rotation observation is already superseded.

## Notes

- 2026-09-12T09:35:40Z (main): moved from dots-5760ef
- 2026-10-14T10:24:45Z (main): scope: scoped; checked 4c1ce3a and 6f09934; four env-based callers remain, wali_rotate is removed; settled two-field read-only walictl config show interface and scratch-only checks; P2/m/mid/direct
- 2026-10-14T10:31:05Z (main): started
  provenance: {"harness_session":"codex:01a139f6-7fcf-7b41-95c2-c0279fb2e672","harness_session_source":"CODEX_THREAD_ID"}
- 2026-10-14T10:31:25Z (wali-b0882b): resumed
  provenance: {"harness_session":"codex:01a139f6-7fcf-7b41-95c2-c0279fb2e672","harness_session_source":"CODEX_THREAD_ID"}
- 2026-10-14T10:37:03Z (wali-b0882b): Implemented two-field read-only config show and invocation-time shared JSON reader for all four helpers; scratch tests proved new CLI RED, then CLI GREEN. Shell regression caught a portrait fixture with landscape dimensions; corrected fixture. Ops inventory prerequisite approved by user and delegated; feedback ops-2dfb52 records missing vendored PATH entry.
- 2026-10-14T10:38:16Z (wali-b0882b): Verification before inventory adoption: just verify with test_surface_equals_table deselected passed 257 Python tests, all shell scratch tests and plugin Lua tests; ruff and tasks check clean. Whole-change read-only reviewer dispatched; unfiltered just verify follows ops adoption.
- 2026-10-14T10:40:40Z (wali-b0882b): review: impl round 1 — verdict: accept; findings: none; reviewer: codex
