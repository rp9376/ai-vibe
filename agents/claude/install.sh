#!/usr/bin/env bash
# Build time, as root. AGENT_VERSION comes from agent.conf.
set -euo pipefail
pkg=@anthropic-ai/claude-code
# The postinstall links the native binary into place; allow it explicitly (newer npm gates install scripts).
npm install -g --no-fund --no-audit --allow-scripts="$pkg" "$pkg@${AGENT_VERSION:-latest}"
echo "claude $(claude --version)" >> /opt/vibe/build-info
