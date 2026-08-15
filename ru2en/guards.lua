-- Deterministic formatting repair for machine-translated text.
-- Pure Lua on purpose: no hs.* calls, so tests run under the standalone
-- interpreter without Hammerspoon.

local M = {}

local EM_DASH = "\226\128\148"
local EN_DASH = "\226\128\147"
local CURLY_APOS = "\226\128\153"
local CURLY_OPEN = "\226\128\156"
local CURLY_CLOSE = "\226\128\157"
local GUILLEMET = "\194\171"

function M.normalize_newlines(s)
  local out = string.gsub(s, "\r\n", "\n")
  out = string.gsub(out, "\r", "\n")
  return out
end

-- Bytes 0xD0/0xD1 can only ever lead a 2-byte sequence in U+0400..U+047F,
-- never appear as continuation bytes, so this cannot false-positive.
function M.has_cyrillic(s)
  return string.find(s, "[\208\209]") ~= nil
end

function M.split_lines(s)
  local lines = {}
  local start = 1
  while true do
    local nl = string.find(s, "\n", start, true)
    if not nl then
      lines[#lines + 1] = string.sub(s, start)
      return lines
    end
    lines[#lines + 1] = string.sub(s, start, nl - 1)
    start = nl + 1
  end
end

function M.leading_ws(line)
  return string.match(line, "^[ \t]*")
end

function M.strip_fences(translated, original)
  if string.find(original, "```", 1, true) then
    return translated
  end
  local body = string.match(translated, "^%s*```[%a]*[ \t]*\n(.-)\n?```[ \t]*%s*$")
  return body or translated
end

local function starts_with_quote(s)
  local first = string.sub(s, 1, 1)
  if first == '"' or first == "'" then
    return true
  end
  return string.sub(s, 1, 3) == CURLY_OPEN or string.sub(s, 1, 2) == GUILLEMET
end

function M.strip_wrapping_quotes(translated, original)
  if starts_with_quote(original) then
    return translated
  end
  local body = string.match(translated, '^"(.*)"$')
  if body and not string.find(body, '"', 1, true) then
    return body
  end
  return translated
end

-- Only swaps a character the user never typed themselves, so deliberate
-- em dashes or curly quotes in the source survive untouched.
function M.normalize_punct(translated, original)
  local out = translated
  local function swap(char, replacement)
    if not string.find(original, char, 1, true) then
      out = string.gsub(out, char, replacement)
    end
  end
  swap(EM_DASH, "-")
  swap(EN_DASH, "-")
  swap(CURLY_APOS, "'")
  swap(CURLY_OPEN, '"')
  swap(CURLY_CLOSE, '"')
  return out
end

-- Models sometimes air out a dense message with an extra blank line. Drops
-- only blank lines that have no counterpart in the source, and only when
-- doing so lands exactly on the original line count.
function M.drop_invented_blanks(translated, original)
  local o = M.split_lines(original)
  local t = M.split_lines(translated)
  if #t <= #o then
    return translated
  end

  local out = {}
  local surplus = #t - #o
  local j = 1
  for i = 1, #t do
    local tBlank = string.match(t[i], "^[ \t]*$") ~= nil
    local oBlank = j <= #o and string.match(o[j], "^[ \t]*$") ~= nil
    if tBlank and not oBlank and surplus > 0 then
      surplus = surplus - 1
    else
      out[#out + 1] = t[i]
      j = j + 1
    end
  end

  if #out == #o then
    return table.concat(out, "\n")
  end
  return translated
end

-- English never writes the sign after the number, so this is safe to apply
-- unconditionally. Also cleans up "$80$", which is what the model produces
-- when it converts the russian form but forgets to drop the original sign.
function M.normalize_currency(translated)
  local out = string.gsub(translated, "%$(%d[%d.,]*)%$+", "$%1")
  out = string.gsub(out, "(%d[%d.,]*)%$+", "$%1")
  return out
end

function M.restore_indent(translated, original)
  local o = M.split_lines(original)
  local t = M.split_lines(translated)
  if #o ~= #t then
    return translated
  end
  local out = {}
  for i = 1, #t do
    local body = string.gsub(t[i], "^[ \t]*", "")
    if body == "" then
      out[i] = string.match(o[i], "^[ \t]*$") and o[i] or ""
    else
      out[i] = M.leading_ws(o[i]) .. body
    end
  end
  return table.concat(out, "\n")
end

-- Finds the first alphabetic character, skipping punctuation and list
-- markers. Returns its case, byte offset and byte width.
local function first_letter_case(line)
  local i = 1
  local n = #line
  while i <= n do
    local b = string.byte(line, i)
    if b >= 65 and b <= 90 then
      return "upper", i, 1
    elseif b >= 97 and b <= 122 then
      return "lower", i, 1
    elseif b == 208 or b == 209 then
      local b2 = string.byte(line, i + 1)
      if b2 then
        local cp = (b - 192) * 64 + (b2 - 128)
        if (cp >= 0x410 and cp <= 0x42F) or cp == 0x401 then
          return "upper", i, 2
        elseif (cp >= 0x430 and cp <= 0x44F) or cp == 0x451 then
          return "lower", i, 2
        end
      end
      i = i + 2
    else
      i = i + 1
    end
  end
  return nil
end

M._first_letter_case = first_letter_case

local function has_uppercase(line)
  local i = 1
  local n = #line
  while i <= n do
    local b = string.byte(line, i)
    if b >= 65 and b <= 90 then
      return true
    elseif b == 208 or b == 209 then
      local b2 = string.byte(line, i + 1)
      if b2 then
        local cp = (b - 192) * 64 + (b2 - 128)
        if (cp >= 0x410 and cp <= 0x42F) or cp == 0x401 then
          return true
        end
      end
      i = i + 2
    else
      i = i + 1
    end
  end
  return false
end

M._has_uppercase = has_uppercase

-- English capitalizes the pronoun "I", which breaks an all-lowercase source
-- line. The frontier pattern matches the standalone word only, so proper
-- nouns like India or Moscow are never touched.
function M.lowercase_pronoun_i(translated, original)
  local o = M.split_lines(original)
  local t = M.split_lines(translated)
  if #o ~= #t then
    return translated
  end
  local out = {}
  for i = 1, #t do
    if has_uppercase(o[i]) then
      out[i] = t[i]
    else
      out[i] = (string.gsub(t[i], "%f[%a]I%f[%A]", "i"))
    end
  end
  return table.concat(out, "\n")
end

function M.match_case(translated, original)
  local o = M.split_lines(original)
  local t = M.split_lines(translated)
  if #o ~= #t then
    return translated
  end
  local out = {}
  for i = 1, #t do
    local line = t[i]
    local ocase = first_letter_case(o[i])
    local tcase, tpos, tlen = first_letter_case(line)
    if ocase and tcase and ocase ~= tcase and tlen == 1 then
      local ch = string.sub(line, tpos, tpos)
      local swapped = ocase == "lower" and string.lower(ch) or string.upper(ch)
      line = string.sub(line, 1, tpos - 1) .. swapped .. string.sub(line, tpos + 1)
    end
    out[i] = line
  end
  return table.concat(out, "\n")
end

function M.apply(translated, original)
  if type(translated) ~= "string" or translated == "" then
    return translated
  end

  local out = M.normalize_newlines(translated)
  out = M.strip_fences(out, original)
  out = M.strip_wrapping_quotes(out, original)
  out = M.normalize_punct(out, original)
  out = M.normalize_currency(out)

  local lead = string.match(original, "^\n*")
  local trail = string.match(original, "\n*$")
  local core = string.sub(original, #lead + 1, #original - #trail)

  out = string.gsub(out, "^\n+", "")
  out = string.gsub(out, "\n+$", "")

  out = M.drop_invented_blanks(out, core)
  out = M.restore_indent(out, core)
  out = M.match_case(out, core)
  out = M.lowercase_pronoun_i(out, core)

  return lead .. out .. trail
end

return M
