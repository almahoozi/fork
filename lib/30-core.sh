# Check if a command exists in PATH
# Arguments:
#   $1 - Command name to check
# Returns:
#   0 if command exists, 1 otherwise
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Get the root directory of the current git repository
# Outputs:
#   Absolute path to repository root
# Returns:
#   0 on success
# Exits:
#   1 if not in a git repository
get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    printf '%s\n' 'Error: not in a git repository' >&2
    exit 1
  }
}

# Get the root directory of the main repository
# If in a worktree, returns the main repository root, not the worktree root
# Outputs:
#   Absolute path to main repository root
# Returns:
#   0 on success
get_main_repo_root() {
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"
  if [ -n "$common_dir" ] && [ "$common_dir" != ".git" ]; then
    # We're in a worktree, get the main repo root
    cd "$(dirname "$common_dir")" && pwd
  else
    get_repo_root
  fi
}

# Get the name of the repository
# Outputs:
#   Repository name (basename of main repo root)
# Returns:
#   0 on success
get_repo_name() {
  basename "$(get_main_repo_root)"
}

# Get the base directory where worktrees are stored
# Follows convention: ../<repo>_forks/
# Outputs:
#   Absolute path to worktree base directory
# Returns:
#   0 on success
get_worktree_base() {
  repo_name="$(get_repo_name)"
  repo_root="$(get_main_repo_root)"
  printf '%s\n' "$(dirname "$repo_root")/${repo_name}_forks"
}

# Get the full path to a specific worktree
# Arguments:
#   $1 - Branch name
# Outputs:
#   Absolute path to worktree for given branch
# Returns:
#   0 on success
get_worktree_path() {
  branch="$1"
  printf '%s\n' "$(get_worktree_base)/$branch"
}
