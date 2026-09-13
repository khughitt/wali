local here = (arg[0]:match("(.*/)") or "")
local Shell = dofile(here .. "shell.luau")
local Logic = dofile(here .. "logic.luau")

local function equal(actual, expected, message)
  if type(actual) ~= type(expected) then
    error(message or ("expected " .. type(expected) .. ", got " .. type(actual)))
  end
  if type(actual) ~= "table" then
    assert(actual == expected, message or ("expected " .. tostring(expected) .. ", got " .. tostring(actual)))
    return
  end
  for key, value in pairs(expected) do equal(actual[key], value, message) end
  for key in pairs(actual) do assert(expected[key] ~= nil, message or "unexpected key") end
end

local commands = {
  current = { "walictl", "current", "--json" },
  previous = { "walictl", "previous" },
  next = { "walictl", "next" },
  random = { "walictl", "random" },
  favorite = { "walictl", "favorite" },
  edit = { "walictl", "edit" },
  hide = { "walictl", "hide" },
  hidden = { "walictl", "hidden", "--json" },
}

for action, expected in pairs(commands) do equal(Logic.commandFor(action), expected) end
equal(Shell.command({ "walictl", "save-current", "/wall papers/a'b.jpg" }),
  "'walictl' 'save-current' '/wall papers/a'\"'\"'b.jpg'")

local payload = {
  ok = true,
  id = "PXL_20260820_000000000",
  date = "2026-08-20",
  display_date = "August 20, 2026",
  path = "/wall/current.jpg",
  source_path = "/wall/source.jpg",
  variant_path = nil,
  favorite = true,
  hidden = false,
  history = { cursor = 3, length = 4 },
}
equal(Logic.decodeCurrent("valid", function(text)
  assert(text == "valid")
  return payload
end), payload)

local decoded, decodeError = Logic.decodeCurrent("invalid", function() error("invalid JSON") end)
assert(decoded == nil and type(decodeError) == "string" and decodeError:find("invalid JSON", 1, true))

local invalid, invalidError = Logic.validateCurrent({ source_path = "/wall/source.jpg" })
assert(invalid == nil and type(invalidError) == "string")

for _, field in ipairs({ "date", "display_date", "source_path", "variant_path" }) do
  local candidate = { ok = true, id = "x", path = "/p", favorite = false, hidden = false, history = { cursor = 0, length = 1 } }
  candidate[field] = 42
  invalid, invalidError = Logic.validateCurrent(candidate)
  assert(invalid == nil and type(invalidError) == "string" and invalidError:find(field, 1, true))
end

for _, field in ipairs({ "id", "path" }) do
  local candidate = { ok = true, id = "x", path = "/p", favorite = false, hidden = false, history = { cursor = 0, length = 1 } }
  candidate[field] = nil
  invalid, invalidError = Logic.validateCurrent(candidate)
  assert(invalid == nil and type(invalidError) == "string" and invalidError:find(field, 1, true))
end
local invalidFavorite, favoriteError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = "yes", hidden = false, history = { cursor = 0, length = 1 } })
assert(invalidFavorite == nil and favoriteError:find("favorite", 1, true))

for _, action in ipairs({ "previous", "next", "random", "favorite" }) do
  assert(Logic.refreshAfter(action), action .. " must refresh current wallpaper metadata")
end
assert(not Logic.refreshAfter("current"))
assert(not Logic.refreshAfter("edit"))
assert(Logic.canStart(false))
assert(not Logic.canStart(true))
equal(Logic.copyTarget({ path = "/p", source_path = "/s" }), "/s")
equal(Logic.copyTarget({ path = "/p" }), "/p")
equal(Logic.favoriteGlyph(true), "heart-filled")
equal(Logic.favoriteGlyph(false), "heart")
equal(Logic.captionTitle(payload), "August 20, 2026")
equal(Logic.captionTitle({ ok = true, id = "x", path = "/p", favorite = false, date = "2026-08-20" }), "2026-08-20")
equal(Logic.captionTitle({ ok = true, id = "x", path = "/p", favorite = false }), "x")
equal(Logic.captionTitle(nil), "")
equal(Logic.captionDetail(payload, nil), { text = "PXL_20260820_000000000", color = "on_surface_variant" })
equal(Logic.captionDetail(payload, "walictl next exited 1"), { text = "walictl next exited 1", color = "error" })
equal(Logic.captionDetail(nil, nil), { text = "", color = "on_surface_variant" })
equal(Logic.captionDetail(nil, "boom"), { text = "boom", color = "error" })
equal(Logic.captionDetail({ ok = true, id = "x", path = "/p", favorite = false, hidden = true, history = { cursor = 0, length = 1 } }, nil), { text = "x · hidden", color = "tertiary" })

equal(Logic.historyLabel(payload), "4/4")
equal(Logic.historyLabel({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 3 } }), "1/3")
equal(Logic.historyLabel({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = nil, length = 0 } }), "")
equal(Logic.historyLabel(nil), "")
assert(Logic.nextSamples(payload), "cursor at the end means Next samples")
assert(not Logic.nextSamples({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 3 } }))
assert(Logic.nextSamples(nil))
equal(Logic.nextTooltip(payload), "Next: sample (l / →)")
equal(Logic.nextTooltip({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 1, length = 3 } }), "Next (l / →)")

equal(Logic.unhideCommand("PXL_1"), { "walictl", "unhide", "PXL_1" })
assert(Logic.refreshAfter("hide"), "hide must refresh current metadata")
local noHidden, noHiddenError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, history = { cursor = 0, length = 1 } })
assert(noHidden == nil and noHiddenError:find("hidden", 1, true), "hidden must be required")
local badHidden, badHiddenError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, hidden = "no", history = { cursor = 0, length = 1 } })
assert(badHidden == nil and badHiddenError:find("hidden", 1, true))
equal(Logic.hideGlyph(false), "eye-off")
equal(Logic.hideGlyph(true), "eye")
equal(Logic.hideTooltip(false), "Hide (x) · right-click: hidden list")
equal(Logic.hideTooltip(true), "Restore (x)")

local hiddenItems = {
  { id = "PXL_20260101_000000000", added = "T", date = "2026-01-01", display_date = "January 1, 2026",
    path = "/wall/a.jpg", source_path = nil, exists = true },
  { id = "gone", added = "T", date = nil, display_date = nil, path = nil, source_path = nil, exists = false },
}
equal(Logic.decodeHidden("list", function(text)
  assert(text == "list")
  return { ok = true, hidden = hiddenItems }
end), hiddenItems)
local badList, badListError = Logic.decodeHidden("x", function() return { ok = true, hidden = "nope" } end)
assert(badList == nil and badListError:find("hidden", 1, true))
badList, badListError = Logic.decodeHidden("x", function() return { ok = true, hidden = { { id = 5 } } } end)
assert(badList == nil and badListError:find("id", 1, true))
badList, badListError = Logic.decodeHidden("x", function() return { ok = false } end)
assert(badList == nil and badListError:find("failure", 1, true))
badList, badListError = Logic.decodeHidden("x", function() error("invalid JSON") end)
assert(badList == nil and badListError:find("invalid JSON", 1, true))

local noHistory, noHistoryError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, hidden = false })
assert(noHistory == nil and noHistoryError:find("history", 1, true), "history must be required")
for _, history in ipairs({ { cursor = "0", length = 1 }, { cursor = 0, length = "1" }, { cursor = 0 }, "3/4" }) do
  local bad, badError = Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, hidden = false, history = history })
  assert(bad == nil and badError:find("history", 1, true), "malformed history must be rejected")
end
assert(Logic.validateCurrent({ ok = true, id = "x", path = "/p", favorite = false, hidden = false, history = { cursor = nil, length = 0 } }))

local rendered
local runs = {}
local clipboardCalls = {}
local toggledPanel
local widgetGlyph

noctalia = {
  copyToClipboard = function(text, mimeType)
    clipboardCalls[#clipboardCalls + 1] = { text, mimeType }
    return true
  end,
  json = {
    decode = function(text)
      if text == "with source" then return payload end
      if text == "without source" then
        return { ok = true, id = "n", path = "/wall/next.jpg", favorite = false, hidden = false, history = { cursor = 0, length = 1 } }
      end
      if text == "hidden list" then
        return { ok = true, hidden = {
          { id = "PXL_20260101_000000000", added = "T", date = "2026-01-01", display_date = "January 1, 2026",
            path = "/wall/a.jpg", exists = true },
          { id = "gone", added = "T", exists = false },
        } }
      end
      if text == "empty list" then return { ok = true, hidden = {} } end
      return nil, "invalid JSON"
    end,
  },
  notify = function() end,
  runAsync = function(command, callback, timeout)
    runs[#runs + 1] = { command = command, callback = callback, timeout = timeout }
    return true
  end,
  togglePanel = function(id) toggledPanel = id end,
}

barWidget = {
  setGlyph = function(glyph) widgetGlyph = glyph end,
  setTooltip = function() end,
}
dofile(here .. "widget.luau")
equal(widgetGlyph, "wallpaper")
onClick()
equal(toggledPanel, "khughitt/wali-panel:panel")

local menuRequests = {}
panel = {
  render = function(tree) rendered = tree end,
  openContextMenu = function(request)
    menuRequests[#menuRequests + 1] = request
    return true
  end,
}
ui = {}
for _, name in ipairs({ "box", "button", "column", "glyph", "image", "label", "row", "scroll", "spacer" }) do
  local nodeType = name
  ui[nodeType] = function(props, children)
    return { type = nodeType, props = props or {}, children = children or {} }
  end
end

local realRequire = require
require = function(path)
  if path == "./logic.luau" then return dofile(here .. "logic.luau") end
  if path == "./shell.luau" then return dofile(here .. "shell.luau") end
  return realRequire(path)
end
dofile(here .. "panel.luau")
require = realRequire

local function button(node, key)
  if node.type == "button" and node.props.key == key then return node end
  for _, child in ipairs(node.children) do
    local found = button(child, key)
    if found then return found end
  end
  return nil
end

local function success(stdout)
  return { exitCode = 0, stdout = stdout or "", stderr = "", timedOut = false }
end

local function find(node, nodeType)
  if node.type == nodeType then return node end
  for _, child in ipairs(node.children) do
    local found = find(child, nodeType)
    if found then return found end
  end
  return nil
end

local function labelNode(node, predicate)
  if node.type == "label" and predicate(node.props) then return node end
  for _, child in ipairs(node.children) do
    local found = labelNode(child, predicate)
    if found then return found end
  end
  return nil
end

onOpen({})
assert(rendered.children[1].type ~= "box", "ui.box cannot hold children; the placeholder frame must be a container")
local placeholderGlyph = assert(find(rendered, "glyph"), "placeholder frame lost its glyph")
equal(placeholderGlyph.props.name, "loader")
equal(#runs, 1)
equal(runs[1].command, Shell.command(commands.current))
equal(runs[1].timeout, 10000)

local historyLabelNode = assert(labelNode(rendered, function(props) return props.text == "" and props.fontFamily == "monospace" and props.visible == false end), "history label not found before metadata loads")

runs[1].callback(success("with source"))

local historyLabelAfter = assert(labelNode(rendered, function(props) return (props.text == "4/4" or props.text == "") and props.fontFamily == "monospace" and props.visible ~= nil end), "history label not found after metadata loads")
assert(historyLabelAfter.props.visible == true, "history label must be visible when loaded")

local copy = assert(button(rendered, "copy"))
assert(copy.props.enabled)
copy.props.onClick()
equal(clipboardCalls, { { "/wall/source.jpg", "text/plain" } })

assert(button(rendered, "previous")).props.onClick()
equal(#runs, 2)
equal(runs[2].command, Shell.command(commands.previous))
local nextWhileBusy = assert(button(rendered, "next"))
assert(not nextWhileBusy.props.enabled)
nextWhileBusy.props.onClick()
equal(#runs, 2, "a second action started while the first was busy")

runs[2].callback(success())
equal(#runs, 3, "successful navigation did not refresh current metadata")
equal(runs[3].command, Shell.command(commands.current))
runs[3].callback(success("without source"))

local copyWithoutSource = assert(button(rendered, "copy"))
assert(copyWithoutSource.props.enabled)
copyWithoutSource.props.onClick()
equal(clipboardCalls, {
  { "/wall/source.jpg", "text/plain" },
  { "/wall/next.jpg", "text/plain" },
})

runs[3].callback(success("with source"))
local favorite = assert(button(rendered, "favorite"))
equal(favorite.props.glyph, "heart-filled")
equal(favorite.props.selected, true)
assert(favorite.props.color == nil, "ui.button has no color prop; the host ignores it")
assert(favorite.props.text == nil, "favorite must be glyph-only")
for _, key in ipairs({ "previous", "next", "random", "edit", "copy", "hide" }) do
  local node = assert(button(rendered, key), key .. " button missing")
  assert(node.props.text == nil, key .. " must be glyph-only")
  assert(type(node.props.tooltip) == "string" and node.props.tooltip ~= "", key .. " needs a tooltip")
end
assert(button(rendered, "refresh") == nil, "Refresh button must be gone")
for _, key in ipairs({ "previous", "next", "random" }) do
  equal(assert(button(rendered, key)).props.variant, "ghost")
end

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
equal(boxes(rendered), { "primary", "secondary", "tertiary" })

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

favorite.props.onClick()
equal(runs[#runs].command, Shell.command(commands.favorite))
runs[#runs].callback(success("favorited PXL_20260820_000000000"))
equal(runs[#runs].command, Shell.command(commands.current), "favorite did not refresh metadata")
runs[#runs].callback(success("without source"))
local unfavorited = assert(button(rendered, "favorite"))
equal(unfavorited.props.glyph, "heart")
equal(unfavorited.props.selected, false)

assert(type(onKey) == "function", "panel must handle captured keys")
for _, binding in ipairs({
  { "h", "previous" }, { "Left", "previous" }, { "l", "next" }, { "Right", "next" },
  { "k", "earlier" }, { "Up", "earlier" }, { "j", "later" }, { "Down", "later" },
  { "r", "random" }, { "f", "favorite" }, { "e", "edit" },
}) do
  local count = #runs
  onKey(binding[1], false)
  equal(#runs, count, "release must not act")
  onKey(binding[1], true)
  equal(#runs, count + 1)
  equal(runs[#runs].command, "'walictl' '" .. binding[2] .. "'")
  onKey("r", true)
  equal(#runs, count + 1, "keyboard action bypassed the busy guard")
  runs[#runs].callback(success())
  if binding[2] ~= "edit" then
    equal(runs[#runs].command, "'walictl' 'current' '--json'")
    runs[#runs].callback(success("with source"))
  end
end

local count = #clipboardCalls
onKey("y", true)
equal(clipboardCalls[count + 1], { "/wall/source.jpg", "text/plain" })
local runCount = #runs
onKey("unknown", true)
equal(#runs, runCount)
onKey("shift+question", true)
assert(find(rendered, "image") == nil, "help must replace the preview")
onKey("shift+question", false)
assert(find(rendered, "image") == nil, "release must leave help open")
onKey("shift+question", true)
assert(find(rendered, "image") ~= nil, "help must toggle back to the preview")
onKey("F1", true)
assert(find(rendered, "image") == nil, "unshifted help key must open help")
onKey("F1", false)
assert(find(rendered, "image") == nil)
onKey("F1", true)
assert(find(rendered, "image") ~= nil)
assert(button(rendered, "help")).props.onClick()
assert(find(rendered, "image") == nil)
onOpen({})
runs[#runs].callback(success("with source"))
assert(find(rendered, "image") ~= nil, "opening must reset help")

onKey("l", true)
runs[#runs].callback({ exitCode = 1, stdout = "", stderr = "navigation failed", timedOut = false })
assert(button(rendered, "next")).props.onClick()
equal(runs[#runs].command, "'walictl' 'next'", "failure must release the busy guard")
runs[#runs].callback(success())
runs[#runs].callback(success("invalid current"))
runCount = #runs
count = #clipboardCalls
for _, chord in ipairs({ "f", "e", "y", "j", "k" }) do onKey(chord, true) end
equal(#runs, runCount, "photo actions require loaded metadata")
equal(#clipboardCalls, count)

-- hide: left-click hides and refreshes even when the command fails
onOpen({})
runs[#runs].callback(success("with source"))
local hide = assert(button(rendered, "hide"), "hide button missing")
equal(hide.props.glyph, "eye-off")
equal(hide.props.tooltip, "Hide (x) · right-click: hidden list")
hide.props.onClick()
equal(runs[#runs].command, Shell.command(commands.hide))
runs[#runs].callback({ exitCode = 1, stdout = "hidden PXL_20260820_000000000\n", stderr = "every photo is hidden", timedOut = false })
equal(runs[#runs].command, Shell.command(commands.current), "hide must refresh metadata even on failure")
runs[#runs].callback(success("with source"))
local detail = nil
for _, text in ipairs(labels(rendered)) do if text == "every photo is hidden" then detail = text end end
assert(detail, "replacement failure must stay visible after the refresh")

-- a hidden current photo shows a restore action
noctalia.json.decode = (function(original)
  return function(text)
    if text == "hidden current" then
      local copy = {}
      for k, v in pairs(payload) do copy[k] = v end
      copy.hidden = true
      return copy
    end
    return original(text)
  end
end)(noctalia.json.decode)
onOpen({})
runs[#runs].callback(success("hidden current"))
local restore = assert(button(rendered, "hide"))
equal(restore.props.glyph, "eye")
equal(restore.props.tooltip, "Restore (x)")
restore.props.onClick()
equal(runs[#runs].command, Shell.command(Logic.unhideCommand("PXL_20260820_000000000")))
runs[#runs].callback(success("unhidden PXL_20260820_000000000"))
equal(runs[#runs].command, Shell.command(commands.current), "restore must refresh metadata")
runs[#runs].callback(success("with source"))

-- right-click opens the menu; its action opens the list view
assert(button(rendered, "hide")).props.onRightClick()
equal(#menuRequests, 1)
equal(menuRequests[1].onActivate, "onHiddenMenu")
equal(menuRequests[1].items[1].id, "show-hidden")
onHiddenMenu("show-hidden", nil)
assert(find(rendered, "image") == nil, "hidden view must replace the photo")
equal(runs[#runs].command, Shell.command(commands.hidden))
runs[#runs].callback(success("hidden list"))
local scroll = assert(find(rendered, "scroll"), "hidden list must scroll")
equal(#scroll.children, 2)
local restoreRow = assert(button(rendered, "restore:gone"))
restoreRow.props.onClick()
equal(runs[#runs].command, Shell.command(Logic.unhideCommand("gone")))
runs[#runs].callback(success("unhidden gone"))
equal(runs[#runs].command, Shell.command(commands.current), "restore from the list must re-read current first")
runs[#runs].callback(success("with source"))
equal(runs[#runs].command, Shell.command(commands.hidden), "restore from the list must then reload the list")
runs[#runs].callback(success("empty list"))
assert(find(rendered, "scroll") == nil)
local empty = false
for _, text in ipairs(labels(rendered)) do if text == "Nothing hidden" then empty = true end end
assert(empty, "empty list must say so")

-- an error from restoring a listed photo survives the list reload that follows it
onHiddenMenu("show-hidden", nil)
runs[#runs].callback(success("hidden list"))
assert(button(rendered, "restore:gone")).props.onClick()
equal(runs[#runs].command, Shell.command(Logic.unhideCommand("gone")))
runs[#runs].callback(success("unhidden gone"))
equal(runs[#runs].command, Shell.command(commands.current))
runs[#runs].callback({ exitCode = 1, stdout = "", stderr = "current broke", timedOut = false })
equal(runs[#runs].command, Shell.command(commands.hidden), "the list still reloads after a failed refresh")
runs[#runs].callback(success("empty list"))
local stillVisible = false
for _, text in ipairs(labels(rendered)) do if text == "current broke" then stillVisible = true end end
assert(stillVisible, "an error from the current re-read must survive the list reload")

-- restoring the displayed photo from the list updates the caption
onOpen({})
runs[#runs].callback(success("hidden current"))
onKey("shift+x", true)
runs[#runs].callback(success("hidden list"))
onHiddenMenu("show-hidden", nil) -- a second open while idle just reloads
runs[#runs].callback(success("hidden list"))
assert(button(rendered, "restore:PXL_20260101_000000000")).props.onClick()
runs[#runs].callback(success("unhidden PXL_20260101_000000000"))
equal(runs[#runs].command, Shell.command(commands.current))
runs[#runs].callback(success("with source"))
runs[#runs].callback(success("empty list"))
onKey("x", true)
assert(find(rendered, "image") ~= nil, "x must close the list view")
equal(assert(button(rendered, "hide")).props.glyph, "eye-off", "caption state must follow the re-read current")

-- opening the list while a command is busy is ignored, so no loader is left behind
assert(button(rendered, "next")).props.onClick()
local busyRuns = #runs
onKey("shift+x", true)
equal(#runs, busyRuns, "list must not load while busy")
assert(find(rendered, "image") ~= nil, "view must not change while busy")
onHiddenMenu("show-hidden", nil)
assert(find(rendered, "image") ~= nil, "menu action must not change the view while busy")
runs[#runs].callback(success())
runs[#runs].callback(success("with source"))

-- keyboard: shift+x toggles the list, x hides from the photo view and closes the list
onKey("shift+x", true)
assert(find(rendered, "image") == nil, "shift+x must open the list view")
runs[#runs].callback(success("empty list"))
onKey("shift+x", true)
assert(find(rendered, "image") ~= nil, "shift+x must leave the list view")
onKey("shift+x", true)
runs[#runs].callback(success("empty list"))
local hideCount = #runs
onKey("x", true)
equal(#runs, hideCount, "x in the list view closes it without hiding")
assert(find(rendered, "image") ~= nil)
onKey("x", true)
equal(runs[#runs].command, Shell.command(commands.hide))
runs[#runs].callback(success("hidden PXL_20260820_000000000"))
runs[#runs].callback(success("with source"))

print("Wali plugin tests passed")
