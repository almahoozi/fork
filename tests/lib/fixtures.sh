#!/bin/sh

setup_repo() {
	repo_name=$1
	REPO_NAME="$repo_name"
	REPO_DIR="$TEST_ROOT/$repo_name"
	WORKTREE_BASE="$TEST_ROOT/${repo_name}_forks"

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
