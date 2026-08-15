-- Shared xAI client. Keeps the key in memory and the HTTP connection warm,
-- which is where most of the speed comes from.

local config = require("ru2en.config")
local cache = require("ru2en.cache")

local M = {}

M.cache = cache
cache.ttl = config.cache_ttl_s or cache.ttl

local apiKey = nil

function M.key()
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

function M.readPromptFile(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local body = f:read("*a")
  f:close()
  return (string.gsub(body, "%s+$", ""))
end

-- opts: system, text, model, temperature, timeout_s
-- Returns a cancel function. The `done` flag makes the timeout final: a
-- response arriving after it can never resurrect the request.
function M.request(opts, onDone, onError)
  onError = onError or function() end

  local key = M.key()
  if not key then
    onError("no key in keychain under '" .. config.keychain_service .. "'")
    return function() end
  end

  local model = opts.model or config.model
  local cacheKey = model .. "\0" .. (opts.system or "") .. "\0" .. opts.text

  if opts.cache ~= false then
    local hit = cache.get(cacheKey)
    if hit then
      -- Deferred by a tick so a cache hit follows the same async path as the
      -- network, and callers that open a panel first still get it in order.
      hs.timer.doAfter(0, function()
        onDone(hit, 0, true)
      end)
      return function() end
    end
  end

  local timeout = opts.timeout_s or config.timeout_s
  local started = hs.timer.secondsSinceEpoch()
  local done = false
  local timer

  local body = hs.json.encode({
    model = model,
    temperature = opts.temperature or config.temperature,
    messages = {
      { role = "system", content = opts.system },
      { role = "user", content = opts.text },
    },
  })

  timer = hs.timer.doAfter(timeout, function()
    if done then
      return
    end
    done = true
    onError("timeout after " .. timeout .. "s")
  end)

  hs.http.asyncPost(config.endpoint, body, {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer " .. key,
  }, function(status, respBody)
    if done then
      return
    end
    done = true
    timer:stop()

    if status ~= 200 then
      return onError("http " .. tostring(status) .. ": " .. string.sub(tostring(respBody), 1, 140))
    end

    local ok, decoded = pcall(hs.json.decode, respBody)
    if not ok or type(decoded) ~= "table" then
      return onError("unparseable response")
    end

    local choice = decoded.choices and decoded.choices[1]
    local content = choice and choice.message and choice.message.content
    if type(content) ~= "string" or content == "" then
      local err = decoded.error
      return onError(type(err) == "table" and tostring(err.message) or "empty response")
    end

    if opts.cache ~= false then
      cache.put(cacheKey, content)
    end
    onDone(content, hs.timer.secondsSinceEpoch() - started, false)
  end)

  return function()
    if not done then
      done = true
      timer:stop()
    end
  end
end

return M
