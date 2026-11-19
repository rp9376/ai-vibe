#!/usr/bin/env bash
# Container start, as 'user'. Only touches ~/.codex when the state dir is actually mounted.
set -eu
dir=/home/user/.codex
mountpoint -q "$dir" 2>/dev/null || exit 0
[ -e "$dir/AGENTS.md" ] || [ -L "$dir/AGENTS.md" ] || ln -s /opt/vibe/AGENTS.md "$dir/AGENTS.md"
[ -e "$dir/config.toml" ] || cp /opt/vibe/agents/codex/config.toml "$dir/config.toml"
