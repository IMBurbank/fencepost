#!/bin/bash
set -e

# Fix .gitconfig if mounted read-only
if [ -f "$HOME/.gitconfig" ] && [ ! -w "$HOME/.gitconfig" ]; then
  cp "$HOME/.gitconfig" "$HOME/.gitconfig.local"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig.local"
fi

# Fix .config ownership if needed
if [ -d "$HOME/.config" ] && [ ! -w "$HOME/.config" ]; then
  sudo chown -R dev:dev "$HOME/.config"
fi

# Ensure gh can write its config
mkdir -p "$HOME/.config/gh"

# Fix target directory ownership (named volume may be root-owned on first run)
if [ -d "/workspace/target" ] && [ ! -w "/workspace/target" ]; then
  sudo chown -R dev:dev /workspace/target
fi

exec "$@"
