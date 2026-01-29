# Mr. Burns Agent Instructions

## Overview

Mr. Burns is an executive-planner-worker autonomous agent swarm that coordinates multiple AI agents to tackle complex, long-running coding projects. Based on Cursor's research on scaling autonomous coding.

## Architecture

Three distinct agent roles with clear responsibilities:

1. **Executive** - Strategic oversight, runs periodically
2. **Planner** - Decomposes goals into tasks, explores codebase
3. **Worker** - Executes single tasks, runs in parallel

## Commands

```bash
# Run Mr. Burns with defaults
./burns.sh

# Run with Claude Code instead of Amp
./burns.sh --tool claude

# Run with 8 parallel workers
./burns.sh --workers 8

# Run executive every 5 cycles
./burns.sh --exec-interval 5

# Full options
./burns.sh --tool amp --workers 4 --exec-interval 10 --max-cycles 100
```

## Key Files

### Orchestrator
- `burns.sh` - Main loop that spawns agents and manages cycles

### Prompts
- `prompts/executive.md` - Executive agent instructions
- `prompts/planner.md` - Planner agent instructions  
- `prompts/worker.md` - Worker agent instructions

### State
- `state/project.json` - Project goals and configuration
- `state/tasks/*.json` - Task queue (one file per task)
- `state/agents/*.json` - Active agent registry
- `state/logs/*.log` - Per-agent activity logs

### Libraries
- `lib/task.sh` - Task queue operations (create, claim, update, release)
- `lib/agent.sh` - Agent lifecycle (register, heartbeat, deregister)
- `lib/git.sh` - Git coordination (branches, merges, conflicts)

## Task Schema

```json
{
  "id": "TASK-001",
  "title": "Add priority field to database",
  "description": "...",
  "status": "pending|claimed|in_progress|completed|failed",
  "priority": 1,
  "assignedTo": null,
  "createdBy": "planner-1",
  "dependencies": [],
  "acceptanceCriteria": [],
  "branch": "burns/task-001",
  "attempts": 0,
  "maxAttempts": 3,
  "createdAt": "...",
  "updatedAt": "..."
}
```

## Signal Protocol

### Executive Signals
- `<burns>CONTINUE</burns>` - Project progressing, continue
- `<burns>COMPLETE</burns>` - All goals achieved
- `<burns>STUCK</burns>` - Needs human intervention
- `<burns>SPAWN_PLANNER:area</burns>` - Create planner for area

### Planner Signals
- `<burns>PLANNING_DONE</burns>` - Tasks created for area
- `<burns>AREA_COMPLETE</burns>` - No more work needed
- `<burns>NEED_CLARIFICATION:question</burns>` - Blocked on ambiguity

### Worker Signals
- `<burns>TASK_COMPLETE:TASK-XXX</burns>` - Task done
- `<burns>TASK_FAILED:TASK-XXX:reason</burns>` - Task failed
- `<burns>NO_TASKS</burns>` - Queue empty

## Patterns

### Lock-Free Task Claiming
Tasks are claimed using atomic `mv` operations - no locks needed. If two workers try to claim the same task, one wins and the other retries with a different task.

### Fresh Context
Each agent iteration is a fresh AI instance. Memory persists only via state files:
- Tasks in `state/tasks/`
- Agent registry in `state/agents/`
- Progress log in `state/progress.txt`

### Small Tasks
Tasks must be completable in ONE agent iteration. If a task is too big, the agent runs out of context before completing.

Good task size:
- Add a database column and migration
- Create a single UI component
- Add one API endpoint

Too big:
- "Build the entire dashboard"
- "Add authentication"

### Dependency Ordering
Tasks execute in priority order. Earlier tasks must not depend on later ones:
1. Schema/database changes
2. Backend logic
3. Frontend components
4. Integration/summary views

## Flowchart

Interactive visualization at `flowchart/`:

```bash
cd flowchart
npm install
npm run dev
```
