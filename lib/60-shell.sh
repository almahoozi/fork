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
