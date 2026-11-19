# 4 · Cheat sheet

## On your computer

| Do this | Command |
|---|---|
| Open a project in the bubble (terminal) | `cd my-project && vibe shell` |
| Open a project in the bubble (VS Code) | `cd my-project && vibe code`, then `vibe doctor .` |
| See all running bubbles | `vibe ls` |
| Jump into bubble #2 from the list | `vibe shell 2` |
| Close a project's bubble | `vibe down my-project` |
| Close all bubbles | `vibe down --all` |
| Sensitive work (no internet, local model) | `vibe up my-project --net local` |
| Back to normal | `vibe up my-project --net agents` |
| What did the agent try to reach? | `vibe logs my-project` |
| Allow a website | `vibe allow example.com` |
| Did the agent touch risky files? | `vibe audit my-project` |
| Check the bubble is safe | `vibe doctor` / `vibe doctor my-project` |
| Update agents to newest versions | `vibe build --fresh`, then `vibe down` + `vibe up` per project |
| All commands | `vibe help` |

## Inside the bubble

| Do this | Command |
|---|---|
| Start Claude (asks before acting) | `claude` |
| Start Claude (no questions) | `claude-vibe` |
| Continue last Claude conversation | `claude -c` |
| Codex | `codex` / `codex-vibe` |
| Local model (local mode only) | `opencode` |
| Where am I, which mode? | `vibe-info` |
| What did the agent change? | `git diff` |
| Leave the bubble | `exit` |

## Inside Claude

| Key / command | Effect |
|---|---|
| Esc | Stop it |
| Shift+Tab | Switch modes (plan mode = think, don't touch) |
| `@file` | Point at a file |
| `!cmd` | Run a shell command yourself |
| `/clear` | Fresh start |
| `/help` | All commands |
| `/exit` | Quit |

## The rules of thumb

1. Small, specific requests. One thing at a time.
2. Plan mode for anything big.
3. `git diff` before you keep anything. Commit often.
4. You push, not the agent.
5. Sensitive code → `--net local` + opencode.
6. Got a 403? `vibe logs` → `vibe allow`.
7. Never run `claude-vibe` / `codex-vibe` **outside** the bubble.
