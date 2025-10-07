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
