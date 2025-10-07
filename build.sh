#!/bin/sh
# build.sh - Build fork.sh from modular source files
#
# Usage:
#   sh build.sh [output]
#
# Arguments:
#   output - Output file path (default: fork.sh)

set -eu

output="${1:-fork.sh}"
lib_dir="lib"

if [ ! -d "$lib_dir" ]; then
	printf '%s\n' "Error: lib directory not found" >&2
	exit 1
fi

printf '%s\n' "Building $output from $lib_dir/*.sh"

: > "$output"

for module in "$lib_dir"/*.sh; do
	if [ ! -f "$module" ]; then
		continue
	fi

	printf '%s\n' "  + $(basename "$module")"
	cat "$module" >> "$output"
	printf '\n' >> "$output"
done

chmod +x "$output"

if [ -f fmt.sh ]; then
	./fmt.sh "$output"
else
	printf '%s\n' "Warning: fmt.sh not found, skipping formatting"
fi

printf '%s\n' "Built $output successfully"
