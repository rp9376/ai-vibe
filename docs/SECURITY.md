# AI VIBE: security model

What the bubble protects, how, how it's verified, and, as importantly, what it does **not** protect. Requirement IDs refer to [SPEC.md](../SPEC.md).

## Threat model in one paragraph

The adversary is the agent itself: buggy, overeager, or prompt-injected by something it read (code, docs, issues, web pages, dependencies). Assume it runs arbitrary code as the container user. The bubble must keep it away from host files outside the workspace, host credentials, host and LAN services, and anything the host will later execute. Inside the bubble, the workspace and the agent's own credentials are accepted risk.

## Layers

Each layer is independent; `vibe doctor` checks each one.

| Layer | Mechanism | Verified by |
|---|---|---|
| Runtime (RUN-1/2) | non-root `user` (host UID), `--cap-drop=ALL`, `no-new-privileges`, Docker default seccomp + AppArmor, `--init`, PID/memory/CPU limits; no sudo | `vibe doctor`: CapEff/CapBnd = 0, NoNewPrivs = 1, Seccomp = 2, AppArmor profile, no sudo |
| Filesystem (RUN-3/4) | Only the workspace, per-agent state, read-only git identity and a per-project home volume are mounted. No Docker socket, no host home, no definitions | `vibe doctor <dir>`: host-backed mounts are exactly the expected set |
| Agent install (IMG-5) | Agents and their policy are root-owned; auto-update disabled | `vibe doctor`: `/opt/node`, `/opt/vibe`, `/etc/claude-code` not writable |
| Network (NET-1..6) | `--internal` Docker network (no route out); per-project tinyproxy with default-deny hostname allowlist; CONNECT only to 443 | `vibe doctor`: no default route, direct egress fails, external DNS fails, unlisted host → 403, host machine refused, listed host reachable |
| Host git (WS-1) | `.git/config` and `.git/hooks` bind-mounted read-only | `vibe doctor <dir>`; writes fail with EBUSY / EROFS |
| Host-trust files (WS-2) | `vibe audit` hashes files the host may execute; `vibe down` reports changes | `vibe audit` |
| Credentials (CRED-1/2) | vibe creates the container, so no editor mounts; host editor settings; `remoteEnv` blanking; post-attach `vibe-scrub`; no ssh/gpg tooling in the image | `vibe doctor <dir>`: no bridge sockets, no SSH_AUTH_SOCK, no credential helper, no keys |
| Sensitive data (AGT-4, NET-3) | `--net local` / `offline`: no cloud egress at all, and cloud agents' state isn't mounted | `vibe doctor <dir>`: cloud state not mounted, cloud API refused |

## What the bubble does **not** protect

1. **Your workspace (N-8).** The agent can delete or corrupt anything in the project. Git and backups are your undo.
2. **The agent's own credentials (N-2).** `~/.claude/.credentials.json` and `~/.codex/auth.json` are readable by any code running as `user`. The allowlist limits where they could be sent, but not to zero (next point). If you suspect a compromise, revoke the token. For sensitive work use `--net local`, where those credentials aren't mounted.
3. **Exfiltration through allowlisted hosts (NET-7).** Any allowlisted service that accepts writes chosen by an attacker is a channel: github.com (an attacker's repo and token), npm and PyPI (publishing), even the agents' own APIs. Wildcard CDN entries (`.githubusercontent.com`) also allow domain-fronting tricks. There is no TLS inspection (N-7). Keep `agents` lean and use `local`/`offline` for sensitive data.
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

To enable inner sandboxes later as defence in depth (SBX-2), the work is:
1. A custom seccomp profile: a pinned, minimal diff over Docker's default that allows `clone`/`unshare` with `CLONE_NEWUSER` (argument-matched), `mount`, `umount2` and `pivot_root`. Record the upstream URL, commit and checksum.
2. A custom AppArmor profile loaded on the host (one-time `sudo apparmor_parser`) that allows `userns` and the mounts bubblewrap performs.
3. A vibe config switch that applies both, plus a doctor phase that runs a write-inside / write-outside / no-network test through the agent's sandbox.

Neither profile may add capabilities. Both are host-specific and must be re-verified on every host (VER-5).

## Re-verify after changes (VER-5)

Run `vibe doctor` (and `vibe doctor <dir>` on a live container) after any change to:
- Docker or runc, the kernel, or host AppArmor policy
- the base image (`VIBE_BASE_IMAGE`) or Node major
- agent versions (`vibe build --fresh`, `AGENT_VERSION`)
- network lists, profiles or the proxy
- runtime flags in `vibe`, or anything in `image/`

If the host or versions are new, add an entry to [SPEC.md](../SPEC.md) §14.
