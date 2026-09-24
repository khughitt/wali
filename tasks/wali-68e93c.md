---
id: wali-68e93c
title: "Ingest applies EXIF orientation; drop 21:9 crop modes and wali_rotate"
status: done
priority: 2
size: s
complexity: low
process: direct
owner: main
created: 2026-09-24T11:07:35Z
updated: 2026-09-24T11:10:18Z
started: 2026-09-24T11:07:51Z
completed: 2026-09-24T11:10:18Z
depends: []
parent: wali-732fcd
tags: [wallpaper]
model: "claude-opus-5-5[1m]"
agent: claude-code/claude-opus-5-5
---

## Notes

- 2026-09-24T11:07:51Z (main): started
  provenance: {"harness_session":"claude-code:ee572825-2b2d-46cd-8cab-2a294e5249a9","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-24T11:10:12Z (main): ingest measures portrait by displayed size (_wali_oriented_size), writes -auto-orient output; modes upright/rotate; crop, rotate-crop and wali_rotate removed
- 2026-09-24T11:10:18Z (main): done
  provenance: {"harness_session":"claude-code:ee572825-2b2d-46cd-8cab-2a294e5249a9","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-24T11:10:18Z (main): ingest applies EXIF orientation and judges portraits by displayed size; crop modes and wali_rotate removed
  provenance: {"harness_session":"claude-code:ee572825-2b2d-46cd-8cab-2a294e5249a9","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
