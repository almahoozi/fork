#!/bin/sh

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

run_fork() {
	(cd "$REPO_DIR" && sh "$FORK_SH" "$@")
}

run_fork_quiet() {
	tmp_prefix="$TEST_ROOT/run_fork_quiet.$$"
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
