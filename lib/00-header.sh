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
