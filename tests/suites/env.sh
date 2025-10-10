#!/bin/sh
# suite: env
# description: Environment file loading and variable propagation

set -eu

. "$TESTS_DIR/lib/utils.sh"
. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/fixtures.sh"

setup_repo "fork-env"
env_file="$REPO_DIR/.fork.env"
cat >"$env_file" <<'EOF'
# Fork configuration
FORK_DIR_PATTERN=../{repo}_forks/{branch}

# This should be ignored (not FORK_ prefix)
OTHER_VAR=ignored

FORK_DEBUG=1
EOF
env_stdout="$TEST_ROOT/env.out"
env_stderr="$TEST_ROOT/env.err"
run_fork_capture "$env_stdout" "$env_stderr" ls
env_out=$(cat "$env_stdout")
env_err=$(cat "$env_stderr")
assert_contains "No worktrees found" "$env_out" "ls works without FORK_ENV set"
assert_not_contains "FORK_DIR_PATTERN" "$env_err" "ls does not show config without FORK_ENV"
env_load_stdout="$TEST_ROOT/env_load.out"
env_load_stderr="$TEST_ROOT/env_load.err"
(cd "$REPO_DIR" && env FORK_ENV="$env_file" sh "$FORK_SH" ls >"$env_load_stdout" 2>"$env_load_stderr")
env_load_out=$(cat "$env_load_stdout")
env_load_err=$(cat "$env_load_stderr")
assert_contains "No worktrees found" "$env_load_out" "ls works with FORK_ENV set"
assert_contains "FORK_DIR_PATTERN=../{repo}_forks/{branch}" "$env_load_err" "ls shows config when FORK_ENV is set"
env_missing_stdout="$TEST_ROOT/env_missing.out"
env_missing_stderr="$TEST_ROOT/env_missing.err"
(cd "$REPO_DIR" && env FORK_ENV="/nonexistent/file" sh "$FORK_SH" ls >"$env_missing_stdout" 2>"$env_missing_stderr")
env_missing_status=$?
env_missing_out=$(cat "$env_missing_stdout")
assert_status 0 "$env_missing_status" "fork proceeds silently for missing FORK_ENV file"
assert_contains "No worktrees found" "$env_missing_out" "fork works normally when FORK_ENV file is missing"
sh_env_stdout="$TEST_ROOT/sh_env.out"
sh_env_stderr="$TEST_ROOT/sh_env.err"
(cd "$REPO_DIR" && env FORK_ENV="$env_file" sh "$FORK_SH" sh bash >"$sh_env_stdout" 2>"$sh_env_stderr")
sh_env_out=$(cat "$sh_env_stdout")
sh_env_err=$(cat "$sh_env_stderr")
assert_status 0 0 "fork sh succeeds with FORK_ENV set"
assert_contains "FORK_DIR_PATTERN='../{repo}_forks/{branch}'" "$sh_env_out" "fork sh includes FORK_DIR_PATTERN in command"
assert_contains "FORK_DEBUG='1'" "$sh_env_out" "fork sh includes FORK_DEBUG in command"
assert_not_contains "OTHER_VAR" "$sh_env_out" "fork sh excludes non-FORK_ variables"
assert_empty "$sh_env_err" "fork sh emits no stderr with valid FORK_ENV"
sh_env_fish_stdout="$TEST_ROOT/sh_env_fish.out"
sh_env_fish_stderr="$TEST_ROOT/sh_env_fish.err"
(cd "$REPO_DIR" && env FORK_ENV="$env_file" sh "$FORK_SH" sh fish >"$sh_env_fish_stdout" 2>"$sh_env_fish_stderr")
sh_env_fish_out=$(cat "$sh_env_fish_stdout")
assert_contains "FORK_DIR_PATTERN='../{repo}_forks/{branch}'" "$sh_env_fish_out" "fork sh fish includes FORK_DIR_PATTERN in command"
assert_contains "FORK_DEBUG='1'" "$sh_env_fish_out" "fork sh fish includes FORK_DEBUG in command"
assert_not_contains "OTHER_VAR" "$sh_env_fish_out" "fork sh fish excludes non-FORK_ variables"
env_cd_stdout="$TEST_ROOT/env_cd.out"
env_cd_stderr="$TEST_ROOT/env_cd.err"
(cd "$REPO_DIR" && env FORK_ENV="$env_file" FORK_CD=1 sh "$FORK_SH" ls >"$env_cd_stdout" 2>"$env_cd_stderr")
env_cd_err=$(cat "$env_cd_stderr")
assert_empty "$env_cd_err" "cd mode suppresses config message"
