# 2 · Working with Claude Code

Claude Code is the main agent. You talk to it in plain language; it reads code, edits files and runs commands to get the job done.

## Starting it

Inside the bubble (`vibe shell`):

| Command | What it does |
|---|---|
| `claude` | Start a conversation. It **asks before** editing files or running commands |
| `claude-vibe` | Same, but **never asks**. Faster; safe here because the bubble is the safety net |
| `claude -c` | Continue your last conversation |
| `claude -p "question"` | Ask one thing, print the answer, exit |

Start with `claude` until you trust how it works, then switch to `claude-vibe`.

## While it's running

| You press or type | Effect |
|---|---|
| **Enter** | Send your message |
| **Esc** | Stop it right now (it keeps what it did so far) |
| **Shift+Tab** | Switch mode: normal → auto-accept edits → **plan mode** (thinks and plans, doesn't change anything) |
| `@path/to/file` | Point it at a specific file |
| `!command` | Run a shell command yourself, e.g. `!git status` |
| `/clear` | Start fresh (forget the conversation) |
| `/help` | All commands |
| `/exit` | Quit |

When it asks permission, you can say yes once, yes for the rest of the session, or no. If you say no, tell it what to do instead.

## How to get good results

**Be specific, the way you'd brief a colleague.**
- ❌ "fix the bug"
- ✅ "the login form accepts empty passwords; make it show an error instead, and add a test for it"

**Give it the context it can't guess.** Which file, what you expect, what you tried, the exact error message (paste it in).

**For anything big, plan first.** Press Shift+Tab until it says *plan mode*, describe the task, and read the plan. Correct it, then let it build.

**Work in small steps.** One feature or fix per request. Check the result, commit, move on. Small steps are easy to review and easy to undo.

**Ask it to check its own work.** "Run the tests" or "build it and fix any errors" at the end of a task saves you a round trip.

**Commit often.** Git is your undo button. You can ask Claude: "commit this with a good message". It can commit but can't push; you push from your own computer after reviewing.

## Reviewing what it did

Always look before you keep it:

```bash
git diff              # what changed
git log --oneline     # what it committed
git restore <file>    # throw away changes to a file
```

Treat its work like a pull request from a new teammate: usually good, sometimes confidently wrong.

## When it gets stuck

- **It goes in circles:** press Esc, run `/clear`, and describe the task again with more detail.
- **"403" or "CONNECT tunnel failed":** it tried to reach a website that isn't on the allowlist. On your computer (not in the bubble), run `vibe logs` to see what it tried, then `vibe allow <site>` if it's legitimate.
- **It needs a system package** (`apt install …`): it can't install one; the bubble has no admin rights. Ask whoever maintains vibe to add it to the image.
- **It wants to push:** it can't. Push yourself from your computer.

## Project instructions (optional, but great)

Create a `CLAUDE.md` in your project root with things it should always know: how to build, how to run tests, code style, what not to touch. Claude reads it at the start of every conversation. Short and concrete beats long.

**Next:** [Other agents](03-other-agents.md)
