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
#   -k|--keep-alive - Keep container running (requires -c)
# Outputs:
#   Worktree path to stdout (or container exec command if -c flag set)
#   Status message to stderr (unless FORK_CD=1)
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
#   FORK_LAST - Exports previous directory when FORK_CD=1
#   FORK_CONTAINER - Set to 1 to enable container mode
#   FORK_CONTAINER_KEEP_ALIVE - Set to 1 to keep containers running
# Exits:
#   1 if worktree doesn't exist or invalid arguments
cmd_co() {
	use_container="${FORK_CONTAINER:-0}"
	keep_alive_override=""
	branch=""

	while [ $# -gt 0 ]; do
		case "$1" in
			-c | --container)
				use_container=1
				shift
				;;
			-k | --keep-alive)
				keep_alive_override=1
				shift
				;;
			-*)
				printf '%s\n' "Error: unknown option: $1" >&2
				exit 1
				;;
			*)
				branch="$1"
				shift
				;;
		esac
	done

	if [ -z "$branch" ]; then
		printf '%s\n' 'Usage: fork co <branch> [-c|--container] [-k|--keep-alive]' >&2
		exit 1
	fi
	path="$(get_worktree_path "$branch")"

	if ! worktree_exists "$branch"; then
		printf '%s\n' "Error: worktree for '$branch' does not exist" >&2
		exit 1
	fi

	if [ "$use_container" = "1" ]; then
		container_name="$(get_container_name "$branch")"
		if [ -n "$keep_alive_override" ]; then
			keep_alive="$keep_alive_override"
		else
			keep_alive="${FORK_CONTAINER_KEEP_ALIVE:-0}"
		fi
		runtime="$(get_container_runtime)"

		if [ "$keep_alive" = "1" ]; then
			if ! container_exists "$container_name"; then
				if [ "${FORK_CD:-0}" != "1" ]; then
					printf '%s\n' "Container does not exist for '$branch', creating..." >&2
				fi
				FORK_CONTAINER_KEEP_ALIVE="$keep_alive" create_container "$branch" "$path" || exit 1
			elif ! container_is_running "$container_name"; then
				if [ "${FORK_CD:-0}" != "1" ]; then
					printf '%s\n' "Starting container for '$branch'..." >&2
				fi
				"$runtime" start "$container_name" > /dev/null 2>&1 || {
					printf '%s\n' "Error: failed to start container: $container_name" >&2
					exit 1
				}
			fi
		fi

		export FORK_CONTAINER_KEEP_ALIVE="$keep_alive"
		printf '%s' "$(get_container_exec_command "$container_name" "$path")"
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
#   -k|--keep-alive - Keep container running (requires -c)
# Outputs:
#   Worktree path to stdout (or container exec command if -c flag set)
#   Status messages to stderr
# Globals:
#   FORK_CD - Set to 1 when called from shell integration
#   FORK_CONTAINER - Set to 1 to enable container mode
#   FORK_CONTAINER_KEEP_ALIVE - Set to 1 to keep containers running
# Exits:
#   1 on error (invalid arguments or creation failure)
cmd_go() {
	base_branch="main"
	use_container="${FORK_CONTAINER:-0}"
	keep_alive_override=""
	branch=""

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
			-k | --keep-alive)
				keep_alive_override=1
				shift
				;;
			-*)
				printf '%s\n' "Error: unknown option: $1" >&2
				exit 1
				;;
			*)
				branch="$1"
				shift
				;;
		esac
	done

	[ -n "$branch" ] || {
		printf '%s\n' 'Usage: fork go <branch> [-t|--target <base>] [-c|--container] [-k|--keep-alive]' >&2
		exit 1
	}
	path="$(get_worktree_path "$branch")"

	created=0
	if ! worktree_exists "$branch"; then
		create_single_worktree "$branch" "$base_branch"
		created=1
	fi

	if [ "$use_container" = "1" ]; then
		container_name="$(get_container_name "$branch")"
		if [ -n "$keep_alive_override" ]; then
			keep_alive="$keep_alive_override"
		else
			keep_alive="${FORK_CONTAINER_KEEP_ALIVE:-0}"
		fi
		runtime="$(get_container_runtime)"

		if [ "$keep_alive" = "1" ]; then
			if ! container_exists "$container_name"; then
				if [ "${FORK_CD:-0}" != "1" ]; then
					printf '%s\n' "Creating container for '$branch'..." >&2
				fi
				FORK_CONTAINER_KEEP_ALIVE="$keep_alive" create_container "$branch" "$path" || exit 1
			elif ! container_is_running "$container_name"; then
				if [ "${FORK_CD:-0}" != "1" ]; then
					printf '%s\n' "Starting container for '$branch'..." >&2
				fi
				"$runtime" start "$container_name" > /dev/null 2>&1 || {
					printf '%s\n' "Error: failed to start container: $container_name" >&2
					exit 1
				}
			fi
		fi

		export FORK_CONTAINER_KEEP_ALIVE="$keep_alive"
		printf '%s' "$(get_container_exec_command "$container_name" "$path")"
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
		' > "$tmpfile"

		while IFS='|' read -r path branch; do
			[ -n "$path" ] && [ -n "$branch" ] || continue
			case "$path" in
				"$worktree_base"/*)
					branches="$branches $branch"
					;;
			esac
		done < "$tmpfile"
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
	: > "$tmpfile"

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
					printf '%s\t%s\t%s\t%s\n' "$branch" "$merge_status" "$dirty_status" "$path" >> "$tmpfile"
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
	' > "$tmpfile"

	queue_file="${worktree_base}/.fork_clean_queue.$$"
	: > "$queue_file"

	while IFS='|' read -r path branch; do
		[ -n "$path" ] && [ -n "$branch" ] || continue

		case "$path" in
			"$worktree_base"/*)
				if is_branch_merged "$branch" && ! is_worktree_dirty "$path"; then
					if [ -n "$current_branch" ] && [ "$branch" = "$current_branch" ] && [ -n "$current_worktree_path" ] && [ "$path" = "$current_worktree_path" ]; then
						current_entry="$path|$branch"
					else
						printf '%s|%s\n' "$path" "$branch" >> "$queue_file"
					fi
				fi
				;;
		esac
	done < "$tmpfile"

	rm -f "$tmpfile"

	removed=0

	while IFS='|' read -r path branch; do
		[ -n "$path" ] && [ -n "$branch" ] || continue

		if (cd "$main_root" && git worktree remove "$path" 2> /dev/null) || (cd "$main_root" && git worktree remove --force "$path"); then
			printf '%s\n' "Removed worktree: $branch" >&2
			remove_container "$branch" || true
			removed=1
		fi
	done < "$queue_file"

	rm -f "$queue_file"

	removed_current=0
	if [ -n "$current_entry" ]; then
		current_path=${current_entry%%|*}
		current_branch_name=${current_entry#*|}
		if (cd "$main_root" && git worktree remove "$current_path" 2> /dev/null) || (cd "$main_root" && git worktree remove --force "$current_path"); then
			printf '%s\n' "Removed worktree: $current_branch_name" >&2
			remove_container "$current_branch_name" || true
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
