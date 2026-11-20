# AI VIBE

*Valheim Impetus Bubble Environment.* A hardened container where AI coding agents can work at full speed, including without approval prompts, while your machine, credentials and network stay out of reach.

- **One image, every agent:** Claude Code (primary), Codex, and opencode for local models.
- **One CLI:** `vibe`. It works on any folder and never writes into your project.
- **Locked down:** non-root, zero capabilities, no-new-privileges, resource limits, and an egress allowlist proxy.
- **Provable:** `vibe doctor` checks every one of those claims.

> **What it is, and isn't.** The bubble keeps agents (including ones tricked by something they read) away from the rest of your machine, your credentials and your network, so they can run fast without approval prompts. It is a container, not a virtual machine. Two things it can't change:
> - a cloud agent (Claude, Codex) sends the code it works on to its vendor; that's how it works;
> - allowlisted sites (GitHub, npm, …) can carry data out.
>
> So: sensitive code → `--net local` with opencode and a model on your own machine. Never keep secrets in a project that you couldn't revoke. Details: [docs/SECURITY.md](docs/SECURITY.md).

> **New to AI agents in the terminal? Start with the [manual](docs/manual/README.md).** It's four short pages, from install to your first task.

Requirements live in [SPEC.md](SPEC.md). The security model and its limits are in [docs/SECURITY.md](docs/SECURITY.md).

## Install

Requires bash, Docker (your user must be able to run `docker`), and, for `vibe code`, VS Code with the Dev Containers extension.

```bash
git clone https://github.com/rp9376/ai-vibe.git ~/vibe
cd ~/vibe
./vibe install                      # puts `vibe` on your PATH (symlink in ~/.local/bin)
```

`vibe install` links to this checkout, so `git pull` updates the CLI too. If `~/.local/bin` isn't on your PATH, it prints the line to add to `~/.bashrc`. To use another folder, run `./vibe install /some/bin`; to undo, run `vibe uninstall`.

## Quick start

```bash
vibe setup                          # once: creates ~/.vibe, git identity, prints editor settings to paste
vibe build                          # ~2–3 min the first time
vibe doctor                         # proves the boundary; re-run after any update

cd ~/code/my-project
vibe shell                          # shell in the bubble → run `claude-vibe`
vibe code                           # …or attach VS Code
```

## Daily use

| Command | Does |
|---|---|
| `vibe up [dir] [--net P]` | Start the project's container (`dir` defaults to `.`) |
| `vibe ls` | List project containers, numbered |
| `vibe shell [project] [-- cmd…]` | Shell, or one command, inside it |
| `vibe code [project] [--net P]` | Start + attach VS Code |
| `vibe down [project] [--purge]` | Remove container and proxy; `--purge` also drops the per-project home volume |
| `vibe down --all [--purge]` | Take down every project container |
| `vibe doctor [project]` | Verify the image (no project) or a running container (after every VS Code attach) |
| `vibe logs [project] [-f]` | Proxy log: what the agent tried to reach, and what was blocked |
| `vibe allow [host…]` | Allow hosts (personal list) and reload running proxies |
| `vibe audit [project] [--accept]` | Report changes to files your host might execute |
| `vibe build [--fresh]` | Rebuild images (agent updates, base image swap) |

**Picking a project:** `project` can be a folder, the `#` from `vibe ls`, or the project name (its folder name). With nothing given, it's the current folder.

```
$ vibe ls
#  PROJECT     STATUS         NET     PATH
1  shop        Up 27 minutes  agents  /home/you/code/shop
2  game        Up 7 minutes   agents  /home/you/code/game

$ vibe shell 2            # or: vibe shell game
$ vibe down shop
```

Numbers run oldest first, so new containers are added at the end, but removing one shifts the numbers after it. Names don't shift, so prefer them for `down`. If two projects share a folder name, vibe refuses to guess and asks for the number or path.

Your agent state, auth and git identity live in `~/.vibe/`, never in the repo. Each project gets one container (`vibe-<name>-<hash>`), with the project mounted at `/workspaces/<name>`.

## Sign in (once, inside the bubble)

Bubble agents have their **own** state in `~/.vibe/state/`, separate from any agent on your host, so you sign in once inside.

- **Claude Code:** run `claude` and pick a login method. Open the printed URL in your host browser and paste the code back.
- **Codex:** `codex login --device-auth`. The default browser callback to `localhost` can't reach the container. Or use `printenv OPENAI_API_KEY | codex login --with-api-key`.

Auth survives `vibe down` / `vibe up` and is shared by all your project containers.

## Vibe mode

`claude-vibe` and `codex-vibe` run the agents with no per-command approvals. That is acceptable here because the container and the egress allowlist are the boundary, not the agent's own prompts. Plain `claude` / `codex` still work if you want the prompts.

Codex's own sandbox (bubblewrap) can't start inside the container on hosts that restrict user namespaces, so the seeded `~/.codex/config.toml` sets `sandbox_mode = "danger-full-access"`. See [docs/SECURITY.md](docs/SECURITY.md#inner-sandboxes).

## Network profiles

| `--net` | Reachable | Cloud agent credentials |
|---|---|---|
| `agents` *(default)* | agent APIs, VS Code marketplace, package registries, your `~/.vibe/allow.txt` | mounted |
| `local` | only the `host:port` entries in `~/.vibe/local-endpoints.txt` | **not** mounted |
| `offline` | nothing | **not** mounted |
| `open` | everything: escape hatch, avoid | mounted |

Switching recreates the container and keeps your state and home volume: `vibe up --net local`.

Every allowlist entry is pinned to a port: `example.com` allows HTTPS to `example.com:443` only, `.example.com` adds its subdomains, and `host:8080` allows exactly that port (HTTP or HTTPS). Your host machine itself is never reachable from a bubble, except through the proxy for entries you list.

**"The agent can't reach X":** run `vibe logs` to see the blocked host, then `vibe allow X`. Running containers pick it up immediately. To change what *everyone* gets, edit [net/lists/](net/lists/) or an agent's `domains.txt`. To make a new profile, add `net/profiles/<name>.txt` (only `vibe doctor <project>` on a container using it verifies it). After editing any list by hand, run `vibe up <project>` or `vibe allow` (no arguments) to reload.

## Local models (sensitive data)

opencode (version 2, npm `@opencode/cli`; both `opencode` and `opencode2` work) is the **local-model-only** agent. Three walls keep it that way:
- **Managed config:** `/etc/opencode/opencode.json` in the image (root-owned) enables only one provider, named `local`. Neither your config nor a project's `opencode.json` can turn any other provider on.
- **Start guard:** opencode refuses to start unless the container is on `--net local` (or `offline`), where nothing but your local endpoints is reachable.
- **No phoning home:** no cloud model catalog (models.dev), no free cloud models, no self-update.

Setup:

1. Run a model server on the host that listens on the Docker bridge, e.g. `OLLAMA_HOST=172.17.0.1:11434 ollama serve`. Prefer the bridge IP to `0.0.0.0`, which would expose it to your LAN.
2. Add `host.docker.internal:11434` to `~/.vibe/local-endpoints.txt`.
3. Define your model in `~/.vibe/state/opencode/config/opencode.jsonc`. It's seeded on first `--net local` start from [agents/opencode/opencode.example.jsonc](agents/opencode/opencode.example.jsonc), which also contains a sensible permission policy. The provider **must** stay named `local`:
   ```jsonc
   "providers": {
     "local": {
       "package": "aisdk:@ai-sdk/openai-compatible",
       "settings": { "baseURL": "http://host.docker.internal:11434/v1", "apiKey": "not-needed" },
       "models": { "qwen3-coder:30b": { "limit": { "context": 131072, "output": 32768 } } }
     }
   },
   "model": "local/qwen3-coder:30b"
   ```
   Any OpenAI-compatible server works (Ollama, LM Studio, llama.cpp, vLLM): change `baseURL`, `apiKey` and the model names, and list the same `host:port` in step 2.
4. `vibe up <project> --net local`, then `vibe shell <project> -- opencode`.

Under `local`, Claude/Codex credentials aren't mounted and cloud APIs are refused. `vibe doctor <project>` tells you whether your endpoint answers. opencode needs no internet, not even on first use (tested through the proxy against a mock model server).

## VS Code

1. Install the Dev Containers extension: `code --install-extension ms-vscode-remote.remote-containers`.
2. Paste the settings `vibe setup` prints into your **User** settings. They stop VS Code from copying your git config and from forwarding git, Docker and GitHub credentials into containers:
   ```jsonc
   "dev.containers.copyGitConfig": false,
   "dev.containers.gitCredentialHelperConfigLocation": "none",
   "dev.containers.dockerCredentialHelper": false,
   "git.terminalAuthentication": false,
   "github.gitAuthentication": false,
   "remote.extensionKind": { "anthropic.claude-code": ["workspace"], "openai.chatgpt": ["workspace"] }
   ```
3. `vibe code`. vibe creates the container itself and VS Code only *attaches*, so the editor can't add mounts. After it connects, run `vibe doctor <dir>`; on attach VS Code can open bridge sockets that `vibe-scrub` removes, and the doctor confirms they're gone.

The terminal path (`vibe shell`) never creates those bridges and is the most locked-down way to work.

## Add, remove or update an agent

An agent is a folder in [agents/](agents/). Nothing else needs editing.

```
agents/mytool/
  agent.conf     # required, see below
  install.sh     # build time, as root:  npm install -g "mytool@${AGENT_VERSION}"
  init.sh        # optional, container start, as user: seed config into its state dir
  domains.txt    # optional, hosts it needs under the 'agents' profile
  rootfs/        # optional, files copied into the image (policy, shell aliases in etc/vibe/bashrc.d/)
```

```bash
# agents/mytool/agent.conf
AGENT_ENABLED=yes                           # no = skipped at build, not mounted
AGENT_VERSION=latest                        # or an exact version
AGENT_CLOUD=yes                             # no = also available under local/offline
AGENT_STATE="mytool:/home/user/.mytool"     # ~/.vibe/state/<dir> : container path (space-separated list)
AGENT_ENV="MYTOOL_HOME=/home/user/.mytool"  # env vars for the container
AGENT_EXTENSIONS=""                         # VS Code extension IDs
AGENT_INSTRUCTIONS=""                       # optional: image path that gets a copy of image/AGENTS.md
AGENT_CHECK="mytool --version"              # vibe doctor runs this
```

Then run `vibe build && vibe doctor`. To remove an agent, set `AGENT_ENABLED=no` or delete the folder, then rebuild. To update all agents to `latest`, run `vibe build --fresh`.

## Swap the base image

Set `VIBE_BASE_IMAGE` in `vibe.conf` (shared) or `~/.vibe/config` (just you) to any Debian/Ubuntu-family image. If it already ships Node, set `VIBE_NODE_MAJOR=""`. Then run `vibe build && vibe doctor`. System packages the agents always need belong in that base image or in step 1 of [image/Dockerfile](image/Dockerfile); agents can't `apt install` themselves (no root, no sudo).

## Files to edit, by task

| You want to… | Edit |
|---|---|
| Change what agents are told about the bubble | [image/AGENTS.md](image/AGENTS.md) |
| Change limits, default profile, base image | [vibe.conf](vibe.conf) or `~/.vibe/config` |
| Allow a host for yourself | `vibe allow <host>` |
| Allow a host for everyone | [net/lists/](net/lists/) or `agents/<name>/domains.txt` |
| Add/remove an agent | [agents/](agents/) |
| Change Claude Code policy for the bubble | [agents/claude/rootfs/etc/claude-code/](agents/claude/rootfs/etc/claude-code/) |
| Change the boundary itself | [vibe](vibe), [image/Dockerfile](image/Dockerfile), [net/proxy/](net/proxy/), then update [SPEC.md](SPEC.md) §14 |

## Troubleshooting

- **"image was rebuilt since … was created":** run `vibe down && vibe up`. State and home are kept.
- **Agent hits 403 / "CONNECT tunnel failed":** the host isn't allowlisted. Run `vibe logs`, then `vibe allow <host>`.
- **`vibe audit` warns after a session:** the agent changed something your host could execute (`.vscode/`, `.envrc`, …). Review it, then run `vibe audit --accept`.
- **Permission errors on project files:** the image is built with your UID/GID. If you build for someone else, they must run their own `vibe build`.
- **"`.git/config` contains credentials":** your repo's remote URL has a token in it (`https://user:TOKEN@…`). The agent could read it and push with it, so vibe refuses. Run `git remote set-url origin https://github.com/OWNER/REPO.git` and keep the token in a credential helper on your host.
- **"…predates host isolation":** that project's network was created by an older vibe. Run `vibe down <project> && vibe up <project>`.
- **Agent can't commit:** set your identity in `~/.vibe/state/git/identity` (`vibe setup` seeds it from your host git config, if present).
