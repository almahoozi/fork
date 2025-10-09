# Get the container runtime to use
# Globals:
#   FORK_CONTAINER_RUNTIME - User-specified runtime (docker or podman)
# Outputs:
#   Runtime name to stdout
# Returns:
#   0 always
get_container_runtime() {
	printf '%s' "${FORK_CONTAINER_RUNTIME:-docker}"
}

# Check if container runtime is available
# Returns:
#   0 if runtime is available, 1 otherwise
container_runtime_available() {
	runtime="$(get_container_runtime)"
	command -v "$runtime" >/dev/null 2>&1
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

detect_auto_dockerfile() {
	current_dir="$(pwd)"
	repo_root="$(get_repo_root)"
	processed=""

	for dir in "$current_dir" "$current_dir/.docker" "$repo_root" "$repo_root/.docker"; do
		if [ -n "$processed" ] && [ "$dir" = "$processed" ]; then
			continue
		fi
		processed="$dir"

		candidate="$dir/Dockerfile.fork"
		if [ -f "$candidate" ]; then
			printf '%s' "$candidate"
			return
		fi

		for candidate in "$dir"/Dockerfile.fork.*; do
			[ -f "$candidate" ] || continue
			printf '%s' "$candidate"
			return
		done
	done

	printf '%s' ""
}

get_container_dockerfile() {
	if [ -n "${FORK_CONTAINER_DOCKERFILE:-}" ] && [ -f "$FORK_CONTAINER_DOCKERFILE" ]; then
		printf '%s' "$FORK_CONTAINER_DOCKERFILE"
		return
	fi

	auto_dockerfile="$(detect_auto_dockerfile)"
	if [ -n "$auto_dockerfile" ]; then
		printf '%s' "$auto_dockerfile"
		return
	fi

	if [ -n "${FORK_CONTAINER_DEFAULT_DOCKERFILE:-}" ] && [ -f "$FORK_CONTAINER_DEFAULT_DOCKERFILE" ]; then
		printf '%s' "$FORK_CONTAINER_DEFAULT_DOCKERFILE"
		return
	fi

	printf '%s' ""
}

get_dockerfile_image_tag() {
	branch="$1"
	dockerfile="$2"

	if [ -z "$dockerfile" ]; then
		printf 'fork_%s_image' "$branch"
		return
	fi

	base="$(basename "$dockerfile")"
	case "$base" in
	Dockerfile.fork.*)
		variant="${base#Dockerfile.fork.}"
		variant="$(printf '%s' "$variant" | tr -c 'A-Za-z0-9_.-' '_')"
		printf 'fork_%s_%s_image' "$branch" "$variant"
		return
		;;
	Dockerfile.fork)
		printf 'fork_%s_image' "$branch"
		return
		;;
	*)
		printf 'fork_%s_image' "$branch"
		return
		;;
	esac
}

build_container_image() {
	dockerfile="$1"
	image_tag="$2"
	runtime="$(get_container_runtime)"

	if [ ! -f "$dockerfile" ]; then
		printf '%s\n' "Error: Dockerfile not found: $dockerfile" >&2
		return 1
	fi

	dockerfile_dir="$(dirname "$dockerfile")"

	"$runtime" build -t "$image_tag" -f "$dockerfile" "$dockerfile_dir" >/dev/null 2>&1 || {
		printf '%s\n' "Error: failed to build image from Dockerfile: $dockerfile" >&2
		return 1
	}

	if [ "${FORK_CD:-0}" != "1" ]; then
		printf '%s\n' "Built image: $image_tag from $dockerfile" >&2
	fi

	return 0
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
	runtime="$(get_container_runtime)"
	"$runtime" ps -a --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Check if container is running
# Arguments:
#   $1 - Container name
# Returns:
#   0 if container is running, 1 otherwise
container_is_running() {
	container_name="$1"
	runtime="$(get_container_runtime)"
	"$runtime" ps --format '{{.Names}}' | grep -q "^${container_name}$"
}

# Create and start a container for a fork
# Arguments:
#   $1 - Branch/fork name
#   $2 - Worktree path
# Globals:
#   FORK_CONTAINER_KEEP_ALIVE - Set to 1 to keep container running in background
# Outputs:
#   Status messages to stderr
# Returns:
#   0 on success, 1 on failure
create_container() {
	branch="$1"
	worktree_path="$2"
	container_name="$(get_container_name "$branch")"
	dockerfile="$(get_container_dockerfile)"
	image="$(get_container_image)"
	runtime="$(get_container_runtime)"
	repo_name="$(get_repo_name)"
	keep_alive="${FORK_CONTAINER_KEEP_ALIVE:-0}"

	if ! container_runtime_available; then
		printf '%s\n' "Error: Container runtime is not available. Please install $runtime." >&2
		return 1
	fi

	if [ -n "$dockerfile" ]; then
		image_tag="$(get_dockerfile_image_tag "$branch" "$dockerfile")"
		if ! build_container_image "$dockerfile" "$image_tag"; then
			return 1
		fi
		image="$image_tag"
	fi

	if [ "$keep_alive" = "1" ]; then
		if container_exists "$container_name"; then
			if container_is_running "$container_name"; then
				return 0
			else
				"$runtime" start "$container_name" >/dev/null 2>&1 || {
					printf '%s\n' "Error: failed to start existing container: $container_name" >&2
					return 1
				}
				return 0
			fi
		fi

		worktree_path_abs="$(cd "$worktree_path" && pwd)"

		"$runtime" run -d \
			--name "$container_name" \
			-v "$worktree_path_abs:/$repo_name:rw" \
			-w "/$repo_name" \
			--entrypoint /bin/sh \
			"$image" \
			-c "while true; do sleep 3600; done" >/dev/null 2>&1 || {
			printf '%s\n' "Error: failed to create container: $container_name" >&2
			return 1
		}

		if [ "${FORK_CD:-0}" != "1" ]; then
			printf '%s\n' "Created container: $container_name" >&2
		fi
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
	runtime="$(get_container_runtime)"

	if ! container_runtime_available; then
		return 0
	fi

	if ! container_exists "$container_name"; then
		return 0
	fi

	"$runtime" rm -f "$container_name" >/dev/null 2>&1 || {
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
#   $2 - Worktree path
# Globals:
#   FORK_CONTAINER_KEEP_ALIVE - Set to 1 to keep container running in background
# Outputs:
#   Command string to stdout with FORK_CONTAINER_EXEC=1 prefix
# Returns:
#   0 always
get_container_exec_command() {
	container_name="$1"
	worktree_path="$2"
	runtime="$(get_container_runtime)"
	repo_name="$(get_repo_name)"
	keep_alive="${FORK_CONTAINER_KEEP_ALIVE:-0}"

	if [ "$keep_alive" = "1" ]; then
		printf 'FORK_CONTAINER_EXEC=1 %s exec -it %s /bin/sh' "$runtime" "$container_name"
	else
		worktree_path_abs="$(cd "$worktree_path" && pwd)"
		dockerfile="$(get_container_dockerfile)"

		if [ -n "$dockerfile" ]; then
			branch="$(basename "$worktree_path")"
			image="$(get_dockerfile_image_tag "$branch" "$dockerfile")"
		else
			image="$(get_container_image)"
		fi

		printf 'FORK_CONTAINER_EXEC=1 %s run --rm -it --name %s -v %s:/%s:rw -w /%s %s /bin/sh' \
			"$runtime" "$container_name" "$worktree_path_abs" "$repo_name" "$repo_name" "$image"
	fi
}
