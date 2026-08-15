-- Live check for the EN->RU reading prompt. Run from the Hammerspoon console:
--   dofile(require("ru2en").root .. "/tests/live_reader.lua")

local api = require("ru2en.api")
local guards = require("ru2en.guards")
local config = require("ru2en.config")

local PROMPT = api.readPromptFile(require("ru2en").dir .. "/prompt.reader.txt")

local cases = {
  {
    name = "single paragraph",
    text = "The hard part of shipping software is not writing the code. It is deciding what not to build.",
  },
  {
    name = "two paragraphs",
    text = "We shipped the beta on Friday and it held up fine.\n\nThe queue backed up once, around 200 jobs, but it drained on its own within a couple of minutes.",
  },
  {
    name = "names and numbers",
    text = "Cloudflare dropped the price to $5 per million requests, which undercuts Fastly by roughly 40%.",
  },
  {
    name = "casual register",
    text = "ngl this is the cleanest api i've used all year, took me like 20 minutes to get it running",
  },
  {
    name = "bullet list",
    text = "what we need:\n- a working demo\n- one customer quote\n- pricing that fits on a slide",
  },
}

local function paragraphs(s)
  local n = 1
  for _ in string.gmatch(s, "\n\n") do
    n = n + 1
  end
  return n
end

local function latinWords(s)
  local n = 0
  for word in string.gmatch(s, "[A-Za-z][A-Za-z']+") do
    if #word > 2 then
      n = n + 1
    end
  end
  return n
end

local function inspect(s)
  return (string.gsub(s, "\n", "\\n"))
end

local index, failures, total = 0, 0, 0

local function runNext()
  index = index + 1
  local case = cases[index]
  if not case then
    print(string.format("\n=== live reader: %d cases, %d failed ===", total, failures))
    return
  end

  api.request({
    system = PROMPT,
    text = case.text,
    timeout_s = config.reader.timeout_s,
  }, function(out, elapsed)
    total = total + 1
    local problems = {}

    if not guards.has_cyrillic(out) then
      problems[#problems + 1] = "no russian in the output"
    end
    if paragraphs(out) ~= paragraphs(case.text) then
      problems[#problems + 1] = string.format("paragraphs %d vs %d", paragraphs(case.text), paragraphs(out))
    end
    -- Proper nouns legitimately survive; a wall of english does not.
    if latinWords(out) > 3 then
      problems[#problems + 1] = "too much english left: " .. latinWords(out) .. " words"
    end

    if #problems == 0 then
      print(string.format("ok   %-18s %.2fs  %s", case.name, elapsed, inspect(out)))
    else
      failures = failures + 1
      print(string.format("FAIL %-18s %.2fs\n       in:  %s\n       out: %s", case.name, elapsed, inspect(case.text), inspect(out)))
      for _, p in ipairs(problems) do
        print("       -> " .. p)
      end
    end
    runNext()
  end, function(err)
    total = total + 1
    failures = failures + 1
    print(string.format("FAIL %-18s api error: %s", case.name, err))
    runNext()
  end)
end

print("=== live reader starting ===")
runNext()
