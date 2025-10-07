#!/bin/sh
# ci-check.sh - Run full CI pipeline locally
#
# Usage:
#   sh ci-check.sh

set -e

printf '%s\n' "=== CI Pipeline Check ==="
printf '\n'

printf '%s\n' "Step 1: Format all shell scripts..."
sh fmt.sh
printf '%s\n' "✓ Formatting passed"
printf '\n'

printf '%s\n' "Step 2: Syntax check modules..."
sh -n lib/*.sh
printf '%s\n' "✓ Module syntax check passed"
printf '\n'

printf '%s\n' "Step 3: Build fork.sh..."
sh build.sh
printf '\n'

printf '%s\n' "Step 4: Verify build is up to date..."
if ! git diff --exit-code fork.sh >/dev/null 2>&1; then
	printf '%s\n' "✗ Error: fork.sh is not up to date with lib/ sources" >&2
	printf '%s\n' "Please run 'sh build.sh' and commit the changes" >&2
	exit 1
fi
printf '%s\n' "✓ Build is up to date"
printf '\n'

printf '%s\n' "Step 5: Syntax check built script..."
sh -n fork.sh
printf '%s\n' "✓ Built script syntax check passed"
printf '\n'

printf '%s\n' "Step 6: Run tests..."
sh test.sh
printf '\n'

printf '%s\n' "=== All CI checks passed! ==="
