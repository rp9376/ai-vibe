#!/usr/bin/env bash
# Build time, as root. opencode V2 is published as @opencode/cli (binaries: opencode, opencode2).
set -euo pipefail
pkg=@opencode/cli
npm install -g --no-fund --no-audit --allow-scripts="$pkg" "$pkg@${AGENT_VERSION:-latest}"
root="$(npm root -g)/$pkg"
real="$root/bin/opencode.exe"
# The package ships several CPU/libc variants (~250 MB each); keep only the one the postinstall linked.
for d in "$root"/node_modules/@opencode/cli-*; do
  [ -d "$d" ] || continue
  [ -n "$(find "$d" -type f -samefile "$real" 2>/dev/null | head -n1)" ] || rm -rf "$d"
done
# Start guard (SPEC AGT-4): opencode runs only where the network reaches nothing but local endpoints.
for name in opencode opencode2; do
  bin="$(npm prefix -g)/bin/$name"
  rm -f "$bin"
  cat > "$bin" <<WRAP
#!/bin/sh
# vibe guard: opencode is the local-model-only agent. It runs only under the 'local' or 'offline'
# network profile, where the proxy reaches nothing but the endpoints in ~/.vibe/local-endpoints.txt.
case "\${1:-}" in --version|-v|--help|-h) exec "$real" "\$@" ;; esac
case "\${VIBE_NET:-}" in local|offline) exec "$real" "\$@" ;; esac
echo "opencode is local-model only; this container is on '\${VIBE_NET:-unknown}'." >&2
echo "On the host run:  vibe up <project> --net local" >&2
exit 1
WRAP
  chmod 0755 "$bin"
done
opencode --version >> /opt/vibe/build-info
