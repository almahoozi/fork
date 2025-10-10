# fork

Simple shell wrapper for `git worktree` that adds helpers like `fork go` and
`fork main`, and integrates with your shell so branch hopping stays fast, clean,
and scriptable.

## Features

- **Consistent worktree layout**: worktrees in `../<repo>_forks/<branch>`
- **Simple navigation**: `fork go <branch>` to switch or create, `fork main` to return
- **Shell integration**: automatic directory changes and config loading
- **Container isolation**: optional containerized development per fork using Docker or Podman

## Installation

```bash
# Make fork.sh executable after downloading it
chmod +x fork.sh
# Make available on PATH by symlinking or copying
sudo ln -sf "$(pwd)/fork.sh" /usr/local/bin/fork
```

## Shell Integration

To support automatic directory changes, add the integration snippet to your shell config.

### Bash/Zsh

Add to `~/.bashrc` or `~/.zshrc`:

```bash
# Optional: set FORK_ENV before loading integration
export FORK_ENV=~/.config/fork/config.env

eval "$(fork sh)"
```

Reload: `source ~/.zshrc` or `source ~/.bashrc`

### Fish

Add to `~/.config/fish/config.fish`:

```fish
# Optional: set FORK_ENV before loading integration
set -gx FORK_ENV ~/.config/fork/config.env

fork sh | source
```

Reload: `source ~/.config/fish/config.fish`

### Manual Installation

The `fork sh` command auto-detects your shell from `$SHELL`. If you prefer to specify explicitly:

- `fork sh bash` for Bash
- `fork sh zsh` for Zsh
- `fork sh fish` for Fish

You can then copy the output of `fork sh` and paste it into your shell config file.

If `FORK_ENV` is set when running `fork sh`, the configuration variables are
embedded directly into the generated shell function, ensuring they're passed to
every `fork` invocation.

## Quick Start

```bash
fork go feature-x       # create from main and switch
git commit -am "work"

fork go feature-y       # jump to another worktree
fork main               # return to main worktree

fork new one two three  # create multiple worktrees
fork co one             # switch to `one` worktree

fork new dev -t develop # create from develop branch

fork ls                 # list worktrees
fork clean              # remove merged and clean worktrees
```

## Commands

### Create

```bash
fork new feature-x                   # create from main
fork new feature-a feature-b         # create multiple
fork new bugfix --target develop     # create from develop branch
```

### Navigate

```bash
fork go feature-x    # go to worktree (create if needed)
fork co feature-x    # go to worktree (must exist)
fork main            # go to main worktree
```

### List worktrees

```bash
fork ls              # list all worktrees
fork ls -u           # list unmerged only
fork ls -m           # list merged only
fork ls -d           # list dirty worktrees (uncommitted/untracked changes)
fork ls -c           # list clean worktrees
```

### Remove

```bash
fork rm              # remove current worktree
fork rm feature-x    # remove specific
fork rm -f feature-x # force remove (if unmerged or dirty)
fork rm -a           # remove all
fork clean           # remove all merged and clean worktrees
```

**Protection**: Worktrees are protected from deletion if they are:

- Unmerged (have commits not in the base branch), OR
- Dirty (have uncommitted changes, staged changes, or untracked files)

Use `-f/--force` to bypass these protections.

## Default Directory Layout

```
/path/to/
├── myproject/              # base repository
└── myproject_forks/        # forks directory
    ├── feature-x/
    ├── feature-y/
    └── bugfix-123/
```

You can customize this pattern using the `FORK_DIR_PATTERN` environment variable
(see Configuration).

## Container Mode

`fork` supports creating isolated containers for each fork, providing a clean environment separate from your host system. This is useful for:

- Testing code in a clean environment
- Isolating dependencies per branch
- Running potentially unsafe code
- Consistent development environments across machines

### Quick Start with Containers

```bash
# Work in a temporary container (auto-removed on exit)
fork go feature-x -c

# Keep container running for faster re-entry
fork go feature-x -c -k

# Use a custom image
export FORK_CONTAINER_IMAGE=ubuntu:22.04
fork go feature-x -c

# Use a Dockerfile override when no Dockerfile.fork* is present
export FORK_CONTAINER_DOCKERFILE=./dev.Dockerfile
fork go feature-x -c

# Provide a default fallback when no Dockerfile.fork* is present
export FORK_CONTAINER_DEFAULT_DOCKERFILE=./default.Dockerfile
fork go feature-x -c

# Or just drop Dockerfile.fork (or Dockerfile.fork.<variant>) in your repo
fork go feature-x -c
```

### Container Configuration

Set these in your `~/.config/fork/config.env` or shell environment:

If your repository contains `Dockerfile.fork` or `Dockerfile.fork.<variant>`, fork automatically uses it.

```bash
FORK_CONTAINER=1                                # Enable container mode by default
FORK_CONTAINER_IMAGE=ubuntu:latest              # Base image to use
FORK_CONTAINER_DEFAULT_DOCKERFILE=./default.Dockerfile
                                               # Fallback when no Dockerfile.fork* is present
FORK_CONTAINER_DOCKERFILE=/path/to/Dockerfile   # Explicit override when no Dockerfile.fork* is present
FORK_CONTAINER_RUNTIME=docker                   # Runtime: docker or podman
FORK_CONTAINER_NAME=myproject                   # Container name prefix
FORK_CONTAINER_KEEP_ALIVE=1                     # Keep containers running in background
```

**Note**: When `Dockerfile.fork*`, `FORK_CONTAINER_DOCKERFILE`, or `FORK_CONTAINER_DEFAULT_DOCKERFILE` is used, images are built with tags like `fork_{branch}_image`. If the Dockerfile filename is `Dockerfile.fork.<suffix>`, the suffix is included: `fork_{branch}_{suffix}_image`.

### Container Behavior

- **Ephemeral mode** (default): Container runs with `--rm` and is automatically removed when you exit
- **Keep-alive mode** (`-k` flag or `FORK_CONTAINER_KEEP_ALIVE=1`): Container runs in background and persists between sessions
- **Mount**: Only the worktree directory is mounted at `/{repo_name}` with read-write access
- **Working directory**: Automatically set to the mounted worktree
- **Removal**: Use `fork rm <branch> -c` to remove both worktree and container

### Requirements

- Docker or Podman installed and running
- Sufficient permissions to run containers
- Base image should have `git` and your preferred shell/tools installed

## How it Works

- Wraps `git worktree`
- Enforces consistent directory structure
- Never deletes branches, only worktrees

## Requirements

- Git 2.5 or newer with `git worktree`
- POSIX-compliant `sh` plus standard utilities (`awk`, `sed`, `grep`, `mkdir`, `rm`)
- Bash, Zsh, or Fish shell for directory-changing integration

## Testing

Run the shell-based harness from the repository root:

```bash
sh test.sh            # run full suite
sh test.sh --fast     # fail fast after the first error
sh test.sh --no-cache # run full suite without reusing cache

# Docker
docker build -f .docker/Dockerfile -t fork-tests .
docker run --rm fork-tests            # full suite
docker run --rm fork-tests --fast     # fail fast mode
docker run --rm fork-tests --no-cache # full suite without cache
docker run --rm fork-tests --verbose  # full verbose output
```

By default only the final summary is shown; pass `--verbose` to stream every assertion. The script creates temporary repositories under `${TMPDIR:-/tmp}` and removes them on exit. Results are cached based on the contents of `fork.sh` and `test.sh`; pass `--no-cache` to bypass the cache for a single run, set `FORK_TEST_CACHE_PATH` to override the cache directory, or delete the cache file to force a rerun.

## Configuration

### Environment File

`fork` supports loading configuration from an environment file via the `FORK_ENV` variable:

```bash
export FORK_ENV=~/.config/fork/config.env
```

The env file should contain `FORK_*` prefixed variables (one per line):

```bash
# ~/.config/fork/config.env
FORK_DIR_PATTERN=../{repo}_forks/{branch}
FORK_DEBUG=1
```

- Only variables prefixed with `FORK_` are loaded
- When using shell integration (`fork sh`), these variables are automatically
  embedded in the generated function so they're passed to every `fork` invocation

### Environment Variables

`fork` inspects the following environment variables:

**`FORK_CD`**: Controls navigation message output

- When `FORK_CD=1`, commands such as `fork go`, `fork co`, `fork main`, and `fork rm` emit only the target path on stdout so wrapper functions can `cd` into place without extra output.
- When `FORK_CD` is unset or `0`, the same commands print human-friendly status messages on stderr in addition to the path.

**`FORK_ENV`**: Path to configuration file

- If set, loads `FORK_*` variables from the specified file on startup

**`FORK_DIR_PATTERN`**: Custom worktree directory pattern

- Currently displays on startup if set (for demonstration purposes)
- Future versions may use this to customize worktree directory patterns

**Container-related variables:**

**`FORK_CONTAINER`**: Enable container mode by default

- Set to `1` to use containers without `-c` flag

**`FORK_CONTAINER_IMAGE`**: Container image to use

- Default: `ubuntu:latest`
- Can be any Docker/Podman image

**`FORK_CONTAINER_DEFAULT_DOCKERFILE`**: Fallback Dockerfile

- Used when no `Dockerfile.fork*` files are present and no override is set
- Built images are tagged as `fork_{branch}_image`

**`FORK_CONTAINER_DOCKERFILE`**: Override Dockerfile

- Highest priority fallback when no `Dockerfile.fork*` files are present
- Built images are tagged as `fork_{branch}_image` (or `fork_{branch}_{suffix}_image` for `Dockerfile.fork.*`)

**`FORK_CONTAINER_RUNTIME`**: Container runtime

- Default: `docker`
- Also supports: `podman`

**`FORK_CONTAINER_NAME`**: Container name prefix

- Default: none (containers named `{branch}_fork`)
- If set, containers named `{prefix}_{branch}_fork`

**`FORK_CONTAINER_KEEP_ALIVE`**: Keep containers running

- Default: `0` (containers auto-removed with `--rm`)
- Set to `1` to keep containers running in background between sessions

## Help

```bash
fork help
fork help --verbose
```

## License

MIT
