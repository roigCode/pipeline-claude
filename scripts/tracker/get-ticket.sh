#!/usr/bin/env bash
# Tracker adapter: writes a request file from a ticket.
#
#   scripts/tracker/get-ticket.sh <issue-number> [--force]
#
# Implementation: GitHub Issues through the gh CLI. To use another tracker,
# replace this script and keep its interface (arguments and output file).
#
# If the issue is a replica (it starts with "<!-- upstream: owner/repo#N -->", see
# replicate-ticket.sh), the request uses the upstream number and URL and drops the
# replica header, so every repository produces exactly the same file.
#
# The output, requests/<NNNN>-<slug>.md, is a snapshot of the ticket at the moment
# the analysis starts. It is committed, so every agent reads exactly the same text
# and the input of each experiment stays recorded even if the ticket changes later.
#
# Repository: TRACKER_REPO (owner/name), or the repository of the current directory.
set -euo pipefail

usage() {
  echo "Usage: $0 <issue-number> [--force]" >&2
  exit 2
}

[[ $# -ge 1 && $# -le 2 ]] || usage
[[ $1 =~ ^[0-9]+$ ]] || usage
[[ $# -eq 1 || $2 == "--force" ]] || usage
number=$((10#$1))
force=${2:-}

command -v gh >/dev/null || { echo "Error: gh CLI not found." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: gh is not authenticated. Run: gh auth login" >&2; exit 1; }

repo=${TRACKER_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}

issue_field() {
  gh issue view "$number" --repo "$repo" --json "$1" --jq ".$1"
}

state=$(issue_field state)
[[ $state == "OPEN" ]] || { echo "Error: issue #$number in $repo is $state." >&2; exit 1; }

title=$(issue_field title)
url=$(issue_field url)
body=$(issue_field body | sed 's/\r$//')
[[ -n ${body//[[:space:]]/} ]] || { echo "Error: issue #$number has no description." >&2; exit 1; }

source_url=$url
source_number=$number
first_line=$(printf '%s\n' "$body" | head -n 1)
if [[ $first_line =~ ^\<\!--\ upstream:\ ([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)#([0-9]+)\ --\>$ ]]; then
  source_number=${BASH_REMATCH[2]}
  source_url="https://github.com/${BASH_REMATCH[1]}/issues/$source_number"
  # Drop the marker, the "Upstream:" line and the blank line after it.
  body=$(printf '%s\n' "$body" | sed '1d' | sed '1{/^Upstream: /d}' | sed '1{/^$/d}')
fi

id=$(printf '%04d' "$source_number")
slug=$(printf '%s' "$title" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')
root=$(git rev-parse --show-toplevel)
dir="$root/requests"
file="$dir/$id-$slug.md"

shopt -s nullglob
for other in "$dir/$id-"*.md; do
  if [[ $other != "$file" ]]; then
    echo "Error: $other already exists for request $id with another name." >&2
    echo "Rename or remove it first (the issue title may have changed)." >&2
    exit 1
  fi
done

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
{
  printf '# %s - %s\n\nSource: %s\n\n' "$id" "$title" "$source_url"
  printf '%s\n' "$body"
} >"$tmp"

if [[ -f $file ]]; then
  if cmp -s "$tmp" "$file"; then
    echo "Up to date: ${file#"$root"/}"
    exit 0
  fi
  if [[ $force != "--force" ]]; then
    echo "Error: ${file#"$root"/} differs from the issue:" >&2
    diff -u "$file" "$tmp" >&2 || true
    echo "Run again with --force to overwrite it." >&2
    exit 1
  fi
fi

mkdir -p "$dir"
mv "$tmp" "$file"
trap - EXIT
echo "Written: ${file#"$root"/}"
