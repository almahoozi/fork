#!/bin/sh
# suite: shell
# description: Shell integration and help system

set -eu

. "$TESTS_DIR/lib/utils.sh"
. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/fixtures.sh"

setup_repo "fork-shell"

bash_integration=$(run_fork sh bash)
assert_contains "fork()" "$bash_integration" "sh bash emits shell function"

help_stdout="$TEST_ROOT/help.out"
help_stderr="$TEST_ROOT/help.err"
set +e
run_fork_capture "$help_stdout" "$help_stderr" help
help_status=$?
set -e
help_out=$(cat "$help_stdout")
help_err=$(cat "$help_stderr")
assert_status 2 "$help_status" "help exits with usage status"
assert_empty "$help_out" "help prints nothing to stdout"
assert_contains "Usage: fork" "$help_err" "help includes usage summary"
help_verbose_stdout="$TEST_ROOT/help_verbose.out"
help_verbose_stderr="$TEST_ROOT/help_verbose.err"
set +e
run_fork_capture "$help_verbose_stdout" "$help_verbose_stderr" help --verbose
help_verbose_status=$?
set -e
help_verbose_out=$(cat "$help_verbose_stdout")
help_verbose_err=$(cat "$help_verbose_stderr")
assert_status 2 "$help_verbose_status" "help --verbose exits with usage status"
assert_contains "Create worktrees" "$help_verbose_err" "help --verbose shows detailed commands"
assert_empty "$help_verbose_out" "help --verbose prints nothing to stdout"
sh_detect_stdout="$TEST_ROOT/sh_detect.out"
sh_detect_stderr="$TEST_ROOT/sh_detect.err"
(
	cd "$REPO_DIR" && env SHELL=/bin/bash sh "$FORK_SH" sh >"$sh_detect_stdout" 2>"$sh_detect_stderr"
)
sh_detect_status=$?
sh_detect_out=$(cat "$sh_detect_stdout")
sh_detect_err=$(cat "$sh_detect_stderr")
assert_status 0 "$sh_detect_status" "fork sh auto-detect succeeds for bash"
assert_contains "fork()" "$sh_detect_out" "fork sh auto-detect emits function"
assert_empty "$sh_detect_err" "fork sh auto-detect emits no stderr"
sh_unknown_stdout="$TEST_ROOT/sh_unknown.out"
sh_unknown_stderr="$TEST_ROOT/sh_unknown.err"
set +e
(
	cd "$REPO_DIR" && env SHELL=/bin/unknown sh "$FORK_SH" sh >"$sh_unknown_stdout" 2>"$sh_unknown_stderr"
)
sh_unknown_status=$?
set -e
sh_unknown_out=$(cat "$sh_unknown_stdout")
sh_unknown_err=$(cat "$sh_unknown_stderr")
assert_status 1 "$sh_unknown_status" "fork sh rejects unknown shell"
assert_empty "$sh_unknown_out" "fork sh unknown shell produces no stdout"
assert_contains "unknown shell" "$sh_unknown_err" "fork sh unknown shell reports error"
