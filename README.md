# fork

A shell wrapper around `git worktree` for managing branch-based worktrees in a
standardized layout.

## Features

- **Consistent worktree layout**: worktrees in `../<repo>_worktrees/<branch>`
- **Simple navigation**: `fork go <branch>` to switch or create, `fork main` to return
- **Shell integration**: automatic directory changes

## Installation

```bash
chmod +x fork.sh
sudo ln -sf "$(pwd)/fork.sh" /usr/local/bin/fork
```

## Shell Integration

To support automatic directory changes, add the integration snippet to your shell config.

### Bash/Zsh

Add to `~/.bashrc` or `~/.zshrc`:

```bash
eval "$(fork sh)"
```

Reload: `source ~/.zshrc` or `source ~/.bashrc`

### Fish

Add to `~/.config/fish/config.fish`:

```fish
fork sh | source
```

Reload: `source ~/.config/fish/config.fish`

### Manual Installation

The `fork sh` command auto-detects your shell from `$SHELL`. If you prefer to specify explicitly:

- `fork sh bash` for Bash
- `fork sh zsh` for Zsh
- `fork sh fish` for Fish

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
fork clean              # remove merged worktrees
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
```

### Remove

```bash
fork rm              # remove current worktree
fork rm feature-x    # remove specific
fork rm -f feature-x # force remove (if unmerged)
fork rm -a           # remove all
fork clean           # remove all merged worktrees
```

## Directory Layout

```
/path/to/
├── myproject/              # base repository
└── myproject_worktrees/    # worktrees directory
    ├── feature-x/
    ├── feature-y/
    └── bugfix-123/
```

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
sh test.sh           # run full suite
sh test.sh --fast    # fail fast after the first error

# Docker
docker build -f .docker/Dockerfile -t fork-tests .
docker run --rm fork-tests            # full suite
docker run --rm fork-tests --fast     # fail fast mode
docker run --rm fork-tests --verbose  # full verbose output
```

By default only the final summary is shown; pass `--verbose` to stream every assertion. The script creates temporary repositories under `${TMPDIR:-/tmp}` and removes them on exit. Results are cached based on the contents of `fork.sh` and `test.sh`; set `FORK_CACHE_PATH` to override the cache directory or delete the cache file to force a rerun.

## Environment

`fork` inspects the `FORK_CD` environment variable to decide whether to print navigation messages:

- When `FORK_CD=1`, commands such as `fork go`, `fork co`, `fork main`, and `fork rm` emit only the target path on stdout so wrapper functions can `cd` into place without extra output.
- When `FORK_CD` is unset or `0`, the same commands print human-friendly status messages on stderr in addition to the path.

## Help

```bash
fork help
fork help --verbose
```

## License

MIT
