-- Live end-to-end check against the real xAI API, exercising prompt, model
-- and guards together. Run from the Hammerspoon console:
--   dofile(require("ru2en").root .. "/tests/live_check.lua")

local ru2en = require("ru2en")
local guards = require("ru2en.guards")

local EM_DASH = "\226\128\148"
local EN_DASH = "\226\128\147"

local cases = {
  { name = "flat sentence", text = "короче задача простая: нажал кнопку - все перевелось" },
  { name = "indented block", text = "привет - я делаю переводчик\n\n  вот такой отступ\n  и еще строка тут" },
  { name = "bullet list", text = "что надо:\n- быстро\n- точно\n- без лишнего текста" },
  { name = "nested indent", text = "план:\n  первый шаг\n    вложенный шаг\n  второй шаг" },
  { name = "mixed en/ru", text = "я поставил Hammerspoon и написал init.lua - вроде работает" },
  { name = "trailing newline", text = "надо чтобы работало прям мгновенно\n" },
  { name = "numbered list", text = "1. открыть\n2. выделить\n3. нажать два раза" },
  { name = "capitalized source", text = "Привет. Я делаю переводчик - он должен быть быстрым." },
}

local function inspect(s)
  local out = string.gsub(s, "\n", "\\n")
  return string.gsub(out, "\t", "\\t")
end

local function check(original, out)
  local problems = {}

  if guards.has_cyrillic(out) then
    problems[#problems + 1] = "cyrillic left in output"
  end

  local hadLongDash = string.find(original, EM_DASH, 1, true) or string.find(original, EN_DASH, 1, true)
  local hasLongDash = string.find(out, EM_DASH, 1, true) or string.find(out, EN_DASH, 1, true)
  if hasLongDash and not hadLongDash then
    problems[#problems + 1] = "long dash introduced"
  end

  local o = guards.split_lines(original)
  local t = guards.split_lines(out)
  if #o ~= #t then
    problems[#problems + 1] = string.format("line count %d vs %d", #o, #t)
    return problems
  end

  for k = 1, #o do
    local ows, tws = guards.leading_ws(o[k]), guards.leading_ws(t[k])
    if ows ~= tws then
      problems[#problems + 1] = string.format("line %d indent [%s] vs [%s]", k, inspect(ows), inspect(tws))
    end
    local oc = guards._first_letter_case(o[k])
    local tc = guards._first_letter_case(t[k])
    if oc and tc and oc ~= tc then
      problems[#problems + 1] = string.format("line %d case %s vs %s", k, oc, tc)
    end
  end

  return problems
end

local index = 0
local failures = 0
local total = 0

local function runNext()
  index = index + 1
  local case = cases[index]
  if not case then
    print(string.format("\n=== live check: %d cases, %d failed ===", total, failures))
    return
  end

  ru2en.translate(case.text, function(out, elapsed)
    total = total + 1
    local problems = check(case.text, out)
    if #problems == 0 then
      print(string.format("ok   %-18s %.2fs  %s", case.name, elapsed, inspect(out)))
    else
      failures = failures + 1
      print(string.format("FAIL %-18s %.2fs", case.name, elapsed))
      print("       in:  " .. inspect(case.text))
      print("       out: " .. inspect(out))
      for _, p in ipairs(problems) do
        print("       -> " .. p)
      end
    end
    runNext()
  end)
end

print("=== live check starting ===")
runNext()
