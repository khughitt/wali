---
id: wali-3bcef2
title: "Wali panel: animate the favorite toggle and add a hover glow"
status: idea
priority: 2
size: s
complexity: mid
created: 2026-09-12T09:35:40Z
updated: 2026-09-24T13:53:27Z
depends: []
tags: [quick-add, noctalia, wallpaper]
source: dots-b9ba7c
---

For fun, after the polish pass (dots-ba0168, done). The heart-only favorite has landed (686450e, 3e48101: a plain heart / heart-filled glyph, no label).

Remaining:
- Favorite click: a short, pretty, colorful, subtle animation for both the on and off transitions (a light sweep or a soft pulse), with slight organic variation so no two clicks look identical.
- The one other small touch (accepted 2026-09-09 on dots-b9ba7c): buttons light up with a subtle glow on hover, a frame-tick fade in and out plus a brief flash on press. No persistent color.

Approach: reuse the help-view fade in integrations/noctalia-plugin/panel.luau (panel.setNeedsFrameTick + onFrameTick, opacity on a node, af0b328). Buttons and rows already expose onHover.

## Open questions
- ui.button has no color prop at API 22 and the existing fade animates only opacity. What carries "colorful": an overlay node behind the heart, the swatch palette, or is opacity or scale enough?
- Sweep or pulse for the favorite toggle?

## Notes

- 2026-09-12T09:35:40Z (main): moved from dots-b9ba7c
- 2026-09-24T13:53:27Z (main): curate: refined; heart-only favorite already landed (686450e, 3e48101), retitled to the remaining click animation and hover glow, restored the hover-glow decision the move from dots-b9ba7c dropped, named the reusable frame-tick fade and the no-color-prop limit as an open question; size s, complexity mid; process left unassessed while the taste questions stand
