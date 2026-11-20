# AI VIBE — Spec v2

**AI VIBE** (*Valheim Impetus Bubble Environment*): *Impetus* = speed, *Bubble* = safety/isolation, *Environment* = the workspace itself.

- **Status:** v2, 2026-11-19. Replaces v1 ([docs/history/v1-requirements.md](docs/history/v1-requirements.md)). Appendix A maps every v1 requirement to v2.
- **IDs** are `<AREA>-<n>`. They are never renumbered; a removed ID is retired, not reused.
- **MUST** = required for "done". **SHOULD** = expected, may be deferred with a note in §14.

## TL;DR

- **One image, every agent.** Claude Code (primary), Codex, and opencode (local models) live in one image. An agent is a folder in `agents/`: add or remove the folder, rebuild.
- **One CLI.** `vibe up | shell | code | down | doctor | allow | audit`. Works on any folder, with or without a git remote, and never writes into the project.
- **The container is the boundary.** Non-root, zero capabilities, no-new-privileges, Docker's default seccomp + AppArmor, resource limits. Inside it, agents may run fully autonomous ("vibe mode").
- **Egress is allowlisted.** The container sits on an internal, isolated Docker network (no route out, and the host has no address on it); the only way out is a per-project proxy whose allowlist is pinned to `host:port`. Profiles: `agents` (default), `local` (local model only, no cloud credentials), `offline`, `open` (escape hatch).
- **Bubble state is not host state.** Agents keep their own state under `~/.vibe/state/`; the host's `~/.claude` / `~/.codex` are never mounted.
- **The workspace is guarded in both directions.** `.git/config` and `.git/hooks` are read-only inside; `vibe audit` flags changes to files the host might execute.
- **Verifiable.** `vibe doctor` proves the image and network boundary; `vibe doctor <dir>` proves a live container after attach.

---

## 1. Purpose, scope, threat model

**GOAL-1** MUST — Provide a container in which AI coding agents work at full speed, including without per-command approvals, while the host machine, its credentials, and its network are protected from them.

**GOAL-2** MUST — Be simple to operate: one CLI, one config file, one folder per agent. Each routine change (add/remove an agent, allow a domain, change limits, swap the base image) touches one file.

**GOAL-3** — Hosts: Linux (Ubuntu, Docker Engine) MUST; macOS (OrbStack / Docker Desktop) SHOULD. Host-sensitive decisions are recorded in §14.

**GOAL-4** MUST — Shared vs private. *Shared* = this repository (definitions, CLI, docs, `AGENTS.md`). *Private* = everything under `~/.vibe/` (agent state and auth, git identity, personal allowlist, local endpoints, personal config). Each developer builds and runs their own image; nothing private is ever copied into the repo or image.

### Threat model

| | |
|---|---|
| **Adversary** | The agent itself: buggy, overeager, or prompt-injected through code, docs, issues, web pages or dependencies. Assume it runs arbitrary code as the container user. |
| **Protected** | Host files outside the workspace. Host credentials (SSH, GPG, git credential helpers, Docker, cloud CLIs, browser). Host and LAN services. **Host code-execution paths** — anything the host later runs: git hooks/config, editor and devcontainer config, the host's own agent config. |
| **Accepted risk** | Anything inside the bubble: workspace contents (git and backups are the undo), the agent's own credentials (readable by same-user code, N-2), exfiltration through allowlisted domains (reduced, not eliminated — NET-7). |
| **Trusted** | Docker daemon and kernel; this repository; the VS Code client and Dev Containers extension (a bridge that is scrubbed, but trusted); base images and registries at build time. |

## 2. Architecture

```
host
 ├─ vibe CLI ──────────── docker ───────────────────────────┐
 ├─ <project>/ ──────────── bind (rw) ──┐                    │
 └─ ~/.vibe/state/<agent>/ ─ bind ──────┤                    │
                                        ▼                    ▼
   ┌─ internal network: no route to host, LAN or internet ──────────┐
   │  vibe-<project>   user · caps=0 · no-new-privs · limits        │      ┌───────────────┐
   │   /workspaces/<name>      (.git/config, .git/hooks: ro)        │─────▶│ vibe-proxy    │──▶ allowlisted
   │   /home/user              (per-project volume)                 │      │ default deny  │    domains only
   └────────────────────────────────────────────────────────────────┘      └───────────────┘
```

Independent layers, each tested by `vibe doctor`: **RUN** runtime hardening · **WS/STATE** filesystem scope · **NET** egress allowlist · **CRED** credential hygiene · **SBX** optional inner sandboxes.

## 3. CLI (CLI)

**CLI-1** MUST — A single executable `vibe`, depending only on bash and the docker client:

| Command | Does |
|---|---|
| `vibe setup` | One-time: create `~/.vibe/`, seed git identity, print editor settings |
| `vibe build [--fresh]` | Build the image and the proxy image |
| `vibe up [dir] [--net P]` | Create/start the project container (+ network + proxy) |
| `vibe shell [dir] [-- cmd…]` | Interactive shell, or run a command, in the container |
| `vibe code [dir] [--net P]` | `up`, then attach VS Code |
| `vibe down [dir] [--purge]` | Remove container, proxy, network; `--purge` also drops the home volume |
| `vibe ls` | List vibe containers |
| `vibe doctor [dir]` | Verification (§12) |
| `vibe allow <domain>` | Add a personal allowlist entry; reload running proxies |
| `vibe logs [dir]` | Proxy log (shows blocked requests) |
| `vibe audit [dir] [--accept]` | Report changes to host-trust files (§9) |

**CLI-2** MUST — Any directory can be opened. No registration step, no git remote required. vibe never writes into the project; the single exception is creating an empty `.git/hooks/` when a repository lacks one (so it can be protected, WS-1).

**CLI-3** MUST — One container per absolute project path, named `vibe-<basename>-<first 8 hex of sha256(path)>`, with the project mounted at `/workspaces/<basename>`. Same basename at different paths never merges.

**CLI-4** MUST — Configuration is `vibe.conf` (shared defaults, in the repo) overridden by `~/.vibe/config` (personal, same syntax): image names, base image, Node major, default network profile, CPU/memory/PID limits, extra VS Code extensions, host-trust paths.

**CLI-5** SHOULD — Idempotent and self-explaining: re-running `up` is safe; if the requested profile differs from the running container's, vibe recreates it (state and home volume kept); if the image is newer than the container, vibe says so.

**CLI-6** SHOULD — Terminal-first: everything works without VS Code (`vibe shell` → `claude`). VS Code is an optional front-end.

## 4. Image (IMG)

**IMG-1** MUST — Exactly one image (`vibe:latest`) for all agents, built locally from this repo. No per-agent, per-project or per-developer forks.

**IMG-2** MUST — The base is a build argument (default `ubuntu:22.04`). Swapping it is one line in `vibe.conf` and nothing else; Debian/Ubuntu-family bases are supported. A swap triggers re-verification (VER-5).

**IMG-3** MUST — Contents: Node.js (official build, checksum-verified, major version from config; skippable when the base already has Node), git, curl, ripgrep, jq, python3 + pip + venv, bubblewrap (for SBX), and the enabled agents. **No** sudo, no SSH or GPG agent tooling.

**IMG-4** MUST — Non-root user `user` whose UID/GID equal the host user's (build args, so bind-mounted files keep sane ownership). A conflicting user in the base (e.g. `ubuntu`, UID 1000, on 24.04 bases) is removed.

**IMG-5** MUST — Agent installs and agent policy files are root-owned, so agents cannot modify their own installation or policy. Agent auto-updaters are disabled; updating = `vibe build`.

**IMG-6** MUST — User-space installs work without root: `npm i -g` → `~/.local`, `pip install --user`, venvs. `~/.local/bin` is on `PATH`. (Dependencies the image should always have go in the image; ad-hoc ones the agent may install itself.)

**IMG-7** SHOULD — Build info (resolved Node and agent versions) is recorded at `/opt/vibe/build-info`.

## 5. Agents (AGT)

**AGT-1** MUST — An agent is a folder `agents/<name>/`:

| File | Purpose |
|---|---|
| `agent.conf` | `AGENT_ENABLED`, `AGENT_VERSION`, `AGENT_CLOUD` (yes/no), `AGENT_STATE` (state mounts), `AGENT_ENV`, `AGENT_EXTENSIONS`, `AGENT_INSTRUCTIONS` (optional: image path that receives a copy of AGENTS.md), `AGENT_CHECK` |
| `install.sh` | Build time, as root |
| `init.sh` *(optional)* | Container start, as `user` (seed config, link instructions) |
| `domains.txt` *(optional)* | Egress the agent needs (used by the `agents` profile) |
| `rootfs/` *(optional)* | Files copied into the image (managed policy, shell aliases) |

Adding an agent = new folder + `vibe build`. Removing = delete the folder or set `AGENT_ENABLED=no`, then rebuild. No other file changes.

**AGT-2** MUST — **Claude Code is primary.** Installed at a configurable version; state at `~/.vibe/state/claude` mounted as `~/.claude` with `CLAUDE_CONFIG_DIR` set (so `.claude.json` persists too); sign-in works inside the container; managed policy in `/etc/claude-code/` (root-owned).

**AGT-3** MUST — **Codex CLI** supported: state at `~/.vibe/state/codex` mounted as `~/.codex`; sign-in works from inside a container (device code or API key).

**AGT-4** MUST — **Local-only harness (opencode V2, npm `@opencode/cli`)** for sensitive data: `AGENT_CLOUD=no`. It is local-only by enforcement, not convention: (a) a root-owned managed config (`/etc/opencode/opencode.json`) enables only the provider named `local`, which user and project configs cannot widen (E-4); (b) a start guard refuses to run outside the `local`/`offline` profiles; (c) the cloud model catalog fetch and self-update are disabled. The endpoint and models of `local` are per-developer config in its state directory (never baked into the image). Under `local` it can reach only the declared local endpoints, and no cloud agent state is mounted. Documented as the recommended path for sensitive data.

**AGT-5** MUST — **Instructions.** One shared [image/AGENTS.md](image/AGENTS.md), installed at `/opt/vibe/AGENTS.md`, tells agents about the bubble. Each agent loads it through its *global* instruction mechanism — Claude: the build copies `AGENTS.md` to `/etc/claude-code/CLAUDE.md` (its managed instructions; D-8); Codex/opencode: a symlink in their global config directory, created by `init.sh`. Projects are never modified; a project's own `AGENTS.md`/`CLAUDE.md` still applies on top.

**AGT-7** MUST — Each `agent.conf` names its version: `latest` (the default, D-13) or an exact pin; the last verified pin stays in the file as a comment so re-pinning is one line. Each agent's non-essential traffic (telemetry, error reporting, self-update, cloud catalogs) is switched off where the pinned version supports it, preferably through root-owned managed config the agent cannot override. The switches are verified against the installed version and recorded in §14; re-verify after a `vibe build --fresh` brings new versions.

**AGT-6** SHOULD — Each agent offers a vibe-mode alias (no per-command approvals), e.g. `claude-vibe`, `codex-vibe`. Approval-free mode is acceptable *here* because RUN, NET and WS hold regardless of the agent's own settings.

## 6. Runtime hardening (RUN)

**RUN-1** MUST — Every vibe container runs with `--cap-drop=ALL`, `--security-opt no-new-privileges`, Docker's **default** seccomp and AppArmor profiles (never `unconfined`), a non-root user, and `--init`.

**RUN-2** MUST — PID, memory and CPU limits (defaults in `vibe.conf`) so a runaway agent cannot freeze the host.

**RUN-3** MUST — No Docker socket, no definitions directory, no host home is mounted. The docker client reads definition files on the host and sends content to the daemon.

**RUN-4** MUST — Host-backed mounts are exactly: the workspace (rw), `.git/config` and `.git/hooks` (ro overlays), per-agent state directories (per profile, STATE-1), git identity (ro), and the per-project home volume. (Docker's own `/etc/hosts`, `/etc/hostname`, `/etc/resolv.conf` excepted.)

**RUN-5** SHOULD *(phase 2)* — A stronger runtime (gVisor `runsc`, rootless Docker/Podman, or a microVM) can be selected by config without other changes.

## 7. Network (NET)

**NET-1** MUST — A container on a filtered profile attaches only to a per-project Docker network that is `--internal` (no route to LAN or internet) **and isolated** (`gateway_mode_ipv4=isolated`, or `inhibit_ipv4` on older Docker): the host has no address on it, so host services are unreachable even when they listen on all interfaces (E-8). Its only egress is a per-project proxy container that sits on that network (alias `vibe-proxy`) and on the default bridge.

**NET-2** MUST — The proxy enforces an allowlist, default deny, **pinned to `host:port`**: an entry `host` allows HTTPS to `host:443` only, `.host` adds subdomains, `host:port` allows exactly that port for HTTPS (`CONNECT`) or plain HTTP (D-11). It runs hardened: non-root, caps dropped, read-only root, limits.

**NET-3** MUST — Profiles, chosen per container at `up` time; each filtered profile is a file in `net/profiles/` listing which domain lists it allows (custom profiles may be added):

| Profile | Allows | Cloud agent state |
|---|---|---|
| `agents` *(default)* | `agents/*/domains.txt` + `net/lists/vscode.txt` + `net/lists/registries.txt` + personal `~/.vibe/allow.txt` | mounted |
| `local` | only the `host:port` entries in `~/.vibe/local-endpoints.txt` | **not** mounted |
| `offline` | nothing (`--network none`) | **not** mounted |
| `open` | everything (plain bridge) — escape hatch, loud warning, never default | mounted |

**NET-4** MUST — Proxy variables (`HTTP_PROXY`, `HTTPS_PROXY`, lower-case variants, `NO_PROXY=localhost,127.0.0.1,::1`) are set in the container. Tools that ignore them fail closed (no route), never open.

**NET-5** MUST — `vibe allow <domain>` adds a personal entry and reloads running proxies without restarting dev containers; `vibe up` on a running project reloads its proxy when the generated allowlist changed; `vibe logs` shows what was blocked. "The agent can't reach X" is fixed with one command.

**NET-6** MUST — Host services are reachable only when explicitly allowlisted (e.g. `host.docker.internal` for a local model server, in `local-endpoints.txt`).

**NET-7** — Documented limits: an allowlist reduces exfiltration but does not eliminate it — any allowlisted service that accepts attacker-chosen writes (package registries, GitHub) is a channel. No TLS interception (N-7). External DNS does not resolve inside filtered containers (E-3). For sensitive data use `local` or `offline`.

## 8. State and identity (STATE)

**STATE-1** MUST — Each agent's state lives in `~/.vibe/state/<agent>/` on the host, is mounted at the agent's expected path, and survives container recreation. This is the **bubble's own** state: the host's `~/.claude`, `~/.codex`, etc. are never mounted, because host agent config (hooks, MCP server commands) is a host code-execution path.

**STATE-2** MUST — One state per developer, shared by all of that developer's project containers. Same-OS (Linux↔Linux) mounts need no SQLite split. On macOS hosts, lock semantics MUST be verified and recorded in §14.

**STATE-3** MUST — vibe creates missing host state directories as the host user before mounting, so Docker never creates root-owned directories on the host.

**STATE-4** MUST — Git identity is private: `~/.vibe/state/git/identity` (mode 0600, `[user] name/email`) is included by the image's `/etc/gitconfig` and mounted read-only. Repository-local identity wins. `vibe setup` seeds it from the host's `user.name`/`user.email` only.

**STATE-5** MUST — Git works inside for commit, branch, diff and log. Push/pull to remotes happens on the host; no remote credentials exist inside.

**STATE-6** MUST — A per-project volume at `/home/user` keeps user-space tools, shell history and the editor server across recreation; `vibe down --purge` removes it.

## 9. Workspace guard (WS)

**WS-1** MUST — `.git/config` and `.git/hooks` are bind-mounted **read-only** over the workspace. This blocks `core.fsmonitor`, `core.hooksPath`, filter drivers and hooks that would otherwise run in the host's git. If `.git` is missing, or is a file (worktree/submodule), vibe warns that git is unprotected.

**WS-2** MUST — `vibe audit` compares host-trust paths (default: `.devcontainer/`, `.devcontainer.json`, `.vscode/`, `.envrc`, `.git/config`, `.git/hooks/`, `.gitattributes`, `.gitmodules`, `mise.toml`, `.mise.toml`, `.tool-versions`; configurable) with a baseline taken at the project's first `up`. `--accept` updates the baseline. `vibe down` runs the audit automatically.

**WS-4** MUST — `vibe up` refuses to create a container when the project's `.git/config` contains credentials (userinfo in a remote URL, a token-shaped user, an `extraheader` authorization, a `password`): the agent could read them through the read-only mount and push with them. The warning shows the lines redacted. The live doctor checks the same.

**WS-3** — Documented rule: after a vibe session, treat the workspace as untrusted input for anything the *host* executes (build scripts, `package.json` scripts, Makefiles). Open it on the host only after `vibe audit` is clean or reviewed.

## 10. Editor integration (EDT)

**EDT-1** MUST — `vibe code` creates the container through vibe (not "Reopen in Container") and attaches VS Code to it, so the editor cannot add mounts or sockets at creation time. No per-repo `devcontainer.json`, no repository-configuration-path registration.

**EDT-2** MUST — A `devcontainer.metadata` label on the container sets `remoteUser`, the extensions (from enabled agents + config), `remoteEnv` blanking `SSH_AUTH_SOCK`, `GPG_AGENT_INFO` and `REMOTE_CONTAINERS_IPC`, and a `postAttachCommand` that runs `vibe-scrub`.

**EDT-3** MUST — Host VS Code settings disable git-config copying and credential helpers; `vibe setup` prints the exact keys and the README lists them.

**EDT-4** MUST — `vibe-scrub` removes the optional bridge sockets VS Code creates on attach (SSH-agent proxy, Dev Containers IPC, forwarded GPG sockets) and touches no other sockets. It is **cleanup, not prevention**: sockets may exist transiently during attach and can reappear on reconnect, so `vibe doctor <dir>` is the proof. Convenience features that use these bridges stop working, by design.

## 11. Credentials (CRED)

**CRED-1** MUST — No host SSH, GPG, git-credential, Docker or cloud credential material enters the container, defended in at least two independent layers: (a) vibe owns container creation, so no credential mounts or sockets exist at creation; (b) host editor settings (EDT-3); (c) `remoteEnv` blanking (EDT-2); (d) post-attach scrub (EDT-4); (e) no ssh/gpg agent tooling in the image (IMG-3).

**CRED-2** MUST — Live checks confirm the absence of: bridge sockets; any visible process (VS Code's server included, not just the doctor's own shell) whose `SSH_AUTH_SOCK`/`GPG_AGENT_INFO`/`REMOTE_CONTAINERS_IPC` points at an existing socket; credential helpers in effective git config; keys in `~/.ssh`.

## 12. Verification (VER)

**VER-1** MUST — `vibe doctor` (no argument) verifies the image with `--pull=never`, no host mounts, and the test script piped in via stdin (never baked in or mounted). Phase 1 runs with `--network none`; phase 2 on a throwaway internal network + proxy using the `agents` profile.

**VER-2** MUST — Assertions: non-root UID; `CapEff` and `CapBnd` zero; `NoNewPrivs: 1`; seccomp filtering active; no sudo; workspace writable; system directories and agent policy not writable; no Docker socket; each enabled agent's `AGENT_CHECK` succeeds. Offline: no egress. Filtered: no default route, direct egress fails, external DNS does not resolve, a reserved unlisted name (`blocked.vibe-doctor.invalid`) is refused by the proxy, **a throwaway test service listening on all host interfaces is not reachable directly**, an allowlisted host is reachable (a proxy 403 there is a FAIL; no answer is a warning, since it needs internet).

**VER-3** MUST — `vibe doctor <dir>` runs the same assertions in the live project container, plus: every mount, of any filesystem type, is in RUN-4's set (or Docker's standard `/proc`, `/sys`, `/dev` tree), `.git/config` and `.git/hooks` are read-only, cloud state is absent under `local`/`offline`, and CRED-2. Run after every (re)attach, before starting agents in VS Code.

**VER-4** MUST — Non-zero exit status on any failure; output names every check.

**VER-5** MUST — Re-run after any change to: Docker/runc, kernel or AppArmor policy, base image, agent versions, network lists or proxy, or the runtime flags in `vibe`. New environments are recorded in §14.

## 13. Inner sandboxes (SBX) — not planned

**SBX-1** SHOULD — Agents' own sandboxes (Codex's Linux sandbox, Claude Code's sandbox) are defence in depth, not the boundary. The default configuration relies on RUN, NET and WS.

**SBX-2** — **Not planned** (too much host-specific upkeep for a sandbox inside the sandbox; a stronger outer runtime, RUN-5, is the better upgrade). Would require: a custom seccomp profile that is a minimal, pinned diff over Docker's default (provenance: source URL, commit, checksum; only the syscalls nested user/mount namespaces need, matched by argument where possible), plus a custom AppArmor profile on hosts that restrict unprivileged user namespaces. No capabilities added.

**SBX-3** — Known blocker: see §14 entry E-1.

## 14. Decision log and tested environments

| ID | Date | Entry |
|---|---|---|
| E-1 | 2026-11-19 | **Ubuntu 26.04.1, kernel 7.0.0-43, Docker 29.10.0 (runc 1.5.3, rootful), `kernel.apparmor_restrict_unprivileged_userns=1`.** Nested user+mount namespaces inside a container (what bubblewrap needs) fail at every step: Docker defaults → `unshare` EPERM (seccomp); `seccomp=unconfined` → mount propagation denied (docker-default AppArmor); `+ apparmor=unconfined` → `uid_map` write EPERM (host userns restriction). A seccomp profile alone (v1 R-012/R-013) cannot work on this host. ⇒ SBX deferred; the container is the boundary. |
| D-1 | 2026-11-19 | vibe creates containers; VS Code attaches. Over "Reopen in Container": no editor-injected mounts/sockets at creation, works without a git remote, works from a terminal. |
| D-2 | 2026-11-19 | Dedicated bubble state instead of sharing the host's agent state. Host agent config is a host code-execution path; also removes v1's double mount and SQLite split. |
| D-3 | 2026-11-19 | Egress proxy sidecar instead of in-container iptables (which needs `NET_ADMIN`, contradicting RUN-1). |
| D-4 | 2026-11-19 | tinyproxy as the proxy: small, hostname-regex allowlist, plain config. Replaceable by anything satisfying NET-2. |
| D-5 | 2026-11-19 | Docker default seccomp instead of a custom profile while SBX is off: nothing in the default configuration needs extra syscalls. |
| E-2 | 2026-11-19 | Codex 0.170.0's Linux sandbox is bubblewrap; inside the vibe container it fails with `bwrap: No permissions to create new namespace` (consequence of E-1). |
| D-6 | 2026-11-19 | Codex is seeded with `sandbox_mode = "danger-full-access"` (its own sandbox can't start, E-2; the container is the boundary). Seeded once into private state; the developer may change it. |
| E-3 | 2026-11-19 | Docker internal networks do not resolve external names through the embedded DNS (verified by `vibe doctor`), so DNS is not an exfiltration path under filtered profiles. |
| D-7 | 2026-11-19 | Agent and VS Code mountpoints are pre-created in the image owned by `user`, so switching profiles never leaves root-owned directories in the home volume. |
| D-8 | 2026-11-19 | Claude's managed `CLAUDE.md` gets a build-time **copy** of `AGENTS.md` instead of an `@/opt/vibe/AGENTS.md` import: Claude Code asks for approval before following imports outside the project, so the briefing didn't load until a human approved it. `image/AGENTS.md` remains the single source. |
| E-4 | 2026-11-19 | opencode 1.19.6 reads a managed config from `/etc/opencode/opencode.json` after user and project configs; with `enabled_providers: ["local"]` there, `opencode models` lists only `local/…` even when user and project configs enable `anthropic`/`openai` and API keys are set. Without it, opencode exposes a built-in cloud model list even with the models.dev fetch disabled. |
| E-5 | 2026-11-19 | opencode's `@ai-sdk/openai-compatible` provider is bundled: a full `opencode run` round-trip against a mock OpenAI-compatible server succeeded with `--network none`. No npm fetch is needed under `local`. |
| D-9 | 2026-11-19 | opencode is enforced local-only (AGT-4): managed provider allowlist + start guard (wrapper replacing the `opencode` bin) + `OPENCODE_DISABLE_MODELS_FETCH`/`_AUTOUPDATE`/`_CLAUDE_CODE`. The guard is a guardrail; the network profile is the wall. |
| E-6 | 2026-11-20 | **opencode 2.3.2** (`@opencode/cli`, same publisher as `opencode-ai`, SLSA provenance; npm `opencode2` is a security placeholder, not the real package): the managed `/etc/opencode/opencode.json` `enabled_providers: ["local"]` blocks other providers (control: with it hidden, a provider named `other` answers; with it, "Model unavailable"); the provider package (`aisdk:@ai-sdk/openai-compatible` or `@opencode/ai/providers/openai-compatible`) is bundled, so a full run works with `--network none` and through the `local` proxy with npm blocked (V1's runtime `@opencode-ai/plugin` install does not occur). `opencode run` reads stdin when it isn't a terminal: scripts must pass `< /dev/null`. |
| E-7 | 2026-11-20 | Non-essential-traffic switches present in the pinned versions: Claude Code 2.1.328 has `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING`, `DISABLE_BUG_COMMAND` (not `DISABLE_NON_ESSENTIAL_MODEL_CALLS` or `DISABLE_STATSIG`); Codex 0.170.0 reads `/etc/codex/managed_config.toml` and has `[analytics] enabled = false`; opencode 2.3.2 has `OPENCODE_DISABLE_MODELS_FETCH`, `_FREE_MODELS`, `_AUTOUPDATE`, `_CLAUDE_CODE`. |
| E-8 | 2026-11-20 | **Found by external review, confirmed:** on a plain `--internal` network the host owns the gateway address, so a container reached a host service bound to `0.0.0.0` directly, bypassing the proxy (the doctor only tested the host *through* the proxy). Fixed by isolated networks (NET-1); the doctor now runs a real test service on the host and must fail to reach it (verified to FAIL on an old-style network). |
| D-10 | 2026-11-20 | Isolation via Docker's network option instead of host `iptables` rules: no `sudo`, nothing to persist or clean up on the host. |
| D-11 | 2026-11-20 | Port pinning via tinyproxy `FilterURLs On` (rules see `host:port` for CONNECT and `http://host:port/…` for HTTP); `ConnectPort` is no longer needed. |
| D-12 | 2026-11-20 | The opencode seed config keeps the owner's permission policy but **allows** `git add`/`git commit` (bubble instructions ask agents to commit often; push is impossible from inside anyway). |
| D-13 | 2026-11-20 | Owner's choice: agents track `latest` instead of exact pins (pins kept as comments). Trade-off accepted: builds on different days can differ, and a renamed switch would silently stop working. Mitigation: re-check switches after `--fresh` builds. Same day, the switches were confirmed present in Claude Code 2.1.329 and Codex 0.171.0. |
| V-2 | 2026-11-20 | Re-verified on E-1's host with the review fixes: `vibe doctor` passes both phases; live doctor passes under `agents` and `local`; `local` round-trip with opencode 2.3.2 through the proxy against a mock model on the host; port pinning (listed port 200, next port 403, cloud API 403); `.git/config` with a token is refused; shellcheck clean. |
| V-1 | 2026-11-19 | **Verified on E-1's host.** Images: `ubuntu:22.04` + Node 24.22.3, Claude Code 2.1.328, Codex 0.170.0, opencode 1.19.6; proxy `alpine:3.22` + tinyproxy 1.11.2. `vibe doctor` passes (34 checks). Acceptance: **1, 2, 3, 4, 9, 10, 11 pass**; 3 includes `up → doctor → down` leaving the tree identical (names, sizes, mtimes, modes). **Not yet verified:** 5 (VS Code attach; Dev Containers extension not installed on this host), 6–7 (agent sign-in round-trips), 8 (local-model round-trip; no model server running; proxy forwarding to the endpoint verified), 12 (docs reviewed by a second person). |

## 15. Non-goals

- **N-1** Running agents on the host.
- **N-2** Hiding container-readable files (including agent credentials) from same-user code.
- **N-3** Syncing conversations between host agents and bubble agents.
- **N-4** Agent memory policy (governed by each agent's own controls).
- **N-5** Changing or requiring changes to the host's git or SSH setup.
- **N-6** Baking model endpoints or weights into the image.
- **N-7** TLS interception or content inspection of allowed traffic.
- **N-8** Protecting workspace contents from the agent (git and backups are the undo).

## 16. Acceptance (definition of done)

1. `vibe build` on a fresh host produces both images from this repo alone.
2. `vibe doctor` passes both phases.
3. `vibe up` on a folder with no git remote works; the project's working tree is byte-identical afterwards.
4. `vibe doctor <dir>` passes for a live container under `agents` and under `local`.
5. `vibe code <dir>` attaches VS Code with the agent extensions running in the container; `vibe doctor <dir>` passes after attach.
6. Claude Code: sign-in and an edit/build round-trip in vibe mode; auth survives `vibe down && vibe up`.
7. Codex: sign-in and an edit/build round-trip.
8. opencode: a round-trip against a local model under `local`, with no cloud agent state mounted.
9. Adding an agent folder + `vibe build` makes it available with no other file edits; disabling it removes it.
10. `vibe logs` shows a blocked domain; `vibe allow` unblocks it without restarting the dev container.
11. An agent's change to `.vscode/tasks.json` is reported by `vibe audit`; writes to `.git/config` and `.git/hooks` fail inside.
12. Docs are current; §14 lists the environment the above was verified on.

## 17. Documentation (DOC)

**DOC-1** MUST — [README.md](README.md): setup, daily use, adding agents, local models, sign-in, troubleshooting. [docs/SECURITY.md](docs/SECURITY.md): threat model, layers, what is *not* protected (N-2, NET-7, WS-3), the VS Code bridge statement (EDT-4), re-verification triggers (VER-5), inner-sandbox notes.

**DOC-2** MUST — Version- or host-sensitive findings go in §14 with the exact environment.

---

## Appendix A — v1 → v2 mapping

| v1 | v2 | Change |
|---|---|---|
| R-001, R-035, R-036, R-037 | GOAL-1, AGT-1–3, IMG-1 | Kept; agents become plug-in folders |
| R-002 | GOAL-3 | Linux MUST, macOS SHOULD |
| R-003, R-030, R-031 | CLI-2, CLI-3 | **Replaced**: no registration or symlinks; any folder works, no git remote needed |
| R-004, R-032 | GOAL-4 | Kept; private root is `~/.vibe/` |
| R-005 | CLI-1, EDT-1 | **Reversed**: a launcher (`vibe`) owns container creation; VS Code attaches |
| R-006 | IMG-4 | Kept; UID follows the host user |
| R-007 | CLI-3 | Kept |
| R-008 | RUN-1 | Kept, except the custom seccomp profile moves to SBX-2 (D-5) |
| R-009, R-041 | IMG-2, IMG-3, IMG-6 | Kept; base is one config line; user-space installs allowed |
| R-010 | IMG-3 | Kept (bubblewrap stays for SBX) |
| R-011 | — | Deferred to the toolchain base swap |
| R-012 – R-016 | SBX-1–3 | **Demoted** to optional phase 2 (E-1). R-016 reversed: the container is the default boundary |
| R-017 – R-019 | VER-1–5 | Kept; extended to network and live checks; covers every agent, not only Codex |
| R-020 – R-022 | CRED-1, CRED-2, EDT-2–4 | Kept; vibe-owned creation removes most bridges at the source |
| R-023 | RUN-3 | Kept |
| R-024, R-025, R-026 | STATE-1, STATE-2 | **Replaced**: dedicated bubble state; no double mount, no SQLite split (D-2) |
| R-027, R-028 | STATE-4, STATE-5 | Kept |
| R-029 | EDT-2 | Kept; extensions come from agent folders |
| R-033, R-034 | DOC-1, DOC-2 | Simplified to README + SECURITY |
| R-038 | AGT-4, NET-3 | Kept; the `local` profile makes "no cloud egress path" true |
| R-039 | AGT-5 | Kept; via global instruction locations, projects untouched |
| R-040 | GOAL-1, NET-1 | Kept; now enforced by the network layer |
| — | NET-\*, WS-\*, RUN-2, RUN-4, STATE-1, STATE-6 | **New** (gaps found in the v1 review) |
