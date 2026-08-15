-- Keyboard and pasteboard plumbing shared by the translator and the reader.

local config = require("ru2en.config")

local M = {}

-- kVK_ANSI_C and kVK_ANSI_V. Hardcoded on purpose: hs.keycodes.map resolves
-- against the active keyboard layout and warns on every lookup while a
-- cyrillic layout is on, which is exactly when this tool gets used. Hardware
-- keycodes are layout independent.
M.KEY_C = 8
M.KEY_V = 9

local synthesizing = false

-- The Cmd+C double-tap listener must ignore the Cmd+C we post ourselves,
-- otherwise capturing a selection would trigger a translation.
function M.isSynthesizing()
  return synthesizing
end

-- Binds by hardware keycode when the spec carries one, so a cyrillic layout
-- neither warns on every reload nor risks moving the binding to another
-- physical key.
function M.bindHotkey(spec, fn)
  if not spec then
    return nil
  end
  return hs.hotkey.bind(spec.mods, spec.keycode or spec.key, fn)
end

function M.postKey(mods, keycode)
  hs.eventtap.event.newKeyEvent(mods, keycode, true):post()
  hs.timer.usleep(20000)
  hs.eventtap.event.newKeyEvent(mods, keycode, false):post()
end

function M.afterPasteboardSettles(baseline, fn)
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

-- Copies whatever is selected and hands the text to fn.
-- opts.restore puts the user's previous pasteboard back, with every flavour
-- intact, so a read-only action never costs them their clipboard.
function M.capture(opts, fn)
  opts = opts or {}

  local previous = opts.restore and hs.pasteboard.readAllData() or nil
  local baseline = hs.pasteboard.changeCount()

  synthesizing = true
  M.postKey({ "cmd" }, M.KEY_C)
  hs.timer.doAfter(0.15, function()
    synthesizing = false
  end)

  M.afterPasteboardSettles(baseline, function()
    -- changeCount only moves if the copy actually landed. Without this the
    -- caller would silently act on whatever was already on the pasteboard
    -- when nothing was selected.
    local copied = hs.pasteboard.changeCount() > baseline
    local text = hs.pasteboard.readString()
    if previous then
      hs.pasteboard.writeAllData(previous)
    end
    fn(text, copied)
  end)
end

return M
