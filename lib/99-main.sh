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

			get_repo_root > /dev/null

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
