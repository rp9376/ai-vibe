# 3 · Other agents

All agents live in the same bubble and follow the same rules. Pick by task:

| Agent | Use it for | Talks to |
|---|---|---|
| **Claude Code** | Everyday work (the default) | Anthropic's cloud |
| **Codex** | A second opinion, or if you prefer OpenAI | OpenAI's cloud |
| **opencode** | **Sensitive code** that must not leave your machine | A model running on your own computer |

## Codex

Sign in once (inside the bubble):

```bash
codex login --device-auth
```

It shows a code and a URL: open the URL in your normal browser and enter the code.

Then use it like Claude:

| Command | What it does |
|---|---|
| `codex` | Start a conversation (asks before acting) |
| `codex-vibe` | Never asks (fine inside the bubble) |
| `codex exec "task"` | Do one task and exit |
| `codex resume` | Pick up an earlier conversation |

Same habits as with Claude: be specific, work in small steps, review with `git diff`.

## opencode (local models, for sensitive code)

opencode only ever talks to an AI model running **on your own computer**. Nothing goes to the cloud. vibe enforces this:
- opencode refuses to start unless the bubble is in **local mode**;
- in local mode, the bubble can't reach the internet at all;
- Claude's and Codex's logins aren't even present.

### One-time setup

1. Install a local model server on your computer, e.g. [Ollama](https://ollama.com), and download a coding model (`ollama pull qwen3-coder:30b`, or whatever your team recommends).
2. Make it reachable from the bubble:
   - **Linux:** start it with `OLLAMA_HOST=172.17.0.1:11434 ollama serve`
   - **Mac:** works as installed
3. Tell vibe where it is: add this line to `~/.vibe/local-endpoints.txt`:
   ```
   host.docker.internal:11434
   ```
4. Tell opencode which model to use: edit `~/.vibe/state/opencode/config/opencode.jsonc` (created on your first local-mode start) and set the model name you downloaded, in both `models` and `model`. The provider must stay named `local`. If your server isn't Ollama, also change `baseURL` (and `apiKey` if it needs one), and put the same `host:port` in `local-endpoints.txt`.

### Daily use

```bash
cd ~/code/secret-project
vibe up --net local        # switch this project's bubble to local mode
vibe shell
opencode                   # start it; type your request like with Claude
```

`vibe doctor secret-project` (on your computer) tells you whether the bubble can reach your model.

Local models are smaller than cloud ones: expect them to be slower and less capable. Give smaller, clearer tasks.

To go back to normal mode: `vibe up --net agents`.

**Next:** [Cheat sheet](04-cheat-sheet.md)
