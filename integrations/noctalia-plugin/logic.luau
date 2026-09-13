local M = {}

local commands = {
  current = { "walictl", "current", "--json" },
  previous = { "walictl", "previous" },
  next = { "walictl", "next" },
  random = { "walictl", "random" },
  earlier = { "walictl", "earlier" },
  later = { "walictl", "later" },
  favorite = { "walictl", "favorite" },
  edit = { "walictl", "edit" },
  hide = { "walictl", "hide" },
  hidden = { "walictl", "hidden", "--json" },
}

function M.commandFor(action)
  return assert(commands[action], "unknown walictl action: " .. tostring(action))
end

function M.unhideCommand(photoId)
  return { "walictl", "unhide", photoId }
end

function M.validateCurrent(payload)
  if type(payload) ~= "table" then return nil, "walictl current did not return an object" end
  if payload.ok ~= true then return nil, "walictl current reported failure" end
  for _, field in ipairs({ "id", "path" }) do
    if type(payload[field]) ~= "string" then return nil, "walictl current returned an invalid " .. field .. " field" end
  end
  if type(payload.favorite) ~= "boolean" then return nil, "walictl current returned an invalid favorite field" end
  if type(payload.hidden) ~= "boolean" then return nil, "walictl current returned an invalid hidden field" end
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

function M.decodeCurrent(text, decoder)
  local decoded, payload, decodeError = pcall(decoder, text)
  if not decoded then return nil, tostring(payload) end
  if payload == nil then return nil, tostring(decodeError or "walictl current returned invalid JSON") end
  return M.validateCurrent(payload)
end

function M.refreshAfter(action)
  return action == "previous" or action == "next" or action == "random" or action == "favorite"
    or action == "earlier" or action == "later" or action == "hide"
end

function M.canStart(busy)
  return not busy
end

function M.copyTarget(payload)
  return payload.source_path or payload.path
end

function M.favoriteGlyph(favorite)
  return favorite and "heart-filled" or "heart"
end

function M.captionTitle(payload)
  if payload == nil then return "" end
  return payload.display_date or payload.date or payload.id
end

function M.captionDetail(payload, errorText)
  if errorText ~= nil then return { text = errorText, color = "error" } end
  return { text = payload and payload.id or "", color = "on_surface_variant" }
end

-- payload is nil or a validateCurrent result, so payload.history is always a table.
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

function M.validateHidden(payload)
  if type(payload) ~= "table" then return nil, "walictl hidden did not return an object" end
  if payload.ok ~= true then return nil, "walictl hidden reported failure" end
  if type(payload.hidden) ~= "table" then return nil, "walictl hidden returned an invalid hidden field" end
  for index, item in ipairs(payload.hidden) do
    if type(item) ~= "table" or type(item.id) ~= "string" then
      return nil, "walictl hidden returned an invalid id in item " .. tostring(index)
    end
    if type(item.exists) ~= "boolean" then
      return nil, "walictl hidden returned an invalid exists field in item " .. tostring(index)
    end
    for _, field in ipairs({ "added", "date", "display_date", "path", "source_path" }) do
      if item[field] ~= nil and type(item[field]) ~= "string" then
        return nil, "walictl hidden returned an invalid " .. field .. " field in item " .. tostring(index)
      end
    end
  end
  return payload.hidden
end

function M.decodeHidden(text, decoder)
  local decoded, payload, decodeError = pcall(decoder, text)
  if not decoded then return nil, tostring(payload) end
  if payload == nil then return nil, tostring(decodeError or "walictl hidden returned invalid JSON") end
  return M.validateHidden(payload)
end

function M.hideGlyph(hidden)
  return hidden and "eye" or "eye-off"
end

function M.hideTooltip(hidden)
  return hidden and "Restore (x)" or "Hide (x) · right-click: hidden list"
end

return M
