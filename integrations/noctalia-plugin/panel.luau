local Logic = require("./logic.luau")
local Shell = require("./shell.luau")

local state = {
  busy = false, loading = false, keepError = false, errorText = nil, current = nil,
  view = "photo", hiddenList = nil, hoverHide = false, edit = nil,
}

local render
local refresh
local loadHidden

local function trimmed(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function resultError(result, label)
  if result.timedOut then return label .. " timed out" end
  if result.exitCode ~= 0 then
    local stderr = trimmed(result.stderr)
    return stderr ~= "" and stderr or label .. " exited " .. tostring(result.exitCode)
  end
  return nil
end

local function run(argv, callback)
  return noctalia.runAsync(Shell.command(argv), callback, 10000)
end

local function finishCurrent(result)
  state.busy = false
  state.loading = false
  local message = resultError(result, "walictl current")
  local payload
  if not message then payload, message = Logic.decodeCurrent(result.stdout, noctalia.json.decode) end
  if message then
    state.current = nil
    state.errorText = message
  else
    state.current = payload
    if not state.keepError then state.errorText = nil end
  end
  state.keepError = false
  render()
  if state.view == "hidden" then loadHidden() end
end

refresh = function(keepError)
  if not Logic.canStart(state.busy) then return end
  state.busy = true
  state.loading = true
  if not keepError then state.errorText = nil end
  state.keepError = keepError == true
  render()
  if not run(Logic.commandFor("current"), finishCurrent) then
    state.busy = false
    state.loading = false
    state.keepError = false
    state.errorText = "Failed to launch walictl current"
    render()
  end
end

local function finishAction(action, result)
  state.busy = false
  local message = resultError(result, "walictl " .. action)
  if message then
    state.errorText = message
    if action == "hide" then
      refresh(true)
      return
    end
    render()
    return
  end
  state.errorText = nil
  if Logic.refreshAfter(action) then
    refresh()
    return
  end
  if action == "edit" then noctalia.notify("Wali Panel", trimmed(result.stdout)) end
  render()
end

local function startAction(action)
  if not Logic.canStart(state.busy) then return end
  if not state.current and (action == "favorite" or action == "edit" or action == "earlier" or action == "later" or action == "hide") then
    return
  end
  state.busy = true
  state.errorText = nil
  render()
  if not run(Logic.commandFor(action), function(result) finishAction(action, result) end) then
    state.busy = false
    state.errorText = "Failed to launch walictl " .. action
    render()
  end
end

local function copyPath()
  if not state.current then return end
  if noctalia.copyToClipboard(Logic.copyTarget(state.current), "text/plain") then
    state.errorText = nil
  else
    state.errorText = "Failed to copy the wallpaper path"
  end
  render()
end

local function finishHidden(result)
  state.busy = false
  local message = resultError(result, "walictl hidden")
  local items
  if not message then items, message = Logic.decodeHidden(result.stdout, noctalia.json.decode) end
  if message then
    state.hiddenList = {}
    state.errorText = message
  else
    state.hiddenList = items
  end
  render()
end

loadHidden = function()
  if not Logic.canStart(state.busy) then return end
  state.busy = true
  state.hiddenList = nil
  render()
  if not run(Logic.commandFor("hidden"), finishHidden) then
    state.busy = false
    state.hiddenList = {}
    state.errorText = "Failed to launch walictl hidden"
    render()
  end
end

local function openHiddenList()
  -- The view flips only when the load can start; otherwise a busy command
  -- would leave the list view showing a loader that nothing completes.
  if not Logic.canStart(state.busy) then return end
  state.errorText = nil
  state.view = "hidden"
  loadHidden()
end

local function closeHiddenList()
  state.view = "photo"
  state.hiddenList = nil
  render()
end

local function toggleHiddenList()
  if state.view == "hidden" then closeHiddenList() else openHiddenList() end
end

local function startUnhide(photoId)
  if not Logic.canStart(state.busy) then return end
  state.busy = true
  state.errorText = nil
  render()
  local launched = run(Logic.unhideCommand(photoId), function(result)
    state.busy = false
    local message = resultError(result, "walictl unhide")
    if message then
      state.errorText = message
      render()
      return
    end
    -- Always re-read current first: the restored photo may be the displayed
    -- one. finishCurrent reloads the list afterwards when the list is open.
    refresh()
  end)
  if not launched then
    state.busy = false
    state.errorText = "Failed to launch walictl unhide"
    render()
  end
end

local function hideOrRestore()
  if not state.current then return end
  if state.current.hidden then
    startUnhide(state.current.id)
  else
    startAction("hide")
  end
end

function onHiddenMenu(actionId, _context)
  if actionId == "show-hidden" then openHiddenList() end
end

local function onHideHover(hovered, _key)
  state.hoverHide = hovered == "true"
  render()
end

local function openHideMenu()
  panel.openContextMenu({
    items = { { id = "show-hidden", label = "Show hidden…" } },
    onActivate = "onHiddenMenu",
  })
end

local function editRecipe()
  local recipe = {}
  for key, value in pairs(state.edit.recipe) do recipe[key] = value end
  return recipe
end

local requestPreview

local function finishPreview(generation, result)
  state.busy = false
  if state.edit then state.edit.previewing = false end
  if state.edit == nil or state.edit.generation ~= generation then
    render()
    return
  end
  local message = resultError(result, "walictl variant preview")
  local path
  if not message then path, message = Logic.previewPath(result.stdout) end
  if message then
    state.errorText = message
  else
    state.edit.previewPath = path
    state.errorText = nil
  end
  render()
  if state.edit.pending then
    state.edit.pending = false
    requestPreview()
  end
end

requestPreview = function()
  if state.edit == nil then return end
  if not Logic.canStart(state.busy) then
    state.edit.pending = true
    return
  end
  state.busy = true
  state.edit.previewing = true
  local generation = state.edit.generation
  render()
  if not run(Logic.variantCommand("preview", state.edit.id, editRecipe()), function(result)
    finishPreview(generation, result)
  end) then
    state.busy = false
    state.edit.previewing = false
    state.errorText = "Failed to launch walictl variant preview"
    render()
  end
end

local function setRecipeValue(key, value)
  if state.edit == nil or not state.edit.seeded then return end
  state.edit.recipe[key] = value
  requestPreview()
end

local generationCounter = 0

local function enterEdit()
  if not state.current or not Logic.canStart(state.busy) then return end
  generationCounter = generationCounter + 1
  local id = state.current.id
  state.edit = {
    id = id, recipe = {}, generation = generationCounter, previewPath = nil, pending = false,
    seeded = false, previewing = false, edited = false,
  }
  state.busy = true
  state.errorText = nil
  render()
  local launched = run(Logic.variantCommand("show", id), function(result)
    state.busy = false
    if state.edit == nil or state.edit.id ~= id then
      render()
      return
    end
    local message = resultError(result, "walictl variant show")
    local payload
    if not message then payload, message = Logic.decodeVariant(result.stdout, noctalia.json.decode) end
    if message then
      state.edit = nil
      state.errorText = message
    else
      state.edit.recipe = payload.recipe
      state.edit.edited = payload.edited
      state.edit.seeded = true
    end
    render()
  end)
  if not launched then
    state.busy = false
    state.edit = nil
    state.errorText = "Failed to launch walictl variant show"
    render()
  end
end

local function leaveEdit()
  generationCounter = generationCounter + 1
  state.edit = nil
  render()
end

local function toggleEdit()
  if state.edit then leaveEdit() else enterEdit() end
end

local function finishVariantChange(action, result)
  state.busy = false
  local message = resultError(result, "walictl variant " .. action)
  if message then
    state.errorText = message
    render()
    return
  end
  generationCounter = generationCounter + 1
  state.edit = nil
  state.errorText = nil
  refresh()
end

local function applyEdit()
  if state.edit == nil or not state.edit.seeded or not Logic.canStart(state.busy) then return end
  state.busy = true
  render()
  local recipe = editRecipe()
  local launched = run(Logic.variantCommand("apply", state.edit.id, recipe), function(result)
    finishVariantChange("apply", result)
  end)
  if not launched then
    state.busy = false
    state.errorText = "Failed to launch walictl variant apply"
    render()
  end
end

local function resetEdit()
  if state.edit == nil or not state.edit.seeded or not Logic.canStart(state.busy) then return end
  state.busy = true
  render()
  local launched = run(Logic.variantCommand("reset", state.edit.id), function(result)
    finishVariantChange("reset", result)
  end)
  if not launched then
    state.busy = false
    state.errorText = "Failed to launch walictl variant reset"
    render()
  end
end

local frameHeight = 304
local editFrameHeight = 200
local fadeMs = 120

-- View switches fade the frame out, swap at zero opacity, and fade back in.
-- Presses during a fade are ignored so a toggle can never land halfway.
local fade = { active = false, phase = nil, alpha = 1, swap = nil }

local function beginViewFade(swap)
  if fade.active then return end
  fade.active = true
  fade.phase = "out"
  fade.swap = swap
  panel.setNeedsFrameTick(true)
end

function onFrameTick(deltaMs)
  if not fade.active then return end
  local delta = tonumber(deltaMs) or 0
  if fade.phase == "out" then
    fade.alpha = math.max(0, fade.alpha - delta / fadeMs)
    if fade.alpha == 0 then
      fade.swap()
      fade.swap = nil
      fade.phase = "in"
    end
  else
    fade.alpha = math.min(1, fade.alpha + delta / fadeMs)
    if fade.alpha == 1 then
      fade.active = false
      fade.phase = nil
      panel.setNeedsFrameTick(false)
    end
  end
  render()
end

local function resetFade()
  fade.active = false
  fade.phase = nil
  fade.alpha = 1
  fade.swap = nil
  panel.setNeedsFrameTick(false)
end

local function toggleHelp()
  beginViewFade(function()
    state.view = state.view == "help" and "photo" or "help"
  end)
end

local function navButton(key, glyph, tooltip, enabled)
  return ui.button({ key = key, glyph = glyph, glyphSize = 20, variant = "ghost", controlSize = "md",
    width = 56, tooltip = tooltip, enabled = enabled, onClick = function() startAction(key) end })
end

local function utilityButton(key, glyph, tooltip, enabled, onClick, onRightClick, onHover)
  return ui.button({ key = key, glyph = glyph, glyphSize = 16, variant = "ghost", controlSize = "sm",
    tooltip = tooltip, enabled = enabled, onClick = onClick, onRightClick = onRightClick, onHover = onHover })
end

local function hiddenRow(item, enabled)
  return ui.row({ align = "center", gap = 12 }, {
    ui.image({ path = item.path or "", width = 64, height = 40, radius = 6, fit = "cover", visible = item.path ~= nil }),
    ui.column({ gap = 2, flexGrow = 1 }, {
      ui.label({ text = item.display_date or item.date or item.id, fontSize = 14, fontWeight = "medium", maxLines = 1 }),
      ui.label({ text = item.id, fontSize = 11, fontFamily = "monospace", color = "on_surface_variant", maxLines = 1,
        visible = item.display_date ~= nil or item.date ~= nil }),
    }),
    ui.button({ key = "restore:" .. item.id, glyph = "eye", glyphSize = 16, variant = "ghost", controlSize = "sm",
      tooltip = "Restore", enabled = enabled, onClick = function() startUnhide(item.id) end }),
  })
end

local function keyChip(keys)
  return ui.row({ fill = "tertiary/0.12", radius = 5, minWidth = 80, justify = "center", paddingV = 2 }, {
    ui.label({ text = keys, fontFamily = "monospace", fontSize = 12, fontWeight = "medium", color = "tertiary" }),
  })
end

local function helpGroup(title, rows)
  local children = {
    ui.label({ text = title, fontSize = 11, fontWeight = "semibold", color = "on_surface_variant" }),
  }
  for _, row in ipairs(rows) do
    children[#children + 1] = ui.row({ align = "center", gap = 8 }, {
      keyChip(row[1]),
      ui.label({ text = row[2], fontSize = 12, maxLines = 1 }),
    })
  end
  return ui.column({ gap = 6 }, children)
end

local function helpView()
  local navigate = helpGroup("Navigate", {
    { "h / ←", "Previous in history" },
    { "l / →", "Next in history, else sample" },
    { "k / ↑", "Earlier by capture time" },
    { "j / ↓", "Later by capture time" },
    { "r", "Random photo" },
  })
  local act = helpGroup("Act", {
    { "f / space", "Toggle favorite" },
    { "x", "Hide or restore" },
    { "shift+x", "Browse the hidden list" },
    { "e", "Edit in GIMP" },
    { "y", "Copy source path" },
  })
  local panelKeys = helpGroup("Panel", {
    { "? / F1", "Toggle this help" },
    { "esc", "Close the panel" },
  })
  return ui.column({
    height = frameHeight, padding = 18, gap = 10, radius = 14,
    fill = "surface_variant", border = "outline/0.5", borderWidth = 1,
  }, {
    ui.label({ text = "Keyboard shortcuts", fontSize = 20, fontWeight = "semibold" }),
    ui.row({ gap = 20, align = "start" }, {
      navigate,
      ui.column({ gap = 12 }, { act, panelKeys }),
    }),
  })
end

local function hiddenView(enabled)
  local rows = {
    ui.row({ align = "center", gap = 8 }, {
      ui.label({ text = "Hidden photos", fontSize = 20, fontWeight = "semibold" }),
      ui.spacer({ flexGrow = 1 }),
      utilityButton("close-hidden", "x", "Back (shift+x)", true, closeHiddenList),
    }),
  }
  if state.hiddenList == nil then
    rows[#rows + 1] = ui.glyph({ name = "loader", size = 32, color = "on_surface_variant/0.6" })
  elseif #state.hiddenList == 0 and state.errorText ~= nil then
    rows[#rows + 1] = ui.label({ text = state.errorText, fontSize = 13, color = "error" })
  elseif #state.hiddenList == 0 then
    rows[#rows + 1] = ui.label({ text = "Nothing hidden", fontSize = 13, color = "on_surface_variant" })
  else
    local items = {}
    for _, item in ipairs(state.hiddenList) do items[#items + 1] = hiddenRow(item, enabled) end
    rows[#rows + 1] = ui.scroll({ flexGrow = 1, gap = 6 }, items)
  end
  return ui.column({ height = frameHeight, padding = 20, gap = 8, radius = 14, fill = "surface_variant" }, rows)
end

local function frame(enabled)
  if state.edit and state.current then
    return ui.image({
      path = state.edit.previewPath or state.current.path, height = editFrameHeight, radius = 14, fit = "contain",
      border = "outline/0.5", borderWidth = 1,
    })
  end
  if state.view == "hidden" then return hiddenView(enabled) end
  if state.view == "help" then return helpView() end
  if state.current then
    return ui.image({
      path = state.current.path, height = frameHeight, radius = 14, fit = "contain",
      border = "outline/0.5", borderWidth = 1,
      onClick = function() startAction("random") end,
    })
  end
  return ui.column({
    height = frameHeight, radius = 14, fill = "surface_variant",
    border = "outline/0.5", borderWidth = 1, align = "center", justify = "center",
  }, {
    ui.glyph({ name = state.loading and "loader" or "wallpaper", size = 48, color = "on_surface_variant/0.6" }),
  })
end

local function sliderRow(spec, enabled)
  local value = state.edit.recipe[spec.key] or spec.default
  return ui.row({ align = "center", gap = 8 }, {
    ui.label({ text = spec.label, fontSize = 12, width = 78 }),
    ui.slider({ key = "slider:" .. spec.key, min = spec.min, max = spec.max, step = 1, value = value,
      controlSize = "sm", flexGrow = 1, enabled = enabled,
      -- onChange streams the value (as a string) during the drag; onDragEnd
      -- carries no value, it only marks the gesture's end, so the preview
      -- request waits for it.
      onChange = function(newValue)
        local numeric = tonumber(newValue)
        if numeric ~= nil and state.edit and state.edit.seeded then
          state.edit.recipe[spec.key] = math.floor(numeric + 0.5)
        end
      end,
      onDragEnd = function()
        if state.edit and state.edit.seeded then requestPreview() end
      end }),
    ui.label({ text = tostring(value), fontSize = 11, fontFamily = "monospace", width = 36, textAlign = "end" }),
  })
end

local function choiceRow(label, key, choices, enabled)
  local buttons = { ui.label({ text = label, fontSize = 12, width = 78 }) }
  local current = state.edit.recipe[key] or Logic.recipeDefaults[key]
  for _, choice in ipairs(choices) do
    buttons[#buttons + 1] = ui.button({ key = key .. ":" .. tostring(choice), text = tostring(choice), fontSize = 11,
      variant = "ghost", controlSize = "sm", selected = current == choice, enabled = enabled,
      onClick = function() setRecipeValue(key, choice) end })
  end
  return ui.row({ align = "center", gap = 4 }, buttons)
end

local function editControls()
  local edit = state.edit
  local draftEnabled = edit.seeded and (not state.busy or edit.previewing)
  local actionEnabled = edit.seeded and not state.busy
  local rows = {}
  for _, spec in ipairs(Logic.sliders) do rows[#rows + 1] = sliderRow(spec, draftEnabled) end
  rows[#rows + 1] = choiceRow("Rotate", "rotate", Logic.rotations, draftEnabled)
  rows[#rows + 1] = choiceRow("Anchor", "anchor", Logic.anchors, draftEnabled)
  return ui.column({ gap = 10, flexGrow = 1 }, {
    ui.scroll({ flexGrow = 1, gap = 6 }, rows),
    ui.row({ align = "center", gap = 8 }, {
      ui.button({ key = "reset", text = "Reset", variant = "destructive", controlSize = "sm",
        enabled = actionEnabled and edit.edited, tooltip = "Remove the recipe and its renders", onClick = resetEdit }),
      ui.spacer({ flexGrow = 1 }),
      ui.button({ key = "cancel", text = "Cancel", variant = "ghost", controlSize = "sm", enabled = true, onClick = leaveEdit }),
      ui.button({ key = "apply", text = "Apply", variant = "primary", controlSize = "sm",
        enabled = actionEnabled and (not Logic.isDefaultRecipe(edit.recipe) or edit.edited),
        tooltip = "Save the recipe and render it", onClick = applyEdit }),
    }),
  })
end

local function swatch(role)
  return ui.box({ width = 10, height = 10, radius = 5, fill = role, border = "outline/0.5", borderWidth = 1 })
end

local function swatches()
  return ui.row({ align = "center", gap = 4 }, {
    swatch("primary"), swatch("secondary"), swatch("tertiary"),
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
      variant = "ghost", controlSize = "md",
      tooltip = favorite and "Remove favorite (f / space)" or "Favorite (f / space)",
      enabled = enabled and current ~= nil, onClick = function() startAction("favorite") end }),
  })
end

local function actions(current, enabled)
  local loaded = enabled and current ~= nil
  local position = Logic.historyLabel(current)
  return ui.row({ align = "center", gap = 8 }, {
    navButton("previous", "arrow-left", "Previous (h / ←)", enabled),
    navButton("next", "arrow-right", Logic.nextTooltip(current), enabled),
    ui.label({ text = position, fontSize = 11, fontFamily = "monospace",
      color = "on_surface_variant", visible = position ~= "" }),
    navButton("random", "dice", "Random (r) · or click the photo", enabled),
    ui.spacer({ flexGrow = 1 }),
    utilityButton("adjust", "adjustments", "Adjust (a)", loaded, toggleEdit),
    utilityButton("hide", Logic.hideGlyph(current ~= nil and current.hidden, state.hoverHide), Logic.hideTooltip(current ~= nil and current.hidden), loaded, hideOrRestore, openHideMenu, onHideHover),
    utilityButton("edit", "photo-edit", "Edit in GIMP (e)", loaded, function() startAction("edit") end),
    utilityButton("copy", "clipboard", "Copy source path (y)", current ~= nil, copyPath),
    utilityButton("help", "keyboard", "Keyboard shortcuts (? / F1)", true, toggleHelp),
  })
end

render = function()
  local enabled = not state.busy
  local current = state.current
  local frameNode = frame(enabled)
  if fade.alpha < 1 then frameNode.props.opacity = fade.alpha end
  if state.edit and current then
    panel.render(ui.column({ flexGrow = 1, gap = 12, padding = 24 }, {
      frameNode,
      ui.label({ text = Logic.captionDetail(current, state.errorText).text, fontSize = 12, fontFamily = "monospace",
        color = Logic.captionDetail(current, state.errorText).color, maxLines = 2 }),
      editControls(),
    }))
    return
  end
  panel.render(ui.column({ flexGrow = 1, gap = 16, padding = 24 }, {
    frameNode,
    caption(current, enabled),
    actions(current, enabled),
  }))
end

function onOpen(_context)
  state.view = "photo"
  state.hiddenList = nil
  state.hoverHide = false
  generationCounter = generationCounter + 1
  state.edit = nil
  resetFade()
  refresh()
end

local keyActions = {
  h = "previous", Left = "previous", l = "next", Right = "next",
  k = "earlier", Up = "earlier", j = "later", Down = "later",
  r = "random", f = "favorite", space = "favorite", e = "edit",
}

function onKey(chord, pressed)
  if not pressed then return end
  if chord == "a" then
    toggleEdit()
    return
  end
  if state.edit then return end
  if chord == "shift+question" or chord == "F1" then
    toggleHelp()
  elseif chord == "shift+x" then
    toggleHiddenList()
  elseif chord == "x" then
    if state.view == "hidden" then closeHiddenList() elseif state.view == "photo" then hideOrRestore() end
  elseif chord == "y" then
    copyPath()
  elseif keyActions[chord] then
    startAction(keyActions[chord])
  end
end

if _G.WALI_TEST then _G.__wali_state = state end
