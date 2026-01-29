#!/bin/bash
# Mr. Burns - Git Coordination Utilities
# Branch management and conflict prevention for parallel workers

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Get the main branch name (main or master)
get_main_branch() {
  if git show-ref --verify --quiet refs/heads/main; then
    echo "main"
  elif git show-ref --verify --quiet refs/heads/master; then
    echo "master"
  else
    echo "main"  # Default to main
  fi
}

# Create a task branch from main
# Usage: create_task_branch "burns/task-001"
create_task_branch() {
  local branch_name="$1"
  local main_branch=$(get_main_branch)
  
  # Fetch latest
  git fetch origin "$main_branch" 2>/dev/null || true
  
  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    git checkout "$branch_name"
    echo "Switched to existing branch: $branch_name"
  else
    # Create from main
    git checkout -b "$branch_name" "origin/$main_branch" 2>/dev/null || \
    git checkout -b "$branch_name" "$main_branch"
    echo "Created branch: $branch_name"
  fi
}

# Switch to a branch (create if doesn't exist)
# Usage: switch_branch "burns/task-001"
switch_branch() {
  local branch_name="$1"
  
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    git checkout "$branch_name"
  else
    create_task_branch "$branch_name"
  fi
}

# Update branch from main (rebase)
# Usage: update_from_main "burns/task-001"
update_from_main() {
  local branch_name="$1"
  local main_branch=$(get_main_branch)
  
  git fetch origin "$main_branch" 2>/dev/null || true
  
  # Try to rebase, abort if conflicts
  if ! git rebase "origin/$main_branch" 2>/dev/null; then
    git rebase --abort 2>/dev/null || true
    return 1
  fi
  
  return 0
}

# Check if branch has conflicts with main
# Usage: has_conflicts_with_main "burns/task-001"
has_conflicts_with_main() {
  local branch_name="$1"
  local main_branch=$(get_main_branch)
  local current_branch=$(git branch --show-current)
  
  # Save current state
  git stash push -m "burns-conflict-check" 2>/dev/null || true
  
  # Try merge without committing
  git checkout "$main_branch" 2>/dev/null
  if git merge --no-commit --no-ff "$branch_name" 2>/dev/null; then
    git merge --abort 2>/dev/null || true
    git checkout "$current_branch" 2>/dev/null
    git stash pop 2>/dev/null || true
    return 1  # No conflicts
  else
    git merge --abort 2>/dev/null || true
    git checkout "$current_branch" 2>/dev/null
    git stash pop 2>/dev/null || true
    return 0  # Has conflicts
  fi
}

# Commit changes with standard format
# Usage: commit_task "TASK-001" "Add priority field to database"
commit_task() {
  local task_id="$1"
  local title="$2"
  
  git add -A
  git commit -m "feat: [$task_id] $title"
}

# Push branch to origin
# Usage: push_branch "burns/task-001"
push_branch() {
  local branch_name="$1"
  git push -u origin "$branch_name" 2>/dev/null || \
  git push --force-with-lease origin "$branch_name"
}

# Get list of files changed in a branch compared to main
# Usage: get_changed_files "burns/task-001"
get_changed_files() {
  local branch_name="$1"
  local main_branch=$(get_main_branch)
  
  git diff --name-only "$main_branch...$branch_name" 2>/dev/null
}

# Check if two branches modify the same files (potential conflict)
# Usage: branches_overlap "burns/task-001" "burns/task-002"
branches_overlap() {
  local branch1="$1"
  local branch2="$2"
  
  local files1=$(get_changed_files "$branch1" | sort)
  local files2=$(get_changed_files "$branch2" | sort)
  
  # Check for common files
  local common=$(comm -12 <(echo "$files1") <(echo "$files2"))
  
  [[ -n "$common" ]]
}

# Merge a completed task branch to main
# Usage: merge_to_main "burns/task-001"
merge_to_main() {
  local branch_name="$1"
  local main_branch=$(get_main_branch)
  local current_branch=$(git branch --show-current)
  
  git checkout "$main_branch"
  git pull origin "$main_branch" 2>/dev/null || true
  
  if git merge --no-ff "$branch_name" -m "Merge $branch_name"; then
    git push origin "$main_branch"
    git checkout "$current_branch" 2>/dev/null || git checkout "$main_branch"
    return 0
  else
    git merge --abort
    git checkout "$current_branch" 2>/dev/null || git checkout "$main_branch"
    return 1
  fi
}

# Delete a task branch (local and remote)
# Usage: delete_task_branch "burns/task-001"
delete_task_branch() {
  local branch_name="$1"
  local main_branch=$(get_main_branch)
  
  # Switch to main first
  git checkout "$main_branch" 2>/dev/null || true
  
  # Delete local
  git branch -d "$branch_name" 2>/dev/null || \
  git branch -D "$branch_name" 2>/dev/null || true
  
  # Delete remote
  git push origin --delete "$branch_name" 2>/dev/null || true
}

# Get current branch
# Usage: current_branch
current_branch() {
  git branch --show-current
}

# Check if working directory is clean
# Usage: is_clean && echo "Clean!"
is_clean() {
  [[ -z "$(git status --porcelain)" ]]
}

# Stash current changes
# Usage: stash_changes "worker-1-wip"
stash_changes() {
  local name="$1"
  git stash push -m "$name"
}

# Pop stashed changes
# Usage: pop_stash "worker-1-wip"
pop_stash() {
  local name="$1"
  local stash_ref=$(git stash list | grep "$name" | head -1 | cut -d: -f1)
  
  if [[ -n "$stash_ref" ]]; then
    git stash pop "$stash_ref"
  fi
}

