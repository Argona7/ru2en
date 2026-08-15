-- EN->RU reading panel: grabs the selection, translates it and shows the
-- result next to where the text sits on screen. Never touches the clipboard.

local config = require("ru2en.config")
local guards = require("ru2en.guards")
local api = require("ru2en.api")
local selection = require("ru2en.selection")
local window = require("ru2en.window")

local M = {}

local function moduleDir()
  local src = debug.getinfo(1, "S").source
  local path = string.sub(src, 1, 1) == "@" and string.sub(src, 2) or src
  return string.match(path, "^(.*)/[^/]+$")
end

local PROMPT_PATH = moduleDir() .. "/prompt.reader.txt"

local ALERT_STYLE = {
  strokeWidth = 0,
  fillColor = { white = 0, alpha = 0.8 },
  textColor = { white = 1 },
  textSize = 15,
  radius = 10,
}

local hotkey = nil
local inFlight = false

M.lastElapsed = nil

local function notify(msg)
  hs.alert.show("ru2en: " .. msg, ALERT_STYLE, hs.screen.mainScreen(), 2.5)
end

-- Accessibility gives the exact rectangle of the selected text in native
-- apps and Safari. Electron apps usually refuse, so fall back to the mouse,
-- which is sitting right where the drag ended.
local function selectionAnchor()
  local ok, bounds = pcall(function()
    local element = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
    if not element then
      return nil
    end
    local range = element:attributeValue("AXSelectedTextRange")
    if not range then
      return nil
    end
    return element:parameterizedAttributeValue("AXBoundsForRange", range)
  end)

  if ok and type(bounds) == "table" and tonumber(bounds.w) and tonumber(bounds.w) > 0 then
    return { x = bounds.x, y = bounds.y, w = bounds.w, h = bounds.h }
  end

  local point = hs.mouse.absolutePosition()
  return { x = point.x, y = point.y, w = 0, h = 0 }
end

local function clean(text, original)
  local out = guards.strip_fences(text, original)
  out = guards.strip_wrapping_quotes(out, original)
  out = string.gsub(out, "^%s+", "")
  out = string.gsub(out, "%s+$", "")
  return out
end

function M.read()
  if inFlight then
    return
  end

  local prompt = api.readPromptFile(PROMPT_PATH)
  if not prompt then
    return notify("cannot read " .. PROMPT_PATH)
  end

  -- Taken before the copy: the selection is guaranteed to still be there.
  local anchor = selectionAnchor()

  selection.capture({ restore = true }, function(raw, copied)
    if not copied or type(raw) ~= "string" or raw == "" then
      return notify("ничего не выделено")
    end

    local text = guards.normalize_newlines(raw)
    if not guards.has_latin(text) then
      return notify("в выделении нет английского текста")
    end

    local chars = utf8.len(text) or #text
    if chars > config.reader.max_chars then
      return notify("слишком длинно: " .. chars .. ", лимит " .. config.reader.max_chars)
    end

    window.show(anchor)
    inFlight = true

    api.request({
      system = prompt,
      text = text,
      timeout_s = config.reader.timeout_s,
    }, function(content, elapsed)
      inFlight = false
      M.lastElapsed = elapsed
      window.setText(clean(content, text))
    end, function(err)
      inFlight = false
      window.setError(err)
    end)
  end)
end

function M.stop()
  if hotkey then
    hotkey:delete()
    hotkey = nil
  end
  window.close()
end

function M.start()
  M.stop()
  hotkey = selection.bindHotkey(config.reader and config.reader.hotkey, M.read)
  return M
end

return M
