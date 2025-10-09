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
              [-k|--keep-alive]
  go <branch> [-t|--target <base>]        Change to worktree (create if needed)
              [-c|--container]
              [-k|--keep-alive]
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
    FORK_CONTAINER_DOCKERFILE=/path/to/Dockerfile
    FORK_CONTAINER_NAME=myproject
    FORK_CONTAINER_RUNTIME=podman
    FORK_CONTAINER_KEEP_ALIVE=0

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

  co <branch> [-c|--container] [-k|--keep-alive]
      Print path to worktree. Use: cd \$(fork co <branch>)
      With -c, opens an interactive shell in a container for isolated work.
      -c, --container  Open worktree in container
      -k, --keep-alive Keep container running in background (requires -c)

  go <branch> [-t|--target <base>] [-c|--container] [-k|--keep-alive]
      Go to worktree (create if doesn't exist). Same options as 'new'.
      With -c, opens an interactive shell in a container for isolated work.
      -c, --container  Open worktree in container
      -k, --keep-alive Keep container running in background (requires -c)

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
    FORK_CONTAINER_DEFAULT_DOCKERFILE=./default.Dockerfile
    FORK_CONTAINER_DOCKERFILE=/path/to/Dockerfile
    FORK_CONTAINER_NAME=myproject
    FORK_CONTAINER_RUNTIME=podman
    FORK_CONTAINER_KEEP_ALIVE=0
  
  When using shell integration (fork sh), env vars are automatically
  embedded in the generated function and passed to every fork invocation.

Environment Variables:
  FORK_ENV                    Path to configuration file (optional)
  FORK_CD                     Internal flag for shell integration (do not set manually)
  FORK_DIR_PATTERN            Example config variable (displays on startup if set)
  FORK_CONTAINER              Set to 1 to enable container mode by default
  FORK_CONTAINER_IMAGE        Container image to use (default: ubuntu:latest)
  FORK_CONTAINER_DEFAULT_DOCKERFILE
                               Fallback Dockerfile when no Dockerfile.fork* exists
  FORK_CONTAINER_DOCKERFILE   Override Dockerfile when no Dockerfile.fork* exists
  FORK_CONTAINER_NAME         Container name prefix (default: none)
  FORK_CONTAINER_RUNTIME      Container runtime to use (default: docker, also supports: podman)
  FORK_CONTAINER_KEEP_ALIVE   Set to 1 to keep containers running (default: 0, containers auto-removed on exit)

Container Mode:
  Container mode creates isolated containers for each fork, mounting only
  the worktree directory. This provides isolation from the host system.
  
  Requirements: Docker or Podman must be installed and running.
  
  By default, containers are created with --rm flag and are automatically
  removed when you exit. Set FORK_CONTAINER_KEEP_ALIVE=1 to keep containers
  running in the background for faster re-entry, or use the -k|--keep-alive
  flag on co/go commands.
  
  Container naming: {FORK_CONTAINER_NAME}_{branch}_fork or {branch}_fork
  Mount point: /{repo_name} (read-write access to worktree only)
  
  Image Sources:
    - Automatic: Use Dockerfile.fork or Dockerfile.fork.* in the current directory when present
      (Dockerfile.fork.* adds its suffix to the image tag: fork_{branch}_{suffix}_image)
    - FORK_CONTAINER_DOCKERFILE: Override Dockerfile when no auto match exists
    - FORK_CONTAINER_DEFAULT_DOCKERFILE: Fallback Dockerfile when no auto match or override exists
    - FORK_CONTAINER_IMAGE: Use a pre-built image (default: ubuntu:latest)
      Images are built with tag: fork_{branch}_image unless a suffix is present

Examples:
  fork new feature-x                   Create worktree for feature-x
  fork new feat-a feat-b               Create multiple worktrees
  fork new bugfix --target develop     Create from develop branch
  fork go feature-x                    Go to feature-x (create if needed)
  fork go feature-x -c                 Go to feature-x in container (auto-removed on exit)
  fork go feature-x -c -k              Go to feature-x in container (kept alive)
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
