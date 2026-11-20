# Review triage: QWEN's_REVIEW.md (2026-11-20)

Each claim in the external review, checked against the code and, where it mattered, tested on this machine. Verdicts:
- **✅ Valid:** fix it.
- **🟡 Partly valid:** a useful nugget inside a wrong or overstated claim.
- **❌ Wrong or not worth it:** with the reason.
- **☑️ Already covered.**

Review section numbers are given as §x.y.

## Outcome (2026-11-20)

All 18 items were resolved without adding new moving parts: no new commands, no host firewall rules, no new dependencies. Every fix was tested on this machine (SPEC §14, E-6 to E-8, D-10 to D-12, V-2). Deliberately skipped: CLI fixture tests and extension-ID validation (cost more than they buy).

## Tracker

| # | Item | Review | Verdict | Severity | Effort | Status |
|---|---|---|---|---|---|---|
| 1 | Host reachable directly via the internal network's gateway (bypasses proxy) | §2.1 | ✅ **confirmed by test** | **High** | S | ✅ done: isolated networks + real host-service test in doctor |
| 2 | Allowlist drops `:port` → `local` allows *any* HTTP port on an allowed host | §2.2 | ✅ (code) | Med-High | M | ✅ done: allowlist pinned to host:port (tinyproxy FilterURLs) |
| 3 | Tokens inside the host's `.git/config` are readable by the agent | §2.3 | ✅ | Med | S | ✅ done: `vibe up` refuses, doctor checks |
| 4 | Positioning: README sounds stronger than the caveats | §2.4 | 🟡 | Med | S | ✅ done: "What it is, and isn't" box in README |
| 5 | Doctor's `SSH_AUTH_SOCK`/`GPG_AGENT_INFO` checks can't fail | §3.1 | ✅ | Med | S | ✅ done: scans every process's env for live bridge sockets |
| 6 | Mount check ignores tmpfs → host `/run/user/…` bind would pass | §3.4 | ✅ (worse than stated) | Med | S | ✅ done: every mount of any fs type checked |
| 7 | opencode: installed 1.19.6 is "V1", your config is "V2" | §7.2 | ✅ **confirmed in binary** | High for opencode | M | ✅ done: opencode V2 2.3.2 (`@opencode/cli`), your config as seed |
| 8 | opencode installs `@opencode-ai/plugin` from npm at runtime | §7.3 | ✅ **confirmed in binary** | High for opencode | M | ✅ resolved by V2: provider bundled, works offline and through the proxy |
| 9 | Pin agent versions (`latest` drifts) | §5.2, §7 | ✅ (item 7 proves it) | Med | S | ↩️ owner chose `latest`; verified pins kept as comments in each agent.conf (SPEC D-13) |
| 10 | Claude: turn off non-essential traffic | §8 | ✅ **with corrections** | Med | S | ✅ done: 4 verified switches in managed-settings.json |
| 11 | Codex: find its telemetry switch | §8 | ✅ (research) | Low-Med | S | ✅ done: `[analytics] enabled = false` in managed_config.toml |
| 12 | `vibe up` on a running project doesn't reload the allowlist | §7.3 | ✅ | Low-Med | S | ✅ done: reloads only when the list changed |
| 13 | No CI / shellcheck / tests for the CLI's parsing | §4 | ✅ | Med | M | ✅ done (lint only): bash -n + shellcheck in GitHub Actions; fixtures skipped |
| 14 | Small CLI hardening: `eval` in `agent_get`, `VIBE_CPUS` validation, extension-ID validation | §4 | ✅ minor | Low | S | ✅ done: no eval, numeric checks, CPU clamp from Docker; ext-ID check skipped |
| 15 | Doctor: a proxy-403 on an *allowed* host should FAIL, not WARN | §3.5 | 🟡 | Low | S | ✅ done |
| 16 | Doctor's "blocked host" test uses `example.com` (could be allowlisted) | §5.3 | ✅ tiny | Low | S | ✅ done: `blocked.vibe-doctor.invalid` |
| 17 | Trim SBX-2 (inner-sandbox plan) to "not planned" | §5.1 | ✅ (docs only) | Low | S | ✅ done: SBX marked not planned |
| 18 | Small doc notes: audit is a tripwire, not integrity; custom profiles need live doctor; home volumes grow | §5.2, §5.3 | ✅ docs | Low | S | ✅ done (custom-profile note in README; others already covered) |
| — | Image-phase doctor is "self-referential" | §3.2 | ❌ mostly wrong | — | — | — |
| — | Doctor checks "now", not "since attach" | §3.3 | ☑️ already documented | — | — | — |
| — | In-place allowlist rewrite invariant | §4 | ☑️ already commented in `start_proxy` | — | — | — |
| — | Empty `NO_PROXY` | §5.2 | ❌ | — | — | — |
| — | Plain container name instead of hex in `code --folder-uri` | §5.3 | ❌ | — | — | — |
| — | "Model server doubles as opencode's telemetry endpoint" | §7.2 | ❌ doubtful, not actionable | — | — | — |

---

## Details

### 1 · Host reachable via the gateway (§2.1): ✅ confirmed, highest priority

**Test (2026-11-20, this host):** on a throwaway `--internal` network, a container connected to a test service on the host bound to `0.0.0.0` via the network's gateway address (`172.19.0.1`) and got its reply. No proxy was involved. The doctor missed it because it only tests the host *through* the proxy.

Right now nothing on this machine listens on all interfaces, so nothing was actually exposed. But anything bound to `0.0.0.0` (an Ollama, a dashboard, sshd) would be reachable from every bubble.

**Better fix than the review's:** the review proposes host `iptables` rules via `sudo`. No need: Docker can give the host **no address** on the network. Both options blocked the test:
- `-o com.docker.network.bridge.gateway_mode_ipv4=isolated` (Docker 28+)
- `-o com.docker.network.bridge.inhibit_ipv4=true` (older)

**Plan:**
1. `start_proxy`: create networks with `gateway_mode_ipv4=isolated`, falling back to `inhibit_ipv4`.
2. Re-verify that the dev container ↔ proxy path still works.
3. Doctor: add a *direct* gateway connect test (FAIL if the host answers).
4. SECURITY.md: record as a decision-log entry.

Existing project networks only pick this up after `vibe down && vibe up`.

### 2 · Ports dropped from the allowlist (§2.2): ✅

`to_regex` strips `:port`, and tinyproxy filters by hostname only. So `host.docker.internal:11434` in `local-endpoints.txt` allows **every** plain-HTTP port on the host through the proxy. That's a real widening of the sensitive-data profile.

Options to investigate:
- (a) tinyproxy `FilterURLs On` with URL-shaped regexes (`^http://host:11434/`), checking how CONNECT is matched in that mode;
- (b) a stricter proxy, e.g. squid with `dstdomain` + `port` ACLs.

Prefer (a) if CONNECT behaves; must stay simple.

### 3 · Tokens in `.git/config` (§2.3): ✅

The read-only mount stops *writing*, not *reading*. A remote like `https://user:TOKEN@github.com/…` hands the agent a working push credential, and github.com is allowlisted.

**Plan:**
- `vibe up` scans the host's `.git/config` for credentials in URLs (`://user:secret@`, `password =`, `extraheader = AUTHORIZATION…`) and **refuses** unless `--allow-git-credentials`, saying how to move the token to a credential helper.
- Doctor gets the same check as a FAIL.

### 4 · Positioning (§2.4): 🟡

Valid: the README leads with "locked down" and "provable", while the important limits are in SECURITY.md. A short **"What it is / isn't"** box at the top of the README (and SPEC §1) should say:
- it keeps agents off the rest of your machine and network;
- it isn't a VM;
- allowlisted sites can carry data out;
- a cloud agent sends your code to its vendor by definition, so sensitive code → `local` + opencode;
- don't put secrets you can't revoke in a project.

Disagree with the reviewer's "fence for lazy agents" framing. The threat model deliberately includes prompt-injected agents, and the network and filesystem walls hold against those.

### 5 · Env-var checks are no-ops (§3.1): ✅

The doctor runs via `docker exec`, which never sees the environment VS Code gives its own server processes. **Fix:** scan `/proc/*/environ` of the user's processes (allowed for the same UID) for a set `SSH_AUTH_SOCK`, `GPG_AGENT_INFO` or `REMOTE_CONTAINERS_IPC`. That actually catches a leaky attach.

### 6 · Mount check blind to tmpfs (§3.4): ✅, worse than the review says

The check filters out tmpfs mounts entirely. The danger isn't a project on tmpfs; it's that a bind of the host's **`/run/user/1000`** (keyring and ssh-agent sockets live there) or **`/dev/shm`** would be invisible. **Fix:** compare *every* mountpoint, of any type, against the expected set plus a fixed list of standard kernel mountpoints (`/proc*`, `/sys*`, `/dev`, `/dev/pts`, `/dev/shm`, `/dev/mqueue`).

### 7 · opencode V1 vs V2 (§7.2): ✅ confirmed, needs your decision

- The installed binary (npm `latest` = 1.19.6) rejects V2 configs with: *"V2 permissions are not supported by OpenCode V1 … run opencode2."*
- ⚠️ **`opencode2` on npm is a security placeholder** (`0.0.1-security`, a removed or squatted name). **Don't install it.** I haven't found where V2 officially ships yet; npm dist-tags only show `latest`=1.19.6 plus `next`/`beta`/`dev` snapshots.

**Decision for you:**
- (a) Convert your config to V1 now and pin 1.19.6. Works today; the review notes the permissions port isn't 1:1.
- (b) Find the official V2 channel, then pin that.

Also note your config **denies `git commit`**, while `image/AGENTS.md` tells agents to commit often. Decide which you want for opencode.

### 8 · opencode runtime npm install (§7.3): ✅ confirmed

The binary installs `@opencode-ai/plugin` into the config dir at startup, and that fails under `local` (npm is blocked). This **conflicts with my earlier test (E-5)**, where a round-trip worked with `--network none`. That test didn't use a real `local` container with the proxy (403 instead of "no network"), and probably no `plugin` key. **Plan:** reproduce in a real `vibe up --net local` container, then pre-install the needed packages at build time where opencode looks for them.

### 9 · Pin agent versions (§5.2): ✅

Item 7 shows `latest` drift biting. Pin exact versions in each `agent.conf`, update deliberately (`vibe build` + doctor), and show the versions in `vibe doctor` / the status screen.

### 10 · Claude non-essential traffic (§8): ✅, but the review's flags are partly wrong

Checked against the installed Claude Code 2.1.328 binary:

| Flag (from the review) | Exists? |
|---|---|
| `DISABLE_TELEMETRY` | ✅ |
| `DISABLE_ERROR_REPORTING` | ✅ |
| `DISABLE_BUG_COMMAND` | ✅ |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` (umbrella switch) | ✅ |
| `DISABLE_NON_ESSENTIAL_MODEL_CALLS` | ❌ **not in this version**, would be a silent no-op |
| `DISABLE_STATSIG` | ❌ not in this version |

**Plan:** set `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` + `DISABLE_TELEMETRY=1` + `DISABLE_ERROR_REPORTING=1` + `DISABLE_BUG_COMMAND=1` in the root-owned `managed-settings.json`, then verify with `vibe logs` that no non-API traffic appears.

### 11 · Codex telemetry (§8): ✅ research

The binary contains `analytics` / `otel` config code, so there's a switch. Find the exact key for the pinned version (`codex --help`, the config reference), put it in a root-owned `/etc/codex/config.toml`, and verify via proxy logs.

### 12 · `vibe up` doesn't refresh the allowlist (§7.3): ✅

`up` only regenerates the allowlist when the proxy isn't running. `vibe allow` (no arguments) already reloads all proxies, but nobody will guess that after editing `local-endpoints.txt`. **Fix:** `up` on a running project regenerates the file and restarts the proxy if the content changed.

### 13 · CI and tests (§4): ✅

Add a GitHub Actions job:
- `bash -n` + shellcheck;
- small fixture tests for `to_regex`, `resolve_target`, profile parsing and `metadata()` JSON, with a stub `docker`. No Docker needed.

### 14 · Small CLI hardening (§4): ✅ minor

- Replace `eval` in `agent_get` with `${!name}`.
- Validate `VIBE_CPUS`/`VIBE_MEMORY`, and clamp CPUs to `docker info` NCPU (also fixes the Mac VM case).
- Validate extension IDs against `[A-Za-z0-9_.-]`.

### 15 · Allowed host returning 403 (§3.5): 🟡

Invalid entries are already rejected by `vibe allow` and `to_regex`, and typos can't be detected offline. The useful nugget: if the proxy answers **403** for an allowlisted host, the generated allowlist is broken. That should be FAIL, separate from "no answer" (no internet), which stays WARN.

### 16 · `example.com` as the blocked test host (§5.3): ✅ tiny

Use a reserved name like `blocked.vibe-doctor.invalid`. The proxy rejects by name before any DNS lookup, so it works offline and can never be allowlisted by accident.

### 17 · SBX-2 overbuild (§5.1): ✅ docs

It isn't built, but the spec still reads like a plan. Mark it **not planned**, keep the measured evidence table (it explains why Codex runs without its own sandbox), and keep one line pointing to gVisor and microVMs.

### 18 · Doc notes (§5.2, §5.3): ✅

One line each:
- `vibe audit` is a tripwire for a few file types, not workspace integrity;
- custom network profiles are only verified by live `vibe doctor <project>`;
- per-project home volumes grow with each project's installs.

---

## Rejected or already covered

- **§3.2 "image phase is self-referential":** wrong. The checks assert fixed values (`CapBnd=0`, `NoNewPrivs=1`); remove `--cap-drop`/`no-new-privileges` from `HARDEN` and phase 1 FAILs. The true part (only `vibe doctor <project>` proves a *project's* flags) is already how the live doctor works.
- **§3.3 "now, not since attach":** already stated in SECURITY.md (VS Code bridge: "cleanup, not prevention") and README.
- **§4 in-place rewrite invariant:** already commented at the write in `start_proxy`.
- **§5.2 empty `NO_PROXY`:** loopback inside the container *is* the container. Keeping it lets agents reach their own dev servers (`localhost:3000`) without going through the proxy. Harmless on an internal network.
- **§5.3 plain name in `--folder-uri`:** VS Code's `attached-container+…` URI requires the hex encoding.
- **§7.2 "model server doubles as telemetry endpoint":** speculative. "Unexpected server error" is much more likely the model server's own reply to a request it couldn't handle. Not actionable.
- **§5.3 `vibe ls` numbers shift; §5.2 single-user build:** known and documented.

## Housekeeping

- `QWEN's_REVIEW.md` is untracked. §7.1 contains your LAN model server's IP and port; redact before committing it to the public repo, or keep it out of git.
- `opencode.jsonc` (with the live API key) is no longer in the repo folder and never reached git history. ✅

## Suggested order

1 → 3 → 5 + 6 (doctor fixes, same session) → 10 + 11 + 9 (pin and quiet the agents) → 7 + 8 (opencode, after your decision) → 2 → 12 → 4 → 13 → the rest.
