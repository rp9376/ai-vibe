#!/usr/bin/env bash
# Container start, as 'user'. Seeds config into the (mounted) private state dir when absent.
set -eu
dir=/home/user/.config/opencode
mountpoint -q "$dir" 2>/dev/null || exit 0
[ -e "$dir/AGENTS.md" ] || [ -L "$dir/AGENTS.md" ] || ln -s /opt/vibe/AGENTS.md "$dir/AGENTS.md"
if [ ! -e "$dir/opencode.json" ] && [ ! -e "$dir/opencode.jsonc" ]; then
  cp /opt/vibe/agents/opencode/opencode.example.jsonc "$dir/opencode.jsonc"
fi
