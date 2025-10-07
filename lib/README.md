# Library Modules

This directory contains the modular source files for `fork.sh`. The build script (`build.sh`) concatenates these files in lexicographic order to produce the final executable.

## Module Organization

Files are numbered to ensure correct load order:

- **00-header.sh** - Shebang, file header comments, and `set -eu`
- **10-env.sh** - Environment variable loading (`load_env_file` + call)
- **20-help.sh** - Help text and usage function
- **30-core.sh** - Core utility functions (repo root, paths, etc.)
- **40-worktree.sh** - Worktree-specific operations
- **50-commands.sh** - User-facing command implementations
- **60-shell.sh** - Shell integration generation
- **99-main.sh** - Main entry point, dispatcher, and `main "$@"` call

## Development Workflow

1. Edit source files in `lib/`
2. Run `sh build.sh` to generate `fork.sh`
3. Test with `sh test.sh`
4. Verify syntax with `sh -n lib/*.sh`

## Design Principles

- **Load Order:** Numbered prefixes ensure dependencies load before dependents
- **Single Responsibility:** Each module has a clear, focused purpose
- **No Cross-Module State:** Modules communicate through function calls only
- **POSIX Compliance:** All code must be POSIX sh compatible
- **LSP-Friendly:** JSDoc-style comments above functions for tooling support

## Adding New Functionality

1. Identify the appropriate module (or create a new one with proper numbering)
2. Add JSDoc-style documentation comments
3. Keep functions focused and well-named
4. Rebuild and test
5. Update this README if adding a new module
