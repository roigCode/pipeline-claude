#!/usr/bin/env bash
# Replicates a ticket of the base repository into the agent repositories.
#
#   scripts/tracker/replicate-ticket.sh <issue-number> <owner/repo> [<owner/repo>...]
#
# Run it from pipeline-base. The base issue is the source of truth: the replicated
# issues are created the first time and overwritten on later runs, so changes are
# always made in the base issue and then replicated again. Never edit a replica.
#
# Each replica starts with a marker that links it to its upstream issue:
#   <!-- upstream: owner/repo#N -->
# get-ticket.sh uses that marker so every repository produces the same request file.
set -euo pipefail

usage() {
  echo "Usage: $0 <issue-number> <owner/repo> [<owner/repo>...]" >&2
  exit 2
}

[[ $# -ge 2 ]] || usage
[[ $1 =~ ^[0-9]+$ ]] || usage
number=$((10#$1))
shift

command -v gh >/dev/null || { echo "Error: gh CLI not found." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Error: gh is not authenticated. Run: gh auth login" >&2; exit 1; }

source_repo=${TRACKER_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}

issue_field() {
  gh issue view "$number" --repo "$source_repo" --json "$1" --jq ".$1"
}

state=$(issue_field state)
[[ $state == "OPEN" ]] || { echo "Error: issue #$number in $source_repo is $state." >&2; exit 1; }
title=$(issue_field title)
url=$(issue_field url)
body=$(issue_field body | sed 's/\r$//')
[[ -n ${body//[[:space:]]/} ]] || { echo "Error: issue #$number has no description." >&2; exit 1; }

marker="<!-- upstream: $source_repo#$number -->"
replica_body=$(printf '%s\nUpstream: %s\n\n%s\n' "$marker" "$url" "$body")

for target in "$@"; do
  [[ $target =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Error: invalid repository '$target'." >&2; exit 2; }
  [[ $target != "$source_repo" ]] || { echo "Error: target $target is the source repository." >&2; exit 2; }

  existing=$(gh issue list --repo "$target" --state all --limit 1000 --json number,body \
    --jq "[.[] | select(.body | startswith(\"$marker\"))] | .[].number")

  count=$(printf '%s\n' "$existing" | grep -c . || true)
  if [[ $count -gt 1 ]]; then
    echo "Error: $target has several replicas of $source_repo#$number: $(echo $existing)." >&2
    exit 1
  elif [[ $count -eq 1 ]]; then
    replica_state=$(gh issue view "$existing" --repo "$target" --json state --jq .state)
    gh issue edit "$existing" --repo "$target" --title "$title" --body "$replica_body" >/dev/null
    echo "Updated: $target#$existing"
    [[ $replica_state == "OPEN" ]] || echo "Warning: $target#$existing is $replica_state." >&2
  else
    created=$(gh issue create --repo "$target" --title "$title" --body "$replica_body")
    echo "Created: $created"
  fi
done
