---
id: wali-732fcd
title: "Library cleanup: EXIF orientation and baked 21:9 crops"
status: doing
priority: 2
process: planned
owner: main
created: 2026-09-24T11:07:35Z
updated: 2026-09-24T11:10:12Z
started: 2026-09-24T11:07:51Z
depends: []
tags: [wallpaper]
agent: claude-code/claude-opus-5-5
---

409 library files carry EXIF orientation Noctalia ignores (95 o3 upside down, 314 o6/o8 portraits sideways); 19 files carry baked 21:9 crops from wali_rotate; 3 were never resized. Closes when ingest orients and stops baking crops, the library-repair tool exists, the plan is reviewed, and it has run on titan with a clean audit.

## Notes

- 2026-09-24T11:07:51Z (main): started
  provenance: {"harness_session":"claude-code:ee572825-2b2d-46cd-8cab-2a294e5249a9","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
