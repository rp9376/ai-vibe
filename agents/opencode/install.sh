#!/usr/bin/env bash
# Build time, as root.
set -euo pipefail
pkg=opencode-ai
npm install -g --no-fund --no-audit --allow-scripts="$pkg" "$pkg@${AGENT_VERSION:-latest}"
root="$(npm root -g)/$pkg"
# The package ships several CPU variants (~200 MB each); keep only the one the postinstall linked.
used=$(stat -c %i "$root/bin/opencode.exe")
for d in "$root"/node_modules/opencode-linux-*; do
  [ "$(stat -c %i "$d/bin/opencode" 2>/dev/null)" = "$used" ] || rm -rf "$d"
done
# Start guard (SPEC AGT-4): opencode runs only where the network can reach nothing but local endpoints.
bin="$(npm prefix -g)/bin/opencode"
rm -f "$bin"
cat > "$bin" <<WRAP
#!/bin/sh
# vibe guard: opencode is the local-model-only agent. It runs only under the 'local' or 'offline'
# network profile, where the proxy reaches nothing but the endpoints in ~/.vibe/local-endpoints.txt.
real="$root/bin/opencode.exe"
case "\${1:-}" in --version|-v|--help|-h) exec "\$real" "\$@" ;; esac
case "\${VIBE_NET:-}" in local|offline) exec "\$real" "\$@" ;; esac
echo "opencode is local-model only; this container is on '\${VIBE_NET:-unknown}'." >&2
echo "On the host run:  vibe up <project> --net local" >&2
exit 1
WRAP
chmod 0755 "$bin"
echo "opencode $(opencode --version)" >> /opt/vibe/build-info
