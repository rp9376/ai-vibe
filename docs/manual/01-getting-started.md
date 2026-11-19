# 1 · Getting started

About 15 minutes the first time, then seconds.

## Before you start

You need **Docker** running, and your user must be able to run `docker ps` without `sudo`. If that command fails, ask whoever manages your machine.

## Step 1: install vibe (once)

```bash
git clone https://github.com/rp9376/ai-vibe.git ~/vibe
cd ~/vibe
./vibe install        # makes the `vibe` command available everywhere
vibe setup            # creates your private folder ~/.vibe
vibe build            # builds the bubble image (2–3 minutes)
vibe doctor           # checks the bubble is locked down: every line should say PASS
```

If `vibe setup` says "no host git identity found", open `~/.vibe/state/git/identity` and fill in your name and email (remove the `#` marks). The agent uses them for commits.

## Step 2: open a project in the bubble

Go to a project you want to work on. Your first time, pick something unimportant or a fresh folder.

```bash
cd ~/code/my-project
vibe shell
```

Your prompt changes to something like `user@vibe-my-project:/workspaces/my-project$`. You're now **inside the bubble**, looking at your project's files.

## Step 3: sign in to Claude (once)

Still inside, type:

```bash
claude
```

The first time, it asks you to log in:
1. Choose your login method.
2. It prints a long URL. Open it in your **normal browser** on your computer.
3. Log in, copy the code it shows you, paste it back into the terminal.

You only do this once; every project uses the same login.

## Step 4: your first task

Claude is now waiting for you to type. Try something small and safe:

```
explain what this project does and how it's structured
```

Press **Enter** and watch. It reads files and answers. Then try a real change:

```
add a README section explaining how to run the tests
```

It shows the edit it wants to make and asks permission. Answer and see what happens. To leave Claude, type `/exit` (or press Ctrl+C twice).

## Step 5: see what changed

You're back in the bubble's shell. Check what the agent did:

```bash
git status
git diff
```

The changes are in your real project folder, so you also see them in your editor on your computer.

## Step 6: finish

Leave the bubble with `exit`, then:

```bash
vibe down
```

This stops the container. Your login and project files stay. If it prints an **audit** warning, the agent changed files your computer might run automatically (like `.vscode/` settings); look at them before trusting them.

## Using VS Code instead

From your project folder, run `vibe code` instead of `vibe shell`. VS Code opens *inside* the bubble: open its terminal (Ctrl+\`) and run `claude` there. After VS Code connects, run `vibe doctor .` in a terminal on your computer to check nothing leaked in.

**Next:** [Working with Claude Code](02-claude-code.md)
