-- Floating reading panel. The window is transparent and borderless; the
-- rounded card and its shadow are drawn in CSS, so the frame carries a
-- padding margin around the visible card.
--
-- Two things a nonactivating panel does not get for free, both handled here
-- by the mouse tap: dragging and resizing (no titlebar, no native resize
-- edge) and hover (the window never receives mouseMoved, so CSS :hover
-- alone would never fire).

local config = require("ru2en.config")

local M = {}

local view = nil
local escHotkey = nil
local mouseTap = nil
local anchorRect = nil
local currentText = nil
local dragMode = nil
local dragOrigin = nil
local hoverId = nil
local controls = nil
local frameCache = nil

-- Size the user dragged to, kept for the rest of the session. Nil means the
-- panel keeps sizing itself to its content.
local userSize = nil

-- kVK_Escape. Bound by keycode so the layout never matters.
local ESC_KEYCODE = 53

-- Must match the CSS below: these are the grab targets.
local HEADER_H = 34
local GRIP = 22
local MIN_CARD_W = 320
local MIN_CARD_H = 150

local TEMPLATE = [[<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
* { margin:0; padding:0; box-sizing:border-box; }
html, body { height:100%; background:transparent; }
body {
  padding:__PAD__px;
  -webkit-font-smoothing:antialiased;
  -webkit-user-select:none;
  cursor:default;
}
#card {
  width:100%; height:100%;
  display:flex; flex-direction:column;
  background:#FCFBF9;
  border:0.5px solid rgba(20,18,14,0.10);
  border-radius:16px;
  box-shadow:
    0 1px 2px rgba(0,0,0,0.04),
    0 8px 24px rgba(0,0,0,0.10),
    0 24px 56px rgba(0,0,0,0.11);
  overflow:hidden;
  color:#1A1815;
}

#head {
  position:relative; flex:0 0 __HEADH__px;
  display:flex; align-items:center; justify-content:center;
  border-bottom:0.5px solid rgba(20,18,14,0.07);
  cursor:grab;
}
#head:active { cursor:grabbing; }
#grab { width:34px; height:4px; border-radius:2px; background:rgba(20,18,14,0.16); }
#close {
  position:absolute; right:9px; top:50%; transform:translateY(-50%);
  width:23px; height:23px; padding:0;
  display:flex; align-items:center; justify-content:center;
  font-size:12px; line-height:1;
  border:0; border-radius:7px; background:transparent;
  color:rgba(20,18,14,0.34); cursor:pointer;
  transition:background 130ms ease, color 130ms ease;
}
#close:hover, #close.hover { background:rgba(20,18,14,0.08); color:rgba(20,18,14,0.72); }
#close:active, #close.press { background:rgba(20,18,14,0.15); }

#text {
  flex:1 1 auto; min-height:0; overflow-y:auto;
  padding:20px 26px 20px;
  font-family:ui-serif, "New York", Georgia, serif;
  font-size:__FS__px;
  line-height:1.62;
  white-space:pre-wrap;
  overflow-wrap:break-word;
  -webkit-user-select:text;
  cursor:text;
}
#text::selection { background:rgba(56,116,214,0.24); }
#text::-webkit-scrollbar { width:10px; }
#text::-webkit-scrollbar-thumb {
  background:rgba(20,18,14,0.15); border-radius:5px;
  border:3px solid transparent; background-clip:content-box;
}
#text::-webkit-scrollbar-thumb:hover { background:rgba(20,18,14,0.26); background-clip:content-box; }
.muted { color:rgba(20,18,14,0.40); font-style:italic; }

#foot {
  position:relative; flex:0 0 46px;
  display:flex; align-items:center;
  padding:0 18px;
  border-top:0.5px solid rgba(20,18,14,0.07);
}
#copy {
  font-family:-apple-system, system-ui, sans-serif;
  font-size:12.5px; font-weight:500; line-height:1;
  border:0.5px solid rgba(20,18,14,0.11);
  background:rgba(20,18,14,0.045);
  border-radius:8px; padding:7px 14px;
  color:#37342E; cursor:pointer;
  transition:background 130ms ease, border-color 130ms ease, color 130ms ease;
}
#copy:hover, #copy.hover { background:rgba(20,18,14,0.09); border-color:rgba(20,18,14,0.18); }
#copy:active, #copy.press { background:rgba(20,18,14,0.14); border-color:rgba(20,18,14,0.22); }
#copy.done {
  background:rgba(47,107,68,0.11); border-color:rgba(47,107,68,0.26); color:#2F6B44;
}
#grip {
  position:absolute; right:0; bottom:0;
  width:__GRIP__px; height:__GRIP__px;
  cursor:nwse-resize;
}
#grip::after {
  content:""; position:absolute; right:5px; bottom:5px; width:11px; height:11px;
  background:repeating-linear-gradient(135deg,
    rgba(20,18,14,0.26) 0 1.5px, transparent 1.5px 4px);
}

@media (prefers-color-scheme:dark) {
  #card {
    background:#1C1B19; border-color:rgba(255,255,255,0.09); color:#E8E4DD;
    box-shadow:
      0 1px 2px rgba(0,0,0,0.30),
      0 8px 24px rgba(0,0,0,0.45),
      0 24px 56px rgba(0,0,0,0.40);
  }
  #head { border-bottom-color:rgba(255,255,255,0.08); }
  #grab { background:rgba(255,255,255,0.18); }
  #close { color:rgba(255,255,255,0.36); }
  #close:hover, #close.hover { background:rgba(255,255,255,0.11); color:rgba(255,255,255,0.82); }
  #close:active, #close.press { background:rgba(255,255,255,0.17); }
  #text::selection { background:rgba(96,150,240,0.32); }
  #foot { border-top-color:rgba(255,255,255,0.08); }
  #copy { background:rgba(255,255,255,0.06); border-color:rgba(255,255,255,0.12); color:#DAD6CF; }
  #copy:hover, #copy.hover { background:rgba(255,255,255,0.12); border-color:rgba(255,255,255,0.20); }
  #copy:active, #copy.press { background:rgba(255,255,255,0.17); border-color:rgba(255,255,255,0.26); }
  #copy.done { background:rgba(120,200,150,0.13); border-color:rgba(120,200,150,0.28); color:#8FD5AC; }
  #text::-webkit-scrollbar-thumb { background:rgba(255,255,255,0.17); background-clip:content-box; }
  #text::-webkit-scrollbar-thumb:hover { background:rgba(255,255,255,0.28); background-clip:content-box; }
  .muted { color:rgba(255,255,255,0.40); }
  #grip::after {
    background:repeating-linear-gradient(135deg,
      rgba(255,255,255,0.28) 0 1.5px, transparent 1.5px 4px);
  }
}
</style></head><body>
<div id="card">
  <div id="head"><div id="grab"></div><button id="close" title="Esc">&#10005;</button></div>
  <div id="text">__BODY__</div>
  __FOOT__
</div>
<script>
var IDS = ['copy','close'];
function send(m){ window.webkit.messageHandlers.ru2enReader.postMessage(m); }
function selectionText(){
  var s = window.getSelection();
  return s ? s.toString() : '';
}
function copyLabel(){
  return selectionText().length > 0 ? 'Скопировать выделенное' : 'Скопировать';
}
function setHover(id){
  IDS.forEach(function(k){
    var e = document.getElementById(k);
    if (e) e.classList.toggle('hover', k === id);
  });
}
function setPress(id){
  IDS.forEach(function(k){
    var e = document.getElementById(k);
    if (e) e.classList.toggle('press', k === id);
  });
}
function flashCopied(){
  var b = document.getElementById('copy'); if(!b) return;
  b.textContent = 'Скопировано'; b.classList.add('done');
  setTimeout(function(){ b.textContent = copyLabel(); b.classList.remove('done'); }, 1400);
}
function controlRects(){
  var out = {};
  IDS.forEach(function(k){
    var e = document.getElementById(k);
    if (e) { var b = e.getBoundingClientRect(); out[k] = {x:b.left, y:b.top, w:b.width, h:b.height}; }
  });
  return JSON.stringify(out);
}
(function(){
  var s = window.getSelection(); if (s) s.removeAllRanges();
  var c = document.getElementById('copy');
  if (c) c.addEventListener('click', function(){ send({action:'copy', selection:selectionText()}); });
  var x = document.getElementById('close');
  if (x) x.addEventListener('click', function(){ send({action:'close'}); });
  document.addEventListener('selectionchange', function(){
    var b = document.getElementById('copy');
    if (b && !b.classList.contains('done')) b.textContent = copyLabel();
  });
})();
</script>
</body></html>]]

local FOOT = [[<div id="foot">
    <button id="copy">Скопировать</button>
    <div id="grip"></div>
  </div>]]

local MEASURE_JS = [[(function(){
  var t = document.getElementById('text');
  var h = document.getElementById('head');
  var f = document.getElementById('foot');
  return t.scrollHeight + (h ? h.offsetHeight : 0) + (f ? f.offsetHeight : 0) + 2;
})()]]

local function escapeHtml(s)
  local out = string.gsub(s, "&", "&amp;")
  out = string.gsub(out, "<", "&lt;")
  out = string.gsub(out, ">", "&gt;")
  return out
end

-- Function replacements on purpose: the translated text is arbitrary and a
-- literal % in it would otherwise be read as a capture reference.
local function render(bodyHtml, withFoot)
  local vars = {
    PAD = tostring(config.reader.padding),
    FS = tostring(config.reader.font_size),
    HEADH = tostring(HEADER_H),
    GRIP = tostring(GRIP),
    BODY = bodyHtml,
    FOOT = withFoot and FOOT or "",
  }
  return (string.gsub(TEMPLATE, "__(%u+)__", function(k)
    return vars[k] or ""
  end))
end

local function setFrame(rect)
  if not view then
    return
  end
  view:frame(rect)
  frameCache = rect
end

local function place(cardHeight)
  local r = config.reader
  local pad = r.padding
  local margin = 10
  local screen = hs.mouse.getCurrentScreen() or hs.screen.mainScreen()
  local sf = screen:frame()

  local cardW = userSize and userSize.w or r.width
  local maxCard = math.floor(sf.h * r.max_height_fraction)
  local cardH = userSize and userSize.h or math.max(r.min_height, math.min(cardHeight, maxCard))
  cardH = math.min(cardH, sf.h - 2 * margin - pad * 2)

  local winW, winH = cardW + pad * 2, cardH + pad * 2
  local a = anchorRect or { x = sf.x + sf.w / 2, y = sf.y + sf.h / 3, w = 0, h = 0, dock = true }

  local x
  local besideRight = a.x + a.w + r.gap
  local besideLeft = a.x - r.gap - cardW

  if not a.dock and besideRight + cardW <= sf.x + sf.w - margin then
    x = besideRight - pad
  elseif not a.dock and besideLeft >= sf.x + margin then
    x = besideLeft - pad
  else
    -- No room beside the selection, or no idea where it is. Dock to the far
    -- side of the screen so the panel cannot sit on top of what is being read.
    if a.x + a.w / 2 <= sf.x + sf.w / 2 then
      x = sf.x + sf.w - margin - cardW - pad
    else
      x = sf.x + margin - pad
    end
  end

  local y = a.y - pad
  if y + winH > sf.y + sf.h - margin then
    y = sf.y + sf.h - margin - winH
  end
  if y < sf.y + margin then
    y = sf.y + margin
  end

  return { x = x, y = y, w = winW, h = winH }
end

local function refreshControls()
  if not view then
    return
  end
  view:evaluateJavaScript("controlRects()", function(result)
    if type(result) ~= "string" then
      return
    end
    local ok, decoded = pcall(hs.json.decode, result)
    if ok and type(decoded) == "table" then
      controls = decoded
    end
  end)
end

local function fit()
  if not view then
    return
  end
  if userSize then
    refreshControls()
    return
  end
  view:evaluateJavaScript(MEASURE_JS, function(result)
    local h = tonumber(result)
    if h and view then
      setFrame(place(h))
      refreshControls()
    end
  end)
end

-- A cache hit replaces the html one runloop tick after the loading state, so
-- a fixed delay measures a document that has not laid out yet and the panel
-- stays at its minimum height. The navigation callback is the only reliable
-- signal; the timer is just a safety net if it never arrives.
local function scheduleFit()
  hs.timer.doAfter(0.2, fit)
end

function M.eval(js, callback)
  if view then
    view:evaluateJavaScript(js, callback)
  end
end

local function zoneAt(point, frame)
  local pad = config.reader.padding
  local cx, cy = frame.x + pad, frame.y + pad
  local cw, ch = frame.w - pad * 2, frame.h - pad * 2

  if point.x < cx or point.x > cx + cw or point.y < cy or point.y > cy + ch then
    return nil
  end
  if point.x >= cx + cw - GRIP and point.y >= cy + ch - GRIP then
    return "resize"
  end
  if point.y <= cy + HEADER_H then
    return "move"
  end
  return nil
end

-- getBoundingClientRect is in viewport coordinates, and the viewport is the
-- whole window, so subtracting the window origin is all it takes.
local function controlAt(point, frame)
  if not controls then
    return nil
  end
  local lx, ly = point.x - frame.x, point.y - frame.y
  for _, id in ipairs({ "copy", "close" }) do
    local r = controls[id]
    if r and lx >= r.x and lx <= r.x + r.w and ly >= r.y and ly <= r.y + r.h then
      return id
    end
  end
  return nil
end

function M.isOpen()
  return view ~= nil
end

function M.frame()
  return view and view:frame() or nil
end

function M.resetSize()
  userSize = nil
end

function M.close()
  if escHotkey then
    escHotkey:delete()
    escHotkey = nil
  end
  if mouseTap then
    mouseTap:stop()
    mouseTap = nil
  end
  if view then
    view:delete()
    view = nil
  end
  dragMode = nil
  hoverId = nil
  controls = nil
  frameCache = nil
  currentText = nil
end

local function newController()
  local controller = hs.webview.usercontent.new("ru2enReader")
  controller:setCallback(function(message)
    local body = message and message.body
    local action = type(body) == "table" and body.action or body

    if action == "copy" then
      -- Whatever the user highlighted wins over the whole translation.
      local selected = type(body) == "table" and body.selection or nil
      local payload = (type(selected) == "string" and #selected > 0) and selected or currentText
      if payload then
        hs.pasteboard.setContents(payload)
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

local function onMouse(event)
  if not view then
    return false
  end

  local types = hs.eventtap.event.types
  local kind = event:getType()
  -- From the event, not the cursor: the event carries the exact location the
  -- click happened at, which also keeps synthetic events honest in tests.
  local point = event:location() or hs.mouse.absolutePosition()
  local frame = frameCache or view:frame()

  if kind == types.mouseMoved then
    local id = controlAt(point, frame)
    if id ~= hoverId then
      hoverId = id
      view:evaluateJavaScript(string.format("setHover(%s)", id and ("'" .. id .. "'") or "null"))
    end
    return false
  end

  if kind == types.leftMouseDown then
    frame = view:frame()
    frameCache = frame
    local pressed = controlAt(point, frame)
    if pressed then
      view:evaluateJavaScript(string.format("setPress('%s')", pressed))
    end

    local zone = zoneAt(point, frame)
    if zone then
      dragMode = zone
      dragOrigin = { mx = point.x, my = point.y, x = frame.x, y = frame.y, w = frame.w, h = frame.h }
      return false
    end

    local inside = point.x >= frame.x and point.x <= frame.x + frame.w
      and point.y >= frame.y and point.y <= frame.y + frame.h
    if not inside and config.reader.close_on_click_outside then
      M.close()
    end
    return false
  end

  if kind == types.leftMouseUp then
    view:evaluateJavaScript("setPress(null)")
    if dragMode then
      dragMode = nil
      refreshControls()
      return true
    end
    return false
  end

  if kind == types.leftMouseDragged and dragMode then
    local pad = config.reader.padding
    local dx, dy = point.x - dragOrigin.mx, point.y - dragOrigin.my
    if dragMode == "move" then
      setFrame({ x = dragOrigin.x + dx, y = dragOrigin.y + dy, w = dragOrigin.w, h = dragOrigin.h })
    else
      local w = math.max(MIN_CARD_W + pad * 2, dragOrigin.w + dx)
      local h = math.max(MIN_CARD_H + pad * 2, dragOrigin.h + dy)
      setFrame({ x = dragOrigin.x, y = dragOrigin.y, w = w, h = h })
      userSize = { w = w - pad * 2, h = h - pad * 2 }
    end
    -- Swallowed so the app underneath does not start selecting text.
    return true
  end

  return false
end

function M.show(anchor)
  M.close()
  anchorRect = anchor

  local rect = place(config.reader.min_height)
  view = hs.webview.new(rect, { developerExtrasEnabled = false }, newController())
  frameCache = rect
  view:windowStyle({ "borderless", "nonactivating" })
  view:level(hs.drawing.windowLevels.floating)
  view:shadow(false)
  view:transparent(true)
  -- Lets the web content take first responder, which is what makes
  -- click-dragging a selection inside the text work.
  view:allowTextEntry(true)
  view:allowGestures(false)
  view:navigationCallback(function(action)
    if action == "didFinishNavigation" then
      fit()
    end
  end)
  view:html(render('<span class="muted">перевожу…</span>', false))
  view:show()

  scheduleFit()

  escHotkey = hs.hotkey.bind({}, ESC_KEYCODE, M.close)

  mouseTap = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.leftMouseDragged,
    hs.eventtap.event.types.leftMouseUp,
    hs.eventtap.event.types.mouseMoved,
  }, onMouse)
  mouseTap:start()
end

function M.setText(text)
  if not view then
    return
  end
  currentText = text
  view:html(render(escapeHtml(text), true))
  scheduleFit()
end

function M.setError(msg)
  if not view then
    return
  end
  currentText = nil
  view:html(render('<span class="muted">' .. escapeHtml(msg) .. "</span>", false))
  scheduleFit()
end

return M
