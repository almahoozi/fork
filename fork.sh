#!/bin/sh
# fork.sh - Manage git worktrees like a forking boss
#
# Usage:
#   fork [command] [args]
#
# Commands:
#   new <branch>... [-t|--target <base>]
#               Create worktrees from main (or --target base)
#   co <branch> Change to worktree (must exist)
#   go <branch> [-t|--target <base>]
#               Go to worktree (create if needed)
#   main        Go to main worktree
#   rm [branch...] [-f|--force] [-a|--all]
#               Remove worktree(s) (current if no branch given)
#               -f: force removal of unmerged or dirty branches
#               -a: remove all worktrees
#   ls [-m|--merged] [-u|--unmerged] [-d|--dirty] [-c|--clean]
#               List worktrees (default: all)
#   clean       Remove merged and clean worktrees
#   sh <bash|zsh|fish>
#               Output shell integration function
#   help [-v|--verbose]
#               Show help
#
# Convention: ../<repo>_forks/<branch>

set -eu

# Load environment variables from FORK_ENV file
# Reads and exports FORK_* prefixed variables from config file
# Globals:
#   FORK_ENV - Path to environment file (optional)
# Returns:
#   0 always (non-fatal if file missing or malformed)
load_env_file() {
  env_file="${FORK_ENV:-}"
  if [ -z "$env_file" ]; then
    return 0
  fi

  if [ ! -f "$env_file" ]; then
    return 0
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [ -z "$line" ] && continue

    case "$line" in
    *=*)
      var_name="${line%%=*}"
      var_value="${line#*=}"

      case "$var_name" in
      FORK_*)
        if printf '%s' "$var_name" | grep -Eq '^FORK_[A-Za-z0-9_]+$'; then
          export "$var_name=$var_value"
        fi
        ;;
      esac
      ;;
    esac
  done <"$env_file"
}

load_env_file

# Display usage information and help text
# Shows brief help by default, verbose help with -v or --verbose
# Arguments:
#   $1 - Optional: -v or --verbose for detailed help
# Outputs:
#   Help text to stderr
# Exits:
#   2 always (after displaying help)
usage() {
	verbose=0
	[ "${1-}" = "-v" ] || [ "${1-}" = "--verbose" ] && verbose=1

	if [ $verbose -eq 0 ]; then
		# Detect shell from $SHELL
		shell_integration=""
		case "${SHELL-}" in
		*/zsh)
			shell_integration='eval "$(fork sh zsh)"   # Add to ~/.zshrc'
			;;
		*/bash)
			shell_integration='eval "$(fork sh bash)"   # Add to ~/.bashrc'
			;;
		*/fish)
			shell_integration='fork sh fish | source   # Add to ~/.config/fish/config.fish'
			;;
		*)
			# Unknown or empty shell - show all options
			shell_integration='Bash/Zsh: eval "$(fork sh bash)"   # Add to ~/.bashrc or ~/.zshrc
  Fish:     fork sh fish | source   # Add to ~/.config/fish/config.fish'
			;;
		esac

		cat >&2 <<EOF
fork - Manage git worktrees like a forking boss

Usage: fork <command> [args]

Commands:
  new <branch>... [-t|--target <base>]    Create worktrees
  co <branch> [-c|--container]            Change to worktree
  go <branch> [-t|--target <base>]        Change to worktree (create if needed)
              [-c|--container]
  main                                    Go to main worktree
  rm [branch...] [-f|--force] [-a|--all]  Remove worktree(s)
                 [-c|--container]
  ls [<filters...>]                       List worktrees
                      [-m|--merged] 
                      [-u|--unmerged]
                      [-d|--dirty]
                      [-c|--clean]
                                              
  clean                                   Remove merged and clean worktrees
  sh [bash|zsh|fish]                      Output shell integration function
  help [-v|--verbose]                     Show help

Convention: ../<repo>_forks/<branch>

Shell Integration:
  $shell_integration

Configuration:
  Set FORK_ENV to load configuration from a file:
    export FORK_ENV=~/.config/fork/config.env
  
  Only FORK_* prefixed variables are loaded. Example config file:
    FORK_DIR_PATTERN=../{repo}_forks/{branch}
    FORK_CONTAINER=1
    FORK_CONTAINER_IMAGE=ubuntu:latest
    FORK_CONTAINER_NAME=myproject

Examples:
  fork new feature-x
  fork go feature-x
  fork go feature-x -c              Open in container
  fork main
  fork ls
  fork rm feature-x
  fork rm feature-x -c              Remove worktree and container
  fork rm -a
  fork clean

Run 'fork help --verbose' for detailed documentation.
EOF
	else
		# Verbose help always shows all shell options
		cat >&2 <<'EOF'
fork - Manage git worktrees like a forking boss

Usage: fork <command> [args]

Commands:
  new <branch>... [-t|--target <base>]
      Create worktrees from 'main' (or --target base). Creates branch if needed.
      Tracks remote branch if it exists, otherwise uses existing local branch,
      otherwise creates a new local branch.
      -t, --target <base>  Create from <base> instead of main

  co <branch> [-c|--container]
      Print path to worktree. Use: cd \$(fork co <branch>)
      With -c, opens an interactive shell in a container for isolated work.
      -c, --container  Open worktree in container

  go <branch> [-t|--target <base>] [-c|--container]
      Go to worktree (create if doesn't exist). Same options as 'new'.
      With -c, opens an interactive shell in a container for isolated work.
      -c, --container  Open worktree in container

  main
      Go to main/primary worktree.

  rm [branch...] [-f] [-a|--all] [-c|--container]
      Remove worktree(s). Defaults to current. Use -a for all.
      Worktrees are protected if unmerged or dirty (uncommitted/untracked changes).
      -f, --force     Force removal of unmerged or dirty branches
      -a, --all       Remove all worktrees
      -c, --container Also remove associated containers

  ls [-m|--merged] [-u|--unmerged] [-d|--dirty] [-c|--clean]
      List worktrees. Default: all. Output: <branch> <merge_status> <dirty_status> <path>
      -m, --merged   List only merged worktrees
      -u, --unmerged List only unmerged worktrees
      -d, --dirty    List only dirty worktrees (uncommitted/untracked changes)
      -c, --clean    List only clean worktrees

  clean
      Remove merged and clean worktrees. Worktrees with uncommitted changes,
      staged changes, or untracked files are automatically skipped.

  sh [bash|zsh|fish]
      Output shell integration function. If no shell specified, detects from $SHELL.

  help [-v|--verbose]
      Show this help.

Convention:
  Worktrees: ../<repo>_forks/<branch>
  Example: myapp_forks/feature-x
  Containers: {prefix}_{branch}_fork or {branch}_fork (if no prefix)

Shell Integration (required for cd-ing):
  Bash:  eval "$(fork sh bash)"   # Add to ~/.bashrc
  Zsh:   eval "$(fork sh zsh)"    # Add to ~/.zshrc
  Fish:  fork sh fish | source    # Add to ~/.config/fish/config.fish

Configuration:
  Set FORK_ENV to load configuration from a file on shell configuration:
    export FORK_ENV=~/.config/fork/config.env
  
  The env file should contain FORK_* prefixed variables (one per line).
  Lines starting with # are treated as comments. Example:
    # Fork configuration
    FORK_DIR_PATTERN=../{repo}_forks/{branch}
    FORK_CONTAINER=1
    FORK_CONTAINER_IMAGE=ubuntu:latest
    FORK_CONTAINER_NAME=myproject
  
  When using shell integration (fork sh), env vars are automatically
  embedded in the generated function and passed to every fork invocation.

Environment Variables:
  FORK_ENV              Path to configuration file (optional)
  FORK_CD               Internal flag for shell integration (do not set manually)
  FORK_DIR_PATTERN      Example config variable (displays on startup if set)
  FORK_CONTAINER        Set to 1 to enable container mode by default
  FORK_CONTAINER_IMAGE  Container image to use (default: ubuntu:latest)
  FORK_CONTAINER_NAME   Container name prefix (default: none)

Container Mode:
  Container mode creates isolated Docker containers for each fork, mounting
  only the worktree directory. This provides isolation from the host system.
  
  Requirements: Docker must be installed and running.
  
  Container naming: {FORK_CONTAINER_NAME}_{branch}_fork or {branch}_fork
  Mount point: /workspace (read-write access to worktree only)

Examples:
  fork new feature-x                   Create worktree for feature-x
  fork new feat-a feat-b               Create multiple worktrees
  fork new bugfix --target develop     Create from develop branch
  fork go feature-x                    Go to feature-x (create if needed)
  fork go feature-x -c                 Go to feature-x in container
  fork co feature-x -c                 Open existing worktree in container
  fork main                            Go to main worktree
  fork rm                              Remove current worktree
  fork rm feature-x                    Remove specific worktree
  fork rm feature-x -c                 Remove worktree and container
  fork rm feat-a feat-b                Remove multiple worktrees
  fork rm -a                           Remove all worktrees
  fork ls                              List all worktrees
  fork ls -u                           List unmerged worktrees
  fork ls -m                           List merged worktrees
  fork ls -d                           List dirty worktrees
  fork ls -c                           List clean worktrees
  fork clean                           Remove merged and clean worktrees
  fork sh                              Output shell integration (auto-detect from $SHELL)
  fork sh bash                         Output shell integration for bash/zsh
EOF
	fi
	exit 2
}

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

# Check if container runtime (Docker) is available
# Returns:
#   0 if Docker is available, 1 otherwise
container_runtime_available() {
	command -v docker >/dev/null 2>&1
}

# Get the container image to use
# Globals:
#   FORK_CONTAINER_IMAGE - User-specified image
# Outputs:
#   Image name to stdout
# Returns:
#   0 always
get_container_image() {
	printf '%s' "${FORK_CONTAINER_IMAGE:-ubuntu:latest}"
}

# Get the container name for a fork
# Arguments:
#   $1 - Branch/fork name
# Globals:
#   FORK_CONTAINER_NAME - User-specified container name prefix
# Outputs:
#   Container name to stdout
# Returns:
#   0 always
get_container_name() {
	branch="$1"
	if [ -n "${FORK_CONTAINER_NAME:-}" ]; then
		printf '%s_%s_fork' "$FORK_CONTAINER_NAME" "$branch"
	else
		printf '%s_fork' "$branch"
	fi
}

# Check if container exists
# Arguments:
#   $1 - Container name
# Returns:
#   0 if container exists, 1 otherwise
container_exists() {
	container_name="$1"
	docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Check if container is running
# Arguments:
#   $1 - Container name
# Returns:
#   0 if container is running, 1 otherwise
container_is_running() {
	container_name="$1"
	docker ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Create and start a container for a fork
# Arguments:
#   $1 - Branch/fork name
#   $2 - Worktree path
# Outputs:
#   Status messages to stderr
# Returns:
#   0 on success, 1 on failure
create_container() {
	branch="$1"
	worktree_path="$2"
	container_name="$(get_container_name "$branch")"
	image="$(get_container_image)"

	if ! container_runtime_available; then
		printf '%s\n' 'Error: Docker is not available. Please install Docker.' >&2
		return 1
	fi

	if container_exists "$container_name"; then
		if container_is_running "$container_name"; then
			return 0
		else
			docker start "$container_name" >/dev/null 2>&1 || {
				printf '%s\n' "Error: failed to start existing container: $container_name" >&2
				return 1
			}
			return 0
		fi
	fi

	worktree_path_abs="$(cd "$worktree_path" && pwd)"

	docker run -d \
		--name "$container_name" \
		-v "$worktree_path_abs:/workspace:rw" \
		-w /workspace \
		--entrypoint /bin/sh \
		"$image" \
		-c "while true; do sleep 3600; done" >/dev/null 2>&1 || {
		printf '%s\n' "Error: failed to create container: $container_name" >&2
		return 1
	}

	if [ "${FORK_CD:-0}" != "1" ]; then
		printf '%s\n' "Created container: $container_name" >&2
	fi

	return 0
}

# Remove a container for a fork
# Arguments:
#   $1 - Branch/fork name
# Outputs:
#   Status messages to stderr
# Returns:
#   0 on success, 1 on failure
remove_container() {
	branch="$1"
	container_name="$(get_container_name "$branch")"

	if ! container_runtime_available; then
		return 0
	fi

	if ! container_exists "$container_name"; then
		return 0
	fi

	docker rm -f "$container_name" >/dev/null 2>&1 || {
		printf '%s\n' "Warning: failed to remove container: $container_name" >&2
		return 1
	}

	if [ "${FORK_CD:-0}" != "1" ]; then
		printf '%s\n' "Removed container: $container_name" >&2
	fi

	return 0
}

# Get the command to enter a container
# Arguments:
#   $1 - Container name
# Outputs:
#   Command string to stdout
# Returns:
#   0 always
get_container_exec_command() {
	container_name="$1"
	printf 'docker exec -it %s /bin/sh' "$container_name"
}

# Check if a local branch exists
# Arguments:
#   $1 - Branch name
# Returns:
#   0 if branch exists, 1 otherwise
branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1" 2>/dev/null
}

# Check if a remote branch exists on origin
# Arguments:
#   $1 - Branch name
# Returns:
#   0 if remote branch exists, 1 otherwise
remote_branch_exists() {
  git show-ref --verify --quiet "refs/remotes/origin/$1" 2>/dev/null
}

# Check if a worktree exists for a given branch
# Verifies both directory existence and git worktree registration
# Arguments:
#   $1 - Branch name
# Returns:
#   0 if worktree exists, 1 otherwise
worktree_exists() {
  path="$(get_worktree_path "$1")"
  [ -d "$path" ] && git worktree list | grep "$(printf '%s' "$path" | sed 's/[]\/$*.^[]/\\&/g')" >/dev/null
}

# Check if a branch is merged into a base branch
# Arguments:
#   $1 - Branch name to check
#   $2 - Base branch (default: main)
# Returns:
#   0 if branch is merged, 1 otherwise
is_branch_merged() {
  branch="$1"
  base="${2:-main}"
  git branch --merged "$base" 2>/dev/null | awk '{print $NF}' | grep "^${branch}$" >/dev/null
}

# Get the branch name of the current worktree
# Only works if current directory is within a worktree (not main repo)
# Outputs:
#   Branch name if in a worktree
# Returns:
#   0 if in a worktree, 1 if in main repo or not in worktree base
get_current_worktree_branch() {
  current_dir="$(pwd)"
  worktree_base="$(get_worktree_base)"
  case "$current_dir" in
  "$worktree_base"/*)
    branch="${current_dir#"$worktree_base"/}"
    branch="${branch%%/*}"
    printf '%s\n' "$branch"
    return 0
    ;;
  *)
    return 1
    ;;
  esac
}

# Check if a worktree has uncommitted or untracked changes
# Arguments:
#   $1 - Path to worktree
# Returns:
#   0 if worktree is dirty (has changes), 1 if clean
is_worktree_dirty() {
  path="$1"
  (cd "$path" && ! git diff --quiet 2>/dev/null) ||
    (cd "$path" && ! git diff --cached --quiet 2>/dev/null) ||
    (cd "$path" && [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ])
}

# Create a worktree for a single branch
# Handles remote branch tracking, existing local branches, and new branch creation
# Arguments:
#   $1 - Branch name
#   $2 - Base branch to create from (if branch doesn't exist)
# Outputs:
#   Success/error messages to stderr
# Returns:
#   0 on success, 1 if worktree already exists
create_single_worktree() {
  branch="$1"
  base_branch="$2"

  path="$(get_worktree_path "$branch")"

  if worktree_exists "$branch"; then
    printf '%s\n' "Error: worktree for '$branch' already exists at $path" >&2
    return 1
  fi

  mkdir -p "$(get_worktree_base)"

  if remote_branch_exists "$branch"; then
    git worktree add "$path" "origin/$branch" >&2
  elif branch_exists "$branch"; then
    git worktree add "$path" "$branch" >&2
  else
    if remote_branch_exists "$base_branch"; then
      git worktree add -b "$branch" "$path" "origin/$base_branch" >&2
    else
      git worktree add -b "$branch" "$path" "$base_branch" >&2
    fi
  fi

  printf '%s\n' "Created worktree: $path" >&2
}

# Remove a single worktree
# Protects against removing unmerged or dirty worktrees unless forced
# Arguments:
#   $1 - Branch name
#   $2 - Force flag (0=no, 1=yes)
# Outputs:
#   Status messages to stderr
# Returns:
#   0 on success, 1 if worktree doesn't exist or is protected
remove_single_worktree() {
  branch="$1"
  force="$2"

  path="$(get_worktree_path "$branch")"

  if ! worktree_exists "$branch"; then
    printf '%s\n' "Error: worktree for '$branch' does not exist" >&2
    return 1
  fi

  if [ $force -eq 0 ]; then
    if ! is_branch_merged "$branch"; then
      printf '%s\n' "Error: branch '$branch' is not merged. Use -f to force removal." >&2
      return 1
    fi

    if is_worktree_dirty "$path"; then
      printf '%s\n' "Error: worktree '$branch' has uncommitted changes. Use -f to force removal." >&2
      return 1
    fi
  fi

  git worktree remove "$path" 2>/dev/null || git worktree remove --force "$path"
  printf '%s\n' "Removed worktree: $branch" >&2
  return 0
}

# Command: Create new worktree(s)
# Creates one or more worktrees from a base branch (default: main)
# Arguments:
#   <branch>... - One or more branch names
#   -t|--target <base> - Base branch to create from (optional)
# Outputs:
#   Status messages to stderr
# Exits:
#   1 on error (invalid arguments or creation failure)
cmd_new() {
	base_branch="main"
	branches=""

	while [ $# -gt 0 ]; do
		case "$1" in
		-t | --target)
			shift
			[ $# -gt 0 ] || {
				printf '%s\n' 'Error: -t|--target requires a branch argument' >&2
				exit 1
			}
			base_branch="$1"
			shift
			;;
		-*)
			printf '%s\n' "Error: unknown option: $1" >&2
			exit 1
			;;
		*)
			branches="$branches $1"
			shift
			;;
		esac
	done

	[ -n "$branches" ] || {
		printf '%s\n' 'Usage: fork new <branch>... [-t|--target <base>]' >&2
		exit 1
	}

	for branch in $branches; do
		create_single_worktree "$branch" "$base_branch"
	done
}

# Command: Change to worktree (checkout)
# Prints path to existing worktree for shell integration to cd into
# Arguments:
#   $1 - Branch name
#   -c|--container - Use container mode
# Outputs:
#   Worktree path to stdout (or container exec command if -c flag set)
#   Status message to stderr (unless FORK_CD=1)
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
#   FORK_LAST - Exports previous directory when FORK_CD=1
#   FORK_CONTAINER - Set to 1 to enable container mode
# Exits:
#   1 if worktree doesn't exist or invalid arguments
cmd_co() {
	use_container="${FORK_CONTAINER:-0}"

	while [ $# -gt 0 ]; do
		case "$1" in
		-c | --container)
			use_container=1
			shift
			;;
		-*)
			printf '%s\n' "Error: unknown option: $1" >&2
			exit 1
			;;
		*)
			break
			;;
		esac
	done

	if [ $# -ne 1 ]; then
		printf '%s\n' 'Usage: fork co <branch> [-c|--container]' >&2
		exit 1
	fi

	branch="$1"
	path="$(get_worktree_path "$branch")"

	if ! worktree_exists "$branch"; then
		printf '%s\n' "Error: worktree for '$branch' does not exist" >&2
		exit 1
	fi

	if [ "$use_container" = "1" ]; then
		export FORK_CONTAINER_EXEC=1
		container_name="$(get_container_name "$branch")"

		if ! container_exists "$container_name"; then
			if [ "${FORK_CD:-0}" != "1" ]; then
				printf '%s\n' "Container does not exist for '$branch', creating..." >&2
			fi
			create_container "$branch" "$path" || exit 1
		elif ! container_is_running "$container_name"; then
			if [ "${FORK_CD:-0}" != "1" ]; then
				printf '%s\n' "Starting container for '$branch'..." >&2
			fi
			docker start "$container_name" >/dev/null 2>&1 || {
				printf '%s\n' "Error: failed to start container: $container_name" >&2
				exit 1
			}
		fi

		printf '%s' "$(get_container_exec_command "$container_name")"
	else
		printf '%s\n' "$path"
	fi

	if [ "${FORK_CD:-0}" = "1" ]; then
		export FORK_LAST="$(pwd)"
	else
		if [ "$use_container" = "1" ]; then
			printf '%s\n' "Switched to container for worktree '$branch'" >&2
		else
			printf '%s\n' "Switched to worktree '$branch'" >&2
		fi
	fi
}

# Command: Go to main worktree
# Prints path to main repository (not a worktree) for shell integration
# Outputs:
#   Main repository path to stdout
#   Status message to stderr (unless FORK_CD=1)
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
# Returns:
#   0 on success
cmd_main() {

	repo_root="$(get_repo_root)"
	git_dir="$(cd "$repo_root" && git rev-parse --git-dir)"

	if [ "$git_dir" = ".git" ]; then
		printf '%s\n' "$repo_root"

		if [ "${FORK_CD:-0}" != "1" ]; then
			printf '%s\n' "Switched to main worktree" >&2
		fi
	else
		worktree_list="$(git worktree list --porcelain)"
		main_worktree="$(printf '%s\n' "$worktree_list" | awk '
			/^worktree / { path = substr($0, 10); getline; if ($0 !~ /^branch /) print path; exit }
		')"
		if [ -n "$main_worktree" ]; then
			printf '%s\n' "$main_worktree"
		else
			printf '%s\n' "$repo_root"
		fi

		if [ "${FORK_CD:-0}" != "1" ]; then
			printf '%s\n' "Switched to main worktree" >&2
		fi
	fi
}

# Command: Go to worktree (create if needed)
# Combines checkout and creation - creates worktree if it doesn't exist
# Arguments:
#   $1 - Branch name
#   -t|--target <base> - Base branch to create from if needed (optional)
#   -c|--container - Use container mode
# Outputs:
#   Worktree path to stdout (or container exec command if -c flag set)
#   Status messages to stderr
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
#   FORK_CONTAINER - Set to 1 to enable container mode
# Exits:
#   1 on error (invalid arguments or creation failure)
cmd_go() {
	base_branch="main"
	use_container="${FORK_CONTAINER:-0}"

	while [ $# -gt 0 ]; do
		case "$1" in
		-t | --target)
			shift
			[ $# -gt 0 ] || {
				printf '%s\n' 'Error: -t|--target requires a branch argument' >&2
				exit 1
			}
			base_branch="$1"
			shift
			;;
		-c | --container)
			use_container=1
			shift
			;;
		-*)
			printf '%s\n' "Error: unknown option: $1" >&2
			exit 1
			;;
		*)
			break
			;;
		esac
	done

	[ $# -eq 1 ] || {
		printf '%s\n' 'Usage: fork go <branch> [-t|--target <base>] [-c|--container]' >&2
		exit 1
	}

	branch="$1"
	path="$(get_worktree_path "$branch")"

	created=0
	if ! worktree_exists "$branch"; then
		create_single_worktree "$branch" "$base_branch"
		created=1
	fi

	if [ "$use_container" = "1" ]; then
		export FORK_CONTAINER_EXEC=1
		container_name="$(get_container_name "$branch")"

		if ! container_exists "$container_name"; then
			if [ "${FORK_CD:-0}" != "1" ]; then
				printf '%s\n' "Creating container for '$branch'..." >&2
			fi
			create_container "$branch" "$path" || exit 1
		elif ! container_is_running "$container_name"; then
			if [ "${FORK_CD:-0}" != "1" ]; then
				printf '%s\n' "Starting container for '$branch'..." >&2
			fi
			docker start "$container_name" >/dev/null 2>&1 || {
				printf '%s\n' "Error: failed to start container: $container_name" >&2
				exit 1
			}
		fi

		printf '%s' "$(get_container_exec_command "$container_name")"
	else
		printf '%s\n' "$path"
	fi

	if [ "${FORK_CD:-0}" != "1" ]; then
		if [ $created -eq 1 ]; then
			if [ "$use_container" = "1" ]; then
				printf '%s\n' "Created worktree and container for '$branch'" >&2
			else
				printf '%s\n' "Created and switched to worktree '$branch'" >&2
			fi
		else
			if [ "$use_container" = "1" ]; then
				printf '%s\n' "Switched to container for worktree '$branch'" >&2
			else
				printf '%s\n' "Switched to worktree '$branch'" >&2
			fi
		fi
	fi
}

# Command: Remove worktree(s)
# Removes one or more worktrees with safety checks for unmerged/dirty branches
# Arguments:
#   [branch...] - Branch names (optional, defaults to current worktree)
#   -f|--force - Force removal of unmerged or dirty branches
#   -a|--all - Remove all worktrees
#   -c|--container - Also remove associated containers
# Outputs:
#   Main repository path to stdout (for shell integration to cd)
#   Status messages to stderr
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
#   FORK_CONTAINER - Set to 1 to also remove containers
# Exits:
#   1 if removal fails or not in worktree when no branch specified
cmd_rm() {
	force=0
	all=0
	remove_containers="${FORK_CONTAINER:-0}"
	branches=""

	while [ $# -gt 0 ]; do
		case "$1" in
		-f | --force)
			force=1
			shift
			;;
		-a | --all)
			all=1
			shift
			;;
		-c | --container)
			remove_containers=1
			shift
			;;
		-*)
			printf '%s\n' "Error: unknown option: $1" >&2
			exit 1
			;;
		*)
			branches="$branches $1"
			shift
			;;
		esac
	done

	# Handle -a/--all flag
	if [ $all -eq 1 ]; then
		# Get all worktrees
		worktree_base="$(get_worktree_base)"
		if [ ! -d "$worktree_base" ]; then
			printf '%s\n' "No worktrees to remove"
			return 0
		fi

		branches=""
		tmpfile="${worktree_base}/.fork_rm_all.$$"
		git worktree list --porcelain | awk '
			/^worktree / { path = substr($0, 10) }
			/^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
			/^$/ {
				if (path != "" && branch != "") {
					print path "|" branch
				}
				path = ""; branch = ""
			}
			END {
				if (path != "" && branch != "") {
					print path "|" branch
				}
			}
		' >"$tmpfile"

		while IFS='|' read -r path branch; do
			[ -n "$path" ] && [ -n "$branch" ] || continue
			case "$path" in
			"$worktree_base"/*)
				branches="$branches $branch"
				;;
			esac
		done <"$tmpfile"
		rm -f "$tmpfile"
	elif [ -z "$branches" ]; then
		# No branch specified, use current
		branch="$(get_current_worktree_branch)" || {
			printf '%s\n' 'Error: not in a worktree and no branch specified' >&2
			exit 1
		}
		branches=" $branch"
	fi

	# Get main repo root before removing (in case we're in a worktree being removed)
	return_path="$(get_main_repo_root)"

	# Remove each worktree
	failed=0
	for branch in $branches; do
		remove_single_worktree "$branch" "$force" || failed=1

		if [ "$remove_containers" = "1" ] && [ $failed -eq 0 ]; then
			remove_container "$branch" || true
		fi
	done

	printf '%s\n' "$return_path"

	if [ "${FORK_CD:-0}" != "1" ]; then
		printf '%s\n' "Return path: $return_path" >&2
	fi

	[ $failed -eq 0 ] || exit 1
}

# Command: List worktrees
# Lists worktrees with optional filtering by merge and dirty status
# Arguments:
#   -m|--merged - Show only merged worktrees
#   -u|--unmerged - Show only unmerged worktrees
#   -d|--dirty - Show only dirty worktrees (uncommitted changes)
#   -c|--clean - Show only clean worktrees
# Outputs:
#   Tab-separated: <branch> <merge_status> <dirty_status> <path>
# Returns:
#   0 on success
# Exits:
#   1 on invalid option
cmd_list() {
	filter_mode="all"
	filter_dirty=""

	while [ $# -gt 0 ]; do
		case "$1" in
		-m | --merged)
			filter_mode="merged"
			shift
			;;
		-u | --unmerged)
			filter_mode="unmerged"
			shift
			;;
		-d | --dirty)
			filter_dirty="dirty"
			shift
			;;
		-c | --clean)
			filter_dirty="clean"
			shift
			;;
		*)
			printf '%s\n' "Error: unknown option: $1" >&2
			exit 1
			;;
		esac
	done

	worktree_base="$(get_worktree_base)"

	if [ ! -d "$worktree_base" ]; then
		printf '%s\n' 'No worktrees found'
		return 0
	fi

	tmpfile="${worktree_base}/.fork_list.$$"
	: >"$tmpfile"

	git worktree list --porcelain | awk '
		/^worktree / { path = substr($0, 10) }
		/^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
		/^$/ {
			if (path != "" && branch != "") {
				print path "|" branch
			}
			path = ""; branch = ""
		}
		END {
			if (path != "" && branch != "") {
				print path "|" branch
			}
		}
	' | while IFS='|' read -r path branch; do
		[ -n "$path" ] && [ -n "$branch" ] || continue

		case "$path" in
		"$worktree_base"/*)
			merged=0
			if is_branch_merged "$branch"; then
				merged=1
			fi

			dirty=0
			if is_worktree_dirty "$path"; then
				dirty=1
			fi

			show=0
			if [ "$filter_mode" = "all" ]; then
				show=1
			elif [ "$filter_mode" = "merged" ] && [ $merged -eq 1 ]; then
				show=1
			elif [ "$filter_mode" = "unmerged" ] && [ $merged -eq 0 ]; then
				show=1
			fi

			if [ $show -eq 1 ] && [ -n "$filter_dirty" ]; then
				if [ "$filter_dirty" = "dirty" ] && [ $dirty -eq 0 ]; then
					show=0
				elif [ "$filter_dirty" = "clean" ] && [ $dirty -eq 1 ]; then
					show=0
				fi
			fi

			if [ $show -eq 1 ]; then
				merge_status="unmerged"
				[ $merged -eq 1 ] && merge_status="merged"
				dirty_status="clean"
				[ $dirty -eq 1 ] && dirty_status="dirty"
				printf '%s\t%s\t%s\t%s\n' "$branch" "$merge_status" "$dirty_status" "$path" >>"$tmpfile"
			fi
			;;
		esac
	done

	if [ -s "$tmpfile" ]; then
		cat "$tmpfile"
		rm -f "$tmpfile"
	else
		rm -f "$tmpfile"
		printf '%s\n' 'No worktrees found'
	fi
}

# Command: Clean merged worktrees
# Removes all worktrees that are merged and have no uncommitted changes
# Automatically skips worktrees with staged/unstaged changes or untracked files
# Outputs:
#   Main repository path to stdout if current worktree was removed
#   Status messages to stderr
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
# Returns:
#   0 on success
# Exits:
#   1 on invalid option
cmd_clean() {
	if [ $# -gt 0 ]; then
		printf '%s\n' "Error: unknown option: $1" >&2
		exit 1
	fi

	worktree_base="$(get_worktree_base)"

	if [ ! -d "$worktree_base" ]; then
		printf '%s\n' 'No worktrees to clean'
		return 0
	fi

	main_root="$(get_main_repo_root)"
	current_branch=""
	current_worktree_path=""
	current_entry=""

	if current_branch="$(get_current_worktree_branch)"; then
		current_worktree_path="$(get_worktree_path "$current_branch")"
	else
		current_branch=""
	fi

	tmpfile="${worktree_base}/.fork_clean.$$"
	git worktree list --porcelain | awk '
		/^worktree / { path = substr($0, 10) }
		/^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
		/^$/ {
			if (path != "" && branch != "") {
				print path "|" branch
			}
			path = ""; branch = ""
		}
		END {
			if (path != "" && branch != "") {
				print path "|" branch
			}
		}
	' >"$tmpfile"

	queue_file="${worktree_base}/.fork_clean_queue.$$"
	: >"$queue_file"

	while IFS='|' read -r path branch; do
		[ -n "$path" ] && [ -n "$branch" ] || continue

		case "$path" in
		"$worktree_base"/*)
			if is_branch_merged "$branch" && ! is_worktree_dirty "$path"; then
				if [ -n "$current_branch" ] && [ "$branch" = "$current_branch" ] && [ -n "$current_worktree_path" ] && [ "$path" = "$current_worktree_path" ]; then
					current_entry="$path|$branch"
				else
					printf '%s|%s\n' "$path" "$branch" >>"$queue_file"
				fi
			fi
			;;
		esac
	done <"$tmpfile"

	rm -f "$tmpfile"

	removed=0

	while IFS='|' read -r path branch; do
		[ -n "$path" ] && [ -n "$branch" ] || continue

		if (cd "$main_root" && git worktree remove "$path" 2>/dev/null) || (cd "$main_root" && git worktree remove --force "$path"); then
			printf '%s\n' "Removed worktree: $branch" >&2
			removed=1
		fi
	done <"$queue_file"

	rm -f "$queue_file"

	removed_current=0
	if [ -n "$current_entry" ]; then
		current_path=${current_entry%%|*}
		current_branch_name=${current_entry#*|}
		if (cd "$main_root" && git worktree remove "$current_path" 2>/dev/null) || (cd "$main_root" && git worktree remove --force "$current_path"); then
			printf '%s\n' "Removed worktree: $current_branch_name" >&2
			removed=1
			removed_current=1
		fi
	fi

	if [ $removed_current -eq 1 ]; then
		printf '%s\n' "$main_root"
		if [ "${FORK_CD:-0}" != "1" ]; then
			printf '%s\n' "Return path: $main_root" >&2
		fi
	elif [ $removed -eq 0 ]; then
		printf '%s\n' 'No worktrees removed'
	fi
}

# Command: Generate shell integration function
# Outputs shell-specific wrapper function that enables cd-ing
# Embeds FORK_* environment variables from FORK_ENV into generated function
# Arguments:
#   $1 - Shell type: bash, zsh, or fish (optional, auto-detected from $SHELL)
# Outputs:
#   Shell function definition to stdout
# Returns:
#   0 on success
# Exits:
#   1 if shell type unknown or $SHELL not set when no argument provided
cmd_sh() {
	shell="${1:-}"

	if [ -z "$shell" ]; then
		if [ -z "${SHELL:-}" ]; then
			printf '%s\n' "Error: \$SHELL is not set and no shell specified" >&2
			exit 1
		fi
		case "$SHELL" in
		*/bash)
			shell="bash"
			;;
		*/zsh)
			shell="zsh"
			;;
		*/fish)
			shell="fish"
			;;
		*)
			printf '%s\n' "Error: unknown shell in \$SHELL: $SHELL (supported: bash, zsh, fish)" >&2
			exit 1
			;;
		esac
	fi

	env_vars=""
	env_list=""
	if [ -n "${FORK_ENV:-}" ]; then
		if [ -f "$FORK_ENV" ]; then
			while IFS= read -r line || [ -n "$line" ]; do
				line="${line%%#*}"
				line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

				[ -z "$line" ] && continue

				case "$line" in
				*=*)
					var_name="${line%%=*}"
					var_value="${line#*=}"

					var_value_escaped=$(printf "%s" "$var_value" | sed "s/'/'\\\\''/g")

					case "$var_name" in
					FORK_*)
						if [ -z "$env_vars" ]; then
							env_vars="$var_name='$var_value_escaped'"
						else
							env_vars="$env_vars $var_name='$var_value_escaped'"
						fi
						if [ -z "$env_list" ]; then
							env_list="$var_name"
						else
							env_list="$env_list $var_name"
						fi
						;;
					esac
					;;
				esac
			done <"$FORK_ENV"
		fi
	fi

	case "$shell" in
	bash | zsh)
		cat <<EOF
fork() {
    case "\$1" in
        co|go|main|rm|clean)
            local output
            output=\$(FORK_CD=1 $env_vars command fork "\$@")
            if [ \$? -eq 0 ] && [ -n "\$output" ]; then
                if [ "\${FORK_CONTAINER_EXEC:-0}" = "1" ]; then
                    unset FORK_CONTAINER_EXEC
                    eval "\$output"
                else
                    builtin cd "\$output"
                fi
            fi
            ;;
        *)
            $env_vars command fork "\$@"
            ;;
    esac
}
EOF
		;;
	fish)
		cat <<EOF
function fork
    switch \$argv[1]
        case co go main rm clean
            set output (env FORK_CD=1 $env_vars command fork \$argv)
            if test \$status -eq 0; and test -n "\$output"
                if test "\$FORK_CONTAINER_EXEC" = "1"
                    set -e FORK_CONTAINER_EXEC
                    eval \$output
                else
                    builtin cd \$output
                end
            end
        case '*'
            env $env_vars command fork \$argv
    end
end
EOF
		;;
	*)
		printf '%s\n' "Error: unknown shell: $shell (supported: bash, zsh, fish)" >&2
		exit 1
		;;
	esac
}

# Main entry point and command dispatcher
# Routes commands to appropriate handlers after common setup
# Arguments:
#   $1 - Command (help, sh, new, co, go, main, rm, ls, clean)
#   $@ - Command-specific arguments
# Globals:
#   FORK_DIR_PATTERN - Optional config display
#   FORK_CD - Internal shell integration flag
# Exits:
#   Various codes depending on command and error conditions
main() {
  cmd="${1-}"
  [ $# -gt 0 ] && shift || true

  case "$cmd" in
  help | -h | --help)
    usage "$@"
    ;;
  sh)
    cmd_sh "$@"
    ;;
  "")
    usage
    ;;
  *)
    if [ -n "${FORK_DIR_PATTERN:-}" ] && [ "${FORK_CD:-0}" != "1" ]; then
      printf '%s\n' "Config: FORK_DIR_PATTERN=$FORK_DIR_PATTERN" >&2
    fi

    command_exists git || {
      printf '%s\n' 'Error: git is required on PATH' >&2
      exit 127
    }

    get_repo_root >/dev/null

    case "$cmd" in
    new)
      cmd_new "$@"
      ;;
    co | checkout)
      cmd_co "$@"
      ;;
    go)
      cmd_go "$@"
      ;;
    main)
      cmd_main
      ;;
    rm)
      cmd_rm "$@"
      ;;
    ls)
      cmd_list "$@"
      ;;
    clean)
      cmd_clean "$@"
      ;;
    *)
      printf '%s\n' "Error: unknown command: $cmd" >&2
      usage
      ;;
    esac
    ;;
  esac
}

main "$@"

