# You are working inside AI VIBE

AI VIBE is a sandbox container. These instructions apply to every agent in it; a project's own `AGENTS.md` / `CLAUDE.md` adds to them.

## Environment

- Linux container, user `user`, no root and no sudo. You cannot install system packages; if one is needed permanently, tell the human so they can add it to the image.
- The project is at `$VIBE_WORKSPACE`, bind-mounted from the host: your changes are real and immediate.
- `/home/user` is a per-project volume. User-space installs persist: `npm i -g <pkg>` (goes to `~/.local`), `pip install --user <pkg>`, `python3 -m venv .venv`.
- `vibe-info` prints the project, network profile and installed tool versions.

## Network

- All traffic goes through an allowlist proxy. `403`, `Filtered`, or `CONNECT tunnel failed` means the host is not on the allowlist. There is no other route out, so do not try to work around it: tell the human which host you need and why. They can run `vibe allow <host>`.
- Under the `local` or `offline` profiles you are handling sensitive work: assume nothing may leave this machine.

## Git

- Commit early and often with clear messages; commits are the human's undo button.
- `.git/config` and `.git/hooks` are read-only on purpose: you cannot add remotes, change git config or install hooks. You cannot push; the human pushes from the host.

## Ground rules

- Keep project changes inside the workspace.
- Do not edit files the host would execute (`.vscode/`, `.devcontainer/`, `.envrc`, git hooks, `mise.toml`) unless the task requires it, and say so when you do.
- Never read, print or move credentials (yours or anyone else's), and do not probe or try to escape the sandbox.
