# Wali Panel Pass 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Quiet the Wali Panel's chrome: ghost nav buttons, the photo itself as the Random affordance, no Refresh button, a history position label, and palette swatches.

**Architecture:** All changes live in the Noctalia plugin under `integrations/noctalia-plugin/`. `logic.luau` gains pure helpers (history label, Next tooltip, history validation) that `plugin_test.lua` exercises directly; `panel.luau` consumes them and changes only its rendering functions. `walictl` is untouched: `current --json` already reports `history.cursor` and `history.length`.

**Tech Stack:** Luau (Noctalia 5.1.0 plugin API 22), `lua` for the test file, `just verify`.

**Spec:** No spec file; this is a bounded change. The design is recorded on task `wali-3e56a3` (its body and notes). Task `wali-3e56a3` is the parent of every step below.

## Global Constraints

- `plugin.toml` stays at `plugin_api = 22`; nothing here needs a newer API.
- The photo context menu from the task's accepted list is dropped: Noctalia opens context menus only from a `ui.button`'s `onRightClick`, never from `ui.image` or containers.
- Keep the shared `utilityButton` helper for Edit, Copy, and Help; remove only Refresh's call to it.
- Every wallpaper action, including the photo click, goes through `startAction` so the `busy` guard applies.
- `ui.button` has no `color` prop at API 22; the existing test asserts the favorite button sets none.
- Run all commands from the worktree root `.worktrees/panel-scope/` (paths below are relative to it). `just verify` must pass before each commit.
- `tasks start <step-id>` before a task, `tasks done <step-id> "<what landed>"` in the same commit as its code.

---

### Task 1: History helpers and validation in `logic.luau`

**Files:**
- Modify: `integrations/noctalia-plugin/logic.luau` (`M.validateCurrent`, new `M.historyLabel`, `M.nextSamples`, `M.nextTooltip`)
- Test: `integrations/noctalia-plugin/plugin_test.lua`

**Interfaces:**
- Consumes: the `current --json` payload shape `{ ok, id, path, favorite, date?, display_date?, source_path?, variant_path?, history = { cursor = number|nil, length = number } }`.
- Produces: `Logic.historyLabel(payload) -> string` (`"65/66"` or `""`), `Logic.nextSamples(payload) -> boolean`, `Logic.nextTooltip(payload) -> string`, and `Logic.validateCurrent` rejecting a missing or malformed `history` field. Task 2 renders these.

- [ ] **Step 1: Write the failing tests**

In `plugin_test.lua`, after the line `equal(Logic.captionDetail(nil, "boom"), { text = "boom", color = "error" })`, add:

```lua
equal(Logic.historyLabel(payload), "4/4")
equal(Logic.historyLabel({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 3 } }), "1/3")
equal(Logic.historyLabel({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = nil, length = 0 } }), "")
equal(Logic.historyLabel(nil), "")
assert(Logic.nextSamples(payload), "cursor at the end means Next samples")
assert(not Logic.nextSamples({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 3 } }))
assert(Logic.nextSamples(nil))
equal(Logic.nextTooltip(payload), "Next: sample (l / →)")
equal(Logic.nextTooltip({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 1, length = 3 } }), "Next (l / →)")

local noHistory, noHistoryError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false })
assert(noHistory == nil and noHistoryError:find("history", 1, true), "history must be required")
for _, history in ipairs({ { cursor = "0", length = 1 }, { cursor = 0, length = "1" }, { cursor = 0 }, "3/4" }) do
  local bad, badError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, history = history })
  assert(bad == nil and badError:find("history", 1, true), "malformed history must be rejected")
end
assert(Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = nil, length = 0 } }))
```

The existing loops that build `candidate` tables without `history` now fail on the missing field before reaching the field under test. Update every candidate in `plugin_test.lua` that is expected to pass or to fail on another field so it carries a valid history:

```lua
for _, field in ipairs({ "date", "display_date", "source_path", "variant_path" }) do
  local candidate = { ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 1 } }
  candidate[field] = 42
  invalid, invalidError = Logic.validateCurrent(candidate)
  assert(invalid == nil and type(invalidError) == "string" and invalidError:find(field, 1, true))
end

for _, field in ipairs({ "id", "path" }) do
  local candidate = { ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 1 } }
  candidate[field] = nil
  invalid, invalidError = Logic.validateCurrent(candidate)
  assert(invalid == nil and type(invalidError) == "string" and invalidError:find(field, 1, true))
end
local invalidFavorite, favoriteError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = "yes", history = { cursor = 0, length = 1 } })
assert(invalidFavorite == nil and favoriteError:find("favorite", 1, true))
```

Also give the panel-level fake decoder's `"without source"` payload a history so the panel tests keep passing once validation is stricter:

```lua
      if text == "without source" then
        return { ok = true, id = "n", path = "/wall/next.jpg", favorite = false, history = { cursor = 0, length = 1 } }
      end
```

And the two `captionTitle` fixtures that omit history are fine as they are: `captionTitle` does not validate.

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: an error at the first `Logic.historyLabel` line: `attempt to call a nil value (field 'historyLabel')`.

- [ ] **Step 3: Implement the helpers and validation**

In `logic.luau`, replace `M.validateCurrent` with:

```lua
function M.validateCurrent(payload)
  if type(payload) ~= "table" then return nil, "walictl current did not return an object" end
  if payload.ok ~= true then return nil, "walictl current reported failure" end
  for _, field in ipairs({ "id", "path" }) do
    if type(payload[field]) ~= "string" then return nil, "walictl current returned an invalid " .. field .. " field" end
  end
  if type(payload.favorite) ~= "boolean" then return nil, "walictl current returned an invalid favorite field" end
  for _, field in ipairs({ "date", "display_date", "source_path", "variant_path" }) do
    if payload[field] ~= nil and type(payload[field]) ~= "string" then
      return nil, "walictl current returned an invalid " .. field .. " field"
    end
  end
  local history = payload.history
  if type(history) ~= "table" or type(history.length) ~= "number"
    or (history.cursor ~= nil and type(history.cursor) ~= "number") then
    return nil, "walictl current returned an invalid history field"
  end
  return payload
end
```

Then add, before `return M`:

```lua
function M.historyLabel(payload)
  if payload == nil or payload.history.cursor == nil then return "" end
  return tostring(payload.history.cursor + 1) .. "/" .. tostring(payload.history.length)
end

function M.nextSamples(payload)
  if payload == nil or payload.history.cursor == nil then return true end
  return payload.history.cursor + 1 >= payload.history.length
end

function M.nextTooltip(payload)
  return M.nextSamples(payload) and "Next: sample (l / →)" or "Next (l / →)"
end
```

`historyLabel` and `nextSamples` take a validated payload (or nil), so `payload.history` is a table whenever `payload` is not nil.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: `Wali plugin tests passed`.

- [ ] **Step 5: Verify and commit**

Run: `just verify`
Expected: all green.

```bash
tasks done <step-1-id> "historyLabel, nextSamples, nextTooltip; validateCurrent requires history"
git add integrations/noctalia-plugin/logic.luau integrations/noctalia-plugin/plugin_test.lua tasks
git commit -m "feat(panel): history helpers and validation in logic.luau"
```

---

### Task 2: Panel chrome — ghost nav, photo click, no Refresh, history label, swatches

**Files:**
- Modify: `integrations/noctalia-plugin/panel.luau` (`frame`, `caption`, `navButton`, `actions`)
- Modify: `integrations/noctalia-plugin/README.md` (key table and the "photo-first" paragraph)
- Modify: `docs/noctalia-wallpaper-switcher.md` (the panel paragraph)
- Test: `integrations/noctalia-plugin/plugin_test.lua`

**Interfaces:**
- Consumes: `Logic.historyLabel`, `Logic.nextTooltip` from Task 1; the existing `startAction(action)`, `utilityButton`, `navButton`, and `refresh` in `panel.luau`.
- Produces: the rendered tree that the tests below assert on. No new module-level names.

- [ ] **Step 1: Write the failing panel tests**

In `plugin_test.lua`, the placeholder assertion right after the first `onOpen({})` currently forbids any `ui.box` in the tree. Swatches are boxes, so narrow it to the frame node (the root column's first child):

```lua
onOpen({})
assert(rendered.children[1].type ~= "box", "ui.box cannot hold children; the placeholder frame must be a container")
```

Replace the glyph-only loop that lists `"refresh"` with one that omits it, and assert Refresh is gone:

```lua
for _, key in ipairs({ "previous", "next", "random", "edit", "copy" }) do
  local node = assert(button(rendered, key), key .. " button missing")
  assert(node.props.text == nil, key .. " must be glyph-only")
  assert(type(node.props.tooltip) == "string" and node.props.tooltip ~= "", key .. " needs a tooltip")
end
assert(button(rendered, "refresh") == nil, "Refresh button must be gone")
for _, key in ipairs({ "previous", "next", "random" }) do
  equal(assert(button(rendered, key)).props.variant, "ghost")
end
```

Then, still while `"with source"` metadata is loaded (immediately after the block above and before `favorite.props.onClick()`), add:

```lua
local function labels(node, found)
  found = found or {}
  if node.type == "label" then found[#found + 1] = node.props.text end
  for _, child in ipairs(node.children) do labels(child, found) end
  return found
end
local function boxes(node, found)
  found = found or {}
  if node.type == "box" then found[#found + 1] = node.props.fill end
  for _, child in ipairs(node.children) do boxes(child, found) end
  return found
end
local seen = {}
for _, text in ipairs(labels(rendered)) do seen[text] = true end
assert(seen["4/4"], "history position label missing")
equal(assert(button(rendered, "next")).props.tooltip, "Next: sample (l / →)")
equal(boxes(rendered), { "primary", "secondary", "tertiary", "surface" })

local photo = assert(find(rendered, "image"))
assert(type(photo.props.onClick) == "function", "photo click must sample")
local before = #runs
photo.props.onClick()
equal(#runs, before + 1)
equal(runs[#runs].command, Shell.command(commands.random))
assert(find(rendered, "image").props.onClick ~= nil)
find(rendered, "image").props.onClick()
equal(#runs, before + 1, "photo click bypassed the busy guard")
runs[#runs].callback(success())
runs[#runs].callback(success("with source"))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: failure at `assert(button(rendered, "refresh") == nil, ...)` with `Refresh button must be gone`.

- [ ] **Step 3: Change the panel rendering**

In `panel.luau`:

Give the photo a click handler in `frame()`:

```lua
  if state.current then
    return ui.image({
      path = state.current.path, height = frameHeight, radius = 14, fit = "contain",
      border = "outline/0.5", borderWidth = 1,
      onClick = function() startAction("random") end,
    })
  end
```

Add a swatch helper above `caption` and put the swatches between the text column and the heart:

```lua
local function swatch(role)
  return ui.box({ width = 10, height = 10, radius = 5, fill = role, border = "outline/0.5", borderWidth = 1 })
end

local function swatches()
  return ui.row({ align = "center", gap = 4 }, {
    swatch("primary"), swatch("secondary"), swatch("tertiary"), swatch("surface"),
  })
end

local function caption(current, enabled)
  local favorite = current ~= nil and current.favorite
  local detail = Logic.captionDetail(current, state.errorText)
  return ui.row({ align = "center", gap = 12 }, {
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.row({ align = "center", gap = 8 }, {
        ui.label({ text = Logic.captionTitle(current), fontSize = 20, fontWeight = "semibold", maxLines = 1 }),
        ui.label({ text = "variant", fontSize = 11, fontWeight = "medium", color = "tertiary",
          visible = current ~= nil and current.variant_path ~= nil }),
      }),
      ui.label({ text = detail.text, fontSize = 12, fontFamily = "monospace", color = detail.color, maxLines = 2 }),
    }),
    swatches(),
    ui.button({ key = "favorite", glyph = Logic.favoriteGlyph(favorite), glyphSize = 22,
      selected = favorite == true, variant = "ghost", controlSize = "md",
      tooltip = favorite and "Remove favorite (f)" or "Favorite (f)",
      enabled = enabled and current ~= nil, onClick = function() startAction("favorite") end }),
  })
end
```

Make nav buttons ghost, drop Refresh, and add the history label:

```lua
local function navButton(key, glyph, tooltip, enabled)
  return ui.button({ key = key, glyph = glyph, glyphSize = 20, variant = "ghost", controlSize = "md",
    width = 56, tooltip = tooltip, enabled = enabled, onClick = function() startAction(key) end })
end

local function utilityButton(key, glyph, tooltip, enabled, onClick)
  return ui.button({ key = key, glyph = glyph, glyphSize = 16, variant = "ghost", controlSize = "sm",
    tooltip = tooltip, enabled = enabled, onClick = onClick })
end

local function actions(current, enabled)
  local loaded = enabled and current ~= nil
  return ui.row({ align = "center", gap = 8 }, {
    navButton("previous", "arrow-left", "Previous (h / ←)", enabled),
    navButton("next", "arrow-right", Logic.nextTooltip(current), enabled),
    ui.label({ text = Logic.historyLabel(current), fontSize = 11, fontFamily = "monospace",
      color = "on_surface_variant" }),
    navButton("random", "dice", "Random (r) · or click the photo", enabled),
    ui.spacer({ flexGrow = 1 }),
    utilityButton("edit", "photo-edit", "Edit in GIMP (e)", loaded, function() startAction("edit") end),
    utilityButton("copy", "clipboard", "Copy source path (y)", current ~= nil, copyPath),
    utilityButton("help", "keyboard", "Keyboard shortcuts (? / F1)", true, toggleHelp),
  })
end
```

`refresh` stays defined: `onOpen` and `finishAction` still call it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua integrations/noctalia-plugin/plugin_test.lua`
Expected: `Wali plugin tests passed`.

- [ ] **Step 5: Update the docs**

In `integrations/noctalia-plugin/README.md`, replace the paragraph beginning `The panel is photo-first:` with:

```markdown
The panel is photo-first: the image sits in a bordered frame and clicking it
samples a random photo. The caption shows the capture date and photo id, four
palette swatches (primary, secondary, tertiary, surface) so the photo-to-palette
relationship is visible, and the favorite heart. The action strip has Previous,
Next, and Random as ghost buttons on the left, with a `cursor/length` history
position beside Next (its tooltip says "sample" when Next would leave history),
and Edit, Copy, and keyboard help as quiet ghost buttons on the right. Colors
come from Noctalia's palette, which it derives from the wallpaper.
```

And replace the paragraph beginning `The panel holds no state` with:

```markdown
The panel holds no state and derives nothing from paths. Navigation and Favorite
run a `walictl` command and then re-read `walictl current --json`; opening the
panel re-reads it too. Copy copies the source path when present (otherwise the
current path), and Edit runs without a metadata refresh.
```

In `docs/noctalia-wallpaper-switcher.md`, extend the panel paragraph so the `Super+N` sentence reads:

```markdown
`Super+N` toggles the Wali Panel. Inside it, `h/l` or Left/Right walks history
(the label beside Next shows the position, `cursor/length`); `k/j` or Up/Down
selects the earlier/later photo by capture time. `f` toggles favorite, `e` edits,
`y` copies the source path (display path if no source exists), `r` or a click on
the photo samples, `?` or `F1` toggles help, and Escape closes the panel.
```

- [ ] **Step 6: Verify and commit**

Run: `just verify`
Expected: all green.

```bash
tasks done <step-2-id> "ghost nav, photo click samples, Refresh removed, history label, palette swatches, docs"
git add integrations/noctalia-plugin/panel.luau integrations/noctalia-plugin/plugin_test.lua integrations/noctalia-plugin/README.md docs/noctalia-wallpaper-switcher.md tasks
git commit -m "feat(panel): quieter chrome with photo-click sampling and history position"
```

---

### Task 3: Review the rendered panel

**Files:** none changed by this task unless review asks for it.

**Interfaces:** none.

- [ ] **Step 1: Load the branch into the running Noctalia**

The dotfiles `setup.sh` (`noctalia-plugins` phase) links `~/.config/noctalia/plugins/wali-panel` to `~/d/wali/integrations/noctalia-plugin`, the main checkout, so Noctalia hot-reloads `.luau` files from `main`, not from this worktree. As of 2026-09-13 that link still points at the old dotfiles location and dangles (`ls ~/.config/noctalia/plugins/wali-panel/` fails); step 3 repairs it. To review without merging, point the link at the worktree temporarily:

```bash
ln -sfn "$(pwd)/integrations/noctalia-plugin" ~/.config/noctalia/plugins/wali-panel
noctalia msg plugins disable khughitt/wali-panel && noctalia msg plugins enable khughitt/wali-panel
noctalia msg panel-toggle khughitt/wali-panel:panel
```

- [ ] **Step 2: Park for review**

Check: nav buttons read as pressable without borders; the history label sits beside Next at the right weight; the swatches are legible on light and dark palettes; clicking the photo samples; Refresh is gone. Then:

```bash
tasks park <step-3-id> "Panel loaded from the worktree; judge ghost nav, history label, and swatches on the rendered panel" --waiting-on user --reason review
```

- [ ] **Step 3: After review, restore the link**

Once the branch merges (or review asks for changes and they land), restore the link to the main checkout:

```bash
ln -sfn "$HOME/d/wali/integrations/noctalia-plugin" ~/.config/noctalia/plugins/wali-panel
noctalia msg plugins disable khughitt/wali-panel && noctalia msg plugins enable khughitt/wali-panel
tasks done <step-3-id> "rendered panel reviewed"
```
