#!/usr/bin/env bash
# Installs ru2en: Hammerspoon, the API key, the loader and autostart.
# Safe to re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="ru2en-xai"
LOADER="$HOME/.hammerspoon/init.lua"

say() { printf '==> %s\n' "$1"; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "ru2en is macOS only" >&2
  exit 1
fi

if [ ! -d /Applications/Hammerspoon.app ]; then
  say "installing Hammerspoon"
  brew install --cask hammerspoon
else
  say "Hammerspoon already installed"
fi

if security find-generic-password -s "$SERVICE" -w >/dev/null 2>&1; then
  say "api key already in keychain"
else
  KEY="${XAI_API_KEY:-}"
  if [ -z "$KEY" ]; then
    printf 'xAI API key (input hidden): '
    read -r -s KEY
    printf '\n'
  fi
  if [ -z "$KEY" ]; then
    echo "no key provided, aborting" >&2
    exit 1
  fi
  # -T pre-authorises both readers so macOS never prompts at translate time.
  security add-generic-password -U -s "$SERVICE" -a "$USER" \
    -T /usr/bin/security -T /Applications/Hammerspoon.app -w "$KEY"
  say "api key stored in keychain under '$SERVICE'"
fi

mkdir -p "$HOME/.hammerspoon"
if [ -f "$LOADER" ] && ! grep -q 'ru2en' "$LOADER" 2>/dev/null; then
  backup="$LOADER.backup.$(date +%Y%m%d%H%M%S)"
  cp "$LOADER" "$backup"
  say "existing config backed up to $backup"
fi
sed "s|__REPO_DIR__|$REPO_DIR|g" "$REPO_DIR/hammerspoon-init.lua" > "$LOADER"
say "loader written to $LOADER"

if pgrep -xq Hammerspoon; then
  say "restarting Hammerspoon"
  killall Hammerspoon
  sleep 2
fi
# Right after a fresh cask install LaunchServices has not indexed the bundle
# yet, so "open -a Hammerspoon" fails by name. Launch by path instead.
if ! open /Applications/Hammerspoon.app 2>/dev/null; then
  open -a Hammerspoon
fi
sleep 6

if command -v hs >/dev/null 2>&1; then
  hs -c 'hs.autoLaunch(true)' >/dev/null 2>&1 || true
  granted="$(hs -c 'return tostring(hs.accessibilityState())' 2>/dev/null | tr -d '\n\r ')"
else
  granted="unknown"
fi

say "done"
echo
if [ "$granted" = "true" ]; then
  echo "Accessibility is granted. Select russian text and hit Cmd+C twice."
else
  echo "One step left: grant Accessibility to Hammerspoon."
  echo "  System Settings -> Privacy & Security -> Accessibility -> enable Hammerspoon"
  echo "Then restart it, macOS only reads the permission at launch:"
  echo "  killall Hammerspoon; sleep 2; open -a Hammerspoon"
fi
