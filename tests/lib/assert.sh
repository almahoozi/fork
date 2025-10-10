#!/bin/sh

ok() {
	if [ "$VERBOSE" -eq 1 ]; then
		printf '%s\n' "ok - $1"
	fi
	PASS=$((PASS + 1))
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
