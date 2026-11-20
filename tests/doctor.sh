#!/usr/bin/env bash
# vibe doctor: runs INSIDE a vibe container, piped in via stdin by `vibe doctor`.
# Never baked into the image or mounted (SPEC VER-1).
#   image : privileges, filesystem, credentials, agents, network for $VIBE_NET   (throwaway container)
#   net   : network checks only                                                (throwaway container + proxy)
#   live  : everything + mounts and workspace guard                           (running project container)
set -u
MODE=${1:-image}
NET=${VIBE_NET:-offline}
WS=${VIBE_WORKSPACE:-$PWD}
FAILS=0 WARNS=0
if [ "${VIBE_COLOR:-0}" = 1 ]; then G=$'\e[32m' R=$'\e[31m' Y=$'\e[33m' B=$'\e[1m' N=$'\e[0m'; else G='' R='' Y='' B='' N=''; fi

pass()    { printf '  %sPASS%s  %s\n' "$G" "$N" "$1"; }
fail()    { printf '  %sFAIL%s  %s\n' "$R" "$N" "$1"; FAILS=$((FAILS + 1)); }
warn()    { printf '  %sWARN%s  %s\n' "$Y" "$N" "$1"; WARNS=$((WARNS + 1)); }
section() { printf '%s%s%s\n' "$B" "$1" "$N"; }
check()   { local d=$1; shift; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d"; fi; }   # pass if command succeeds
refute()  { local d=$1; shift; if "$@" >/dev/null 2>&1; then fail "$d"; else pass "$d"; fi; }  # pass if command fails
st()      { awk -v k="$1:" '$1 == k { print $2 }' /proc/self/status; }
default_route() { awk 'NR > 1 && $2 == "00000000" { f = 1 } END { exit !f }' /proc/net/route; }
any()     { compgen -G "$1" >/dev/null; }
only_loopback() { local i; for i in /sys/class/net/*; do [ "${i##*/}" = lo ] || return 1; done; }
subnet_gateway() {   # first non-default route → its network address + 1 (Docker's gateway convention)
  local h
  h=$(awk 'NR > 1 && $2 != "00000000" { print $2; exit }' /proc/net/route)
  [ -n "$h" ] && printf '%d.%d.%d.%d' "0x${h:6:2}" "0x${h:4:2}" "0x${h:2:2}" "$((0x${h:0:2} + 1))"
}
bridge_in_env() {   # succeeds if any visible process has a host-bridge variable pointing at an existing socket
  local f v
  for f in /proc/[0-9]*/environ; do
    for v in $(tr '\0' '\n' < "$f" 2>/dev/null | sed -n -E 's/^(SSH_AUTH_SOCK|GPG_AGENT_INFO|REMOTE_CONTAINERS_IPC)=(.+)$/\2/p'); do
      [ -S "${v%%:*}" ] && return 0
    done
  done
  return 1
}
GIT_SECRET_RE='https?://[^/@[:space:]]*:[^/@[:space:]]+@|https?://(ghp_|gho_|ghu_|ghs_|github_pat_|glpat-)[^/@[:space:]]*@|extraheader[[:space:]]*=.*(authorization|bearer|basic)|^[[:space:]]*password[[:space:]]*='

privileges() {
  section "privileges (RUN-1)"
  refute "not root (uid $(id -u))" test "$(id -u)" = 0
  check  "runs as 'user'" test "$(id -un)" = user
  check  "no effective capabilities (CapEff=0)" test "$(st CapEff)" = 0000000000000000
  check  "empty capability bounding set (CapBnd=0)" test "$(st CapBnd)" = 0000000000000000
  check  "no-new-privileges (NoNewPrivs=1)" test "$(st NoNewPrivs)" = 1
  check  "seccomp filter active (Seccomp=2)" test "$(st Seccomp)" = 2
  refute "no sudo" command -v sudo
  local aa
  aa=$(cat /proc/self/attr/apparmor/current 2>/dev/null || cat /proc/self/attr/current 2>/dev/null || true)
  case $aa in
    ""|unconfined*) warn "AppArmor: ${aa:-not available} (expected docker-default on AppArmor hosts)" ;;
    *) pass "AppArmor: $aa" ;;
  esac
}

filesystem() {
  section "filesystem (RUN-3, IMG-5)"
  if [ "$MODE" = live ]; then   # never touch a real project, not even its mtime
    check "workspace writable ($WS)" test -w "$WS"
  else
    local f="$WS/.vibe-doctor-$$"
    check "workspace writable ($WS)" sh -c "echo ok > '$f' && grep -qx ok '$f'"
    rm -f "$f"
  fi
  refute "/etc not writable" test -w /etc
  refute "/usr/local not writable" test -w /usr/local
  refute "agent installs not writable (/opt/node)" test -w /opt/node/lib/node_modules
  refute "/opt/vibe not writable" test -w /opt/vibe
  if [ -e /etc/claude-code/managed-settings.json ]; then
    refute "Claude managed policy not writable" test -w /etc/claude-code/managed-settings.json
  fi
  refute "no Docker socket" sh -c 'ls /var/run/docker.sock /run/docker.sock'
}

credentials() {
  section "credentials (CRED-1, CRED-2)"
  # Every process we can see (VS Code's server included, not just this shell): does any of them point
  # at a host bridge socket that still exists?
  refute "no process references a live SSH/GPG/Dev Containers bridge socket" bridge_in_env
  refute "no VS Code SSH-agent bridge sockets" any '/tmp/vscode-ssh-auth-*'
  refute "no Dev Containers IPC bridge sockets" any '/tmp/vscode-remote-containers-ipc-*'
  refute "no GPG agent sockets" any "$HOME/.gnupg/S.gpg-agent*"
  if any '/tmp/vscode-git-*.sock'; then warn "VS Code git askpass socket present (set git.terminalAuthentication=false on the host)"; fi
  check  "no git credential helper" test -z "$(git config --get-all credential.helper 2>/dev/null)"
  refute "no private keys in ~/.ssh" sh -c 'grep -l "PRIVATE KEY" "$HOME"/.ssh/* 2>/dev/null | grep -q .'
}

agents() {
  section "agents (AGT-1)"
  local d name chk out
  for d in /opt/vibe/agents/*/; do
    [ -f "$d/agent.conf" ] || continue
    name=$(basename "$d")
    chk=$( (set +u; . "$d/agent.conf"; printf '%s' "${AGENT_CHECK:-}") )
    if [ -z "$chk" ]; then warn "$name: no AGENT_CHECK"; continue; fi
    if out=$(timeout 60 bash -c "$chk" 2>&1); then pass "$name: $(printf '%s' "$out" | head -n1)"
    else fail "$name: '$chk' failed: $(printf '%s' "$out" | tail -n1)"; fi
  done
}

network() {
  section "network: $NET (NET-1..NET-6)"
  case $NET in
    offline)
      check  "only loopback interface" only_loopback
      refute "outbound HTTPS fails" curl -sS -m 5 -o /dev/null https://example.com
      ;;
    open)
      warn "profile 'open': egress is unrestricted (escape hatch)"
      ;;
    *)
      refute "no default route" default_route
      refute "direct egress fails (bypassing the proxy)" curl -sS -m 5 --noproxy '*' -o /dev/null https://1.1.1.1
      refute "external DNS does not resolve" getent hosts example.com
      check  "proxy reachable (vibe-proxy)" getent hosts vibe-proxy
      local code gw blocked=blocked.vibe-doctor.invalid   # reserved name: can never be allowlisted by accident
      code=$(curl -sS -m 10 -o /dev/null -w '%{http_connect}' "https://$blocked/" 2>/dev/null || true)
      if [ "$code" = 403 ]; then pass "proxy refuses an unlisted host ($blocked → 403)"
      else fail "proxy refuses an unlisted host ($blocked → ${code:-no answer}, expected 403)"; fi
      if [ "$NET" != local ]; then
        refute "host machine not reachable via proxy (host.docker.internal)" curl -fsS -m 5 -o /dev/null http://host.docker.internal/
      fi
      # NET-1: a real service on the host (started by vibe doctor) must not be reachable directly.
      gw=$(subnet_gateway)
      if [ -n "${VIBE_DOCTOR_HOSTPORT:-}" ] && [ -n "$gw" ]; then
        refute "host services not reachable directly (test service on host :$VIBE_DOCTOR_HOSTPORT via $gw)" \
          curl -sS -m 3 --noproxy '*' -o /dev/null "http://$gw:$VIBE_DOCTOR_HOSTPORT/"
      else
        warn "direct host-reachability test skipped (no host test service)"
      fi
      local a=${VIBE_DOCTOR_ALLOWED:-} out
      if [ -z "$a" ]; then
        warn "allowlist is empty for '$NET' (nothing is reachable)"
      elif [ "$NET" = local ] && [ "${a#*:}" != "$a" ]; then   # host:port endpoint: plain HTTP, custom port
        code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "http://$a/" 2>/dev/null || true)
        case $code in
          403) fail "proxy refuses the local endpoint $a (check ~/.vibe/local-endpoints.txt)" ;;
          000|5??) warn "proxy forwards to $a but nothing answers (HTTP $code) — model server running, listening on the docker bridge?" ;;
          *) pass "local endpoint reachable ($a → HTTP $code)" ;;
        esac
      else
        out=$(curl -sS -m 15 -o /dev/null -w '%{http_connect}' "https://${a%%:*}/" 2>/dev/null || true)
        case $out in
          200) pass "allowlisted host reachable through the proxy (${a%%:*})" ;;
          403) fail "proxy refuses an ALLOWLISTED host (${a%%:*} → 403): the generated allowlist is broken" ;;
          *)   warn "allowlisted host not reachable (${a%%:*}, CONNECT ${out:-no answer}) — no internet on the host?" ;;
        esac
      fi
      ;;
  esac
}

mounts() {
  section "mounts (RUN-4, STATE-1)"
  local expected d dst m unexpected cloud
  # Docker's own: /etc/{hosts,hostname,resolv.conf}, and docker-init for --init.
  expected="/etc/hosts /etc/hostname /etc/resolv.conf /usr/sbin/docker-init /sbin/docker-init"
  expected="$expected /home/user /home/user/.vibe-git $WS $WS/.git/config $WS/.git/hooks"
  for d in /opt/vibe/agents/*/; do
    for m in $( (set +u; . "$d/agent.conf"; printf '%s' "${AGENT_STATE:-}") ); do expected="$expected ${m#*:}"; done
  done
  # Every mountpoint of ANY filesystem type (a bind of the host's /run/user/… is tmpfs, too) must be
  # either Docker's standard /, /proc, /sys, /dev tree or in the expected set. mountinfo escapes spaces as \040.
  unexpected=$(awk '{ print $5 }' /proc/self/mountinfo | sed 's/\\040/ /g' | while IFS= read -r m; do
      case $m in /|/proc|/proc/*|/sys|/sys/*|/dev|/dev/*) continue ;; esac
      case " $expected " in *" $m "*) ;; *) printf '%s ' "$m" ;; esac
    done)
  if [ -z "$unexpected" ]; then pass "mounts are only the expected set"; else fail "unexpected mounts: $unexpected"; fi

  if [ "${VIBE_CLOUD_STATE:-yes}" = no ]; then
    for d in /opt/vibe/agents/*/; do
      cloud=$( (set +u; . "$d/agent.conf"; printf '%s' "${AGENT_CLOUD:-}") )
      [ "$cloud" = yes ] || continue
      for m in $( (set +u; . "$d/agent.conf"; printf '%s' "${AGENT_STATE:-}") ); do
        dst=${m#*:}
        refute "$(basename "$d") state not mounted ($dst)" mountpoint -q "$dst"
      done
    done
  fi
}

workspace() {
  section "workspace guard (WS-1)"
  if [ -d "$WS/.git" ]; then
    refute ".git/config read-only" test -w "$WS/.git/config"
    refute ".git/hooks read-only" test -w "$WS/.git/hooks"
    refute "no credentials in .git/config" grep -qiE "$GIT_SECRET_RE" "$WS/.git/config"
  else
    warn "no .git directory in the workspace — nothing to protect yet"
  fi
}

case $MODE in
  image) privileges; filesystem; credentials; agents; network ;;
  net)   network ;;
  live)  privileges; filesystem; credentials; agents; network; mounts; workspace ;;
  *) echo "usage: doctor.sh image|net|live" >&2; exit 2 ;;
esac

echo
if [ "$FAILS" -eq 0 ]; then printf '%s%s: all checks passed%s (%d warning(s))\n' "$G" "$MODE" "$N" "$WARNS"; exit 0
else printf '%s%s: %d check(s) failed%s (%d warning(s))\n' "$R" "$MODE" "$FAILS" "$N" "$WARNS"; exit 1; fi
