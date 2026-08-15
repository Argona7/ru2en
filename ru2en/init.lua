-- ru2en: double Cmd+C translates the selected russian text into english
-- and pastes it back over the selection.

local config = require("ru2en.config")
local guards = require("ru2en.guards")
local api = require("ru2en.api")
local selection = require("ru2en.selection")

local M = {}

local function moduleDir()
  local src = debug.getinfo(1, "S").source
  local path = string.sub(src, 1, 1) == "@" and string.sub(src, 2) or src
  return string.match(path, "^(.*)/[^/]+$")
end

local PROMPT_PATH = moduleDir() .. "/prompt.txt"

M.dir = moduleDir()
M.root = string.match(moduleDir(), "^(.*)/[^/]+$")

local ALERT_STYLE = {
  strokeWidth = 0,
  fillColor = { white = 0, alpha = 0.8 },
  textColor = { white = 1 },
  textSize = 15,
  radius = 10,
}

local inFlight = false
local spinnerId = nil
local lastCmdC = 0
local tap = nil
local hotkeys = {}
local reader = nil

M.lastOriginal = nil
M.lastElapsed = nil
M.cmdCSeen = 0

local function hideSpinner()
  if spinnerId then
    hs.alert.closeSpecific(spinnerId)
    spinnerId = nil
  end
end

local function showSpinner()
  if not config.show_spinner then
    return
  end
  hideSpinner()
  spinnerId = hs.alert.show("translating\226\128\166", ALERT_STYLE, hs.screen.mainScreen(), config.timeout_s + 2)
end

local function fail(msg)
  hideSpinner()
  hs.alert.show("ru2en: " .. msg, ALERT_STYLE, hs.screen.mainScreen(), 3)
  print("ru2en error: " .. msg)
end

M.alertStyle = ALERT_STYLE
M.fail = fail

local function paste(text)
  hs.pasteboard.setContents(text)
  hs.timer.doAfter(config.paste_delay_ms / 1000, function()
    selection.postKey({ "cmd" }, selection.KEY_V)
  end)
end

function M.translate(original, onDone)
  onDone = onDone or paste

  local prompt = api.readPromptFile(PROMPT_PATH)
  if not prompt then
    return fail("cannot read " .. PROMPT_PATH)
  end

  inFlight = true
  M.lastOriginal = original
  showSpinner()

  api.request({ system = prompt, text = original }, function(content, elapsed)
    inFlight = false
    hideSpinner()
    M.lastElapsed = elapsed
    onDone(guards.apply(content, original), elapsed)
  end, function(err)
    inFlight = false
    fail(err)
  end)
end

function M.translateClipboard(opts)
  opts = opts or {}
  if inFlight then
    return
  end

  local raw = hs.pasteboard.readString()
  if type(raw) ~= "string" or raw == "" then
    return
  end

  local text = guards.normalize_newlines(raw)
  -- Silent bail-out: a double Cmd+C on english text must stay a plain copy.
  if not opts.force and not guards.has_cyrillic(text) then
    return
  end

  local chars = utf8.len(text) or #text
  if chars > config.max_chars then
    return fail("too long: " .. chars .. " chars, limit is " .. config.max_chars)
  end

  M.translate(text)
end

-- Unlike the double tap, this fires on a selection the user never copied,
-- so it has to take the copy itself.
function M.forceTranslate()
  if inFlight then
    return
  end
  selection.capture({ restore = false }, function()
    M.translateClipboard({ force = true })
  end)
end

function M.rollback()
  if not M.lastOriginal then
    return fail("nothing to roll back")
  end
  paste(M.lastOriginal)
end

function M.doctor()
  local prompt = api.readPromptFile(PROMPT_PATH)
  local report = table.concat({
    "accessibility:    " .. tostring(hs.accessibilityState()),
    "eventtap running: " .. tostring(tap ~= nil and tap:isEnabled() or false),
    "hotkeys bound:    " .. #hs.hotkey.getHotkeys(),
    "api key:          " .. (api.key() and "found in keychain" or "MISSING"),
    "prompt:           " .. (prompt and (#prompt .. " chars") or "MISSING"),
    "reader prompt:    " .. (api.readPromptFile(M.dir .. "/prompt.reader.txt") and "loaded" or "MISSING"),
    "reader panel:     " .. (reader and "armed" or "not started"),
    "model:            " .. config.model,
    "cmd+c seen:       " .. M.cmdCSeen,
    "last latency:     " .. (M.lastElapsed and string.format("%.2fs", M.lastElapsed) or "n/a"),
    "reader latency:   " .. (reader and reader.lastElapsed and string.format("%.2fs", reader.lastElapsed) or "n/a"),
  }, "\n")
  return report
end

function M.benchmark(text)
  text = text or "привет - я делаю переводчик\n\n  вот такой отступ\n  и еще строка тут"
  M.translate(guards.normalize_newlines(text), function(result, elapsed)
    print(string.format("ru2en benchmark: %.2fs\n--- input ---\n%s\n--- output ---\n%s\n---", elapsed, text, result))
  end)
end

local function onKey(event)
  if selection.isSynthesizing() then
    return false
  end
  if event:getKeyCode() ~= selection.KEY_C then
    return false
  end
  if not event:getFlags():containExactly({ "cmd" }) then
    return false
  end

  M.cmdCSeen = M.cmdCSeen + 1

  local now = hs.timer.secondsSinceEpoch()
  if (now - lastCmdC) * 1000 <= config.double_tap_ms then
    lastCmdC = 0
    local baseline = hs.pasteboard.changeCount()
    selection.afterPasteboardSettles(baseline, function()
      M.translateClipboard()
    end)
  else
    lastCmdC = now
  end

  return false
end

function M.stop()
  if tap then
    tap:stop()
    tap = nil
  end
  for _, hk in ipairs(hotkeys) do
    hk:delete()
  end
  hotkeys = {}
  if reader then
    reader.stop()
  end
end

function M.start()
  M.stop()

  tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, onKey)
  tap:start()

  hotkeys[#hotkeys + 1] = selection.bindHotkey(config.force_hotkey, M.forceTranslate)
  hotkeys[#hotkeys + 1] = selection.bindHotkey(config.rollback_hotkey, M.rollback)

  reader = require("ru2en.reader")
  reader.start()

  return M
end

return M
