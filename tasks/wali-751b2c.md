---
id: wali-751b2c
title: Nonlinear slider mapping in edit mode (fine control near defaults)
status: idea
priority: 2
reviewed: true
created: 2026-09-16T23:55:39Z
updated: 2026-10-17T13:03:23Z
depends: [wali-ae2aa9]
parent: wali-9a738d
tags: [noctalia]
agent: crush
---

From live review: slider values should map nonlinearly — near the default position, large thumb movements produce small recipe changes, so fine adjustments are easy; less resolution at unlikely extremes (e.g. brightness ±90). Default on, opt-out option. Open design points: curve shape (e.g. cubic/ease-out around the default), where the option lives (walictl config vs plugin state), and how the value label shows the mapped value.

## Notes

- 2026-10-09T11:56:37Z (main): scope: briefed; wali-ae2aa9 settles curves, inverse mapping, rounding and the requested default-on opt-out; preserve recipe semantics and the actual-value label; brief: docs/notes/2026-10-09-noctalia-panel-refinements-brief.md
