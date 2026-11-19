# Vibe mode: no per-command approvals. Acceptable here because the container and the
# egress allowlist are the boundary (SPEC AGT-6), not Claude's own permission prompts.
alias claude-vibe='claude --dangerously-skip-permissions'
