# Mr. Burns

![Mr Burns](mrburns.webp)

Mr. Burns is an executive-planner-worker autonomous agent swarm for long-running coding projects. Mr. Burns coordinates Planer aggents (Smithers) and Worker agents (Homer) to tackle complex projects that would overwhelm a single agent.

Separating planning from execution, running workers in parallel, and adding periodic executive oversight allows autonomous agents to scale to very large projects.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     EXECUTIVE LAYER                         │
│  • Monitors overall progress                                │
│  • Spawns/terminates planners                               │
│  • Makes go/no-go decisions                                 │
│  • Runs periodically (not every cycle)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     PLANNER LAYER                           │
│  • Explores assigned codebase area                          │
│  • Creates atomic, executable tasks                         │
│  • Ensures proper dependency ordering                       │
│  • Can spawn sub-planners for complex areas                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                     WORKER LAYER                            │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐        │
│  │Worker 1 │  │Worker 2 │  │Worker 3 │  │Worker N │        │
│  │ TASK-01 │  │ TASK-02 │  │ TASK-03 │  │ TASK-NN │        │
│  └─────────┘  └─────────┘  └─────────┘  └─────────┘        │
│  • Claim tasks from queue (lock-free)                       │
│  • Don't coordinate with each other                         │
│  • Grind until task complete                                │
│  • Push to individual branches                              │
└─────────────────────────────────────────────────────────────┘
```

## Why This Works (Lessons from [Scaling long running tasks](https://cursor.com/blog/scaling-agents))

1. **Planners and Workers Separated** - Planners don't execute, workers don't plan. This prevents the "risk-averse" behavior seen when equal-status agents self-coordinate.

2. **No Integrator Role** - Workers handle their own conflicts. Adding an integrator creates bottlenecks.

3. **Lock-Free Coordination** - Optimistic concurrency (atomic file moves) over locks. Locks caused throughput to drop to 2-3x even with 20 agents.

4. **Fresh Context Per Iteration** - Each agent spawns fresh. Memory persists via files, not in-context.

5. **Periodic Executive Oversight** - Strategic decisions happen periodically, not every cycle. This provides direction without creating bottlenecks.

## Prerequisites

- One of the following AI coding tools:
  - [Amp CLI](https://ampcode.com) (default)
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- `jq` installed (`brew install jq` on macOS, `apt install jq` on Linux)
- A git repository for your project

## Quick Start

### 1. Create a Project File

Copy `state/project.example.json` to `state/project.json` and customize:

```json
{
  "name": "MyApp",
  "description": "What you're building",
  "goals": [
    "Goal 1: Specific, measurable objective",
    "Goal 2: Another clear goal"
  ],
  "config": {
    "maxWorkers": 4,
    "executiveInterval": 10,
    "tool": "amp",
    "qualityChecks": ["npm run typecheck", "npm run test"]
  },
  "areas": [
    { "name": "backend", "path": "src/api/", "description": "API routes" },
    { "name": "frontend", "path": "src/components/", "description": "React UI" }
  ]
}
```

### 2. Run Mr. Burns

```bash
# Using Amp (default)
./burns.sh

# Using Claude Code
./burns.sh --tool claude

# With options
./burns.sh --workers 8 --max-cycles 200
```

### 3. Watch the Swarm Work

Mr. Burns will:
1. **Executive** reviews project goals and spawns planners
2. **Planners** explore the codebase and create atomic tasks
3. **Workers** claim tasks in parallel and implement them
4. **Executive** periodically checks progress and adjusts resources
5. Loop continues until all goals achieved or max cycles reached

## Configuration Options

```bash
./burns.sh [options]
  --tool amp|claude    AI tool to use (default: amp)
  --workers N          Number of parallel workers (default: 4)
  --exec-interval N    Run executive every N cycles (default: 10)
  --max-cycles N       Maximum total cycles (default: 100)
  --project FILE       Project config file (default: state/project.json)
```

## Directory Structure

```
mrburns/
├── burns.sh                 # Main orchestrator
├── state/
│   ├── project.json         # Project goals and config
│   ├── tasks/               # Task queue (one file per task)
│   │   ├── TASK-001.json
│   │   └── TASK-002.json
│   ├── agents/              # Active agent registry
│   └── logs/                # Per-agent logs
├── prompts/
│   ├── executive.md         # Executive agent instructions
│   ├── planner.md           # Planner agent instructions
│   └── worker.md            # Worker agent instructions
├── lib/
│   ├── task.sh              # Task queue operations
│   ├── agent.sh             # Agent lifecycle management
│   └── git.sh               # Git coordination utilities
└── flowchart/               # Interactive visualization
```

## Task Lifecycle

```
pending → claimed → in_progress → completed
                         │
                         └──→ failed (retry up to maxAttempts)
```

Tasks are claimed using atomic file operations (no locks). If a worker fails, the task is released back to the queue for another worker to attempt.

## Git Strategy

Each task gets its own branch:
```
main
├── burns/task-001 (worker-1)
├── burns/task-002 (worker-2)
├── burns/task-003 (worker-3)
└── burns/task-004 (worker-4)
```

Workers push to their task branch. Merges happen after task completion.

## Monitoring Progress

```bash
# See task status
cat state/tasks/*.json | jq '{id, title, status}'

# See active agents
cat state/agents/*.json | jq '{id, type, currentTask}'

# See task counts
source lib/task.sh && count_tasks

# Check progress log
cat state/progress.txt
```

## Flowchart

The `flowchart/` directory contains an interactive visualization of the swarm architecture.

```bash
cd flowchart
npm install
npm run dev
```

## References

- [Cursor: Scaling Long-Running Autonomous Coding](https://cursor.com/blog/scaling-autonomous-coding)
- [Amp Documentation](https://ampcode.com/manual)
- [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code)
