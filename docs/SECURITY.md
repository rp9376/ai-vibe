# AI VIBE: security model

What the bubble protects, how, how it's verified, and, as importantly, what it does **not** protect. Requirement IDs refer to [SPEC.md](../SPEC.md).

## Threat model in one paragraph

The adversary is the agent itself: buggy, overeager, or prompt-injected by something it read (code, docs, issues, web pages, dependencies). Assume it runs arbitrary code as the container user. The bubble must keep it away from host files outside the workspace, host credentials, host and LAN services, and anything the host will later execute. Inside the bubble, the workspace and the agent's own credentials are accepted risk.

## Layers

Each layer is independent; `vibe doctor` checks each one.

| Layer | Mechanism | Verified by |
|---|---|---|
| Runtime (RUN-1/2) | non-root `user` (host UID), `--cap-drop=ALL`, `no-new-privileges`, Docker default seccomp + AppArmor, `--init`, PID/memory/CPU limits; no sudo | `vibe doctor`: CapEff/CapBnd = 0, NoNewPrivs = 1, Seccomp = 2, AppArmor profile, no sudo |
| Filesystem (RUN-3/4) | Only the workspace, per-agent state, read-only git identity and a per-project home volume are mounted. No Docker socket, no host home, no definitions | `vibe doctor <dir>`: every mount (any filesystem type) is in the expected set |
| Agent install (IMG-5) | Agents and their policy are root-owned; auto-update disabled | `vibe doctor`: `/opt/node`, `/opt/vibe`, `/etc/claude-code` not writable |
| Network (NET-1..6) | `--internal` + **isolated** Docker network: no route out, and the host has no address on it; per-project tinyproxy with a default-deny allowlist pinned to `host:port` | `vibe doctor`: no default route, direct egress fails, external DNS fails, unlisted host → 403, a real test service on the host is unreachable, listed host reachable |
| Host git (WS-1, WS-4) | `.git/config` and `.git/hooks` bind-mounted read-only; `vibe up` refuses a `.git/config` that contains credentials | `vibe doctor <dir>`: read-only, and no credentials in it |
| Host-trust files (WS-2) | `vibe audit` hashes files the host may execute; `vibe down` reports changes | `vibe audit` |
| Credentials (CRED-1/2) | vibe creates the container, so no editor mounts; host editor settings; `remoteEnv` blanking; post-attach `vibe-scrub`; no ssh/gpg tooling in the image | `vibe doctor <dir>`: no bridge sockets, no process (VS Code's server included) pointing at one, no credential helper, no keys |
| Agent traffic | Agent versions named in each `agent.conf` (`latest` by default, verified pins kept as comments); non-essential traffic off via root-owned managed config (Claude, Codex) and env (opencode) | proxy log (`vibe logs`) |
| Sensitive data (AGT-4, NET-3) | `--net local` / `offline`: no cloud egress at all, and cloud agents' state isn't mounted | `vibe doctor <dir>`: cloud state not mounted, cloud API refused |

## What the bubble does **not** protect

1. **Your workspace (N-8).** The agent can delete or corrupt anything in the project. Git and backups are your undo.
2. **The agent's own credentials (N-2).** `~/.claude/.credentials.json` and `~/.codex/auth.json` are readable by any code running as `user`. The allowlist limits where they could be sent, but not to zero (next point). If you suspect a compromise, revoke the token. For sensitive work use `--net local`, where those credentials aren't mounted.
3. **Exfiltration through allowlisted hosts (NET-7).** Entries are pinned to their port, so this is limited to the exact services listed. Any allowlisted service that accepts writes chosen by an attacker is a channel: github.com (an attacker's repo and token), npm and PyPI (publishing), even the agents' own APIs. Wildcard CDN entries (`.githubusercontent.com`) also allow domain-fronting tricks. There is no TLS inspection (N-7). Keep `agents` lean and use `local`/`offline` for sensitive data.
4. **Things the host runs later (WS-3).** The git guard and `vibe audit` cover the automatic paths: git config/hooks, `.vscode/`, `.devcontainer/`, `.envrc`, `mise.toml`. They do **not** cover build scripts, `package.json` scripts, Makefiles, test suites or binaries the agent produced. Treat the workspace as untrusted input when you run anything from it **on the host**; prefer running it inside the bubble.
5. **Kernel and container escapes.** This is rootful Docker, and your user is in the `docker` group, so a container escape means root on the host. Dropped capabilities, no-new-privileges, seccomp and AppArmor shrink the kernel attack surface, but a namespace container is not a VM. Stronger options are listed under RUN-5: gVisor (`runsc`), rootless Docker/Podman, or a microVM.
6. **The VS Code bridge (EDT-4).** When attached, the VS Code client on your host talks to its server in the container. It is a trusted component. On attach it can create bridge sockets (SSH agent, Dev Containers IPC, GPG, git askpass) that would lead back to host credentials. The host settings from the README stop most of them; `vibe-scrub` removes the rest **after** attach (cleanup, not prevention: sockets can exist briefly and can reappear on reconnect). Always run `vibe doctor <dir>` after attaching and before starting an agent. `vibe shell` never creates these bridges.
7. **Supply chain at build time.** The base image, Node.js (verified against the release's own checksum file, same origin), npm packages and Alpine/tinyproxy are trusted at build. Pin versions in `agent.conf` and `vibe.conf` if you need reproducible builds.

## Inner sandboxes

Agents ship their own sandboxes: Codex runs commands under bubblewrap, and Claude Code has an optional sandbox. They need unprivileged user namespaces inside the container. Measured on Ubuntu 26.04, kernel 7.0, Docker 29.10 (SPEC §14, E-1/E-2), they can't have them:

| Configuration | Result |
|---|---|
| Docker defaults | `unshare` → EPERM (seccomp blocks namespace creation without CAP_SYS_ADMIN) |
| `seccomp=unconfined` | userns created, then mount propagation denied (docker-default AppArmor) |
| `+ apparmor=unconfined` | `uid_map` write → EPERM (host `kernel.apparmor_restrict_unprivileged_userns=1`) |
| Codex 0.170.0 `codex sandbox` in the vibe container | `bwrap: No permissions to create new namespace` |

So by default **the container is the sandbox** (SBX-1). Codex is seeded with `sandbox_mode = "danger-full-access"`, and the vibe-mode aliases skip approvals.

Making inner sandboxes work would take a custom seccomp profile *and* a host AppArmor profile, both host-specific. That's a lot of upkeep for a sandbox inside the sandbox, so it is **not planned** (SBX-2). If you ever need a stronger outer wall, run the bubble under gVisor (`runsc`) or in a VM instead.

## Re-verify after changes (VER-5)

Run `vibe doctor` (and `vibe doctor <dir>` on a live container) after any change to:
- Docker or runc, the kernel, or host AppArmor policy
- the base image (`VIBE_BASE_IMAGE`) or Node major
- agent versions (`vibe build --fresh`, `AGENT_VERSION`)
- network lists, profiles or the proxy
- runtime flags in `vibe`, or anything in `image/`

If the host or versions are new, add an entry to [SPEC.md](../SPEC.md) §14.
