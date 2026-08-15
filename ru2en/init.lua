-- ru2en: double Cmd+C translates the selected russian text into english
-- and pastes it back over the selection.

local config = require("ru2en.config")
local guards = require("ru2en.guards")

local M = {}

local function moduleDir()
  local src = debug.getinfo(1, "S").source
  local path = string.sub(src, 1, 1) == "@" and string.sub(src, 2) or src
  return string.match(path, "^(.*)/[^/]+$")
end

local PROMPT_PATH = moduleDir() .. "/prompt.txt"

M.root = string.match(moduleDir(), "^(.*)/[^/]+$")

-- kVK_ANSI_C and kVK_ANSI_V. Hardcoded on purpose: hs.keycodes.map resolves
-- against the active keyboard layout and warns on every lookup while a
-- cyrillic layout is on, which is exactly when this tool gets used. Hardware
-- keycodes are layout independent.
local KEYCODE_C = 8
local KEYCODE_V = 9

local ALERT_STYLE = {
  strokeWidth = 0,
  fillColor = { white = 0, alpha = 0.8 },
  textColor = { white = 1 },
  textSize = 15,
  radius = 10,
}

local apiKey = nil
local inFlight = false
local generation = 0
local spinnerId = nil
local lastCmdC = 0
local synthesizing = false
local tap = nil
local hotkeys = {}

M.lastOriginal = nil
M.lastElapsed = nil
M.cmdCSeen = 0

local function readPrompt()
  local f = io.open(PROMPT_PATH, "r")
  if not f then
    return nil
  end
  local body = f:read("*a")
  f:close()
  return (string.gsub(body, "%s+$", ""))
end

local function getApiKey()
  if apiKey then
    return apiKey
  end
  local out, ok = hs.execute(
    "/usr/bin/security find-generic-password -s '" .. config.keychain_service .. "' -w 2>/dev/null"
  )
  if not ok or type(out) ~= "string" then
    return nil
  end
  local key = string.gsub(out, "%s+$", "")
  if key == "" then
    return nil
  end
  apiKey = key
  return apiKey
end

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

local function postKey(mods, keycode)
  hs.eventtap.event.newKeyEvent(mods, keycode, true):post()
  hs.timer.usleep(20000)
  hs.eventtap.event.newKeyEvent(mods, keycode, false):post()
end

local function paste(text)
  hs.pasteboard.setContents(text)
  hs.timer.doAfter(config.paste_delay_ms / 1000, function()
    postKey({ "cmd" }, KEYCODE_V)
  end)
end

-- The triggering Cmd+C has already put the selection on the pasteboard, so we
-- wait for changeCount to move rather than copying a second time.
local function afterPasteboardSettles(baseline, fn)
  local deadline = hs.timer.secondsSinceEpoch() + config.pasteboard_wait_ms / 1000
  local function poll()
    if hs.pasteboard.changeCount() > baseline or hs.timer.secondsSinceEpoch() >= deadline then
      fn()
    else
      hs.timer.doAfter(0.015, poll)
    end
  end
  hs.timer.doAfter(0.015, poll)
end

function M.translate(original, onDone)
  onDone = onDone or paste

  local key = getApiKey()
  if not key then
    return fail("no key in keychain under '" .. config.keychain_service .. "'")
  end
  local prompt = readPrompt()
  if not prompt then
    return fail("cannot read " .. PROMPT_PATH)
  end

  generation = generation + 1
  local myGen = generation
  inFlight = true
  M.lastOriginal = original
  showSpinner()

  local started = hs.timer.secondsSinceEpoch()

  local body = hs.json.encode({
    model = config.model,
    temperature = config.temperature,
    messages = {
      { role = "system", content = prompt },
      { role = "user", content = original },
    },
  })

  hs.timer.doAfter(config.timeout_s, function()
    if inFlight and generation == myGen then
      inFlight = false
      fail("timeout after " .. config.timeout_s .. "s")
    end
  end)

  hs.http.asyncPost(config.endpoint, body, {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. key,
  }, function(status, respBody)
    if generation ~= myGen or not inFlight then
      return
    end
    inFlight = false
    hideSpinner()

    if status ~= 200 then
      return fail("http " .. tostring(status) .. ": " .. string.sub(tostring(respBody), 1, 140))
    end

    local ok, decoded = pcall(hs.json.decode, respBody)
    if not ok or type(decoded) ~= "table" then
      return fail("unparseable response")
    end

    local choice = decoded.choices and decoded.choices[1]
    local content = choice and choice.message and choice.message.content
    if type(content) ~= "string" or content == "" then
      local err = decoded.error
      return fail(type(err) == "table" and tostring(err.message) or "empty response")
    end

    M.lastElapsed = hs.timer.secondsSinceEpoch() - started
    onDone(guards.apply(content, original), M.lastElapsed)
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
  local baseline = hs.pasteboard.changeCount()
  synthesizing = true
  postKey({ "cmd" }, KEYCODE_C)
  hs.timer.doAfter(0.15, function()
    synthesizing = false
  end)
  afterPasteboardSettles(baseline, function()
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
  local prompt = readPrompt()
  local report = table.concat({
    "accessibility:    " .. tostring(hs.accessibilityState()),
    "eventtap running: " .. tostring(tap ~= nil and tap:isEnabled() or false),
    "hotkeys bound:    " .. #hotkeys,
    "api key:          " .. (getApiKey() and "found in keychain" or "MISSING"),
    "prompt:           " .. (prompt and (#prompt .. " chars") or "MISSING"),
    "model:            " .. config.model,
    "cmd+c seen:       " .. M.cmdCSeen,
    "last latency:     " .. (M.lastElapsed and string.format("%.2fs", M.lastElapsed) or "n/a"),
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
  if synthesizing then
    return false
  end
  if event:getKeyCode() ~= KEYCODE_C then
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
    afterPasteboardSettles(baseline, function()
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
end

function M.start()
  M.stop()

  tap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, onKey)
  tap:start()

  if config.force_hotkey then
    hotkeys[#hotkeys + 1] = hs.hotkey.bind(config.force_hotkey.mods, config.force_hotkey.key, M.forceTranslate)
  end
  if config.rollback_hotkey then
    hotkeys[#hotkeys + 1] = hs.hotkey.bind(config.rollback_hotkey.mods, config.rollback_hotkey.key, M.rollback)
  end

  return M
end

return M
