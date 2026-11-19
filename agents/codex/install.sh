#!/usr/bin/env bash
# Build time, as root.
set -euo pipefail
npm install -g --no-fund --no-audit "@openai/codex@${AGENT_VERSION:-latest}"
echo "$(codex --version)" >> /opt/vibe/build-info
