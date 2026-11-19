#!/usr/bin/env bash
# Container start, as 'user'. Seeds config into the (mounted) private state dir when absent.
set -eu
dir=/home/user/.config/opencode
mountpoint -q "$dir" 2>/dev/null || exit 0
[ -e "$dir/AGENTS.md" ] || [ -L "$dir/AGENTS.md" ] || ln -s /opt/vibe/AGENTS.md "$dir/AGENTS.md"
[ -e "$dir/opencode.json" ] || cp /opt/vibe/agents/opencode/opencode.example.json "$dir/opencode.json"
