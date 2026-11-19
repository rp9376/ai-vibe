# AI VIBE — Rebuild Requirements

Specification for reconstructing the VIBE-container setup (the `codex-dev` definitions) from scratch. This document states **how the system must work and what it must support**; it is intentionally implementation-agnostic (any set of files, scripts, or tooling that satisfies these requirements is acceptable). Requirement IDs are stable so gaps can be tracked: `R<n>` is a MUST (mandatory), `S<n>` is a SHOULD (important but negotiable). The product vision and naming from [README.md](README.md) — **AI VIBE (Valheim Impetus Bubble Environment)**: *Impetus* = speed, *Bubble* = safety/isolation, *Environment* = the workspace itself — is incorporated into §1 and §2; where the vision is broader than the current implementation, the requirement says so explicitly.

## TL;DR

A set of shared definitions that spins up a **hardened, non-root Docker container** (via native VS Code Dev Containers) so a developer can attach and use AI coding agents **without worrying the agent touches the rest of the machine or network**:

- **AI agents, Claude Code primary.** Claude Code is the primary agent and must be fully supported; Codex CLI + the Codex VS Code extension are supported alongside. **One single image/container type supports all agent harnesses** — no per-agent forks. For **sensitive data** there is a third, **local-only harness** (e.g. opencode): it talks only to locally hosted model endpoints, stores no cloud credentials, and is the recommended no-cloud path.
- **Agent sandbox on.** Codex's internal Bubblewrap sandbox is fixed by a pinned, minimal-diff seccomp profile over the Docker default; the container is hardened at the runtime level (`--cap-drop=ALL`, no-new-privileges).
- **Isolating the machine from the agent.** Only the workspace and each agent's own state directory are mounted in; host SSH/GPG/Git/Docker credentials never enter the container (defended in at least two independent layers, with explicit counters for known tooling leaks and a post-attach bridge cleanup).
- **State lives on the host.** Each agent's state directory (e.g. `~/.codex`) is the single authoritative store, mounted in so config/auth/sessions survive container recreation; per-developer Git identity and SQLite indexes are carved out as private/per-runtime exceptions.
- **One definition, every project.** A single shared `devcontainer.json` serves all checkouts via a per-repo symlink from `git origin`; projects are never modified. The image is self-contained ("include all dependencies"); every developer builds and runs **their own local** image and container — only the definitions are shared.
- **Verifiable offline.** One command runs a no-mount, no-network smoke container asserting caps, NoNewPrivs, write boundaries, and network denial — re-run after every runtime/image/agent/policy update.
- **Shared** = definitions, profiles, scripts, docs, `AGENTS.md`. **Private** = agent state, auth, Git identity, editor-settings edits. Never shared, never copied.

---

## 1. Purpose and scope

R-001 The system provides a shared, reproducible Linux development environment ("the bubble") in which **AI coding agents** — **Claude Code (the primary agent)** and the **OpenAI Codex CLI** / **Codex VS Code extension** (`openai.chatgpt`) — operate with their built-in command sandboxing enabled wherever such a sandbox exists.

R-002 The target hosts are **macOS** (OrbStack Docker) and **Linux** (Ubuntu). The design MUST work on any host where the Docker daemon, VS Code, and the Dev Containers extension are available; architecture- or host-sensitive choices MUST be recorded and re-reviewed for new targets.

R-003 One shared configuration serves **any number of project checkouts**; adding a project MUST NOT modify the project's own files (no in-repo devcontainer config required).

R-004 Each developer builds their own image and owns their own private state. Everything shared between developers is limited to the definitions (image definition, configuration, profiles, scripts, docs).

R-040 **Isolation direction.** The primary isolation goal is protecting **the rest of the machine and the network from the AI agent** (not only the agent from the machine). All agent commands MUST execute inside the container; by default the agent must be unable to reach host files or the host network. Host mounts are limited to the opened workspace and the agents' own state directories.

## 2. AI agent support

R-035 **Claude Code is the primary citizen** of the environment. It MUST be fully supported: installed in the image at a build-time-controllable version, its host state directory mounted the same way as other agents' state (§7), authentication/sign-in working inside the container, and its commands running under the same hardened runtime (§3) with the same credential isolation (§6).

R-036 **Codex support is retained**: Codex CLI and the `openai.chatgpt` VS Code extension with the internal Bubblewrap sandbox enabled (§4). Both agents MUST behave consistently under the hardening and isolation requirements.

R-037 **Single image, all agents.** There is exactly **one image and one container type that supports all agent harnesses** (Claude Code, Codex, and any later-added agent). All supported agents are installed in that one image; per-project, per-developer, or per-agent forks of the image/definition are not allowed. Adding a new agent is done by extending the shared definitions and rebuilding the same image.

R-038 **Local-only harness for sensitive data (no-cloud mode).** Claude Code and Codex are cloud-connected agents (OpenAI/Anthropic APIs) and are *not* the local-model path. Instead, strict local operation is provided by a **dedicated local-model harness — e.g. opencode** — whose model access is restricted to **locally hosted model endpoints only**:
  - it MUST NOT require or store cloud-provider credentials,
  - the model endpoint MUST be configurable per developer (per-developer state, never baked into the image),
  - its model traffic MUST be limited to the developer-specified local endpoint (no cloud egress path exists to fall back onto),
  - it is still installed in the single shared image per R-037.
  The documentation MUST describe how to point this harness at a local model and MUST identify it as the recommended agent for sensitive data.

R-039 **Instruction files.** The environment MUST provide an **`AGENTS.md`** as the single source of truth for shared agent instructions, plus a **`CLAUDE.md`** whose only job is to *point to* `AGENTS.md` (no duplicated instructions). How these files reach agents and projects (e.g. global rules directories vs. per-project copies) MUST be documented.

## 3. Runtime model

R-005 The environment is a **Docker container** managed by the standard **VS Code Dev Containers** workflow (native "Reopen in Container"); no dedicated editor instance, launcher script, or custom host environment variable is required.

R-006 The container MUST run as a **dedicated non-root user** (convention: `user`, UID 1000). All workspaces, tools, and state directories the agent needs MUST be writable by that user.

R-007 The opened local folder is bind-mounted at a **deterministic container path derived from the folder basename** (no generated identifiers). One container is managed per local workspace; identical folder names in different host paths MUST NOT be merged.

R-008 The container is **hardened at the runtime level**, not just by configuration:
  - all capabilities dropped (`--cap-drop=ALL`),
  - `no-new-privileges` enabled,
  - a **custom seccomp profile** applied.
  Verification MUST confirm zero effective capabilities and `NoNewPrivs: 1` inside the container.

R-009 The image MUST be built on the **stock Ubuntu 22.04** base (or its derivative), on top of which a minimal layer is added: a pinned or current **Node.js runtime**, **npm/npx**, and the supported agents installed globally at build-time-controllable versions. The stock base MUST be swappable, without changing any other image layer, for a richer internally maintained toolchain base of the **same Ubuntu version** (build toolchains, package managers, e.g. vcpkg tree); such a swap MUST trigger the R-019 re-verification.

R-010 The image MUST include **Bubblewrap** and its shared-library dependencies, because Codex's command sandbox depends on it at runtime.

R-011 Wherever the image carries a vcpkg tree (i.e. the toolchain base of R-009 is in use), its **dependency cache** MUST be user-writable so non-root builds can create and reuse cached binaries; newly created cache directories MUST inherit correct ownership.

R-041 **Self-contained ("include all dependencies").** The image MUST be self-contained: every tool and library needed to write, build, and test the target project classes is present at attach time. A developer must never need to install packages, fetch toolchains, or adjust host configuration before the first agent round-trip; dependency updates happen by rebuilding the image, not by patching containers.

## 4. Agent sandbox (inner layer)

This section is stated for the Codex implementation (Bubblewrap); the same guarantees (sandboxed execution, workspace-write boundary, no default egress) are expected of every supported agent's sandboxing mechanism, and the runtime hardening of §3 applies to all of them regardless.

R-012 Codex CLI MUST be able to run agent commands in its **internal Bubblewrap sandbox** (nested user + mount namespaces) inside the container. If the default Docker seccomp policy blocks this, a **custom seccomp profile** MUST replace it.

R-013 The custom seccomp profile MUST be a **minimal diff over the upstream Docker default profile**:
  - the upstream baseline MUST be **pinned** (source URL, commit, and file checksum recorded in a provenance artifact),
  - only the syscalls strictly needed for nested user/mount namespaces and the sandbox root swap (clone/unshare with `CLONE_NEWUSER`, mount, pivot_root, umount) are added,
  - namespace flags MUST be matched by argument where the seccomp policy supports it (allow `CLONE_NEWUSER` only), not blanket-allowed,
  - no container capabilities are added as part of this fix.

R-014 The effective sandbox MUST enforce, at minimum:
  - **workspace-write**: agent commands may write inside the opened workspace,
  - writes **outside** the workspace are denied,
  - **no network access** from sandboxed commands when network is disabled in the Codex config (verified against a reachable outer loopback service).

R-015 The documented sandbox boundary MUST state what it does **not** provide: it does not hide files readable by the container user (including Codex's own credentials) from same-user code; Docker mounts and control-socket restrictions remain the host-file boundary; the VS Code client bridge remains a trusted component.

R-016 An **optional alternative mode** (Codex with its internal sandbox disabled, relying solely on the outer container) MUST be documented as an escape hatch, but MUST NOT be the default.

## 5. Verification

R-017 A **sandbox smoke test** MUST exist and be runnable with a single host command, offline, against the locally built image only (`--pull=never`), with **no host folders mounted** and no network. The test source MUST be passed in (e.g. stdin), not mounted or baked into the image.

R-018 The smoke test MUST assert, inside a sandboxed Codex command:
  - running as the non-root UID,
  - zero effective capabilities and no-new-privileges set,
  - a write inside the workspace succeeds and is visible,
  - a write to a sentinel path outside the workspace fails (verified again from outside),
  - a connection to an outer-process-reachable loopback service fails.

R-019 Verification MUST be **re-run after any** update of the Docker runtime, base image, Codex version, or seccomp policy, and re-runs are part of the documented workflow.

## 6. Credential and state isolation

R-020 The image and configuration MUST **not import host SSH, GPG, Git, or Docker credential material**. Specifically, host agent/credential forwarding is defended in **at least two independent layers** (e.g. emptied `SSH_AUTH_SOCK` / `GPG_AGENT_INFO` / `REMOTE_CONTAINERS_IPC` variables, host-level Dev Containers credential-helper settings, image-local blockers, and post-attach cleanup), because any single layer alone is insufficient.

R-021 Known failure modes of the tooling MUST be countered explicitly:
  - the editor may copy the host `known_hosts` — counter with a container-owned empty file,
  - the Dev Containers extension may create an SSH-agent proxy socket regardless of credential-helper settings — a post-attach cleanup hook MUST remove these optional bridge sockets and MUST touch no other sockets,
  - automatic host GPG agent/keyring discovery — countered by a PATH-shadowing blocker while keeping the original tool reachable at an explicit path.

R-022 The post-attach cleanup is **cleanup, not prevention**: the documentation MUST state that bridge sockets may exist transiently during attachment, that live inspection after each (re)attach is required before starting Codex, and that the hook may disable optional Dev Containers convenience commands that use those bridges.

R-023 No Docker socket and no definitions directory are mounted into the development container; the Docker client reads files (e.g. the seccomp profile) on the host and sends content to the daemon.

## 7. Shared agent state

These requirements are stated for Codex (`~/.codex`); the same pattern (authoritative host state directory, double mount, per-developer identity, per-runtime indexes where OS lock semantics require it) MUST apply to every supported agent, starting with Claude Code.

R-024 The host `~/.codex` is the **single authoritative state directory**. It MUST be mounted into the container so that configuration, authentication, skills, rules, plugins, generated memory files, and session rollouts **survive container recreation** and remain the host's files.

R-025 The state directory MUST be mounted **twice**: at the container-home path (`/home/user/.codex`) and at the same **absolute path it has on the host**. The second mount keeps stored absolute skill/plugin/session paths usable inside Linux without mounting the rest of the host home. `CODEX_HOME` is set accordingly in both the container and the editor's remote environment.

R-026 **SQLite index databases are the exception**: the container MUST use a separate `CODEX_SQLITE_HOME` subdirectory under the same host state directory, because macOS file-lock semantics are not honored through the mount (OrbStack). This is a cross-OS-mount concern; on same-OS Linux↔Linux mounts the indexes may be shared instead — the chosen behavior MUST be documented. Consequences of the separate-directory approach that MUST be documented:
  - conversation indexes are per-runtime (new conversations do not appear in the other runtime's list),
  - rollout and memory files remain shared,
  - a given chat is continued in only one runtime at a time,
  - live SQLite files are never copied or merged; migrations stop containers first and preserve consistent backups.

R-027 **Git commit identity is private per-developer state**, not baked into the image. The container's global Git configuration MUST load an include file from the private state directory; the include file lives on the host with restrictive permissions (0600). Repository-specific identity settings take precedence.

R-028 Git is enabled inside the container for commit identity and inspection; **push/pull credential flows remain on the host** (credential sharing is off), so the container is not expected to authenticate to remote hosts.

R-029 The editor MUST install the required extensions **inside the container** (Codex extension, C/C++, CMake) on attach, with the Codex extension assigned to the **workspace extension host** (so its backend runs in the container, not on the host).

## 8. Project registration and sharing

R-030 A one-time per-machine registration MUST link the definitions checkout into a user-level directory, and that directory's per-repository config subdirectory MUST be added to the editor's *Dev Containers: Repository Configuration Paths*. No custom host environment variables are needed; the configuration resolves the host home via `${localEnv:HOME}`.

R-031 A helper MUST register an arbitrary local checkout **without modifying it**: read the `origin` remote (HTTPS without embedded credentials, or `user@host:path`), normalize it to a repository identity (git host + path, `.git` suffix stripped), and create a relative symlink to the shared configuration at `<configs>/<host>/<repo>/.devcontainer/devcontainer.json`.
  - registrations are idempotent and refuse to overwrite a different existing configuration,
  - repository identity is used (not the local path), so the mapping directory is shareable between colleagues using the same remotes,
  - symlinks escaping the configuration root MUST be rejected.

R-032 The sharing contract MUST be explicit: **shared** = image definition, seccomp profiles + provenance, scripts, docs; **private** = `~/.codex` state, Git identity, SQLite indexes, editor User-setting edits (with private backups of any modified settings).

## 9. Documentation requirements

R-033 The system MUST ship two documents:
  - a **setup guide** (one-time registration, per-project registration, required host editor settings and their exact JSON keys, Git identity init, state-directory init, vcpkg cache notes, and a checklist of *live checks to perform after each attach* — including explicit warnings that static config and offline guard tests are not proof of a live pass),
  - a **sandbox runtime document** (diagnosis of the seccomp problem, the pinned baseline and precise added rules, verification instructions, the R-015 boundary statement, and re-verification triggers).

R-034 Any architecture- or version-sensitive decision (seccomp argument order, tested Docker/Codex versions, lock semantics) MUST be recorded with the exact tested environment.

## 10. Out of scope (explicit non-goals)

- N-1 Running AI agents on the host (outside the container) as a supported mode — all agent execution happens inside the container.
- N-2 Hiding container-readable files (including agent credentials) from same-user code — impossible at this isolation level and out of scope.
- N-3 Automatic cross-runtime conversation-list syncing between macOS and Linux.
- N-4 Automatic memory generation (governed by each agent's own memory controls).
- N-5 Stopping, reconfiguring, or requiring changes to the host's Git or SSH agents.
- N-6 Baking local-model endpoints or model weights into the image (R-038 keeps both as per-developer state).

## 11. Acceptance criteria (definition of done)

A rebuild is complete when, on a fresh machine with Docker (OrbStack on macOS, or native/Ubuntu) + VS Code:

1. `docker build` produces the image from the shared definitions alone.
2. One-time + per-project registration succeed; the project checkout is byte-identical before/after.
3. "Reopen in Container" attaches with the shared configuration, non-root user, and the three security options in effect.
4. The offline smoke test passes all assertions (UID, caps, NoNewPrivs, write boundary, network denial).
5. Host bridge sockets are absent after the post-attach hook; live checks from the setup guide pass.
6. The Codex extension and its backend run inside the container; sign-in works.
7. A test edit/build round-trip succeeds; a write outside the workspace by a sandboxed command fails.
8. After container recreation, authentication, skills, sessions, and Git identity are intact; the host's files are unchanged except under the designated state directories.
9. All documentation (setup guide, runtime doc, provenance) is current and re-verification is recorded.
10. **Claude Code (primary agent)** completes a sign-in and an edit/build round-trip inside the container; the **local-only harness** (R-038) completes a no-cloud round-trip against a locally hosted model, with no cloud credentials present, and no image change.
11. `AGENTS.md` is present and `CLAUDE.md` points to it without duplicating instructions; both agents pick up the shared instructions.
