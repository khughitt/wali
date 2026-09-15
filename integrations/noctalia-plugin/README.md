# Wali Panel

A native Noctalia v5 plugin for previewing and managing Wali's current wallpaper.

## Entries

- Plugin API: `28`
- Widget: `khughitt/wali-panel:widget`
- Panel: `khughitt/wali-panel:panel`

Add the widget to a Noctalia bar and click its wallpaper glyph, or open the panel with:

```sh
noctalia msg panel-toggle khughitt/wali-panel:panel
```

In niri, `Super+N` toggles the panel and gives it keyboard focus immediately.

| Key | Action |
|---|---|
| `h` / Left | Previous in history |
| `l` / Right | Next in history, or sample at the end |
| `k` / Up | Earlier photo by capture time |
| `j` / Down | Later photo by capture time |
| `r` | Random photo (clicking the photo also samples) |
| `f` / Space | Toggle favorite |
| `x` | Hide the photo (never sampled again); restore it when it is already hidden |
| `shift+x` | Toggle the hidden list in the preview area |
| `e` | Edit in GIMP |
| `y` | Copy source path, or display path if unavailable |
| `?` / `F1` | Toggle shortcut help in the preview area |
| Escape | Close panel |

Capture-time navigation uses `walictl earlier`/`later`, the same ordering as
`neighbors`, and records the selection in history. It stops at the library
boundaries. Actions run once per press; while a command is busy, additional
wallpaper actions are ignored. The keyboard button also opens help, which
groups the bindings as tinted key chips and fades the preview out and back in
while it swaps.

Noctalia 5.0.1 can keep `?` held if Shift is released before the question-mark
key. Use `F1` or the keyboard button if that happens; closing the panel resets
the captured keys. This is in the
[host's release handling](https://github.com/noctalia-dev/noctalia/blob/v5.0.1/src/shell/panel/plugin_panel.cpp#L85).

Global niri controls work with the panel closed: `Super+Alt+Left/Right` for
history, `Super+Alt+R` for random, and `Super+Alt+F` for favorite, with a short
notification showing the result or error. These require `notify-send`.

## Requirements

- `walictl` on `PATH`, configured through `$XDG_CONFIG_HOME/wali/config.toml`.
- GIMP for the Edit button.

The panel is photo-first: the image sits in a bordered frame and clicking it
samples a random photo. The caption shows the capture date and photo id, three
palette swatches (primary, secondary, tertiary) so the photo-to-palette
relationship is visible, and the favorite heart. The action strip has Previous,
Next, and Random as ghost buttons on the left, with a `cursor/length` history
position beside Next (its tooltip says "sample" when Next would leave history),
and Hide, Edit, Copy, and keyboard help as quiet ghost buttons on the right. Colors
come from Noctalia's palette, which it derives from the wallpaper.

Hide (`eye`, turning into `eye-off` on hover to preview the action) sits with
the other quiet buttons. A click runs `walictl hide`,
which records the hide and samples a replacement; the panel re-reads the
metadata whether or not the replacement succeeded, so a failure ("every photo
is hidden") stays in the caption. Right-click the button, or press `shift+x`,
for the hidden list: a scrolling set of thumbnails with a Restore button each.
A photo reached through history that is hidden shows `hidden` in the caption
and turns the button into Restore.

Noctalia hot-reloads the `.luau` files. A change to `plugin.toml` (for example the
panel size) needs `noctalia msg plugins disable khughitt/wali-panel` followed by
`enable`.

The panel holds no state and derives nothing from paths. Navigation and Favorite
run a `walictl` command and then re-read `walictl current --json`; opening the
panel re-reads it too. Copy copies the source path when present (otherwise the
current path), and Edit runs without a metadata refresh.
