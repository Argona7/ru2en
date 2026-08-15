-- Template for ~/.hammerspoon/init.lua. install.sh fills the placeholder
-- below with the absolute path of the checkout.

local ROOT = "__REPO_DIR__"
package.path = ROOT .. "/?.lua;" .. ROOT .. "/?/init.lua;" .. package.path

require("hs.ipc")

local ok, ru2en = pcall(require, "ru2en")
if ok then
  ru2en.start()
  hs.alert.show("ru2en ready")
else
  print("ru2en load error: " .. tostring(ru2en))
  hs.alert.show("ru2en failed to load, see console")
end

local reloadTimer = nil
configWatcher = hs.pathwatcher.new(ROOT, function(files)
  for _, f in ipairs(files) do
    if string.match(f, "%.lua$") or string.match(f, "prompt%.txt$") then
      if reloadTimer then
        reloadTimer:stop()
      end
      reloadTimer = hs.timer.doAfter(0.4, hs.reload)
      return
    end
  end
end)
configWatcher:start()
