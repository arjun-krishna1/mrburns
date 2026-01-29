#!/bin/bash
# Mr. Burns - Executive-Planner-Worker Swarm Orchestrator
# Multi-agent autonomous coding system
#
# Usage: ./burns.sh [options]
#   --tool amp|claude    AI tool to use (default: amp)
#   --workers N          Number of parallel workers (default: 4)
#   --exec-interval N    Run executive every N worker cycles (default: 10)
#   --max-cycles N       Maximum total cycles (default: 100)
#   --project FILE       Project config file (default: state/project.json)

set -e

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$SCRIPT_DIR/state"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
LIB_DIR="$SCRIPT_DIR/lib"

# Defaults
TOOL="amp"
MAX_WORKERS=4
EXECUTIVE_INTERVAL=10
MAX_CYCLES=100
PROJECT_FILE="$STATE_DIR/project.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
    --workers)
      MAX_WORKERS="$2"
      shift 2
      ;;
    --workers=*)
      MAX_WORKERS="${1#*=}"
      shift
      ;;
    --exec-interval)
      EXECUTIVE_INTERVAL="$2"
      shift 2
      ;;
    --exec-interval=*)
      EXECUTIVE_INTERVAL="${1#*=}"
      shift
      ;;
    --max-cycles)
      MAX_CYCLES="$2"
      shift 2
      ;;
    --max-cycles=*)
      MAX_CYCLES="${1#*=}"
      shift
      ;;
    --project)
      PROJECT_FILE="$2"
      shift 2
      ;;
    --project=*)
      PROJECT_FILE="${1#*=}"
      shift
      ;;
    --help|-h)
      echo "Mr. Burns - Executive-Planner-Worker Swarm"
      echo ""
      echo "Usage: ./burns.sh [options]"
      echo ""
      echo "Options:"
      echo "  --tool amp|claude    AI tool to use (default: amp)"
      echo "  --workers N          Number of parallel workers (default: 4)"
      echo "  --exec-interval N    Run executive every N cycles (default: 10)"
      echo "  --max-cycles N       Maximum total cycles (default: 100)"
      echo "  --project FILE       Project config file"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi

# Source libraries
source "$LIB_DIR/task.sh"
source "$LIB_DIR/agent.sh"
source "$LIB_DIR/git.sh"

# =============================================================================
# Initialization
# =============================================================================

init_state() {
  echo "Initializing Mr. Burns state..."
  
  mkdir -p "$STATE_DIR/tasks" "$STATE_DIR/agents" "$STATE_DIR/logs"
  
  # Check for project file
  if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "Error: Project file not found: $PROJECT_FILE"
    echo "Create one based on state/project.example.json"
    exit 1
  fi
  
  # Initialize progress log
  if [[ ! -f "$STATE_DIR/progress.txt" ]]; then
    echo "# Mr. Burns Progress Log" > "$STATE_DIR/progress.txt"
    echo "Started: $(date)" >> "$STATE_DIR/progress.txt"
    echo "---" >> "$STATE_DIR/progress.txt"
  fi
  
  echo "State initialized."
}

# =============================================================================
# Agent Runners
# =============================================================================

run_executive() {
  local exec_id="executive-1"
  
  echo ""
  echo "========================================"
  echo "  Running Executive Agent"
  echo "========================================"
  
  register_agent "executive" "$exec_id"
  agent_log "$exec_id" "Starting executive review"
  
  # Build context for executive
  local context=$(cat << EOF
# Current State

## Project
$(cat "$PROJECT_FILE")

## Task Counts
$(count_tasks)

## Task Details
$(list_tasks)

## Active Agents
$(list_agents)

EOF
)
  
  # Run the AI tool with executive prompt
  local prompt_file="$PROMPTS_DIR/executive.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  agent_log "$exec_id" "Executive review complete"
  heartbeat "$exec_id"
  
  # Parse executive decision
  if echo "$output" | grep -q "<burns>COMPLETE</burns>"; then
    echo "Executive: Project COMPLETE"
    return 0
  elif echo "$output" | grep -q "<burns>STUCK</burns>"; then
    echo "Executive: Project STUCK - needs human intervention"
    return 2
  elif echo "$output" | grep -q "<burns>SPAWN_PLANNER:"; then
    local area=$(echo "$output" | grep -o "<burns>SPAWN_PLANNER:[^<]*</burns>" | sed 's/<burns>SPAWN_PLANNER:\([^<]*\)<\/burns>/\1/')
    echo "Executive: Spawning planner for area: $area"
    spawn_planner "$area" &
  elif echo "$output" | grep -q "<burns>TERMINATE_PLANNER:"; then
    local planner_id=$(echo "$output" | grep -o "<burns>TERMINATE_PLANNER:[^<]*</burns>" | sed 's/<burns>TERMINATE_PLANNER:\([^<]*\)<\/burns>/\1/')
    echo "Executive: Terminating planner: $planner_id"
    deregister_agent "$planner_id"
  fi
  
  # Default: continue
  return 1
}

run_planner() {
  local area="${1:-general}"
  local planner_id=$(next_agent_id "planner")
  
  echo ""
  echo "========================================"
  echo "  Running Planner: $planner_id (area: $area)"
  echo "========================================"
  
  register_agent "planner" "$planner_id" "$area"
  agent_log "$planner_id" "Starting planning for area: $area"
  
  # Build context for planner
  local context=$(cat << EOF
# Planning Context

## Your Assignment
Area: $area

## Project Goals
$(cat "$PROJECT_FILE")

## Existing Tasks
$(list_tasks)

EOF
)
  
  # Run the AI tool with planner prompt
  local prompt_file="$PROMPTS_DIR/planner.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  agent_log "$planner_id" "Planning complete"
  heartbeat "$planner_id"
  
  # Check for planning signals
  if echo "$output" | grep -q "<burns>PLANNING_DONE</burns>"; then
    echo "Planner $planner_id: Planning complete for $area"
  elif echo "$output" | grep -q "<burns>AREA_COMPLETE</burns>"; then
    echo "Planner $planner_id: Area $area is already complete"
    deregister_agent "$planner_id"
  elif echo "$output" | grep -q "<burns>NEED_CLARIFICATION:"; then
    local question=$(echo "$output" | grep -o "<burns>NEED_CLARIFICATION:[^<]*</burns>" | sed 's/<burns>NEED_CLARIFICATION:\([^<]*\)<\/burns>/\1/')
    echo "Planner $planner_id needs clarification: $question"
    agent_log "$planner_id" "Needs clarification: $question"
  fi
}

spawn_planner() {
  local area="$1"
  run_planner "$area"
}

run_worker() {
  local worker_num="$1"
  local worker_id="worker-$worker_num"
  
  echo ""
  echo "----------------------------------------"
  echo "  Worker $worker_id starting"
  echo "----------------------------------------"
  
  register_agent "worker" "$worker_id"
  agent_log "$worker_id" "Worker starting"
  
  # Try to claim a task
  local task_id=$(claim_task "$worker_id")
  
  if [[ -z "$task_id" ]]; then
    echo "Worker $worker_id: No tasks available"
    agent_log "$worker_id" "No tasks available"
    deregister_agent "$worker_id"
    return 0
  fi
  
  echo "Worker $worker_id: Claimed task $task_id"
  set_agent_task "$worker_id" "$task_id"
  agent_log "$worker_id" "Claimed task: $task_id"
  
  # Update task status to in_progress
  update_task_status "$task_id" "in_progress"
  
  # Get task details
  local task_json=$(get_task "$task_id")
  local task_title=$(echo "$task_json" | jq -r '.title')
  local task_branch=$(echo "$task_json" | jq -r '.branch')
  
  # Build context for worker
  local context=$(cat << EOF
# Your Task

## Task Details
$task_json

## Project Info
$(cat "$PROJECT_FILE" | jq '{name, description, config}')

EOF
)
  
  # Run the AI tool with worker prompt
  local prompt_file="$PROMPTS_DIR/worker.md"
  local output
  
  if [[ "$TOOL" == "amp" ]]; then
    output=$(echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | amp --dangerously-allow-all 2>&1 | tee /dev/stderr) || true
  else
    output=$(echo -e "$context\n\n---\n\n$(cat "$prompt_file")" | claude --dangerously-skip-permissions --print 2>&1 | tee /dev/stderr) || true
  fi
  
  heartbeat "$worker_id"
  
  # Parse worker result
  if echo "$output" | grep -q "<burns>TASK_COMPLETE:$task_id</burns>"; then
    echo "Worker $worker_id: Task $task_id COMPLETED"
    update_task_status "$task_id" "completed"
    agent_task_completed "$worker_id"
    agent_log "$worker_id" "Completed task: $task_id"
    
    # Log to progress file
    echo "" >> "$STATE_DIR/progress.txt"
    echo "## $(date) - $task_id" >> "$STATE_DIR/progress.txt"
    echo "- Completed by: $worker_id" >> "$STATE_DIR/progress.txt"
    echo "- Title: $task_title" >> "$STATE_DIR/progress.txt"
    echo "---" >> "$STATE_DIR/progress.txt"
    
  elif echo "$output" | grep -q "<burns>TASK_FAILED:$task_id"; then
    local reason=$(echo "$output" | grep -o "<burns>TASK_FAILED:$task_id:[^<]*</burns>" | sed "s/<burns>TASK_FAILED:$task_id:\([^<]*\)<\/burns>/\1/")
    echo "Worker $worker_id: Task $task_id FAILED - $reason"
    agent_task_failed "$worker_id"
    agent_log "$worker_id" "Failed task: $task_id - $reason"
    release_task "$task_id"
    
  elif echo "$output" | grep -q "<burns>NO_TASKS</burns>"; then
    echo "Worker $worker_id: No tasks available"
    agent_log "$worker_id" "No tasks to claim"
    
  else
    # No clear signal - treat as incomplete, release task
    echo "Worker $worker_id: Task $task_id - no completion signal, releasing"
    agent_log "$worker_id" "No completion signal for: $task_id"
    release_task "$task_id"
  fi
  
  set_agent_task "$worker_id" ""
  deregister_agent "$worker_id"
}

# =============================================================================
# Main Loop
# =============================================================================

main() {
  echo "=============================================="
  echo "  Mr. Burns - Executive-Planner-Worker Swarm"
  echo "=============================================="
  echo ""
  echo "Configuration:"
  echo "  Tool: $TOOL"
  echo "  Max Workers: $MAX_WORKERS"
  echo "  Executive Interval: $EXECUTIVE_INTERVAL cycles"
  echo "  Max Cycles: $MAX_CYCLES"
  echo "  Project: $PROJECT_FILE"
  echo ""
  
  # Initialize
  init_state
  
  # Check if we need initial planning
  local task_count=$(list_tasks | jq -s 'length')
  if [[ "$task_count" == "0" ]]; then
    echo "No tasks found. Running initial planner..."
    run_planner "general"
  fi
  
  # Main loop
  local cycle=0
  while (( cycle < MAX_CYCLES )); do
    ((cycle++))
    
    echo ""
    echo "=============================================="
    echo "  Cycle $cycle of $MAX_CYCLES"
    echo "=============================================="
    
    # Periodic executive check
    if (( cycle % EXECUTIVE_INTERVAL == 0 )) || (( cycle == 1 )); then
      run_executive
      local exec_result=$?
      
      if [[ $exec_result -eq 0 ]]; then
        echo ""
        echo "=============================================="
        echo "  PROJECT COMPLETE!"
        echo "=============================================="
        echo "Completed at cycle $cycle of $MAX_CYCLES"
        exit 0
      elif [[ $exec_result -eq 2 ]]; then
        echo ""
        echo "=============================================="
        echo "  PROJECT STUCK - Human intervention needed"
        echo "=============================================="
        exit 2
      fi
    fi
    
    # Check if there are tasks to work on
    local pending=$(count_tasks | jq -r '.pending')
    local in_progress=$(count_tasks | jq -r '.in_progress')
    
    if [[ "$pending" == "0" && "$in_progress" == "0" ]]; then
      # Check if all complete
      if all_tasks_complete; then
        echo ""
        echo "=============================================="
        echo "  ALL TASKS COMPLETE!"
        echo "=============================================="
        exit 0
      fi
      
      # No work available but not complete - might need more planning
      echo "No pending tasks. Running planner..."
      run_planner "general"
      continue
    fi
    
    # Run workers in parallel
    local num_workers=$MAX_WORKERS
    if (( pending < MAX_WORKERS )); then
      num_workers=$pending
    fi
    
    echo "Spawning $num_workers workers..."
    
    local pids=()
    for i in $(seq 1 $num_workers); do
      run_worker $i &
      pids+=($!)
    done
    
    # Wait for all workers to complete
    for pid in "${pids[@]}"; do
      wait $pid 2>/dev/null || true
    done
    
    echo "Cycle $cycle complete."
    
    # Brief pause between cycles
    sleep 2
    
    # Clean up stale agents
    cleanup_stale_agents 300 2>/dev/null || true
  done
  
  echo ""
  echo "=============================================="
  echo "  Max cycles ($MAX_CYCLES) reached"
  echo "=============================================="
  echo "Check state/progress.txt for status."
  exit 1
}

# Run main
main

