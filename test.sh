#!/bin/sh
# test.sh - Minimal POSIX test harness for fork.sh
#
# Usage:
#   ./test.sh            # run with current shell
#   sh test.sh           # explicit POSIX sh invocation
#
# The tests require git to be available on PATH. They create temporary
# repositories and worktrees under ${TMPDIR:-/tmp}. All temporary files
# and directories are removed on exit.

set -eu

FAST=0
VERBOSE=0
USE_CACHE=1
ORIG_ARGS="$*"

usage() {
	printf '%s\n' "Usage: $0 [--fast|-f] [--verbose|-v] [--no-cache|-n]"
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	--fast | -f | fast)
		FAST=1
		;;
	--verbose | -v | verbose)
		VERBOSE=1
		;;
	--no-cache | -n | nocache | no-cache)
		USE_CACHE=0
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		printf '%s\n' "Error: unknown option '$1'" >&2
		usage >&2
		exit 2
		;;
	esac
	shift
done

if [ "${FORK_TEST_CACHE_FORCE_VERBOSE:-0}" -eq 1 ]; then
	VERBOSE=1
fi

display_results() {
	result_file=$1
	result_status=$2
	if [ "$VERBOSE" -eq 1 ]; then
		cat "$result_file"
	else
		if [ "$result_status" -eq 0 ]; then
			awk 'BEGIN{capture=0} /^---/{capture=1} capture{print}' "$result_file"
		else
			cat "$result_file"
		fi
	fi
}

hash_file() {
	file_path=$1
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file_path" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file_path" | awk '{print $1}'
	else
		git hash-object "$file_path"
	fi
}

project_root() {
	dirname "$0" | {
		IFS=/ read -r first rest || true
		if [ -z "$rest" ]; then
			echo "."
		else
			echo "${first}${rest:+/}${rest%%/*}"
		fi
	}
}

SCRIPT_PATH=$0
case "$SCRIPT_PATH" in
/*)
	:
	;;
*)
	SCRIPT_PATH="$(pwd)/$SCRIPT_PATH"
	;;
esac

SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
FORK_SH="$SCRIPT_DIR/fork.sh"

if [ ! -f "$FORK_SH" ]; then
	printf '%s\n' 'Error: fork.sh not found next to test.sh' >&2
	exit 1
fi

if ! command -v git >/dev/null 2>&1; then
	printf '%s\n' 'Error: git not found on PATH' >&2
	exit 1
fi

if [ "$USE_CACHE" -eq 1 ] && [ "${FORK_TEST_CACHE_PHASE:-0}" -ne 1 ]; then
	if [ -n "${FORK_CACHE_PATH:-}" ]; then
		cache_dir="$FORK_CACHE_PATH"
	elif [ -n "${XDG_CACHE_HOME:-}" ]; then
		cache_dir="$XDG_CACHE_HOME/fork"
	elif [ -n "${HOME:-}" ]; then
		cache_dir="$HOME/.cache/fork"
	else
		cache_dir="$SCRIPT_DIR/.fork-cache"
	fi

	fork_hash=$(hash_file "$FORK_SH")
	test_hash=$(hash_file "$SCRIPT_PATH")
	cache_key="${fork_hash}_${test_hash}_fast${FAST}"
	cache_file="$cache_dir/fork_test_cache_${cache_key}"
	cache_status_file="$cache_file.status"

	mkdir -p "$cache_dir"

	if [ -f "$cache_file" ] && [ -f "$cache_status_file" ]; then
		cached_status=$(cat "$cache_status_file")
		if [ "$VERBOSE" -eq 1 ]; then
			printf '%s\n' "Using cached test results (hash ${cache_key})"
		else
			printf '%s\n' "Using cached test results"
		fi
		display_results "$cache_file" "$cached_status"
		exit "$cached_status"
	fi

	tmp_prefix="$cache_dir/fork_test_cache_tmp.$$"
	tmp_cache="$tmp_prefix"
	suffix=0
	while :; do
		if (umask 077 && : >"$tmp_cache") 2>/dev/null; then
			break
		fi
		suffix=$((suffix + 1))
		tmp_cache="${tmp_prefix}.$suffix"
		if [ "$suffix" -ge 1000 ]; then
			printf '%s\n' 'Error: unable to create temporary cache file' >&2
			exit 1
		fi
	done

	trap 'rm -f "$tmp_cache"' INT TERM HUP EXIT
	set +e
	if [ -n "$ORIG_ARGS" ]; then
		FORK_TEST_CACHE_PHASE=1 FORK_TEST_CACHE_FORCE_VERBOSE=1 sh "$0" $ORIG_ARGS >"$tmp_cache" 2>&1
	else
		FORK_TEST_CACHE_PHASE=1 FORK_TEST_CACHE_FORCE_VERBOSE=1 sh "$0" >"$tmp_cache" 2>&1
	fi
	status=$?
	set -e
	display_results "$tmp_cache" "$status"
	mv "$tmp_cache" "$cache_file"
	printf '%s\n' "$status" >"$cache_status_file"
	trap - INT TERM HUP EXIT
	exit "$status"
fi

test_root="${TMPDIR:-/tmp}/fork-test-$$"
mkdir -p "$test_root"
TEST_ROOT_REAL=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

FAIL_LOG="$test_root/failures.log"
: >"$FAIL_LOG"

PASS=0
FAIL=0

print_summary() {
	printf '%s\n' "---"
	printf '%s\n' "Passed: $PASS"
	printf '%s\n' "Failed: $FAIL"
	if [ "$FAIL" -ne 0 ] && [ -s "$FAIL_LOG" ]; then
		printf '%s\n' "Failed tests:"
		while IFS= read -r line; do
			printf '  - %s\n' "$line"
		done <"$FAIL_LOG"
	fi
}

die() {
	desc=$1
	reason=$2
	printf '%s\n' "not ok - $desc: $reason" >&2
	printf '%s\n' "$desc: $reason" >>"$FAIL_LOG"
	FAIL=$((FAIL + 1))
	if [ "$FAST" -eq 1 ]; then
		printf '%s\n' "Fast mode enabled; aborting after first failure." >&2
		print_summary
		exit 1
	fi
}

ok() {
	if [ "$VERBOSE" -eq 1 ]; then
		printf '%s\n' "ok - $1"
	fi
	PASS=$((PASS + 1))
}

run_fork() {
	(cd "$REPO_DIR" && sh "$FORK_SH" "$@")
}

run_fork_quiet() {
	tmp_prefix="$test_root/run_fork_quiet.$$"
	tmp_base="$tmp_prefix"
	suffix=0

	while :; do
		out_file="${tmp_base}.out"
		err_file="${tmp_base}.err"
		if (umask 077 && : >"$out_file" && : >"$err_file") 2>/dev/null; then
			break
		fi
		suffix=$((suffix + 1))
		tmp_base="${tmp_prefix}.$suffix"
		if [ "$suffix" -ge 1000 ]; then
			printf '%s\n' 'Error: unable to create temporary capture files' >&2
			exit 1
		fi
	done

	set +e
	(cd "$REPO_DIR" && sh "$FORK_SH" "$@" >"$out_file" 2>"$err_file")
	status=$?
	set -e

	if [ "$status" -ne 0 ]; then
		printf '%s' 'Command failed: fork.sh' >&2
		for arg in "$@"; do
			printf ' %s' "$arg" >&2
		done
		printf '\n' >&2

		if [ -s "$out_file" ]; then
			printf '%s\n' "-- stdout --" >&2
			cat "$out_file" >&2
		fi

		if [ -s "$err_file" ]; then
			printf '%s\n' "-- stderr --" >&2
			cat "$err_file" >&2
		fi
	fi

	rm -f "$out_file" "$err_file"
	return "$status"
}

run_fork_capture() {
	out_file=$1
	err_file=$2
	shift 2
	(cd "$REPO_DIR" && sh "$FORK_SH" "$@" >"$out_file" 2>"$err_file")
}

run_fork_capture_cd() {
	out_file=$1
	err_file=$2
	shift 2
	(cd "$REPO_DIR" && env FORK_CD=1 sh "$FORK_SH" "$@" >"$out_file" 2>"$err_file")
}

setup_repo() {
	repo_name=$1
	REPO_NAME="$repo_name"
	REPO_DIR="$test_root/$repo_name"
	WORKTREE_BASE="$test_root/${repo_name}_forks"

	mkdir -p "$REPO_DIR"
	cd "$REPO_DIR"
	git init . >/dev/null 2>&1
	git config user.email "tester@example.com"
	git config user.name "Fork Tester"
	echo "initial" >README.md
	git add README.md
	git commit -m "Initial commit" >/dev/null 2>&1
	git branch -M main >/dev/null 2>&1
	REPO_REALPATH=$(pwd -P)
	WORKTREE_BASE_REAL="$TEST_ROOT_REAL/${repo_name}_forks"
	cd "$SCRIPT_DIR"
}

assert_equal() {
	expected=$1
	actual=$2
	desc=$3
	if [ "$expected" = "$actual" ]; then
		ok "$desc"
	else
		die "$desc" "expected '$expected' got '$actual'"
	fi
}

assert_dir_exists() {
	path=$1
	desc=$2
	if [ -d "$path" ]; then
		ok "$desc"
	else
		die "$desc" "directory '$path' missing"
	fi
}

assert_dir_missing() {
	path=$1
	desc=$2
	if [ ! -d "$path" ]; then
		ok "$desc"
	else
		die "$desc" "directory '$path' still present"
	fi
}

assert_contains() {
	needle=$1
	haystack=$2
	desc=$3
	case "$haystack" in
	*"$needle"*)
		ok "$desc"
		;;
	*)
		die "$desc" "missing '$needle' in output"
		;;
	esac
}

assert_not_contains() {
	needle=$1
	haystack=$2
	desc=$3
	case "$haystack" in
	*"$needle"*)
		die "$desc" "unexpected '$needle' in output"
		;;
	*)
		ok "$desc"
		;;
	esac
}

assert_empty() {
	value=$1
	desc=$2
	if [ -z "$value" ]; then
		ok "$desc"
	else
		die "$desc" "expected empty but got '$value'"
	fi
}

assert_status() {
	expected=$1
	actual=$2
	desc=$3
	if [ "$actual" -eq "$expected" ]; then
		ok "$desc"
	else
		die "$desc" "expected status $expected but got $actual"
	fi
}

setup_repo "fork-main"

main_stdout="$test_root/main.out"
main_stderr="$test_root/main.err"
run_fork_capture "$main_stdout" "$main_stderr" main
main_path=$(cat "$main_stdout")
main_msg=$(cat "$main_stderr")
assert_equal "$REPO_REALPATH" "$main_path" "main returns repository root"
assert_contains "Switched to main worktree" "$main_msg" "main reports switch in CLI mode"

main_cd_stdout="$test_root/main_cd.out"
main_cd_stderr="$test_root/main_cd.err"
run_fork_capture_cd "$main_cd_stdout" "$main_cd_stderr" main
main_cd_path=$(cat "$main_cd_stdout")
main_cd_msg=$(cat "$main_cd_stderr")
assert_equal "$REPO_REALPATH" "$main_cd_path" "main returns repository root in cd mode"
assert_empty "$main_cd_msg" "main suppresses stderr in cd mode"

run_fork_quiet new feature-alpha
assert_dir_exists "$WORKTREE_BASE_REAL/feature-alpha" "new creates feature-alpha worktree"

go_create_stdout="$test_root/go_create.out"
go_create_stderr="$test_root/go_create.err"
run_fork_capture "$go_create_stdout" "$go_create_stderr" go feature-beta
feature_beta_path=$(cat "$go_create_stdout")
go_create_msg=$(cat "$go_create_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-beta" "$feature_beta_path" "go prints feature-beta path on creation"
assert_contains "Created and switched to worktree 'feature-beta'" "$go_create_msg" "go reports creation in CLI mode"

ls_output=$(run_fork ls)
assert_contains "feature-alpha" "$ls_output" "ls lists feature-alpha"
assert_contains "feature-beta" "$ls_output" "ls lists feature-beta"

go_again_stdout="$test_root/go_again.out"
go_again_stderr="$test_root/go_again.err"
run_fork_capture "$go_again_stdout" "$go_again_stderr" go feature-beta
go_again_path=$(cat "$go_again_stdout")
go_again_msg=$(cat "$go_again_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-beta" "$go_again_path" "go prints feature-beta path on revisit"
assert_contains "Switched to worktree 'feature-beta'" "$go_again_msg" "go reports switch in CLI mode"

go_cd_stdout="$test_root/go_cd.out"
go_cd_stderr="$test_root/go_cd.err"
run_fork_capture_cd "$go_cd_stdout" "$go_cd_stderr" go feature-beta
go_cd_path=$(cat "$go_cd_stdout")
go_cd_msg=$(cat "$go_cd_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-beta" "$go_cd_path" "go prints feature-beta path in cd mode"
assert_empty "$go_cd_msg" "go suppresses stderr in cd mode"

co_stdout="$test_root/co_cli.out"
co_stderr="$test_root/co_cli.err"
run_fork_capture "$co_stdout" "$co_stderr" co feature-alpha
co_path=$(cat "$co_stdout")
co_msg=$(cat "$co_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-alpha" "$co_path" "co prints feature-alpha path"
assert_contains "Switched to worktree 'feature-alpha'" "$co_msg" "co reports switch in CLI mode"

co_cd_stdout="$test_root/co_cd.out"
co_cd_stderr="$test_root/co_cd.err"
run_fork_capture_cd "$co_cd_stdout" "$co_cd_stderr" co feature-alpha
co_cd_path=$(cat "$co_cd_stdout")
co_cd_msg=$(cat "$co_cd_stderr")
assert_equal "$WORKTREE_BASE_REAL/feature-alpha" "$co_cd_path" "co prints feature-alpha path in cd mode"
assert_empty "$co_cd_msg" "co suppresses stderr in cd mode"

rm_stdout="$test_root/rm_cli.out"
rm_stderr="$test_root/rm_cli.err"
run_fork_capture "$rm_stdout" "$rm_stderr" rm -f feature-alpha
rm_path=$(cat "$rm_stdout")
rm_msg=$(cat "$rm_stderr")
assert_equal "$REPO_REALPATH" "$rm_path" "rm prints return path in CLI mode"
assert_contains "Return path: $REPO_REALPATH" "$rm_msg" "rm reports return path in CLI mode"

assert_dir_missing "$WORKTREE_BASE_REAL/feature-alpha" "rm -f removes feature-alpha"

rm_cd_stdout="$test_root/rm_cd.out"
rm_cd_stderr="$test_root/rm_cd.err"
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

bash_integration=$(run_fork sh bash)
assert_contains "fork()" "$bash_integration" "sh bash emits shell function"

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

clean_first_stdout="$test_root/clean_first.out"
clean_first_stderr="$test_root/clean_first.err"
run_fork_capture "$clean_first_stdout" "$clean_first_stderr" clean
clean_first_out=$(cat "$clean_first_stdout")
clean_first_err=$(cat "$clean_first_stderr")
assert_empty "$clean_first_out" "clean emits no stdout when only removing others"
assert_contains "Removed worktree: feature-merged" "$clean_first_err" "clean removes merged worktrees when present"
assert_not_contains "feature-unmerged" "$clean_first_err" "clean skips unmerged worktrees"
assert_dir_missing "$WORKTREE_BASE_REAL/feature-merged" "clean prunes merged worktree directory"
assert_dir_exists "$WORKTREE_BASE_REAL/feature-unmerged" "clean preserves unmerged worktree"
clean_second_stdout="$test_root/clean_second.out"
clean_second_stderr="$test_root/clean_second.err"
run_fork_capture "$clean_second_stdout" "$clean_second_stderr" clean
clean_second_out=$(cat "$clean_second_stdout")
clean_second_err=$(cat "$clean_second_stderr")
assert_contains "No worktrees removed" "$clean_second_out" "clean reports when nothing to remove"
assert_empty "$clean_second_err" "clean emits no stderr when nothing to remove"
rm_all_stdout="$test_root/rm_all_cli.out"
rm_all_stderr="$test_root/rm_all_cli.err"
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
clean_current_stdout="$test_root/clean_current.out"
clean_current_stderr="$test_root/clean_current.err"
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

setup_repo "fork-errors"
missing_co_stdout="$test_root/co_missing.out"
missing_co_stderr="$test_root/co_missing.err"
set +e
run_fork_capture "$missing_co_stdout" "$missing_co_stderr" co ghost
missing_co_status=$?
set -e
missing_co_err=$(cat "$missing_co_stderr")
assert_status 1 "$missing_co_status" "co exits non-zero for missing worktree"
assert_contains "does not exist" "$missing_co_err" "co missing emits helpful error"
missing_rm_stdout="$test_root/rm_missing.out"
missing_rm_stderr="$test_root/rm_missing.err"
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
unmerged_rm_stdout="$test_root/rm_unmerged.out"
unmerged_rm_stderr="$test_root/rm_unmerged.err"
set +e
run_fork_capture "$unmerged_rm_stdout" "$unmerged_rm_stderr" rm stubborn
unmerged_rm_status=$?
set -e
unmerged_rm_err=$(cat "$unmerged_rm_stderr")
assert_status 1 "$unmerged_rm_status" "rm refuses to delete unmerged without force"
assert_contains "not merged" "$unmerged_rm_err" "rm unmerged emits merge warning"
assert_dir_exists "$WORKTREE_BASE_REAL/stubborn" "rm without force leaves worktree"
run_fork_quiet new aux
rm_force_all_out="$test_root/rm_force_all.out"
rm_force_all_err="$test_root/rm_force_all.err"
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
dirty_staged_rm_stdout="$test_root/dirty_staged_rm.out"
dirty_staged_rm_stderr="$test_root/dirty_staged_rm.err"
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
dirty_unstaged_rm_stdout="$test_root/dirty_unstaged_rm.out"
dirty_unstaged_rm_stderr="$test_root/dirty_unstaged_rm.err"
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
dirty_untracked_rm_stdout="$test_root/dirty_untracked_rm.out"
dirty_untracked_rm_stderr="$test_root/dirty_untracked_rm.err"
set +e
run_fork_capture "$dirty_untracked_rm_stdout" "$dirty_untracked_rm_stderr" rm dirty-untracked
dirty_untracked_rm_status=$?
set -e
dirty_untracked_rm_err=$(cat "$dirty_untracked_rm_stderr")
assert_status 1 "$dirty_untracked_rm_status" "rm refuses to delete worktree with untracked files"
assert_contains "uncommitted changes" "$dirty_untracked_rm_err" "rm untracked emits dirty error"
assert_dir_exists "$WORKTREE_BASE_REAL/dirty-untracked" "rm without force leaves dirty worktree with untracked files"

dirty_force_rm_stdout="$test_root/dirty_force_rm.out"
dirty_force_rm_stderr="$test_root/dirty_force_rm.err"
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
clean_skip_dirty_stdout="$test_root/clean_skip_dirty.out"
clean_skip_dirty_stderr="$test_root/clean_skip_dirty.err"
run_fork_capture "$clean_skip_dirty_stdout" "$clean_skip_dirty_stderr" clean
clean_skip_dirty_out=$(cat "$clean_skip_dirty_stdout")
clean_skip_dirty_err=$(cat "$clean_skip_dirty_stderr")
assert_empty "$clean_skip_dirty_out" "clean emits no stdout when only removing non-dirty worktrees"
assert_contains "Removed worktree: clean-normal" "$clean_skip_dirty_err" "clean removes clean merged worktrees"
assert_not_contains "clean-dirty-staged" "$clean_skip_dirty_err" "clean skips dirty worktree with staged changes"
assert_not_contains "clean-dirty-untracked" "$clean_skip_dirty_err" "clean skips dirty worktree with untracked files"
assert_dir_exists "$WORKTREE_BASE_REAL/clean-dirty-staged" "clean preserves dirty worktree with staged changes"
assert_dir_exists "$WORKTREE_BASE_REAL/clean-dirty-untracked" "clean preserves dirty worktree with untracked files"
assert_dir_missing "$WORKTREE_BASE_REAL/clean-normal" "clean removes clean merged worktree"

help_stdout="$test_root/help.out"
help_stderr="$test_root/help.err"
set +e
run_fork_capture "$help_stdout" "$help_stderr" help
help_status=$?
set -e
help_out=$(cat "$help_stdout")
help_err=$(cat "$help_stderr")
assert_status 2 "$help_status" "help exits with usage status"
assert_empty "$help_out" "help prints nothing to stdout"
assert_contains "Usage: fork" "$help_err" "help includes usage summary"
help_verbose_stdout="$test_root/help_verbose.out"
help_verbose_stderr="$test_root/help_verbose.err"
set +e
run_fork_capture "$help_verbose_stdout" "$help_verbose_stderr" help --verbose
help_verbose_status=$?
set -e
help_verbose_out=$(cat "$help_verbose_stdout")
help_verbose_err=$(cat "$help_verbose_stderr")
assert_status 2 "$help_verbose_status" "help --verbose exits with usage status"
assert_contains "Create worktrees" "$help_verbose_err" "help --verbose shows detailed commands"
assert_empty "$help_verbose_out" "help --verbose prints nothing to stdout"
sh_detect_stdout="$test_root/sh_detect.out"
sh_detect_stderr="$test_root/sh_detect.err"
(
	cd "$REPO_DIR" && env SHELL=/bin/bash sh "$FORK_SH" sh >"$sh_detect_stdout" 2>"$sh_detect_stderr"
)
sh_detect_status=$?
sh_detect_out=$(cat "$sh_detect_stdout")
sh_detect_err=$(cat "$sh_detect_stderr")
assert_status 0 "$sh_detect_status" "fork sh auto-detect succeeds for bash"
assert_contains "fork()" "$sh_detect_out" "fork sh auto-detect emits function"
assert_empty "$sh_detect_err" "fork sh auto-detect emits no stderr"
sh_unknown_stdout="$test_root/sh_unknown.out"
sh_unknown_stderr="$test_root/sh_unknown.err"
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

print_summary

[ "$FAIL" -eq 0 ]
