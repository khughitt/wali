---
id: wali-3bbc34
title: Clear ruff findings in bin/walictl
status: done
priority: 3
size: s
complexity: low
owner: main
created: 2026-09-11T23:11:44Z
updated: 2026-09-12T17:20:00Z
started: 2026-09-12T17:03:03Z
completed: 2026-09-12T17:20:00Z
depends: []
tags: [lint]
---

Ruff check exited 1 with 7 findings inherited from dotfiles; it remains outside just check until cleared: DTZ007 at bin/walictl:114; UP017 at bin/walictl:177; I001 at tests/test_walictl.py:1; SIM117 at tests/test_walictl.py:292; DTZ007 at tests/test_walictl.py:306; SIM117 at tests/test_walictl.py:724; RUF015 at tests/test_walictl.py:744. Pyright exited 0 with 0 errors, 0 warnings, and 0 informations.

## Notes

- 2026-09-12T16:45:57Z (main): Complexity low: reproduced all seven listed Ruff findings and read the affected code. Cleanup is localized with established fixes; preserve date-only capture parsing and UTC timestamp semantics. Ruff, existing pytest coverage, and Pyright provide clear checks.
- 2026-09-12T17:20:00Z (main): Cleared all seven Ruff findings in bin/walictl and tests/test_walictl.py and wired ruff check into just check so the gate holds.
