-- Floating reading panel. The window itself is transparent and borderless;
-- the rounded card and its shadow are drawn in CSS, which is why the frame
-- carries a padding margin around the visible card.

local config = require("ru2en.config")

local M = {}

local view = nil
local escHotkey = nil
local clickTap = nil
local anchorRect = nil
local currentText = nil

-- kVK_Escape. Bound by keycode so the layout never matters.
local ESC_KEYCODE = 53

local TEMPLATE = [[<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
* { margin:0; padding:0; box-sizing:border-box; }
html, body { height:100%; background:transparent; }
body {
  padding:__PAD__px;
  display:flex; align-items:flex-start;
  -webkit-font-smoothing:antialiased;
  /* a reading panel should never pick up a stray drag-selection */
  -webkit-user-select:none;
  cursor:default;
}
#card {
  width:__W__px;
  max-height:100%;
  display:flex; flex-direction:column;
  background:#FBFAF7;
  border:0.5px solid rgba(0,0,0,0.12);
  border-radius:14px;
  box-shadow:0 12px 38px rgba(0,0,0,0.20), 0 2px 8px rgba(0,0,0,0.10);
  overflow:hidden;
  color:#1B1A17;
}
#text {
  padding:22px 26px 18px;
  overflow-y:auto;
  font-family:ui-serif, "New York", Georgia, serif;
  font-size:__FS__px;
  line-height:1.62;
  white-space:pre-wrap;
  overflow-wrap:break-word;
}
#text::-webkit-scrollbar { width:9px; }
#text::-webkit-scrollbar-thumb {
  background:rgba(0,0,0,0.16); border-radius:5px;
  border:3px solid transparent; background-clip:content-box;
}
.muted { color:rgba(0,0,0,0.42); font-style:italic; }
#bar {
  display:flex; align-items:center; justify-content:space-between; gap:10px;
  padding:10px 14px 11px 20px;
  border-top:0.5px solid rgba(0,0,0,0.08);
}
button {
  font-family:-apple-system, system-ui, sans-serif;
  font-size:12.5px; line-height:1;
  border:0.5px solid rgba(0,0,0,0.16);
  background:rgba(0,0,0,0.035);
  border-radius:7px; padding:6px 12px;
  color:#3A3833; cursor:pointer;
}
button:hover { background:rgba(0,0,0,0.07); }
button:active { background:rgba(0,0,0,0.12); }
#close { padding:6px 10px; color:rgba(0,0,0,0.42); }
@media (prefers-color-scheme:dark) {
  #card {
    background:#1E1D1B; border-color:rgba(255,255,255,0.10); color:#E9E6E0;
    box-shadow:0 12px 38px rgba(0,0,0,0.55), 0 2px 8px rgba(0,0,0,0.35);
  }
  #bar { border-top-color:rgba(255,255,255,0.09); }
  button { background:rgba(255,255,255,0.07); border-color:rgba(255,255,255,0.14); color:#D9D5CE; }
  button:hover { background:rgba(255,255,255,0.12); }
  #close { color:rgba(255,255,255,0.42); }
  .muted { color:rgba(255,255,255,0.40); }
  #text::-webkit-scrollbar-thumb { background:rgba(255,255,255,0.20); background-clip:content-box; }
}
</style></head><body>
<div id="card">
  <div id="text">__BODY__</div>
  __BAR__
</div>
<script>
function send(m){ window.webkit.messageHandlers.ru2enReader.postMessage(m); }
function flashCopied(){
  var b=document.getElementById('copy'); if(!b) return;
  b.textContent='Скопировано';
  setTimeout(function(){ b.textContent='Скопировать'; }, 1300);
}
(function(){
  var s=window.getSelection(); if(s) s.removeAllRanges();
  var c=document.getElementById('copy');
  if(c) c.addEventListener('click', function(){ send('copy'); });
  var x=document.getElementById('close');
  if(x) x.addEventListener('click', function(){ send('close'); });
})();
</script>
</body></html>]]

local BAR = [[<div id="bar">
    <button id="copy">Скопировать</button>
    <button id="close" title="Esc">&#10005;</button>
  </div>]]

local function escapeHtml(s)
  local out = string.gsub(s, "&", "&amp;")
  out = string.gsub(out, "<", "&lt;")
  out = string.gsub(out, ">", "&gt;")
  return out
end

-- Function replacements on purpose: the translated text is arbitrary and a
-- literal % in it would be read as a capture reference.
local function render(bodyHtml, withBar)
  local vars = {
    PAD = tostring(config.reader.padding),
    W = tostring(config.reader.width),
    FS = tostring(config.reader.font_size),
    BODY = bodyHtml,
    BAR = withBar and BAR or "",
  }
  return (string.gsub(TEMPLATE, "__(%u+)__", function(k)
    return vars[k] or ""
  end))
end

local function place(cardHeight)
  local r = config.reader
  local pad = r.padding
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local sf = screen:frame()

  local winW = r.width + pad * 2
  local maxCard = math.floor(sf.h * r.max_height_fraction)
  local winH = math.max(r.min_height, math.min(cardHeight, maxCard)) + pad * 2

  local a = anchorRect or { x = sf.x + sf.w / 2, y = sf.y + sf.h / 3, w = 0, h = 0 }

  -- pad is subtracted so the visible gap between card and selection is
  -- exactly r.gap rather than r.gap plus the invisible shadow margin.
  local rightX = a.x + a.w + r.gap - pad
  local leftX = a.x - r.gap - winW + pad

  local x
  if rightX + winW <= sf.x + sf.w - 8 then
    x = rightX
  elseif leftX >= sf.x + 8 then
    x = leftX
  else
    x = sf.x + sf.w - winW - 8
  end

  local y = a.y - pad
  if y + winH > sf.y + sf.h - 8 then
    y = sf.y + sf.h - winH - 8
  end
  if y < sf.y + 8 then
    y = sf.y + 8
  end

  return { x = x, y = y, w = winW, h = winH }
end

-- Measures the text's unclipped scrollHeight rather than the card's own
-- height: the card is capped at max-height:100%, so asking it how tall it is
-- would only ever echo back the window size the panel already has.
local MEASURE_JS = [[(function(){
  var t = document.getElementById('text');
  var b = document.getElementById('bar');
  return t.scrollHeight + (b ? b.offsetHeight : 0) + 2;
})()]]

local function fit()
  if not view then
    return
  end
  view:evaluateJavaScript(MEASURE_JS, function(result)
    local h = tonumber(result)
    if h and view then
      view:frame(place(h))
    end
  end)
end

function M.isOpen()
  return view ~= nil
end

function M.frame()
  return view and view:frame() or nil
end

function M.close()
  if escHotkey then
    escHotkey:delete()
    escHotkey = nil
  end
  if clickTap then
    clickTap:stop()
    clickTap = nil
  end
  if view then
    view:delete()
    view = nil
  end
  currentText = nil
end

local function newController()
  local controller = hs.webview.usercontent.new("ru2enReader")
  controller:setCallback(function(message)
    local action = message and message.body
    if action == "copy" then
      if currentText then
        hs.pasteboard.setContents(currentText)
        if view then
          view:evaluateJavaScript("flashCopied()")
        end
      end
    elseif action == "close" then
      M.close()
    end
  end)
  return controller
end

function M.show(anchor)
  M.close()
  anchorRect = anchor

  view = hs.webview.new(place(config.reader.min_height), { developerExtrasEnabled = false }, newController())
  view:windowStyle({ "borderless", "nonactivating" })
  view:level(hs.drawing.windowLevels.floating)
  view:shadow(false)
  view:transparent(true)
  view:allowTextEntry(false)
  view:allowGestures(false)
  view:html(render('<span class="muted">перевожу…</span>', false))
  view:show()

  hs.timer.doAfter(0.06, fit)

  escHotkey = hs.hotkey.bind({}, ESC_KEYCODE, M.close)

  if config.reader.close_on_click_outside then
    clickTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function()
      if not view then
        return false
      end
      local p = hs.mouse.absolutePosition()
      local f = view:frame()
      if p.x < f.x or p.x > f.x + f.w or p.y < f.y or p.y > f.y + f.h then
        M.close()
      end
      return false
    end)
    clickTap:start()
  end
end

function M.setText(text)
  if not view then
    return
  end
  currentText = text
  view:html(render(escapeHtml(text), true))
  hs.timer.doAfter(0.06, fit)
end

function M.setError(msg)
  if not view then
    return
  end
  currentText = nil
  view:html(render('<span class="muted">' .. escapeHtml(msg) .. "</span>", false))
  hs.timer.doAfter(0.06, fit)
end

return M
