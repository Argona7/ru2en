-- In-memory translation cache. Lives for the Hammerspoon session, which is
-- the right lifetime: editing a prompt reloads the config and wipes it, so a
-- stale prompt can never keep serving old translations.

local M = {}

local store = {}
local order = {}

M.ttl = 3600
M.limit = 200

function M.get(key)
  local entry = store[key]
  if not entry then
    return nil
  end
  if os.time() - entry.at > M.ttl then
    store[key] = nil
    return nil
  end
  return entry.value
end

function M.put(key, value)
  if not store[key] then
    order[#order + 1] = key
    if #order > M.limit then
      local oldest = table.remove(order, 1)
      store[oldest] = nil
    end
  end
  store[key] = { value = value, at = os.time() }
end

function M.clear()
  store = {}
  order = {}
end

function M.size()
  local n = 0
  for _ in pairs(store) do
    n = n + 1
  end
  return n
end

return M
