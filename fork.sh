#!/bin/sh
# fork.sh - Manage git worktrees in a standardized directory layout
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
#               -f: force removal of unmerged branches
#               -a: remove all worktrees
#   ls [-m|--merged] [-u|--unmerged]
#               List worktrees (default: all)
#   clean       Remove merged worktrees
#   sh <bash|zsh|fish>
#               Output shell integration function
#   help [-v|--verbose]
#               Show help
#
# Convention: ../<repo>_forks/<branch>

set -eu

load_env_file() {
  env_file="${FORK_ENV:-}"
  if [ -z "$env_file" ]; then
    return 0
  fi

  if [ ! -f "$env_file" ]; then
    printf '%s\n' "Error: FORK_ENV file not found: $env_file" >&2
    exit 1
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
        eval "export $var_name=\$var_value"
        ;;
      esac
      ;;
    esac
  done <"$env_file"
}

load_env_file

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
fork - Manage git worktrees in a standardized directory layout

Usage: fork <command> [args]

Commands:
  new <branch>... [-t|--target <base>]    Create worktrees
  co <branch>                             Change to worktree
  go <branch> [-t|--target <base>]        Change to worktree (create if needed)
  main                                    Go to main worktree
  rm [branch...] [-f|--force] [-a|--all]  Remove worktree(s)
  ls [-m|--merged] [-u|--unmerged]        List worktrees
  clean                                   Remove merged worktrees
  sh [bash|zsh|fish]                      Output shell integration function
  help [-v|--verbose]                     Show help

Convention: ../<repo>_forks/<branch>

Shell Integration (required for cd-ing):
  $shell_integration

Configuration:
  Set FORK_ENV to load configuration from a file:
    export FORK_ENV=~/.config/fork/config.env
  
  Only FORK_* prefixed variables are loaded. Example config file:
    FORK_DIR_PATTERN=*_feature_*
    FORK_DEBUG=1

Examples:
  fork new feature-x
  fork go feature-x
  fork main
  fork ls
  fork rm feature-x
  fork rm -a
  fork clean

Run 'fork help --verbose' for detailed documentation.
EOF
  else
    # Verbose help always shows all shell options
    cat >&2 <<'EOF'
fork - Manage git worktrees in a standardized directory layout

Usage: fork <command> [args]

Commands:
  new <branch>... [-t|--target <base>]
      Create worktrees from 'main' (or --target base). Creates branch if needed.
      Tracks remote branch if it exists, otherwise uses existing local branch,
      otherwise creates a new local branch.
      -t, --target <base>  Create from <base> instead of main

  co <branch>
      Print path to worktree. Use: cd \$(fork co <branch>)

  go <branch> [-t|--target <base>]
      Go to worktree (create if doesn't exist). Same options as 'new'.

  main
      Go to main/primary worktree.

  rm [branch...] [-f] [-a|--all]
      Remove worktree(s). Defaults to current. Use -a for all.
      -f, --force Force removal of unmerged branches
      -a, --all   Remove all worktrees

  ls [-m|--merged] [-u|--unmerged]
      List worktrees. Default: all. Output: <branch> <status> <path>

  clean
      Remove merged worktrees.

  sh [bash|zsh|fish]
      Output shell integration function. If no shell specified, detects from $SHELL.

  help [-v|--verbose]
      Show this help.

Convention:
  Worktrees: ../<repo>_forks/<branch>
  Example: myapp_forks/feature-x

Shell Integration (required for cd-ing):
  Bash:  eval "$(fork sh bash)"   # Add to ~/.bashrc
  Zsh:   eval "$(fork sh zsh)"    # Add to ~/.zshrc
  Fish:  fork sh fish | source    # Add to ~/.config/fish/config.fish

Configuration:
  Set FORK_ENV to load configuration from a file on startup:
    export FORK_ENV=~/.config/fork/config.env
  
  The env file should contain FORK_* prefixed variables (one per line).
  Lines starting with # are treated as comments. Example:
    # Fork configuration
    FORK_DIR_PATTERN=*_feature_*
    FORK_DEBUG=1
  
  When using shell integration (fork sh), env vars are automatically
  embedded in the generated function and passed to every fork invocation.

Environment Variables:
  FORK_ENV          Path to configuration file (optional)
  FORK_CD           Internal flag for shell integration (do not set manually)
  FORK_DIR_PATTERN  Example config variable (displays on startup if set)

Examples:
  fork new feature-x                   Create worktree for feature-x
  fork new feat-a feat-b               Create multiple worktrees
  fork new bugfix --target develop     Create from develop branch
  fork go feature-x                    Go to feature-x (create if needed)
  fork main                            Go to main worktree
  fork rm                              Remove current worktree
  fork rm feature-x                    Remove specific worktree
  fork rm feat-a feat-b                Remove multiple worktrees
  fork rm -a                           Remove all worktrees
  fork ls                              List all worktrees
  fork ls -u                           List unmerged worktrees
  fork ls -m                           List merged worktrees
  fork clean                           Remove merged worktrees
  fork sh                              Output shell integration (auto-detect from $SHELL)
  fork sh bash                         Output shell integration for bash/zsh
EOF
  fi
  exit 2
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

get_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || {
    printf '%s\n' 'Error: not in a git repository' >&2
    exit 1
  }
}

get_main_repo_root() {
  common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"
  if [ -n "$common_dir" ] && [ "$common_dir" != ".git" ]; then
    # We're in a worktree, get the main repo root
    cd "$(dirname "$common_dir")" && pwd
  else
    get_repo_root
  fi
}

get_repo_name() {
  basename "$(get_main_repo_root)"
}

get_worktree_base() {
  repo_name="$(get_repo_name)"
  repo_root="$(get_main_repo_root)"
  printf '%s\n' "$(dirname "$repo_root")/${repo_name}_forks"
}

get_worktree_path() {
  branch="$1"
  printf '%s\n' "$(get_worktree_base)/$branch"
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1" 2>/dev/null
}

remote_branch_exists() {
  git show-ref --verify --quiet "refs/remotes/origin/$1" 2>/dev/null
}

worktree_exists() {
  path="$(get_worktree_path "$1")"
  [ -d "$path" ] && git worktree list | grep "$(printf '%s' "$path" | sed 's/[]\/$*.^[]/\\&/g')" >/dev/null
}

is_branch_merged() {
  branch="$1"
  base="${2:-main}"
  git branch --merged "$base" 2>/dev/null | awk '{print $NF}' | grep "^${branch}$" >/dev/null
}

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

is_worktree_dirty() {
  path="$1"
  (cd "$path" && ! git diff --quiet 2>/dev/null) ||
    (cd "$path" && ! git diff --cached --quiet 2>/dev/null) ||
    (cd "$path" && [ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ])
}

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

cmd_co() {
  if [ $# -ne 1 ]; then
    printf '%s\n' 'Usage: fork co <branch>' >&2
    exit 1
  fi

  branch="$1"
  path="$(get_worktree_path "$branch")"

  if ! worktree_exists "$branch"; then
    printf '%s\n' "Error: worktree for '$branch' does not exist" >&2
    exit 1
  fi

  printf '%s\n' "$path"

  if [ "${FORK_CD:-0}" = "1" ]; then
    export FORK_LAST="$(pwd)"
  else
    printf '%s\n' "Switched to worktree '$branch'" >&2
  fi
}

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

cmd_go() {
  base_branch="main"

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
      break
      ;;
    esac
  done

  [ $# -eq 1 ] || {
    printf '%s\n' 'Usage: fork go <branch> [-t|--target <base>]' >&2
    exit 1
  }

  branch="$1"
  path="$(get_worktree_path "$branch")"

  created=0
  if ! worktree_exists "$branch"; then
    create_single_worktree "$branch" "$base_branch"
    created=1
  fi

  printf '%s\n' "$path"

  if [ "${FORK_CD:-0}" != "1" ]; then
    if [ $created -eq 1 ]; then
      printf '%s\n' "Created and switched to worktree '$branch'" >&2
    else
      printf '%s\n' "Switched to worktree '$branch'" >&2
    fi
  fi
}

remove_single_worktree() {
  branch="$1"
  force="$2"

  path="$(get_worktree_path "$branch")"

  if ! worktree_exists "$branch"; then
    printf '%s\n' "Error: worktree for '$branch' does not exist" >&2
    return 1
  fi

  # Check if branch is merged (unless force flag is set)
  if [ $force -eq 0 ] && ! is_branch_merged "$branch"; then
    printf '%s\n' "Error: branch '$branch' is not merged. Use -f to force removal." >&2
    return 1
  fi

  if is_worktree_dirty "$path"; then
    printf '%s\n' "Warning: worktree '$branch' has uncommitted changes" >&2
  fi

  git worktree remove "$path" 2>/dev/null || git worktree remove --force "$path"
  printf '%s\n' "Removed worktree: $branch" >&2
  return 0
}

cmd_rm() {
  force=0
  all=0
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
  done

  printf '%s\n' "$return_path"

  if [ "${FORK_CD:-0}" != "1" ]; then
    printf '%s\n' "Return path: $return_path" >&2
  fi

  [ $failed -eq 0 ] || exit 1
}

cmd_list() {
  filter_mode="all"

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

      show=0
      if [ "$filter_mode" = "all" ]; then
        show=1
      elif [ "$filter_mode" = "merged" ] && [ $merged -eq 1 ]; then
        show=1
      elif [ "$filter_mode" = "unmerged" ] && [ $merged -eq 0 ]; then
        show=1
      fi

      if [ $show -eq 1 ]; then
        status="unmerged"
        [ $merged -eq 1 ] && status="merged"
        printf '%s\t%s\t%s\n' "$branch" "$status" "$path" >>"$tmpfile"
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
      if is_branch_merged "$branch"; then
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

          case "$var_name" in
          FORK_*)
            if [ -z "$env_vars" ]; then
              env_vars="$var_name='$var_value'"
            else
              env_vars="$env_vars $var_name='$var_value'"
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
                builtin cd "\$output"
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
            and builtin cd \$output
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
