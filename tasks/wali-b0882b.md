---
id: wali-b0882b
title: Move wali ingestion functions off WALI_DIR/BACKGROUND_IMG_DIR env vars
status: idea
priority: 2
created: 2026-09-12T09:35:40Z
updated: 2026-09-12T09:35:40Z
depends: []
tags: [wallpaper]
source: dots-5760ef
---

The walictl runtime reads ~/.config/wali/config.toml, but wali_ingest/wali_reprocess and wali_search/wali_edit_search in shell/wali still read WALI_DIR or BACKGROUND_IMG_DIR. Make these consumers use the same configured wallpaper/archive paths. wali_rotate already reads source_path and path from one walictl current --json payload and needs no further migration. Scope a minimal shared config interface when implementing; do not change the other wallpaper backends incidentally.

## Notes

- 2026-09-12T09:35:40Z (main): moved from dots-5760ef
