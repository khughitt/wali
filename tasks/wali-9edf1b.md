---
id: wali-9edf1b
title: Script to find gaps in local photo coverage vs. Google Photos
status: dropped
priority: 2
created: 2026-09-13T16:33:37Z
updated: 2026-09-24T14:06:30Z
depends: []
tags: [wallpaper]
---

Build a dataset of every photo in the Google Photos library with its date, starred (favorited) status, and downloaded status (present on the local machine). Compare all vs. starred vs. downloaded to find gaps: days with many photos and zero local, or few stars or few downloads. Follow-up: if Google Takeout can be scripted or accepts a file list, use the gap set to sample photos and download them.

The script lives outside the wali repo: it targets a separate upstream issue and is specific to one library.

## Open questions
- Which project or repository owns it? No registered project covers photos.
- What is the separate upstream issue it targets?
- Where does the full library listing come from (Takeout metadata, the Picker API, other)? Since 2025 the Library API reportedly lists only items the calling app created.

## Notes

- 2026-09-24T13:53:27Z (main): curate: decision; body split into the goal, the stated out-of-repo scope, and open questions on its home, the upstream issue, and the data source; proposal: move it out of wali once a home is named (ops, or a photo-tools repository), or drop it if none is wanted; and lower P2 to P3 while it has no home
- 2026-09-24T14:06:30Z (main): Decided (user): a separate project; 'upstream' meant upstream of wali (retrieve the raw photos before wali consumes them). moved to glean-4c81c5
- 2026-09-24T14:06:30Z (main): dropped
  provenance: {"harness_session":"claude-code:c3b66540-0acc-4861-917d-8c10dfaea3bd","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
- 2026-09-24T14:06:30Z (main): moved to glean-4c81c5 in the new glean project
  provenance: {"harness_session":"claude-code:c3b66540-0acc-4861-917d-8c10dfaea3bd","harness_session_source":"CLAUDE_CODE_SESSION_ID"}
