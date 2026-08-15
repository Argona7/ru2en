return {
  endpoint = "https://api.x.ai/v1/chat/completions",
  -- Non-reasoning on purpose: benchmarked at 1.3s against 8.1s for grok-4.3,
  -- 13.0s for grok-4.5 and 28.6s for grok-4.6.
  model = "grok-4.20-0309-non-reasoning",
  temperature = 0.3,
  keychain_service = "ru2en-xai",

  -- Two Cmd+C presses closer than this fire a translation.
  double_tap_ms = 400,
  -- How long to wait for the second copy to land on the pasteboard.
  pasteboard_wait_ms = 300,
  paste_delay_ms = 30,
  timeout_s = 8,
  max_chars = 8000,

  show_spinner = true,
  -- Hotkeys carry hardware keycodes, not letters: hs.keycodes resolves
  -- against the active layout and warns on every bind while a cyrillic
  -- layout is on. kVK_ANSI_T, kVK_ANSI_Z, kVK_ANSI_R.
  -- Translate whatever is selected even without Cyrillic in it.
  force_hotkey = { mods = { "alt", "cmd" }, keycode = 17 },
  -- Paste the pre-translation text back over the result.
  rollback_hotkey = { mods = { "alt", "cmd" }, keycode = 6 },

  -- EN->RU reading panel.
  reader = {
    -- Note: this shadows hard reload in browsers, a global hotkey wins over
    -- the focused app. Change it here if you want Cmd+Shift+R back.
    hotkey = { mods = { "cmd", "shift" }, keycode = 15 },
    -- Wide enough for roughly 60 characters a line, which is where prose
    -- stops being tiring to read.
    width = 540,
    padding = 22,
    gap = 18,
    min_height = 110,
    max_height_fraction = 0.62,
    font_size = 17,
    -- Reading material runs longer than a chat reply, and so does its
    -- translation, hence the roomier limits.
    max_chars = 12000,
    timeout_s = 25,
    -- Esc and the close button always work; this one is about whether a
    -- click anywhere else should dismiss the panel too.
    close_on_click_outside = true,
  },
}
