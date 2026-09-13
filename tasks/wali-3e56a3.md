---
id: wali-3e56a3
title: "Wali panel polish pass 2: borderless buttons, subtle color, drop Refresh"
status: todo
priority: 2
size: s
complexity: mid
created: 2026-09-12T09:35:40Z
updated: 2026-09-13T17:30:47Z
depends: []
tags: [quick-add, noctalia, wallpaper]
source: dots-9bfdc0
---

Second design pass on noctalia/plugins/wali-panel after pass 1 (dots-ba0168). Try the nav buttons without discrete borders: ghost variant or a quieter indication of the pressable area. Explore subtle color or effects beyond Random in primary. Remove the Refresh button: onOpen already refreshes and the button is usually a no-op. Keep the 16:9 frame and the date-and-id caption.

## Accepted suggestions (2026-09-08 review)

- History position hint: walictl current returns history.cursor and history.length; show "65 / 66" or a dot beside Next so it is clear whether Next replays history or samples a fresh photo.
- Palette swatches under the frame: four small dots in primary, secondary, tertiary, and surface so the photo-to-palette relationship is visible (ties to prism and the glass material).
- Move Edit and Copy behind a right-click context menu on the photo (panel.openContextMenu), leaving nav plus heart as the visible chrome. Needs plugin_api 28+; check the installed Noctalia's supported range first (5.0.1 today).
- Click the photo for Random (ui.image accepts onClick), so the Random button can drop to the same weight as its neighbors.

## Notes

- 2026-09-12T09:35:40Z (main): moved from dots-9bfdc0
- 2026-09-12T16:45:57Z (main): Complexity mid: existing panel flow and accepted changes bound the work, but styling choices and installed Noctalia support for context menus remain to be checked; plugin.toml currently declares API 22 while the requested menu needs 28+. Verify interaction behavior with plugin_test.lua and review the rendered panel.
- 2026-09-13T16:33:37Z (main): 2026-09-13 user re-confirmed: drop the Refresh button; it does not seem helpful.
- 2026-09-13T16:50:03Z (panel-scope): Scoped 2026-09-13 (bounded, in-chat design): the photo context menu is infeasible — Noctalia opens context menus only from ui.button onRightClick, never from ui.image or containers. Keep Edit/Copy as ghost buttons. Remaining items: ghost nav buttons, click photo for Random, drop Refresh, history position label, palette swatches.
- 2026-09-13T17:30:47Z (panel-scope): Plan constraints from review: keep the utilityButton helper (remove only Refresh's call), add history {cursor,length} validation to validateCurrent next to historyLabel/nextTooltip, route the photo onClick through startAction's busy guard.
