---
id: wali-8ad74b
title: Design phone wallpaper sync from the brief
status: todo
priority: 2
size: m
complexity: high
process: planned
created: 2026-09-19T11:25:22Z
updated: 2026-09-19T11:25:22Z
depends: [wali-0b4022]
parent: wali-51adcc
tags: [wallpaper]
source: docs/notes/2026-09-19-phone-wallpapers-brief.md
agent: claude-code/claude-opus-5
---

Settle transport (Dropbox folder mirror vs. rsync to Termux over the tailnet), crop policy (from wali-0b4022), the [phone] config table on the rendering host, and the walictl phone sync mirror semantics (render missing, remove unfavorited/hidden), then a plan. Inputs: the brief (docs/notes/2026-09-19-phone-wallpapers-brief.md), the user's answers to its questions 1-2 (what the phone does with the set; whether its wallpaper source can read a Dropbox offline folder), and whether the quick-edit magick pipeline (wali-e00eb6) is the render path or a minimal magick call ships first.
