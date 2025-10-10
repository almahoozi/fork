#!/bin/sh
# suite: errors
# description: Error handling (missing worktrees, dirty state, unmerged branches)

set -eu

. "$TESTS_DIR/lib/utils.sh"
. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/fixtures.sh"

setup_repo "fork-errors"
missing_co_stdout="$TEST_ROOT/co_missing.out"
missing_co_stderr="$TEST_ROOT/co_missing.err"
set +e
run_fork_capture "$missing_co_stdout" "$missing_co_stderr" co ghost
missing_co_status=$?
set -e
missing_co_err=$(cat "$missing_co_stderr")
assert_status 1 "$missing_co_status" "co exits non-zero for missing worktree"
assert_contains "does not exist" "$missing_co_err" "co missing emits helpful error"
missing_rm_stdout="$TEST_ROOT/rm_missing.out"
missing_rm_stderr="$TEST_ROOT/rm_missing.err"
set +e
run_fork_capture "$missing_rm_stdout" "$missing_rm_stderr" rm ghost
missing_rm_status=$?
set -e
missing_rm_err=$(cat "$missing_rm_stderr")
assert_status 1 "$missing_rm_status" "rm exits non-zero for missing worktree"
assert_contains "does not exist" "$missing_rm_err" "rm missing emits helpful error"
run_fork_quiet new stubborn
(
	cd "$WORKTREE_BASE_REAL/stubborn" &&
		echo "pending" >pending.txt &&
		git add pending.txt &&
		git commit -m "Pending work" >/dev/null 2>&1
)
unmerged_rm_stdout="$TEST_ROOT/rm_unmerged.out"
unmerged_rm_stderr="$TEST_ROOT/rm_unmerged.err"
set +e
run_fork_capture "$unmerged_rm_stdout" "$unmerged_rm_stderr" rm stubborn
unmerged_rm_status=$?
set -e
unmerged_rm_err=$(cat "$unmerged_rm_stderr")
assert_status 1 "$unmerged_rm_status" "rm refuses to delete unmerged without force"
assert_contains "not merged" "$unmerged_rm_err" "rm unmerged emits merge warning"
assert_dir_exists "$WORKTREE_BASE_REAL/stubborn" "rm without force leaves worktree"
run_fork_quiet new aux
rm_force_all_out="$TEST_ROOT/rm_force_all.out"
rm_force_all_err="$TEST_ROOT/rm_force_all.err"
run_fork_capture "$rm_force_all_out" "$rm_force_all_err" rm -a -f
rm_force_all_status=$?
rm_force_all_path=$(cat "$rm_force_all_out")
rm_force_all_msg=$(cat "$rm_force_all_err")
assert_status 0 "$rm_force_all_status" "rm -a -f succeeds with multiple worktrees"
assert_equal "$REPO_REALPATH" "$rm_force_all_path" "rm -a -f prints repo path after cleanup"
assert_contains "Removed worktree:" "$rm_force_all_msg" "rm -a -f reports removals"
assert_dir_missing "$WORKTREE_BASE_REAL/stubborn" "rm -a -f removes stubborn worktree"
assert_dir_missing "$WORKTREE_BASE_REAL/aux" "rm -a -f removes auxiliary worktree"

setup_repo "fork-dirty"
run_fork_quiet new dirty-staged
(
	cd "$WORKTREE_BASE_REAL/dirty-staged" &&
		echo "staged" >staged.txt &&
		git add staged.txt
)
dirty_staged_rm_stdout="$TEST_ROOT/dirty_staged_rm.out"
dirty_staged_rm_stderr="$TEST_ROOT/dirty_staged_rm.err"
set +e
run_fork_capture "$dirty_staged_rm_stdout" "$dirty_staged_rm_stderr" rm dirty-staged
dirty_staged_rm_status=$?
set -e
dirty_staged_rm_err=$(cat "$dirty_staged_rm_stderr")
assert_status 1 "$dirty_staged_rm_status" "rm refuses to delete worktree with staged changes"
assert_contains "uncommitted changes" "$dirty_staged_rm_err" "rm staged emits dirty error"
assert_dir_exists "$WORKTREE_BASE_REAL/dirty-staged" "rm without force leaves dirty worktree with staged changes"

run_fork_quiet new dirty-unstaged
(
	cd "$WORKTREE_BASE_REAL/dirty-unstaged" &&
		echo "modified" >README.md
)
dirty_unstaged_rm_stdout="$TEST_ROOT/dirty_unstaged_rm.out"
dirty_unstaged_rm_stderr="$TEST_ROOT/dirty_unstaged_rm.err"
set +e
run_fork_capture "$dirty_unstaged_rm_stdout" "$dirty_unstaged_rm_stderr" rm dirty-unstaged
dirty_unstaged_rm_status=$?
set -e
dirty_unstaged_rm_err=$(cat "$dirty_unstaged_rm_stderr")
assert_status 1 "$dirty_unstaged_rm_status" "rm refuses to delete worktree with unstaged changes"
assert_contains "uncommitted changes" "$dirty_unstaged_rm_err" "rm unstaged emits dirty error"
assert_dir_exists "$WORKTREE_BASE_REAL/dirty-unstaged" "rm without force leaves dirty worktree with unstaged changes"

run_fork_quiet new dirty-untracked
(
	cd "$WORKTREE_BASE_REAL/dirty-untracked" &&
		echo "untracked" >untracked.txt
)
dirty_untracked_rm_stdout="$TEST_ROOT/dirty_untracked_rm.out"
dirty_untracked_rm_stderr="$TEST_ROOT/dirty_untracked_rm.err"
set +e
run_fork_capture "$dirty_untracked_rm_stdout" "$dirty_untracked_rm_stderr" rm dirty-untracked
dirty_untracked_rm_status=$?
set -e
dirty_untracked_rm_err=$(cat "$dirty_untracked_rm_stderr")
assert_status 1 "$dirty_untracked_rm_status" "rm refuses to delete worktree with untracked files"
assert_contains "uncommitted changes" "$dirty_untracked_rm_err" "rm untracked emits dirty error"
assert_dir_exists "$WORKTREE_BASE_REAL/dirty-untracked" "rm without force leaves dirty worktree with untracked files"

dirty_force_rm_stdout="$TEST_ROOT/dirty_force_rm.out"
dirty_force_rm_stderr="$TEST_ROOT/dirty_force_rm.err"
run_fork_capture "$dirty_force_rm_stdout" "$dirty_force_rm_stderr" rm -f dirty-staged dirty-unstaged dirty-untracked
dirty_force_rm_status=$?
dirty_force_rm_path=$(cat "$dirty_force_rm_stdout")
dirty_force_rm_msg=$(cat "$dirty_force_rm_stderr")
assert_status 0 "$dirty_force_rm_status" "rm -f succeeds with dirty worktrees"
assert_equal "$REPO_REALPATH" "$dirty_force_rm_path" "rm -f prints repo path after dirty cleanup"
assert_contains "Removed worktree:" "$dirty_force_rm_msg" "rm -f reports removals of dirty worktrees"
assert_dir_missing "$WORKTREE_BASE_REAL/dirty-staged" "rm -f removes dirty worktree with staged changes"
assert_dir_missing "$WORKTREE_BASE_REAL/dirty-unstaged" "rm -f removes dirty worktree with unstaged changes"
assert_dir_missing "$WORKTREE_BASE_REAL/dirty-untracked" "rm -f removes dirty worktree with untracked files"
