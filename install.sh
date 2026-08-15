#!/usr/bin/env bash
# Installs ru2en: Hammerspoon, the API key, the loader and autostart.
# Safe to re-run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="ru2en-xai"
LOADER="$HOME/.hammerspoon/init.lua"

say() { printf '==> %s\n' "$1"; }

# macOS ships no timeout(1). Hammerspoon stops answering the ipc socket while
# it holds a modal permission dialog, so every hs call needs a cap or the
# installer hangs forever on a machine nobody is sitting at. Perl handles the
# alarm itself and exits normally, otherwise the shell reports "Alarm clock"
# and set -e kills the run.
run_capped() {
  local secs="$1"
  shift
  perl -e '
    my $t = shift;
    my $pid = fork();
    exit 1 unless defined $pid;
    if ($pid == 0) { exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "TERM", $pid; waitpid($pid, 0); exit 124 };
    alarm $t;
    waitpid($pid, 0);
    alarm 0;
    exit($? >> 8);
  ' "$secs" "$@" 2>/dev/null || true
}

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

granted="unknown"
if command -v hs >/dev/null 2>&1; then
  run_capped 6 hs -c 'hs.autoLaunch(true)' >/dev/null || true
  granted="$(run_capped 6 hs -c 'return tostring(hs.accessibilityState())' | tr -d '\n\r ')"
fi

say "done"
echo
if [ "$granted" = "true" ]; then
  echo "Accessibility is granted. Select russian text and hit Cmd+C twice."
else
  echo "One step left, and it has to be done on the machine's own screen:"
  echo "  System Settings -> Privacy & Security -> Accessibility -> enable Hammerspoon"
  echo
  echo "macOS only reads that permission at launch, so restart it afterwards:"
  echo "  killall Hammerspoon; sleep 2; open /Applications/Hammerspoon.app"
  echo
  echo "Verify with:  hs -c 'require(\"ru2en\").doctor()'"
fi
