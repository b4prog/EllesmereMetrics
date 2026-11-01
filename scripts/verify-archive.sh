#!/bin/sh
# Checks the release archive built by `make pack`: a single top-level folder
# named after the addon, holding the TOC, every file the TOC lists and LICENSE,
# nothing else, each identical to the working tree.
#
# Usage: scripts/verify-archive.sh <archive.zip> <AddonName>
# Run from the repository root.

set -eu
set -f # file names come from the archive; never glob them

usage="usage: scripts/verify-archive.sh <archive.zip> <AddonName>"
archive=${1:?$usage}
addon=${2:?$usage}
toc="$addon/$addon.toc"
newline='
'

fail() {
	printf 'verify: %s\n' "$1" >&2
	exit 1
}

# True when the newline-separated list $1 contains the line $2.
contains_line() {
	case "$newline$1$newline" in
		*"$newline$2$newline"*) return 0 ;;
		*) return 1 ;;
	esac
}

[ -f "$archive" ] || fail "$archive not found; run 'make pack' first"
unzip -tqq "$archive" >/dev/null 2>&1 || fail "$archive is not a valid zip archive"

entries=$(unzip -Z1 "$archive")
files=$(printf '%s\n' "$entries" | grep -v '/$' || true)

top_level=$(printf '%s\n' "$entries" | sed 's|/.*||' | sort -u)
[ "$top_level" = "$addon" ] ||
	fail "expected a single top-level folder $addon/, found: $(printf '%s' "$top_level" | tr '\n' ' ')"

for path in .git/ .github/ tests/ scripts/ build/ dist/ AGENTS.md CLAUDE.md README.md Makefile \
	.editorconfig .gitignore .luacheckrc .coderabbit.yaml; do
	case "$newline$entries" in
		*"$newline$addon/$path"*) fail "development-only path $path must not be in the archive" ;;
	esac
done

contains_line "$files" "$toc" || fail "$toc is missing"
contains_line "$files" "$addon/LICENSE" || fail "$addon/LICENSE is missing"

toc_text=$(unzip -p "$archive" "$toc" | tr -d '\r')
version=$(printf '%s\n' "$toc_text" | sed -n 's/^## Version:[[:space:]]*//p')
[ -n "$version" ] || fail "$toc has no '## Version:' line"
[ "$(basename "$archive")" = "$addon-$version.zip" ] ||
	fail "$(basename "$archive") does not match the TOC version $version"

listed=$(printf '%s\n' "$toc_text" | sed -e '/^#/d' -e '/^[[:space:]]*$/d' | tr '\\' '/')
[ -n "$listed" ] || fail "$toc lists no files"
expected="$toc$newline$addon/LICENSE$newline$(printf '%s\n' "$listed" | sed "s|^|$addon/|")"

IFS=$newline
for file in $listed; do
	contains_line "$files" "$addon/$file" || fail "$toc lists $file, which the archive lacks"
done
for entry in $files; do
	contains_line "$expected" "$entry" || fail "unexpected file in the archive: $entry"
	path=${entry#"$addon"/}
	[ -f "$path" ] || fail "$entry has no counterpart $path in the working tree"
	unzip -p "$archive" "$entry" | cmp -s - "$path" ||
		fail "$entry differs from $path; run 'make pack' again"
done

printf 'verify: %s OK\n' "$archive"
printf '%s\n' "$files" | sed 's/^/  /'
