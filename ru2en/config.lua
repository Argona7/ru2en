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
  -- Translate whatever is selected even without Cyrillic in it.
  force_hotkey = { mods = { "alt", "cmd" }, key = "t" },
  -- Paste the pre-translation text back over the result.
  rollback_hotkey = { mods = { "alt", "cmd" }, key = "z" },
}
