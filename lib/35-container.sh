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
#   Command string to stdout with FORK_CONTAINER_EXEC=1 prefix
# Returns:
#   0 always
get_container_exec_command() {
	container_name="$1"
	printf 'FORK_CONTAINER_EXEC=1 docker exec -it %s /bin/sh' "$container_name"
}
