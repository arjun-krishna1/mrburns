#!/bin/bash
# Mr. Burns - Agent Lifecycle Management
# Manages executive, planner, and worker agent instances

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(dirname "$SCRIPT_DIR")/state"
AGENTS_DIR="$STATE_DIR/agents"
LOGS_DIR="$STATE_DIR/logs"

# Agent types
AGENT_TYPE_EXECUTIVE="executive"
AGENT_TYPE_PLANNER="planner"
AGENT_TYPE_WORKER="worker"

# Initialize agent directories
init_agents() {
  mkdir -p "$AGENTS_DIR" "$LOGS_DIR"
}

# Register a new agent
# Usage: register_agent "worker" "worker-1" ["area"]
register_agent() {
  local agent_type="$1"
  local agent_id="$2"
  local area="${3:-}"
  
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  cat > "$agent_file" << EOF
{
  "id": "$agent_id",
  "type": "$agent_type",
  "status": "active",
  "area": "$area",
  "currentTask": null,
  "tasksCompleted": 0,
  "tasksFailed": 0,
  "startedAt": "$now",
  "lastHeartbeat": "$now",
  "pid": $$
}
EOF
  
  echo "Registered agent: $agent_id ($agent_type)"
}

# Update agent heartbeat
# Usage: heartbeat "worker-1"
heartbeat() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ ! -f "$agent_file" ]]; then
    return 1
  fi
  
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  jq --arg now "$now" '.lastHeartbeat = $now' \
    "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
}

# Update agent's current task
# Usage: set_agent_task "worker-1" "TASK-001"
set_agent_task() {
  local agent_id="$1"
  local task_id="$2"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ ! -f "$agent_file" ]]; then
    return 1
  fi
  
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  if [[ -z "$task_id" || "$task_id" == "null" ]]; then
    jq --arg now "$now" '.currentTask = null | .lastHeartbeat = $now' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
  else
    jq --arg task "$task_id" --arg now "$now" \
      '.currentTask = $task | .lastHeartbeat = $now' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
  fi
}

# Increment agent task counters
# Usage: agent_task_completed "worker-1"
# Usage: agent_task_failed "worker-1"
agent_task_completed() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    jq '.tasksCompleted += 1 | .currentTask = null' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
  fi
}

agent_task_failed() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    jq '.tasksFailed += 1 | .currentTask = null' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
  fi
}

# Deregister an agent
# Usage: deregister_agent "worker-1"
deregister_agent() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --arg now "$now" '.status = "stopped" | .stoppedAt = $now' \
      "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
    echo "Deregistered agent: $agent_id"
  fi
}

# Get agent info
# Usage: get_agent "worker-1"
get_agent() {
  local agent_id="$1"
  local agent_file="$AGENTS_DIR/${agent_id}.json"
  
  if [[ -f "$agent_file" ]]; then
    cat "$agent_file"
  else
    return 1
  fi
}

# List all agents by type
# Usage: list_agents [type]
list_agents() {
  local filter_type="$1"
  
  for agent_file in "$AGENTS_DIR"/*.json; do
    [[ ! -f "$agent_file" ]] && continue
    
    if [[ -n "$filter_type" ]]; then
      local type=$(jq -r '.type' "$agent_file")
      [[ "$type" != "$filter_type" ]] && continue
    fi
    
    jq -c '{id, type, status, currentTask, tasksCompleted}' "$agent_file"
  done | jq -s '.'
}

# Count active agents by type
# Usage: count_active_agents "worker"
count_active_agents() {
  local agent_type="$1"
  local count=0
  
  for agent_file in "$AGENTS_DIR"/*.json; do
    [[ ! -f "$agent_file" ]] && continue
    
    local type=$(jq -r '.type' "$agent_file")
    local status=$(jq -r '.status' "$agent_file")
    
    if [[ "$type" == "$agent_type" && "$status" == "active" ]]; then
      ((count++))
    fi
  done
  
  echo "$count"
}

# Generate next agent ID for a type
# Usage: next_agent_id "worker" -> "worker-3"
next_agent_id() {
  local agent_type="$1"
  local max_num=0
  
  for agent_file in "$AGENTS_DIR"/${agent_type}-*.json; do
    [[ ! -f "$agent_file" ]] && continue
    local id=$(basename "$agent_file" .json)
    local num=${id#${agent_type}-}
    (( num > max_num )) && max_num=$num
  done
  
  echo "${agent_type}-$((max_num + 1))"
}

# Log to agent's log file
# Usage: agent_log "worker-1" "Started working on TASK-001"
agent_log() {
  local agent_id="$1"
  local message="$2"
  local log_file="$LOGS_DIR/${agent_id}.log"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  echo "[$timestamp] $message" >> "$log_file"
}

# Check for stale agents (no heartbeat in X seconds)
# Usage: check_stale_agents 300
check_stale_agents() {
  local timeout_seconds="${1:-300}"
  local now=$(date +%s)
  local stale_agents=()
  
  for agent_file in "$AGENTS_DIR"/*.json; do
    [[ ! -f "$agent_file" ]] && continue
    
    local status=$(jq -r '.status' "$agent_file")
    [[ "$status" != "active" ]] && continue
    
    local last_heartbeat=$(jq -r '.lastHeartbeat' "$agent_file")
    local heartbeat_epoch=$(date -d "$last_heartbeat" +%s 2>/dev/null || echo 0)
    local age=$((now - heartbeat_epoch))
    
    if (( age > timeout_seconds )); then
      local agent_id=$(jq -r '.id' "$agent_file")
      stale_agents+=("$agent_id")
    fi
  done
  
  printf '%s\n' "${stale_agents[@]}"
}

# Clean up stale agents and release their tasks
# Usage: cleanup_stale_agents 300
cleanup_stale_agents() {
  local timeout_seconds="${1:-300}"
  
  source "$(dirname "${BASH_SOURCE[0]}")/task.sh"
  
  for agent_id in $(check_stale_agents "$timeout_seconds"); do
    local agent_file="$AGENTS_DIR/${agent_id}.json"
    local current_task=$(jq -r '.currentTask // empty' "$agent_file")
    
    # Release the task if agent had one
    if [[ -n "$current_task" ]]; then
      release_task "$current_task"
      echo "Released task $current_task from stale agent $agent_id"
    fi
    
    # Mark agent as stale
    jq '.status = "stale"' "$agent_file" > "$agent_file.tmp" && mv "$agent_file.tmp" "$agent_file"
    echo "Marked agent $agent_id as stale"
  done
}

