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
	done < "$env_file"
}

load_env_file
