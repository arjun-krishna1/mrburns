---
name: mrburns
description: Use when the user asks to run the Mr. Burns swarm (planning + parallel execution) via Codex CLI.
---

# Mr. Burns (mrburns) Skill Guide

Mr. Burns is a file-backed swarm coordinator. It delegates to a single **“mrburns” Codex run** which creates/updates tasks in `state/tasks/`, then (when useful) spawns additional Codex runs as sub-agents (executive / planner / worker) coordinated via the same `state/` files.

## Defaults (do not prompt unless overriding)

- **model**: `gpt-5.2-codex`
- **reasoning effort**: `xhigh`
- **sandbox**:
  - default: `--sandbox workspace-write` (for implementing tasks)
  - use `--sandbox read-only` for audit/planning-only runs

## Running Mr. Burns

1. If the user requests an override, ask in a single `AskUserQuestion`:
   - model (`gpt-5.2-codex` or `gpt-5.2`)
   - reasoning effort (`xhigh`, `high`, `medium`, `low`)
     Otherwise, use the defaults above.
2. Pick sandbox mode:
   - Default to `--sandbox workspace-write`
   - Use `--sandbox read-only` if the user asks for analysis/planning only
   - Use `--sandbox danger-full-access` only with explicit user permission
3. Always include these flags:
   - `--skip-git-repo-check`
   - `--full-auto`
4. **IMPORTANT**: By default, append `2>/dev/null` to suppress thinking tokens (stderr). Only show stderr if the user explicitly requests it or debugging is needed.

### Command template

Run from the repo root directory.

```bash
codex exec \
  -m gpt-5.2-codex \
  --config model_reasoning_effort="xhigh" \
  --sandbox workspace-write \
  --full-auto \
  --skip-git-repo-check \
  -C . \
  "$(cat <<'EOF'
You are Mr. Burns, an executive-planner-worker swarm orchestrator operating inside this repository.

Your job:
- Read `state/project.json` for goals/config/areas. If it does not exist, create it by copying `state/project.example.json` and making reasonable placeholder values, then continue.
- Ensure `state/tasks/`, `state/agents/`, and `state/logs/` exist.
- Maintain progress in `state/progress.txt` (append updates; do not spam).

Planning:
- Create small, atomic tasks as JSON files in `state/tasks/` using the repo's existing task schema.
- Keep tasks small enough to be completed in one worker iteration.
- Encode dependencies explicitly.

Execution:
- For each cycle, coordinate work by running additional Codex commands as sub-agents when useful:
  - executive: strategic oversight
  - planner: task decomposition for an area
  - worker: claim exactly one task and implement it
- Sub-agents MUST coordinate only via files in `state/` (no in-memory assumptions).
- Workers should claim tasks lock-free (one task per worker) and write back status updates.

Quality:
- Run any configured checks in `state/project.json` (e.g. `qualityChecks`) before marking tasks complete.
- Prefer minimal, focused diffs.

Output:
- Summarize what you did and what changed.
- If blocked, explain the blocker and propose next steps.
EOF
  )" 2>/dev/null
```

## Resuming

When continuing the last Codex session, do **not** add configuration flags unless the user explicitly requests them.

```bash
echo "Continue Mr. Burns from the current repo state." | codex exec --skip-git-repo-check resume --last 2>/dev/null
```

After every run, tell the user they can resume by saying **“mrburns resume”** or asking to continue.
