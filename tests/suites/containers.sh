#!/bin/sh
# suite: containers
# description: Container integration (flags, env vars, dockerfile detection)

set -eu

. "$TESTS_DIR/lib/utils.sh"
. "$TESTS_DIR/lib/assert.sh"
. "$TESTS_DIR/lib/fixtures.sh"

setup_repo "fork-container-flags"
run_fork_quiet new feature-container
container_co_stdout="$TEST_ROOT/container_co.out"
container_co_stderr="$TEST_ROOT/container_co.err"
set +e
run_fork_capture_cd "$container_co_stdout" "$container_co_stderr" co feature-container -c
container_co_status=$?
set -e
container_co_out=$(cat "$container_co_stdout")
container_co_err=$(cat "$container_co_stderr")
assert_status 0 "$container_co_status" "fork co -c flag accepted"
assert_contains "FORK_CONTAINER_EXEC=1" "$container_co_out" "fork co -c outputs container exec command"
assert_contains "run --rm -it" "$container_co_out" "fork co -c uses --rm flag by default"
container_go_stdout="$TEST_ROOT/container_go.out"
container_go_stderr="$TEST_ROOT/container_go.err"
set +e
run_fork_capture_cd "$container_go_stdout" "$container_go_stderr" go feature-container-go -c
container_go_status=$?
set -e
container_go_out=$(cat "$container_go_stdout")
container_go_err=$(cat "$container_go_stderr")
assert_status 0 "$container_go_status" "fork go -c flag accepted"
assert_contains "FORK_CONTAINER_EXEC=1" "$container_go_out" "fork go -c outputs container exec command"
assert_contains "run --rm -it" "$container_go_out" "fork go -c uses --rm flag by default"

setup_repo "fork-container-env"
container_env_file="$REPO_DIR/.fork-container.env"
cat >"$container_env_file" <<'EOF'
FORK_CONTAINER=1
FORK_CONTAINER_IMAGE=alpine:latest
FORK_CONTAINER_NAME=test
FORK_CONTAINER_RUNTIME=docker
EOF
run_fork_quiet new feature-env-container
container_env_stdout="$TEST_ROOT/container_env.out"
container_env_stderr="$TEST_ROOT/container_env.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$container_env_file" FORK_CD=1 sh "$FORK_SH" co feature-env-container >"$container_env_stdout" 2>"$container_env_stderr")
container_env_status=$?
set -e
container_env_out=$(cat "$container_env_stdout")
container_env_err=$(cat "$container_env_stderr")
assert_status 0 "$container_env_status" "fork co respects FORK_CONTAINER env var"
assert_contains "FORK_CONTAINER_EXEC=1" "$container_env_out" "fork uses container mode when FORK_CONTAINER=1"
assert_contains "alpine:latest" "$container_env_out" "fork uses FORK_CONTAINER_IMAGE"
assert_contains "docker" "$container_env_out" "fork uses FORK_CONTAINER_RUNTIME"

setup_repo "fork-container-keep-alive"
container_keep_file="$REPO_DIR/.fork-keep.env"
cat >"$container_keep_file" <<'EOF'
FORK_CONTAINER=1
FORK_CONTAINER_KEEP_ALIVE=1
EOF
run_fork_quiet new feature-keep-alive
container_keep_stdout="$TEST_ROOT/container_keep.out"
container_keep_stderr="$TEST_ROOT/container_keep.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$container_keep_file" FORK_CD=1 sh "$FORK_SH" co feature-keep-alive >"$container_keep_stdout" 2>"$container_keep_stderr")
container_keep_status=$?
set -e
container_keep_out=$(cat "$container_keep_stdout")
container_keep_err=$(cat "$container_keep_stderr")
assert_status 0 "$container_keep_status" "fork co respects FORK_CONTAINER_KEEP_ALIVE"
assert_contains "FORK_CONTAINER_EXEC=1" "$container_keep_out" "fork uses container mode"
assert_contains "exec -it" "$container_keep_out" "fork uses exec mode when FORK_CONTAINER_KEEP_ALIVE=1"
assert_not_contains "run --rm" "$container_keep_out" "fork does not use --rm when FORK_CONTAINER_KEEP_ALIVE=1"

setup_repo "fork-container-runtime"
podman_env_file="$REPO_DIR/.fork-podman.env"
cat >"$podman_env_file" <<'EOF'
FORK_CONTAINER=1
FORK_CONTAINER_RUNTIME=podman
EOF
run_fork_quiet new feature-podman
podman_stdout="$TEST_ROOT/podman.out"
podman_stderr="$TEST_ROOT/podman.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$podman_env_file" FORK_CD=1 sh "$FORK_SH" co feature-podman >"$podman_stdout" 2>"$podman_stderr")
podman_status=$?
set -e
podman_out=$(cat "$podman_stdout")
podman_err=$(cat "$podman_stderr")
assert_status 0 "$podman_status" "fork co respects FORK_CONTAINER_RUNTIME=podman"
assert_contains "podman run" "$podman_out" "fork uses podman when FORK_CONTAINER_RUNTIME=podman"

setup_repo "fork-container-mount"
run_fork_quiet new feature-mount
container_mount_stdout="$TEST_ROOT/container_mount.out"
container_mount_stderr="$TEST_ROOT/container_mount.err"
set +e
run_fork_capture_cd "$container_mount_stdout" "$container_mount_stderr" co feature-mount -c
container_mount_status=$?
set -e
container_mount_out=$(cat "$container_mount_stdout")
repo_name=$(basename "$REPO_DIR")
assert_status 0 "$container_mount_status" "fork co -c succeeds"
assert_contains ":/$repo_name:" "$container_mount_out" "fork mounts to /repo_name in container"
assert_contains "-w /$repo_name" "$container_mount_out" "fork sets working directory to /repo_name"

setup_repo "fork-container-auto-dockerfile"
cat >"$REPO_DIR/Dockerfile.fork" <<'EOF'
FROM alpine:3.19
EOF
run_fork_quiet new feature-auto-dockerfile
auto_dockerfile_stdout="$TEST_ROOT/auto_dockerfile.out"
auto_dockerfile_stderr="$TEST_ROOT/auto_dockerfile.err"
set +e
run_fork_capture_cd "$auto_dockerfile_stdout" "$auto_dockerfile_stderr" co feature-auto-dockerfile -c
auto_dockerfile_status=$?
set -e
auto_dockerfile_out=$(cat "$auto_dockerfile_stdout")
auto_dockerfile_err=$(cat "$auto_dockerfile_stderr")
assert_status 0 "$auto_dockerfile_status" "fork detects Dockerfile.fork automatically"
assert_contains "fork_feature-auto-dockerfile_image" "$auto_dockerfile_out" "auto dockerfile uses branch-scoped image tag"
assert_not_contains "ubuntu:latest" "$auto_dockerfile_out" "auto dockerfile overrides default image"
assert_not_contains "Dockerfile not found" "$auto_dockerfile_err" "auto dockerfile avoids missing dockerfile errors"

setup_repo "fork-container-auto-dockerfile-ext"
cat >"$REPO_DIR/Dockerfile.fork.dev" <<'EOF'
FROM alpine:3.18
EOF
run_fork_quiet new feature-auto-dockerfile-ext
auto_dockerfile_ext_stdout="$TEST_ROOT/auto_dockerfile_ext.out"
auto_dockerfile_ext_stderr="$TEST_ROOT/auto_dockerfile_ext.err"
set +e
run_fork_capture_cd "$auto_dockerfile_ext_stdout" "$auto_dockerfile_ext_stderr" co feature-auto-dockerfile-ext -c
auto_dockerfile_ext_status=$?
set -e
auto_dockerfile_ext_out=$(cat "$auto_dockerfile_ext_stdout")
auto_dockerfile_ext_err=$(cat "$auto_dockerfile_ext_stderr")
assert_status 0 "$auto_dockerfile_ext_status" "fork detects Dockerfile.fork.* automatically"
assert_contains "fork_feature-auto-dockerfile-ext_dev_image" "$auto_dockerfile_ext_out" "dockerfile pattern with extension uses variant-specific tag"
assert_not_contains "ubuntu:latest" "$auto_dockerfile_ext_out" "dockerfile pattern with extension overrides default image"
assert_not_contains "Dockerfile not found" "$auto_dockerfile_ext_err" "dockerfile pattern with extension avoids missing dockerfile errors"

setup_repo "fork-container-default-dockerfile"
cat >"$REPO_DIR/default.Dockerfile" <<'EOF'
FROM alpine:3.17
EOF
container_default_env_file="$REPO_DIR/.fork-default.env"
cat >"$container_default_env_file" <<EOF
FORK_CONTAINER=1
FORK_CONTAINER_KEEP_ALIVE=1
FORK_CONTAINER_DEFAULT_DOCKERFILE=$REPO_DIR/default.Dockerfile
EOF
run_fork_quiet new feature-default-dockerfile
default_stdout="$TEST_ROOT/default_dockerfile.out"
default_stderr="$TEST_ROOT/default_dockerfile.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$container_default_env_file" sh "$FORK_SH" co feature-default-dockerfile -c >"$default_stdout" 2>"$default_stderr")
default_status=$?
set -e
default_out=$(cat "$default_stdout")
default_err=$(cat "$default_stderr")
assert_status 0 "$default_status" "fork uses default Dockerfile when auto pattern missing"
assert_contains "FORK_CONTAINER_EXEC=1" "$default_out" "default dockerfile outputs container exec command"
assert_contains "exec -it" "$default_out" "default dockerfile keep-alive uses exec"
assert_contains "Built image: fork_feature-default-dockerfile_image" "$default_err" "default dockerfile builds expected image tag"
assert_contains "default.Dockerfile" "$default_err" "default dockerfile references configured path"

setup_repo "fork-container-override-dockerfile"
cat >"$REPO_DIR/default.Dockerfile" <<'EOF'
FROM alpine:3.16
EOF
cat >"$REPO_DIR/override.Dockerfile" <<'EOF'
FROM alpine:3.18
EOF
container_override_env_file="$REPO_DIR/.fork-override.env"
cat >"$container_override_env_file" <<EOF
FORK_CONTAINER=1
FORK_CONTAINER_KEEP_ALIVE=1
FORK_CONTAINER_DEFAULT_DOCKERFILE=$REPO_DIR/default.Dockerfile
FORK_CONTAINER_DOCKERFILE=$REPO_DIR/override.Dockerfile
EOF
run_fork_quiet new feature-override-dockerfile
override_stdout="$TEST_ROOT/override_dockerfile.out"
override_stderr="$TEST_ROOT/override_dockerfile.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$container_override_env_file" sh "$FORK_SH" co feature-override-dockerfile -c >"$override_stdout" 2>"$override_stderr")
override_status=$?
set -e
override_out=$(cat "$override_stdout")
override_err=$(cat "$override_stderr")
assert_status 0 "$override_status" "fork uses override Dockerfile when configured"
assert_contains "FORK_CONTAINER_EXEC=1" "$override_out" "override dockerfile outputs container exec command"
assert_contains "exec -it" "$override_out" "override dockerfile keep-alive uses exec"
assert_contains "Built image: fork_feature-override-dockerfile_image" "$override_err" "override dockerfile builds expected image tag"
assert_contains "override.Dockerfile" "$override_err" "override dockerfile references override path"
assert_not_contains "default.Dockerfile" "$override_err" "override dockerfile supersedes default path"

setup_repo "fork-container-precedence-auto"
cat >"$REPO_DIR/Dockerfile.fork" <<'EOF'
FROM alpine:3.15
EOF
cat >"$REPO_DIR/default.Dockerfile" <<'EOF'
FROM alpine:3.14
EOF
cat >"$REPO_DIR/override.Dockerfile" <<'EOF'
FROM alpine:3.13
EOF
container_precedence_env_file="$REPO_DIR/.fork-precedence.env"
cat >"$container_precedence_env_file" <<EOF
FORK_CONTAINER=1
FORK_CONTAINER_KEEP_ALIVE=1
FORK_CONTAINER_DEFAULT_DOCKERFILE=$REPO_DIR/default.Dockerfile
FORK_CONTAINER_DOCKERFILE=$REPO_DIR/other.Dockerfile
EOF
run_fork_quiet new feature-precedence
auto_precedence_stdout="$TEST_ROOT/auto_precedence.out"
auto_precedence_stderr="$TEST_ROOT/auto_precedence.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$container_precedence_env_file" sh "$FORK_SH" co feature-precedence -c >"$auto_precedence_stdout" 2>"$auto_precedence_stderr")
auto_precedence_status=$?
set -e
auto_precedence_out=$(cat "$auto_precedence_stdout")
auto_precedence_err=$(cat "$auto_precedence_stderr")
assert_status 0 "$auto_precedence_status" "auto dockerfile takes precedence over env overrides"
assert_contains "FORK_CONTAINER_EXEC=1" "$auto_precedence_out" "auto precedence outputs container exec command"
assert_contains "exec -it" "$auto_precedence_out" "auto precedence keep-alive uses exec"
assert_contains "Built image: fork_feature-precedence_image" "$auto_precedence_err" "auto precedence builds expected tag"
assert_contains "Dockerfile.fork" "$auto_precedence_err" "auto precedence references dockerfile.fork"
assert_not_contains "other.Dockerfile" "$auto_precedence_err" "auto precedence ignores override when override file not present"
assert_not_contains "default.Dockerfile" "$auto_precedence_err" "auto precedence ignores default when auto file present"

setup_repo "fork-container-flag-k"
run_fork_quiet new feature-flag-k
k_flag_stdout="$TEST_ROOT/k_flag.out"
k_flag_stderr="$TEST_ROOT/k_flag.err"
set +e
run_fork_capture_cd "$k_flag_stdout" "$k_flag_stderr" co feature-flag-k -c -k
k_flag_status=$?
set -e
k_flag_out=$(cat "$k_flag_stdout")
assert_status 0 "$k_flag_status" "fork co -c -k succeeds"
assert_contains "FORK_CONTAINER_EXEC=1" "$k_flag_out" "fork co -c -k uses container mode"
assert_contains "exec -it" "$k_flag_out" "fork co -c -k uses exec when -k flag set"
assert_not_contains "run --rm" "$k_flag_out" "fork co -c -k does not use --rm when -k flag set"

setup_repo "fork-container-flag-k-go"
k_go_flag_stdout="$TEST_ROOT/k_go_flag.out"
k_go_flag_stderr="$TEST_ROOT/k_go_flag.err"
set +e
run_fork_capture_cd "$k_go_flag_stdout" "$k_go_flag_stderr" go feature-flag-k-go -c -k
k_go_flag_status=$?
set -e
k_go_flag_out=$(cat "$k_go_flag_stdout")
assert_status 0 "$k_go_flag_status" "fork go -c -k succeeds"
assert_contains "FORK_CONTAINER_EXEC=1" "$k_go_flag_out" "fork go -c -k uses container mode"
assert_contains "exec -it" "$k_go_flag_out" "fork go -c -k uses exec when -k flag set"
assert_not_contains "run --rm" "$k_go_flag_out" "fork go -c -k does not use --rm when -k flag set"

setup_repo "fork-container-flag-k-override"
k_override_env_file="$REPO_DIR/.fork-k-override.env"
cat >"$k_override_env_file" <<'EOF'
FORK_CONTAINER=1
FORK_CONTAINER_KEEP_ALIVE=0
EOF
run_fork_quiet new feature-k-override
k_override_stdout="$TEST_ROOT/k_override.out"
k_override_stderr="$TEST_ROOT/k_override.err"
set +e
(cd "$REPO_DIR" && env FORK_ENV="$k_override_env_file" FORK_CD=1 sh "$FORK_SH" co feature-k-override -k >"$k_override_stdout" 2>"$k_override_stderr")
k_override_status=$?
set -e
k_override_out=$(cat "$k_override_stdout")
assert_status 0 "$k_override_status" "fork co -k overrides FORK_CONTAINER_KEEP_ALIVE=0"
assert_contains "exec -it" "$k_override_out" "fork co -k uses exec mode despite env var"
assert_not_contains "run --rm" "$k_override_out" "fork co -k does not use --rm despite env var"
