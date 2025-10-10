#!/bin/sh
# test.sh - Modular POSIX test runner for fork.sh
#
# Usage:
#   ./test.sh [suite...] [options]
#   ./test.sh                    # run all suites
#   ./test.sh worktrees          # run only worktrees suite
#   ./test.sh worktrees errors   # run worktrees and errors suites
#
# Options:
#   --fast, -f          Abort on first failure
#   --verbose, -v       Show passing tests
#   --no-cache, -n      Disable caching
#   --list, -l          List available suites
#   --select, -s        Auto-select suites based on git diff
#   --help, -h          Show this help

set -eu

FAST=0
VERBOSE=0
USE_CACHE=1
LIST_SUITES=0
SELECT_MODE=0
REQUESTED_SUITES=""

## NOTE: Use the following block to assert POSIX checking
#foo="barz"
#if [[ "$foo" == "bar" ]]; then
#echo "match"
#fi

usage() {
	printf '%s\n' "Usage: $0 [suite...] [options]"
	printf '%s\n' ""
	printf '%s\n' "Options:"
	printf '%s\n' "  --fast, -f          Abort on first failure"
	printf '%s\n' "  --verbose, -v       Show passing tests"
	printf '%s\n' "  --no-cache, -n      Disable caching"
	printf '%s\n' "  --list, -l          List available suites"
	printf '%s\n' "  --select, -s        Auto-select suites based on git diff"
	printf '%s\n' "  --help, -h          Show this help"
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
	--list | -l | list)
		LIST_SUITES=1
		;;
	--select | -s | select)
		SELECT_MODE=1
		;;
	--help | -h)
		usage
		exit 0
		;;
	-*)
		printf '%s\n' "Error: unknown option '$1'" >&2
		usage >&2
		exit 2
		;;
	*)
		REQUESTED_SUITES="$REQUESTED_SUITES $1"
		;;
	esac
	shift
done

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
TESTS_DIR="$SCRIPT_DIR/tests"
SUITES_DIR="$TESTS_DIR/suites"

if [ ! -f "$FORK_SH" ]; then
	printf '%s\n' 'Error: fork.sh not found next to test.sh' >&2
	exit 1
fi

if ! command -v git >/dev/null 2>&1; then
	printf '%s\n' 'Error: git not found on PATH' >&2
	exit 1
fi

if [ ! -d "$SUITES_DIR" ]; then
	printf '%s\n' 'Error: tests/suites directory not found' >&2
	exit 1
fi

discover_suites() {
	for suite_file in "$SUITES_DIR"/*.sh; do
		[ -f "$suite_file" ] || continue
		suite_name=$(basename "$suite_file" .sh)
		printf '%s\n' "$suite_name"
	done
}

list_suites() {
	printf '%s\n' "Available test suites:"
	for suite_file in "$SUITES_DIR"/*.sh; do
		[ -f "$suite_file" ] || continue
		suite_name=$(basename "$suite_file" .sh)
		desc=$(grep '^# description:' "$suite_file" | head -1 | sed 's/^# description: //')
		if [ -n "$desc" ]; then
			printf '  %-15s %s\n' "$suite_name" "$desc"
		else
			printf '  %s\n' "$suite_name"
		fi
	done
}

select_suites_from_diff() {
	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		printf '%s\n' "Warning: not in git repository; running all suites" >&2
		discover_suites
		return
	fi

	base_ref="main"
	if ! git rev-parse "$base_ref" >/dev/null 2>&1; then
		base_ref="master"
		if ! git rev-parse "$base_ref" >/dev/null 2>&1; then
			printf '%s\n' "Warning: no main/master branch found; running all suites" >&2
			discover_suites
			return
		fi
	fi

	changed_files=$(git diff --name-only "$base_ref"...HEAD 2>/dev/null || git diff --name-only HEAD)
	selected=""

	for file in $changed_files; do
		case "$file" in
		lib/35-container.sh | lib/*container*)
			selected="$selected containers"
			;;
		lib/10-env.sh | lib/*env*)
			selected="$selected env"
			;;
		lib/40-worktree.sh | lib/50-commands.sh | lib/*worktree*)
			selected="$selected worktrees"
			;;
		lib/60-shell.sh | lib/*shell*)
			selected="$selected shell"
			;;
		lib/30-core.sh)
			selected="$selected worktrees errors"
			;;
		fork.sh | test.sh | tests/*)
			discover_suites
			return
			;;
		esac
	done

	# TODO: If no actual changed files we don't need to run anything

	if [ -z "$selected" ]; then
		printf '%s\n' "No changed files map to test suites; running all suites" >&2
		discover_suites
		return
	fi

	printf '%s' "$selected" | tr ' ' '\n' | sort -u
}

if [ "$LIST_SUITES" -eq 1 ]; then
	list_suites
	exit 0
fi

if [ "$SELECT_MODE" -eq 1 ]; then
	REQUESTED_SUITES=$(select_suites_from_diff)
	if [ "$VERBOSE" -eq 1 ]; then
		printf '%s\n' "Selected suites: $REQUESTED_SUITES"
	fi
fi

if [ -z "$REQUESTED_SUITES" ]; then
	REQUESTED_SUITES=$(discover_suites)
fi

test_root="${TMPDIR:-/tmp}/fork-test-$$"
mkdir -p "$test_root"
TEST_ROOT_REAL=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM

FAIL_LOG="$test_root/failures.log"
: >"$FAIL_LOG"

TOTAL_PASS=0
TOTAL_FAIL=0
SUITES_RUN=0
SUITES_CACHED=0

if [ -n "${FORK_TEST_CACHE_PATH:-}" ]; then
	cache_dir="$FORK_TEST_CACHE_PATH"
elif [ -n "${XDG_CACHE_HOME:-}" ]; then
	cache_dir="$XDG_CACHE_HOME/fork"
elif [ -n "${HOME:-}" ]; then
	cache_dir="$HOME/.cache/fork"
else
	cache_dir="$SCRIPT_DIR/.fork-cache"
fi
mkdir -p "$cache_dir"

# TODO: hash_file is repeated in utils.sh
hash_file() {
	file_path=$1
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$file_path" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$file_path" | awk '{print $1}'
	else
		git hash-object "$file_path"
		# TODO: Why not start with (and just use) the git object hash?
	fi
}

compute_suite_cache_key() {
	suite_file=$1
	suite_hash=$(hash_file "$suite_file")
	utils_hash=$(hash_file "$TESTS_DIR/lib/utils.sh")
	assert_hash=$(hash_file "$TESTS_DIR/lib/assert.sh")
	fixtures_hash=$(hash_file "$TESTS_DIR/lib/fixtures.sh")
	fork_hash=$(hash_file "$FORK_SH")
	combined="${suite_hash}_${utils_hash}_${assert_hash}_${fixtures_hash}_${fork_hash}_fast${FAST}"
	if command -v sha256sum >/dev/null 2>&1; then
		printf '%s' "$combined" | sha256sum | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		printf '%s' "$combined" | shasum -a 256 | awk '{print $1}'
	else
		printf '%s' "$combined"
	fi
}

print_summary() {
	printf '%s\n' "---"
	printf '%s\n' "Suites run:    $SUITES_RUN"
	printf '%s\n' "Suites cached: $SUITES_CACHED"
	printf '%s\n' "Tests passed:  $TOTAL_PASS"
	printf '%s\n' "Tests failed:  $TOTAL_FAIL"
	if [ "$TOTAL_FAIL" -ne 0 ] && [ -s "$FAIL_LOG" ]; then
		printf '%s\n' "Failed tests:"
		while IFS= read -r line; do
			printf '  - %s\n' "$line"
		done <"$FAIL_LOG"
	fi
}

run_suite() {
	suite_name=$1
	suite_file="$SUITES_DIR/${suite_name}.sh"

	if [ ! -f "$suite_file" ]; then
		printf '%s\n' "Error: suite '$suite_name' not found" >&2
		return 1
	fi

	cache_key=$(compute_suite_cache_key "$suite_file")
	cache_file="$cache_dir/${suite_name}_${cache_key}.cache"
	cache_status_file="$cache_file.status"
	cache_counts_file="$cache_file.counts"

	if [ "$USE_CACHE" -eq 1 ] && [ -f "$cache_file" ] && [ -f "$cache_status_file" ] && [ -f "$cache_counts_file" ]; then
		cached_status=$(cat "$cache_status_file")
		cached_pass=$(sed -n '1p' "$cache_counts_file")
		cached_fail=$(sed -n '2p' "$cache_counts_file")

		TOTAL_PASS=$((TOTAL_PASS + cached_pass))
		TOTAL_FAIL=$((TOTAL_FAIL + cached_fail))
		SUITES_CACHED=$((SUITES_CACHED + 1))

		if [ "$VERBOSE" -eq 1 ]; then
			printf '%s\n' "=== Suite: $suite_name (cached) ==="
			cat "$cache_file"
		else
			if [ "$cached_status" -ne 0 ]; then
				printf '%s\n' "=== Suite: $suite_name (cached, FAILED) ==="
				cat "$cache_file"
			else
				printf '%s\n' "=== Suite: $suite_name (cached, passed) ==="
			fi
		fi

		if [ "$cached_status" -ne 0 ]; then
			sed -n '3,$p' "$cache_counts_file" >>"$FAIL_LOG"
		fi

		return "$cached_status"
	fi

	SUITES_RUN=$((SUITES_RUN + 1))

	user_verbose=$VERBOSE

	# TODO: I think our exports should all be prefixed with FORK_TEST_
	# Also, why do we need to even export? I assume since we're running the other
	# suites as child processes?

	export TEST_ROOT="$test_root"
	export TEST_ROOT_REAL="$TEST_ROOT_REAL"
	export FORK_SH="$FORK_SH"
	export SCRIPT_DIR="$SCRIPT_DIR"
	export TESTS_DIR="$TESTS_DIR"
	export FAST="$FAST"
	export VERBOSE=1
	export PASS=0
	export FAIL=0
	export FAIL_LOG="$FAIL_LOG"

	setup_docker_stub() {
		test_bin="$TEST_ROOT/bin"
		mkdir -p "$test_bin"
		PATH="$test_bin:$PATH"
		export PATH

		cat >"$test_bin/docker" <<'EOF'
#!/bin/sh
cmd="$1"
shift || true
case "$cmd" in
ps)
	exit 0
	;;
run|start|rm|build|exec|info)
	exit 0
	;;
*)
	exit 0
	;;
esac
EOF
		chmod +x "$test_bin/docker"
	}

	setup_docker_stub

	suite_output="$test_root/${suite_name}_output.log"
	suite_fail_start=$(wc -l <"$FAIL_LOG" | tr -d ' ')

	if [ "$user_verbose" -eq 1 ]; then
		printf '%s\n' "=== Suite: $suite_name ==="
	fi

	# WARN: If the suite fails with a syntax error (ex: non-POSIX code) the
	# suite will be essentially skipped and the suite_status will still be 0.
	set +e
	(
		set -e
		. "$suite_file"
	) >"$suite_output" 2>&1
	suite_status=$?
	set -e

	if [ "$user_verbose" -eq 1 ]; then
		cat "$suite_output"
	elif [ "$suite_status" -ne 0 ]; then
		printf '%s\n' "=== Suite: $suite_name (FAILED) ==="
		# TODO: When there are failures, and we're not in verbose mode,
		# we should only print the failing tests, not the whole suite output.
		cat "$suite_output"
	else
		printf '%s\n' "=== Suite: $suite_name (passed) ==="
	fi

	suite_fail_end=$(wc -l <"$FAIL_LOG" | tr -d ' ')
	suite_failures=$((suite_fail_end - suite_fail_start))

	set +e
	suite_pass=$(grep -c '^ok -' "$suite_output" 2>/dev/null)
	suite_pass_status=$?
	suite_fail=$(grep -c '^not ok -' "$suite_output" 2>/dev/null)
	suite_fail_status=$?
	set -e

	[ "$suite_pass_status" -ne 0 ] && suite_pass=0
	[ "$suite_fail_status" -ne 0 ] && suite_fail=0

	suite_pass=$(printf '%s' "$suite_pass" | tr -d ' ')
	suite_fail=$(printf '%s' "$suite_fail" | tr -d ' ')

	TOTAL_PASS=$((TOTAL_PASS + suite_pass))
	TOTAL_FAIL=$((TOTAL_FAIL + suite_fail))

	if [ "$USE_CACHE" -eq 1 ]; then
		cp "$suite_output" "$cache_file"
		printf '%s\n' "$suite_status" >"$cache_status_file"
		printf '%s\n' "$suite_pass" >"$cache_counts_file"
		printf '%s\n' "$suite_fail" >>"$cache_counts_file"
		if [ "$suite_failures" -gt 0 ]; then
			tail -n "$suite_failures" "$FAIL_LOG" >>"$cache_counts_file"
		fi
	fi

	if [ "$suite_status" -ne 0 ] && [ "$FAST" -eq 1 ]; then
		printf '%s\n' ""
		printf '%s\n' "Fast mode enabled; aborting after first suite failure." >&2
		print_summary
		exit 1
	fi

	return "$suite_status"
}

overall_status=0

for suite in $REQUESTED_SUITES; do
	if ! run_suite "$suite"; then
		overall_status=1
	fi
	printf '%s\n' ""
done

print_summary

exit "$overall_status"
