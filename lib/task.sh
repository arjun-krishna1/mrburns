#!/bin/bash
# Mr. Burns - Task Queue Operations
# Lock-free task management using filesystem atomic operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$(dirname "$SCRIPT_DIR")/state"
TASKS_DIR="$STATE_DIR/tasks"

# Initialize task directory
init_tasks() {
  mkdir -p "$TASKS_DIR"
}

# Create a new task
# Usage: create_task "TASK-001" "title" "description" "planner-1" 1 '["dep1"]' '["criterion1"]'
create_task() {
  local id="$1"
  local title="$2"
  local description="$3"
  local created_by="$4"
  local priority="${5:-1}"
  local dependencies="${6:-[]}"
  local criteria="${7:-[]}"
  
  local task_file="$TASKS_DIR/${id}.json"
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  # Don't overwrite existing task
  if [[ -f "$task_file" ]]; then
    echo "Task $id already exists" >&2
    return 1
  fi
  
  cat > "$task_file" << EOF
{
  "id": "$id",
  "title": "$title",
  "description": "$description",
  "status": "pending",
  "priority": $priority,
  "assignedTo": null,
  "createdBy": "$created_by",
  "dependencies": $dependencies,
  "acceptanceCriteria": $criteria,
  "branch": "burns/${id,,}",
  "attempts": 0,
  "maxAttempts": 3,
  "createdAt": "$now",
  "updatedAt": "$now"
}
EOF
  
  echo "Created task: $id"
}

# Claim a task atomically (lock-free using mv)
# Usage: claim_task "worker-1"
# Returns: task ID if successful, empty if no tasks available
claim_task() {
  local agent_id="$1"
  
  # Find pending tasks sorted by priority
  for task_file in $(ls -1 "$TASKS_DIR"/*.json 2>/dev/null | sort); do
    # Skip if not a pending task
    local status=$(jq -r '.status' "$task_file" 2>/dev/null)
    [[ "$status" != "pending" ]] && continue
    
    # Check dependencies are met
    local deps_met=true
    local deps=$(jq -r '.dependencies[]' "$task_file" 2>/dev/null)
    for dep in $deps; do
      local dep_status=$(jq -r '.status' "$TASKS_DIR/${dep}.json" 2>/dev/null)
      if [[ "$dep_status" != "completed" ]]; then
        deps_met=false
        break
      fi
    done
    [[ "$deps_met" != "true" ]] && continue
    
    # Try to claim using atomic rename
    local task_id=$(jq -r '.id' "$task_file")
    local claimed_file="$TASKS_DIR/${task_id}.claimed.json"
    
    # Atomic move - fails if another agent claimed first
    if mv "$task_file" "$claimed_file" 2>/dev/null; then
      # Update task status
      local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      jq --arg agent "$agent_id" --arg now "$now" \
        '.status = "claimed" | .assignedTo = $agent | .updatedAt = $now | .attempts += 1' \
        "$claimed_file" > "$claimed_file.tmp" && mv "$claimed_file.tmp" "$claimed_file"
      
      # Move back to standard name
      mv "$claimed_file" "$task_file"
      
      echo "$task_id"
      return 0
    fi
  done
  
  # No tasks available
  return 1
}

# Update task status
# Usage: update_task_status "TASK-001" "in_progress|completed|failed" ["error message"]
update_task_status() {
  local task_id="$1"
  local new_status="$2"
  local error_msg="${3:-}"
  local task_file="$TASKS_DIR/${task_id}.json"
  
  if [[ ! -f "$task_file" ]]; then
    echo "Task $task_id not found" >&2
    return 1
  fi
  
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  if [[ -n "$error_msg" ]]; then
    jq --arg status "$new_status" --arg now "$now" --arg err "$error_msg" \
      '.status = $status | .updatedAt = $now | .error = $err' \
      "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
  else
    jq --arg status "$new_status" --arg now "$now" \
      '.status = $status | .updatedAt = $now' \
      "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
  fi
}

# Release a claimed task (on failure/timeout)
# Usage: release_task "TASK-001"
release_task() {
  local task_id="$1"
  local task_file="$TASKS_DIR/${task_id}.json"
  
  if [[ ! -f "$task_file" ]]; then
    echo "Task $task_id not found" >&2
    return 1
  fi
  
  local attempts=$(jq -r '.attempts' "$task_file")
  local max_attempts=$(jq -r '.maxAttempts' "$task_file")
  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  
  if (( attempts >= max_attempts )); then
    # Mark as failed after max attempts
    jq --arg now "$now" \
      '.status = "failed" | .assignedTo = null | .updatedAt = $now | .error = "Max attempts exceeded"' \
      "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
    echo "Task $task_id failed after $max_attempts attempts"
  else
    # Release back to pending
    jq --arg now "$now" \
      '.status = "pending" | .assignedTo = null | .updatedAt = $now' \
      "$task_file" > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
    echo "Task $task_id released (attempt $attempts of $max_attempts)"
  fi
}

# Get task details
# Usage: get_task "TASK-001"
get_task() {
  local task_id="$1"
  local task_file="$TASKS_DIR/${task_id}.json"
  
  if [[ -f "$task_file" ]]; then
    cat "$task_file"
  else
    echo "Task $task_id not found" >&2
    return 1
  fi
}

# List all tasks with optional status filter
# Usage: list_tasks [status]
list_tasks() {
  local filter_status="$1"
  
  for task_file in "$TASKS_DIR"/*.json; do
    [[ ! -f "$task_file" ]] && continue
    
    if [[ -n "$filter_status" ]]; then
      local status=$(jq -r '.status' "$task_file")
      [[ "$status" != "$filter_status" ]] && continue
    fi
    
    jq -c '{id, title, status, priority, assignedTo}' "$task_file"
  done | jq -s 'sort_by(.priority)'
}

# Count tasks by status
# Usage: count_tasks
count_tasks() {
  local pending=0 claimed=0 in_progress=0 completed=0 failed=0
  
  for task_file in "$TASKS_DIR"/*.json; do
    [[ ! -f "$task_file" ]] && continue
    local status=$(jq -r '.status' "$task_file")
    case "$status" in
      pending) ((pending++)) ;;
      claimed) ((claimed++)) ;;
      in_progress) ((in_progress++)) ;;
      completed) ((completed++)) ;;
      failed) ((failed++)) ;;
    esac
  done
  
  echo "{\"pending\":$pending,\"claimed\":$claimed,\"in_progress\":$in_progress,\"completed\":$completed,\"failed\":$failed}"
}

# Check if all tasks are complete
# Usage: all_tasks_complete && echo "Done!"
all_tasks_complete() {
  local counts=$(count_tasks)
  local pending=$(echo "$counts" | jq -r '.pending')
  local claimed=$(echo "$counts" | jq -r '.claimed')
  local in_progress=$(echo "$counts" | jq -r '.in_progress')
  
  [[ "$pending" == "0" && "$claimed" == "0" && "$in_progress" == "0" ]]
}

# Get next task ID
# Usage: next_task_id
next_task_id() {
  local max_num=0
  
  for task_file in "$TASKS_DIR"/TASK-*.json; do
    [[ ! -f "$task_file" ]] && continue
    local id=$(basename "$task_file" .json)
    local num=${id#TASK-}
    num=${num%%.*}  # Remove any .claimed suffix
    num=$((10#$num))  # Force decimal interpretation
    (( num > max_num )) && max_num=$num
  done
  
  printf "TASK-%03d" $((max_num + 1))
}

