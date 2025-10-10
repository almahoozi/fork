#!/bin/sh
# suite: worktrees
# description: Basic worktree operations (new, go, co, main, ls, rm, clean)

set -eu

. "$TESTS_DIR/lib/utils.sh"
. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/fixtures.sh"

setup_repo "fork-main"

main_stdout="$TEST_ROOT/main.out"
main_stderr="$TEST_ROOT/main.err"
run_fork_capture "$main_stdout" "$main_stderr" main
main_path=$(cat "$main_stdout")
main_msg=$(cat "$main_stderr")
assert_equal "$REPO_REALPATH" "$main_path" "main returns repository root"
assert_contains "Switched to main worktree" "$main_msg" "main reports switch in CLI mode"

main_cd_stdout="$TEST_ROOT/main_cd.out"
main_cd_stderr="$TEST_ROOT/main_cd.err"
run_fork_capture_cd "$main_cd_stdout" "$main_cd_stderr" main
main_cd_path=$(cat "$main_cd_stdout")
main_cd_msg=$(cat "$main_cd_stderr")
assert_equal "$REPO_REALPATH" "$main_cd_path" "main returns repository root in cd mode"
assert_empty "$main_cd_msg" "main suppresses stderr in cd mode"

run_fork_quiet new feature-alpha
assert_dir_exists "$WORKTREE_BASE_REAL/feature-alpha" "new creates feature-alpha worktree"

go_create_stdout="$TEST_ROOT/go_create.out"
go_create_stderr="$TEST_ROOT/go_create.err"
run_fork_capture "$go_create_stdout" "$go_create_stderr" go feature-beta
feature_beta_path=$(cat "$go_create_stdout")
go_create_msg=$(cat "$go_create_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-beta" "$feature_beta_path" "go prints feature-beta path on creation"
assert_contains "Created and switched to worktree 'feature-beta'" "$go_create_msg" "go reports creation in CLI mode"

ls_output=$(run_fork ls)
assert_contains "feature-alpha" "$ls_output" "ls lists feature-alpha"
assert_contains "feature-beta" "$ls_output" "ls lists feature-beta"

go_again_stdout="$TEST_ROOT/go_again.out"
go_again_stderr="$TEST_ROOT/go_again.err"
run_fork_capture "$go_again_stdout" "$go_again_stderr" go feature-beta
go_again_path=$(cat "$go_again_stdout")
go_again_msg=$(cat "$go_again_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-beta" "$go_again_path" "go prints feature-beta path on revisit"
assert_contains "Switched to worktree 'feature-beta'" "$go_again_msg" "go reports switch in CLI mode"

go_cd_stdout="$TEST_ROOT/go_cd.out"
go_cd_stderr="$TEST_ROOT/go_cd.err"
run_fork_capture_cd "$go_cd_stdout" "$go_cd_stderr" go feature-beta
go_cd_path=$(cat "$go_cd_stdout")
go_cd_msg=$(cat "$go_cd_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-beta" "$go_cd_path" "go prints feature-beta path in cd mode"
assert_empty "$go_cd_msg" "go suppresses stderr in cd mode"

co_stdout="$TEST_ROOT/co_cli.out"
co_stderr="$TEST_ROOT/co_cli.err"
run_fork_capture "$co_stdout" "$co_stderr" co feature-alpha
co_path=$(cat "$co_stdout")
co_msg=$(cat "$co_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-alpha" "$co_path" "co prints feature-alpha path"
assert_contains "Switched to worktree 'feature-alpha'" "$co_msg" "co reports switch in CLI mode"

co_cd_stdout="$TEST_ROOT/co_cd.out"
co_cd_stderr="$TEST_ROOT/co_cd.err"
run_fork_capture_cd "$co_cd_stdout" "$co_cd_stderr" co feature-alpha
co_cd_path=$(cat "$co_cd_stdout")
co_cd_msg=$(cat "$co_cd_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-alpha" "$co_cd_path" "co prints feature-alpha path in cd mode"
assert_empty "$co_cd_msg" "co suppresses stderr in cd mode"

rm_stdout="$TEST_ROOT/rm_cli.out"
rm_stderr="$TEST_ROOT/rm_cli.err"
run_fork_capture "$rm_stdout" "$rm_stderr" rm -f feature-alpha
rm_path=$(cat "$rm_stdout")
rm_msg=$(cat "$rm_stderr")
assert_equal "$REPO_REALPATH" "$rm_path" "rm prints return path in CLI mode"
assert_contains "Return path: $REPO_REALPATH" "$rm_msg" "rm reports return path in CLI mode"

assert_dir_missing "$WORKTREE_BASE_REAL/feature-alpha" "rm -f removes feature-alpha"

rm_cd_stdout="$TEST_ROOT/rm_cd.out"
rm_cd_stderr="$TEST_ROOT/rm_cd.err"
run_fork_capture_cd "$rm_cd_stdout" "$rm_cd_stderr" rm -f feature-beta
rm_cd_path=$(cat "$rm_cd_stdout")
rm_cd_msg=$(cat "$rm_cd_stderr")
assert_equal "$REPO_REALPATH" "$rm_cd_path" "rm prints return path in cd mode"
assert_contains "Removed worktree: feature-beta" "$rm_cd_msg" "rm reports removal in cd mode"
assert_not_contains "Return path:" "$rm_cd_msg" "rm suppresses return path message in cd mode"
assert_dir_missing "$WORKTREE_BASE_REAL/feature-beta" "rm -f removes feature-beta in cd mode"

run_fork_quiet new feature-clean
run_fork_quiet clean
assert_dir_missing "$WORKTREE_BASE_REAL/feature-clean" "clean removes merged worktrees"

setup_repo "fork-target"
(
	cd "$REPO_DIR" &&
		git checkout -b develop >/dev/null 2>&1 &&
		echo "develop base" >develop.txt &&
		git add develop.txt &&
		git commit -m "Seed develop" >/dev/null 2>&1 &&
		git checkout main >/dev/null 2>&1
)
run_fork_quiet new --target develop feature-one feature-two
assert_dir_exists "$WORKTREE_BASE_REAL/feature-one" "new --target creates feature-one worktree"
assert_dir_exists "$WORKTREE_BASE_REAL/feature-two" "new --target creates feature-two worktree"
develop_commit=$(cd "$REPO_DIR" && git rev-parse develop)
feature_one_commit=$(cd "$WORKTREE_BASE_REAL/feature-one" && git rev-parse HEAD)
feature_two_commit=$(cd "$WORKTREE_BASE_REAL/feature-two" && git rev-parse HEAD)
assert_equal "$develop_commit" "$feature_one_commit" "feature-one tracks develop tip"
assert_equal "$develop_commit" "$feature_two_commit" "feature-two tracks develop tip"

setup_repo "fork-ls"
run_fork_quiet new feature-merged
run_fork_quiet new feature-unmerged
(
	cd "$WORKTREE_BASE_REAL/feature-unmerged" &&
		echo "change" >work.txt &&
		git add work.txt &&
		git commit -m "WIP change" >/dev/null 2>&1
)
ls_merged=$(run_fork ls -m)
ls_unmerged=$(run_fork ls -u)
assert_contains "feature-merged" "$ls_merged" "ls -m lists merged worktrees"
assert_not_contains "feature-unmerged" "$ls_merged" "ls -m excludes unmerged worktrees"
assert_contains "feature-unmerged" "$ls_unmerged" "ls -u lists unmerged worktrees"
assert_not_contains "feature-merged" "$ls_unmerged" "ls -u excludes merged worktrees"

ls_all=$(run_fork ls)
assert_contains "merged" "$ls_all" "ls shows merge status"
assert_contains "clean" "$ls_all" "ls shows dirty status"

run_fork_quiet new feature-dirty
(
	cd "$WORKTREE_BASE_REAL/feature-dirty" &&
		echo "dirty" >dirty.txt
)
ls_dirty=$(run_fork ls -d)
ls_clean=$(run_fork ls -c)
assert_contains "feature-dirty" "$ls_dirty" "ls -d lists dirty worktrees"
assert_not_contains "feature-merged" "$ls_dirty" "ls -d excludes clean worktrees"
assert_not_contains "feature-dirty" "$ls_clean" "ls -c excludes dirty worktrees"
assert_contains "feature-merged" "$ls_clean" "ls -c lists clean worktrees"

ls_dirty_line=$(run_fork ls | grep "feature-dirty" || true)
assert_contains "dirty" "$ls_dirty_line" "ls indicates dirty status for dirty worktree"
ls_clean_line=$(run_fork ls | grep "feature-merged" || true)
assert_contains "clean" "$ls_clean_line" "ls indicates clean status for clean worktree"

clean_first_stdout="$TEST_ROOT/clean_first.out"
clean_first_stderr="$TEST_ROOT/clean_first.err"
run_fork_capture "$clean_first_stdout" "$clean_first_stderr" clean
clean_first_out=$(cat "$clean_first_stdout")
clean_first_err=$(cat "$clean_first_stderr")
assert_empty "$clean_first_out" "clean emits no stdout when only removing others"
assert_contains "Removed worktree: feature-merged" "$clean_first_err" "clean removes merged worktrees when present"
assert_not_contains "feature-unmerged" "$clean_first_err" "clean skips unmerged worktrees"
assert_dir_missing "$WORKTREE_BASE_REAL/feature-merged" "clean prunes merged worktree directory"
assert_dir_exists "$WORKTREE_BASE_REAL/feature-unmerged" "clean preserves unmerged worktree"
clean_second_stdout="$TEST_ROOT/clean_second.out"
clean_second_stderr="$TEST_ROOT/clean_second.err"
run_fork_capture "$clean_second_stdout" "$clean_second_stderr" clean
clean_second_out=$(cat "$clean_second_stdout")
clean_second_err=$(cat "$clean_second_stderr")
assert_contains "No worktrees removed" "$clean_second_out" "clean reports when nothing to remove"
assert_empty "$clean_second_err" "clean emits no stderr when nothing to remove"
rm_all_stdout="$TEST_ROOT/rm_all_cli.out"
rm_all_stderr="$TEST_ROOT/rm_all_cli.err"
run_fork_capture "$rm_all_stdout" "$rm_all_stderr" rm -a -f
rm_all_status=$?
rm_all_path=$(cat "$rm_all_stdout")
rm_all_msg=$(cat "$rm_all_stderr")
assert_status 0 "$rm_all_status" "rm -a -f exits successfully"
assert_equal "$REPO_REALPATH" "$rm_all_path" "rm -a -f prints return path"
assert_contains "Return path:" "$rm_all_msg" "rm -a -f reports return path"
assert_dir_missing "$WORKTREE_BASE_REAL/feature-unmerged" "rm -a -f removes all worktrees"

setup_repo "fork-clean-current"
run_fork_quiet new feature-current
run_fork_quiet new feature-other
run_fork_quiet new feature-keep
(
	cd "$WORKTREE_BASE_REAL/feature-keep" &&
		echo "keep" >keep.txt &&
		git add keep.txt &&
		git commit -m "Keep changes" >/dev/null 2>&1
)
clean_current_stdout="$TEST_ROOT/clean_current.out"
clean_current_stderr="$TEST_ROOT/clean_current.err"
(
	cd "$WORKTREE_BASE_REAL/feature-current" &&
		env FORK_CD=1 sh "$FORK_SH" clean >"$clean_current_stdout" 2>"$clean_current_stderr"
)
clean_current_out=$(cat "$clean_current_stdout")
clean_current_err=$(cat "$clean_current_stderr")
assert_equal "$REPO_REALPATH" "$clean_current_out" "clean prints return path when removing current worktree"
assert_contains "Removed worktree: feature-other" "$clean_current_err" "clean removes other merged worktrees first"
assert_contains "Removed worktree: feature-current" "$clean_current_err" "clean reports removal of current worktree"
assert_not_contains "Return path:" "$clean_current_err" "clean suppresses return message in cd mode"
assert_not_contains "feature-keep" "$clean_current_err" "clean leaves unmerged worktree untouched"
assert_dir_missing "$WORKTREE_BASE_REAL/feature-current" "clean removes current merged worktree"
assert_dir_missing "$WORKTREE_BASE_REAL/feature-other" "clean removes merged peer worktree"
assert_dir_exists "$WORKTREE_BASE_REAL/feature-keep" "clean preserves unmerged worktree"

setup_repo "fork-clean-dirty"
run_fork_quiet new clean-dirty-staged
run_fork_quiet new clean-dirty-untracked
run_fork_quiet new clean-normal
(
	cd "$WORKTREE_BASE_REAL/clean-dirty-staged" &&
		echo "staged" >staged.txt &&
		git add staged.txt
)
(
	cd "$WORKTREE_BASE_REAL/clean-dirty-untracked" &&
		echo "untracked" >untracked.txt
)
clean_skip_dirty_stdout="$TEST_ROOT/clean_skip_dirty.out"
clean_skip_dirty_stderr="$TEST_ROOT/clean_skip_dirty.err"
run_fork_capture "$clean_skip_dirty_stdout" "$clean_skip_dirty_stderr" clean
clean_skip_dirty_out=$(cat "$clean_skip_dirty_stdout")
clean_skip_dirty_err=$(cat "$clean_skip_dirty_stderr")
assert_empty "$clean_skip_dirty_out" "clean emits no stdout when removing only non-dirty worktrees"
assert_contains "Removed worktree: clean-normal" "$clean_skip_dirty_err" "clean removes clean merged worktrees"
assert_not_contains "clean-dirty-staged" "$clean_skip_dirty_err" "clean skips dirty worktree with staged changes"
assert_not_contains "clean-dirty-untracked" "$clean_skip_dirty_err" "clean skips dirty worktree with untracked files"
assert_dir_exists "$WORKTREE_BASE_REAL/clean-dirty-staged" "clean preserves dirty worktree with staged changes"
assert_dir_exists "$WORKTREE_BASE_REAL/clean-dirty-untracked" "clean preserves dirty worktree with untracked files"
assert_dir_missing "$WORKTREE_BASE_REAL/clean-normal" "clean removes clean merged worktree"
