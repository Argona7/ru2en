-- Drives a real double Cmd+C through the eventtap inside a scratch TextEdit
-- document, so the keyboard path gets tested the same way a human uses it.
-- Run from the Hammerspoon console:
--   dofile(require("ru2en").root .. "/tests/app_check.lua")

local guards = require("ru2en.guards")

local SAMPLE = "привет - я делаю переводчик\n\n  вот такой отступ\n  и еще строка"
local TARGET = "TextEdit"

local KEY_A, KEY_C, KEY_N, KEY_V = 0, 8, 45, 9

local function pk(mods, kc)
  hs.eventtap.event.newKeyEvent(mods, kc, true):post()
  hs.timer.usleep(20000)
  hs.eventtap.event.newKeyEvent(mods, kc, false):post()
end

local function frontName()
  local app = hs.application.frontmostApplication()
  return app and app:name() or "?"
end

local function inspect(s)
  local out = string.gsub(s or "", "\n", "\\n")
  return string.gsub(out, "\t", "\\t")
end

local function report(final)
  print("--- expected shape of: " .. inspect(SAMPLE))
  print("--- got:                " .. inspect(final))

  local problems = {}
  if guards.has_cyrillic(final) then
    problems[#problems + 1] = "cyrillic survived, nothing was translated"
  end
  local o, t = guards.split_lines(SAMPLE), guards.split_lines(final)
  if #o ~= #t then
    problems[#problems + 1] = string.format("line count %d vs %d", #o, #t)
  else
    for k = 1, #o do
      if guards.leading_ws(o[k]) ~= guards.leading_ws(t[k]) then
        problems[#problems + 1] = string.format("line %d indent differs", k)
      end
    end
  end
  if string.find(final, "\226\128\148", 1, true) then
    problems[#problems + 1] = "em dash introduced"
  end

  if #problems == 0 then
    print("=== app check PASSED ===")
  else
    print("=== app check FAILED ===")
    for _, p in ipairs(problems) do
      print("  -> " .. p)
    end
  end
end

local steps = {
  {
    waitFront = true,
    fn = function()
      hs.application.launchOrFocus(TARGET)
    end,
  },
  { wait = 1.2, guard = true, fn = function() pk({ "cmd" }, KEY_N) end },
  {
    wait = 1.0,
    guard = true,
    fn = function()
      hs.pasteboard.setContents(SAMPLE)
      pk({ "cmd" }, KEY_V)
    end,
  },
  { wait = 0.6, guard = true, fn = function() pk({ "cmd" }, KEY_A) end },
  {
    wait = 6.0,
    guard = true,
    fn = function()
      print("firing double Cmd+C in " .. frontName())
      pk({ "cmd" }, KEY_C)
      hs.timer.usleep(150000)
      pk({ "cmd" }, KEY_C)
    end,
  },
  {
    wait = 1.0,
    guard = true,
    fn = function()
      pk({ "cmd" }, KEY_A)
      hs.timer.usleep(150000)
      pk({ "cmd" }, KEY_C)
    end,
  },
  {
    wait = 0,
    fn = function()
      report(hs.pasteboard.readString() or "")
    end,
  },
}

local index = 0
local run

local function waitForFront(deadline)
  if frontName() == TARGET then
    return run()
  end
  if hs.timer.secondsSinceEpoch() > deadline then
    print("ABORT: " .. TARGET .. " never came to the front, still on " .. frontName())
    return
  end
  hs.timer.doAfter(0.25, function()
    waitForFront(deadline)
  end)
end

run = function()
  index = index + 1
  local step = steps[index]
  if not step then
    return
  end
  -- Never post keystrokes blind: if focus drifted, stop instead of typing
  -- into whatever happens to be in front.
  if step.guard and frontName() ~= TARGET then
    print("ABORT at step " .. index .. ": frontmost app is " .. frontName() .. ", not " .. TARGET)
    return
  end
  step.fn()
  if step.waitFront then
    waitForFront(hs.timer.secondsSinceEpoch() + 15)
  else
    hs.timer.doAfter(step.wait, run)
  end
end

print("=== app check starting ===")
run()
