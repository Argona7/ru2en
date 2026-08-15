-- Run: lua tests/test_guards.lua

local root = (arg and arg[0] or ""):match("^(.*)/tests/[^/]+$") or "."
package.path = root .. "/?.lua;" .. package.path

local guards = require("ru2en.guards")

local passed, failed = 0, 0

local function show(s)
  if type(s) ~= "string" then
    return tostring(s)
  end
  local out = string.gsub(s, "\n", "\\n")
  out = string.gsub(out, "\t", "\\t")
  return "[" .. out .. "]"
end

local function eq(name, got, want)
  if got == want then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. name)
    print("  want: " .. show(want))
    print("  got:  " .. show(got))
  end
end

local function apply(name, original, translated, want)
  eq(name, guards.apply(translated, original), want)
end

-- cyrillic detection gates the whole feature
eq("cyrillic: russian", guards.has_cyrillic("привет"), true)
eq("cyrillic: english", guards.has_cyrillic("hello world"), false)
eq("cyrillic: mixed", guards.has_cyrillic("hello мир"), true)
eq("cyrillic: digits and punct", guards.has_cyrillic("1. foo - bar (baz)"), false)
eq("cyrillic: emoji only", guards.has_cyrillic("ok \240\159\154\128"), false)

-- newline normalization
eq("crlf", guards.normalize_newlines("a\r\nb"), "a\nb")
eq("cr", guards.normalize_newlines("a\rb"), "a\nb")

-- line splitting round-trips exactly
eq("split: count", #guards.split_lines("a\nb\nc"), 3)
eq("split: trailing newline", #guards.split_lines("a\nb\n"), 3)
eq("split: single", #guards.split_lines("a"), 1)

-- indentation
apply("indent: two spaces restored", "  вот такой отступ", "here's the indent", "  here's the indent")
apply("indent: tab restored", "\tотступ табом", "tab indent", "\ttab indent")
apply("indent: model kept its own wrong indent", "нет отступа", "    no indent", "no indent")

apply(
  "indent: multiline block",
  "привет - я делаю переводчик\n\n  вот такой отступ\n  и еще строка",
  "hey - i'm making a translator\n\nhere's the indent\nand another line",
  "hey - i'm making a translator\n\n  here's the indent\n  and another line"
)

apply(
  "indent: whitespace-only line preserved verbatim",
  "привет\n  \nмир",
  "hey\n\nworld",
  "hey\n  \nworld"
)

-- dashes: swap only what the user never typed
apply("dash: em dash becomes hyphen", "привет - как дела", "hey — how's it going", "hey - how's it going")
apply("dash: en dash becomes hyphen", "привет - как дела", "hey – how's it going", "hey - how's it going")
apply("dash: em dash kept when user typed one", "привет — как дела", "hey — how's it going", "hey — how's it going")

-- quotes and apostrophes
apply("punct: curly apostrophe straightened", "я не знаю", "i don’t know", "i don't know")
apply("punct: curly quotes straightened", "он сказал привет", "he said “hey”", 'he said "hey"')
apply("punct: curly apostrophe kept when user typed one", "не знаю ’ вот", "don’t know ’ here", "don’t know ’ here")

-- currency: the sign always moves in front of the number
eq("currency: trailing sign moved", guards.normalize_currency("i charge 150$"), "i charge $150")
eq("currency: doubled sign collapsed", guards.normalize_currency("for a regular one $80$"), "for a regular one $80")
eq("currency: emphasis run collapsed", guards.normalize_currency("let's do a qrt for 200$$$"), "let's do a qrt for $200")
eq("currency: already correct is untouched", guards.normalize_currency("i charge $150"), "i charge $150")
eq("currency: thousands separator survives", guards.normalize_currency("that's 1,500$ total"), "that's $1,500 total")
eq("currency: decimals survive", guards.normalize_currency("12.50$ each"), "$12.50 each")
eq("currency: several amounts in one line", guards.normalize_currency("150$ pinned, 80$ regular"), "$150 pinned, $80 regular")
eq("currency: no amount is a no-op", guards.normalize_currency("hit 100% of the target"), "hit 100% of the target")
apply("currency: fixed through the full pipeline", "беру 150$ за пост", "i charge 150$ for a post", "i charge $150 for a post")

-- wrapping quotes
apply("quotes: wrapper stripped", "привет", '"hey"', "hey")
apply("quotes: wrapper kept when user quoted", '"привет"', '"hey"', '"hey"')
apply("quotes: inner quotes left alone", "он сказал привет мне", 'he said "hey" to me', 'he said "hey" to me')

-- code fences
apply("fence: bare fence stripped", "привет", "```\nhey there\n```", "hey there")
apply("fence: tagged fence stripped", "привет", "```text\nhey there\n```", "hey there")
apply("fence: kept when user wrote a fence", "```\nпривет\n```", "```\nhey\n```", "```\nhey\n```")

-- capitalization mirrors the source line by line
apply("case: lowercase enforced", "привет", "Hey", "hey")
apply("case: uppercase enforced", "Привет", "hey", "Hey")
apply("case: skips list marker", "- привет", "- Hey", "- hey")
apply("case: numbered marker", "1. привет", "1. Hey", "1. hey")
apply("case: per-line", "привет\nКак дела", "Hey\nhow's it going", "hey\nHow's it going")
apply("case: leaves mid-sentence capitals", "я поехал в москву", "i went to Moscow", "i went to Moscow")
apply("case: standalone I lowercased for an all-lowercase source", "я поехал", "I went", "i went")
apply("case: I'm contraction lowercased", "я делаю переводчик", "yeah I'm making a translator", "yeah i'm making a translator")
apply("case: I kept when the source line has a capital", "Я поехал", "I went", "I went")
apply("case: India survives the pronoun rule", "я был в индии", "i was in India", "i was in India")

-- edge newlines
apply("edge: trailing newline preserved", "привет\n", "hey", "hey\n")
apply("edge: model's extra trailing newline dropped", "привет", "hey\n\n", "hey")
apply("edge: model's leading newline dropped", "привет", "\nhey", "hey")
apply("edge: leading newline preserved", "\nпривет", "hey", "\nhey")

-- invented blank lines get dropped so the rest of the guards can run
apply(
  "blanks: model aired out a two-liner",
  "честно говоря не думаю что зайдет\nдавай лучше сделаю квоут",
  "tbh i don't think it'll land\n\nlet's do a qrt instead",
  "tbh i don't think it'll land\nlet's do a qrt instead"
)
apply(
  "blanks: whitespace-only invented line dropped",
  "скинь тз в лс\nзапущу завтра",
  "drop the brief in dms\n   \ni'll kick it off tomorrow",
  "drop the brief in dms\ni'll kick it off tomorrow"
)
apply(
  "blanks: real blank line in source survives",
  "привет\n\nкак дела",
  "hey\n\nhow's it going",
  "hey\n\nhow's it going"
)
apply(
  "blanks: source blank kept while invented one is dropped",
  "привет\n\nкак дела",
  "hey\n\nhow's it going\n",
  "hey\n\nhow's it going"
)
apply(
  "blanks: indent restored after dropping the invented line",
  "план:\n  первый шаг\n  второй шаг",
  "plan:\n\nfirst step\nsecond step",
  "plan:\n  first step\n  second step"
)
eq(
  "blanks: untouched when dropping cannot reach the target count",
  guards.drop_invented_blanks("one\ntwo\nthree", "первый"),
  "one\ntwo\nthree"
)
eq(
  "blanks: no-op when counts already match",
  guards.drop_invented_blanks("a\nb", "раз\nдва"),
  "a\nb"
)

-- line count mismatch: indent guards stand down, punctuation guards do not
apply("mismatch: indent untouched, dash still fixed", "привет\nкак дела", "hey — how are you", "hey - how are you")
apply(
  "mismatch: no indent restore on merged lines",
  "  привет\n  как дела",
  "hey how are you",
  "hey how are you"
)

-- degenerate input
eq("empty translation passes through", guards.apply("", "привет"), "")
eq("nil translation passes through", guards.apply(nil, "привет"), nil)

-- the real benchmark text end to end
local original = "привет - я делаю переводчик\n\n  вот такой отступ\n  и еще строка тут\n\n"
  .. "короче задача простая: нажал кнопку - все перевелось\nнадо чтобы прям мгновенно работало, без тормозов"
local model_output = "Hey — I'm making a translator\n\nhere's this indent\nand another line here\n\n"
  .. "basically the task is simple: hit the button — everything gets translated\nit needs to work instantly, no lag at all"
local want = "hey - i'm making a translator\n\n  here's this indent\n  and another line here\n\n"
  .. "basically the task is simple: hit the button - everything gets translated\nit needs to work instantly, no lag at all"
apply("integration: benchmark text", original, model_output, want)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
