#!/usr/bin/env bash
# prp installer
#
#   curl -fsSL https://raw.githubusercontent.com/0xanto/prp/main/install.sh | bash
#
# Re-run it any time to update. Options (environment variables):
#   PRP_VERSION=v0.1.0      install a tag or branch instead of main
#   PRP_BIN_DIR=~/bin       where to put the `prp` command
#   PRP_INSTALL_DIR=...     where to keep prp.py (default ~/.local/share/prp)
#
# Uninstall:  curl -fsSL https://raw.githubusercontent.com/0xanto/prp/main/install.sh | bash -s -- --uninstall
set -euo pipefail

REPO="${PRP_REPO:-0xanto/prp}"
REF="${PRP_VERSION:-main}"
INSTALL_DIR="${PRP_INSTALL_DIR:-$HOME/.local/share/prp}"

if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; N=$'\033[0m'; else B= G= Y= R= N=; fi
ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*"; }
die()  { printf '%s✗%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

pick_bin_dir() {
  if [ -n "${PRP_BIN_DIR:-}" ]; then echo "$PRP_BIN_DIR"; return; fi
  for d in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
    if [ -d "$d" ] && [ -w "$d" ] && [[ ":$PATH:" == *":$d:"* ]]; then echo "$d"; return; fi
  done
  echo "$HOME/.local/bin"
}

BIN_DIR="$(pick_bin_dir)"

if [ "${1:-}" = "--uninstall" ]; then
  for d in "$BIN_DIR" /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
    [ -L "$d/prp" ] && rm -f "$d/prp" && ok "Removed $d/prp"
  done
  [ -d "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR" && ok "Removed $INSTALL_DIR"
  echo "Your settings and history in ~/.prp were kept. Delete that folder to remove them too."
  exit 0
fi

printf '%sInstalling prp%s\n' "$B" "$N"

# --- requirements
command -v python3 >/dev/null 2>&1 || die "python3 is required (macOS: xcode-select --install)"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
  || die "prp needs Python 3.9+ (found $(python3 --version 2>&1))"
command -v git >/dev/null 2>&1 || die "git is required"

# --- get prp.py: use the local checkout when run from a clone, else download
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/prp.py" ]; then
  SRC="$SCRIPT_DIR/prp.py"
  ok "Using your checkout at $SCRIPT_DIR (edits there take effect immediately)"
else
  command -v curl >/dev/null 2>&1 || die "curl is required"
  mkdir -p "$INSTALL_DIR"
  TMP="$(mktemp)"
  trap 'rm -f "$TMP"' EXIT
  URL="https://raw.githubusercontent.com/$REPO/$REF/prp.py"
  curl -fsSL "$URL" -o "$TMP" || die "Download failed: $URL"
  python3 -m py_compile "$TMP" 2>/dev/null || die "Downloaded file isn't valid Python: $URL"
  mv "$TMP" "$INSTALL_DIR/prp.py"
  SRC="$INSTALL_DIR/prp.py"
  ok "Downloaded prp ($REF) to $SRC"
fi
chmod +x "$SRC"

# --- link onto PATH
mkdir -p "$BIN_DIR"
ln -sf "$SRC" "$BIN_DIR/prp"
ok "Linked $BIN_DIR/prp"

if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  case "$(basename "${SHELL:-}")" in
    zsh)  RC="$HOME/.zshrc" ;;
    bash) if [ "$(uname)" = Darwin ]; then RC="$HOME/.bash_profile"; else RC="$HOME/.bashrc"; fi ;;
    *)    RC="" ;;
  esac
  if [ -n "$RC" ]; then
    if ! grep -qsF "$BIN_DIR" "$RC"; then
      printf '\n# prp\nexport PATH="%s:$PATH"\n' "$BIN_DIR" >> "$RC"
      ok "Added $BIN_DIR to PATH in $RC"
    fi
    warn "Open a new terminal (or run: source $RC) before using prp"
  else
    warn "Add $BIN_DIR to your PATH to use prp"
  fi
fi

VERSION="$("$SRC" --version 2>/dev/null || true)"
[ -n "$VERSION" ] && ok "prp $VERSION installed"

# --- what else is needed
echo
if ! command -v gh >/dev/null 2>&1; then
  warn "GitHub CLI not found. Install it: https://cli.github.com (macOS: brew install gh), then: gh auth login"
elif ! gh auth status >/dev/null 2>&1; then
  warn "GitHub CLI isn't logged in. Run: gh auth login"
else
  ok "GitHub CLI ready"
fi
if command -v claude >/dev/null 2>&1 || command -v codex >/dev/null 2>&1; then
  for a in claude codex; do command -v "$a" >/dev/null 2>&1 && ok "$a found"; done
else
  warn "Install at least one agent: Claude Code (claude) or Codex CLI (codex)"
fi

echo
printf '%sNext:%s cd into a repo you want watched and run:  %sprp init%s\n' "$B" "$N" "$B" "$N"
