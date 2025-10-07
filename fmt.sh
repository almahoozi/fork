#!/bin/sh
# fmt.sh - Format shell scripts with shfmt
#
# Usage:
#   sh fmt.sh         # Format files (write mode)
#   sh fmt.sh --check # Check formatting only (CI mode)

set -eu

CHECK_MODE=0

if [ "${1:-}" = "--check" ] || [ "${1:-}" = "-c" ]; then
	CHECK_MODE=1
fi

if ! command -v shfmt >/dev/null 2>&1; then
	printf '%s\n' "Error: shfmt is not installed" >&2
	printf '%s\n' "Install: brew install shfmt" >&2
	exit 127
fi

if [ "$CHECK_MODE" -eq 1 ]; then
	printf '%s\n' "Checking formatting..."
	if shfmt -d lib/*.sh ./*.sh; then
		printf '%s\n' "All files are properly formatted."
		exit 0
	else
		printf '%s\n' "Files need formatting. Run: sh fmt.sh" >&2
		exit 1
	fi
else
	printf '%s\n' "Formatting files..."
	shfmt -w lib/*.sh ./*.sh
	printf '%s\n' "Formatting complete."
fi
