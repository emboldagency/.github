#!/bin/bash

# Release metadata for a WordPress plugin tag
# 1. Title: "<version> - <summary>", whatever the summary's source wrote
# 2. Notes: the version's readme.txt changelog block, else what the release
#    already says, else the annotated tag's body, else GitHub's generated notes
#
# Usage (from the plugin repo, at the tag):
#   TAG=1.2.3 NOTES_FILE=/tmp/notes.md bash release-meta.sh
#
# EXISTING_TITLE / EXISTING_BODY are read from the release when unset, so the
# workflow and a local dry run share one code path.

set -euo pipefail

TAG="${TAG:?TAG must be set}"
NOTES_FILE="${NOTES_FILE:?NOTES_FILE must be set}"
README_FILE="${README_FILE:-readme.txt}"
SUMMARY_MAX=80

if [ -z "${EXISTING_TITLE+x}" ] || [ -z "${EXISTING_BODY+x}" ]; then
	EXISTING_JSON=$(gh release view "$TAG" --json name,body 2>/dev/null || echo '{}')
	EXISTING_TITLE="${EXISTING_TITLE-$(jq -r '.name // ""' <<<"$EXISTING_JSON")}"
	EXISTING_BODY="${EXISTING_BODY-$(jq -r '.body // ""' <<<"$EXISTING_JSON")}"
fi

# Prints the "= 1.2.3 =" block of readme.txt's changelog, blank lines dropped.
changelog_block() {
	[ -f "$README_FILE" ] || return 0

	awk -v want="$1" '
		{ line = $0; sub(/[ \t\r]+$/, "", line) }
		found && (line ~ /^= *v?[0-9]/ || line ~ /^==/) { exit }
		found && line != "" { print line }
		line == "= " want " =" { found = 1 }
	' "$README_FILE"
}

# Drops a leading version ("v1.2.3", "1.2.3-beta.1") and the separator after it.
strip_version() {
	sed -E 's/^[[:space:]]*[vV]?[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?//; s/^[[:space:]]*([-–—:|][[:space:]]*)*//; s/[[:space:]]+$//' <<<"$1"
}

shorten() {
	if [ "${#1}" -le "$SUMMARY_MAX" ]; then
		echo "$1"
	else
		echo "${1:0:$SUMMARY_MAX}" | sed -E 's/[[:space:]]+[^[:space:]]*$//; s/[[:space:],;.]+$//' | sed 's/$/…/'
	fi
}

BASE_VERSION="${TAG%%-*}"
BLOCK=$(changelog_block "$TAG")
[ -n "$BLOCK" ] || BLOCK=$(changelog_block "$BASE_VERSION")

ANNOTATED=0
if [ "$(git cat-file -t "refs/tags/$TAG" 2>/dev/null)" = "tag" ]; then
	ANNOTATED=1
fi

# Title: the first source that says something beyond the version wins.
SUMMARY=""
if [ -n "$EXISTING_TITLE" ]; then
	SUMMARY=$(strip_version "$EXISTING_TITLE")
fi
if [ -z "$SUMMARY" ] && [ "$ANNOTATED" = "1" ]; then
	SUBJECT=$(git tag -l --format='%(contents:subject)' "$TAG")
	[[ "$SUBJECT" == Merge* ]] || SUMMARY=$(strip_version "$SUBJECT")
fi
if [ -z "$SUMMARY" ] && [ -n "$BLOCK" ]; then
	FIRST=$(head -n1 <<<"$BLOCK" | sed -E 's/^[[:space:]]*[*-][[:space:]]*//')
	SUMMARY=$(shorten "$(strip_version "$FIRST")")
fi

TITLE="$TAG"
[ -z "$SUMMARY" ] || TITLE="$TAG - $SUMMARY"

# Notes: the changelog is the source of truth when it has this version.
GENERATED=false
if [ -n "$BLOCK" ]; then
	echo "$BLOCK" >"$NOTES_FILE"
elif [ -n "$EXISTING_BODY" ]; then
	echo "$EXISTING_BODY" >"$NOTES_FILE"
elif [ "$ANNOTATED" = "1" ] && [ -n "$(git tag -l --format='%(contents:body)' "$TAG")" ]; then
	git tag -l --format='%(contents:body)' "$TAG" >"$NOTES_FILE"
else
	: >"$NOTES_FILE"
	GENERATED=true
fi

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "title<<__EOF__"
		echo "$TITLE"
		echo "__EOF__"
		echo "generated=$GENERATED"
	} >>"$GITHUB_OUTPUT"
fi

echo "title=$TITLE"
echo "generated=$GENERATED"
