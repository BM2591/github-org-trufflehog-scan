#!/bin/bash

# ========================================================
# Script: scan_github_org_public_repos.sh
# Purpose: Scan all public GitHub repos of an organization using TruffleHog
#          Saves individual JSON reports and combines them into one.
#
# Usage:
#   1. Make sure you have:
#      - bash
#      - curl
#      - jq (https://stedolan.github.io/jq/)
#      - trufflehog installed and in your PATH
#
#   2. Make the script executable:
#      chmod +x scan_github_org_public_repos.sh
#
#   3. Run the script with the GitHub org name as argument:
#      ./scan_github_org_public_repos.sh <github-org-name>
#
#      Example:
#      ./scan_github_org_public_repos.sh Tap-Payments
#
#   4. Results:
#      - Individual JSON reports per repo saved in:
#        trufflehog-results-<org>/
#      - Combined JSON report at:
#        trufflehog-results-<org>/combined-results.json
#
# Notes:
#   - No GitHub token required for public repos, but watch out for API rate limits.
#   - Modify parallelism by changing -P5 in the script.
#   - For private repos, add GitHub PAT support (not included here).
# ========================================================

set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <github-org-name>"
  exit 1
fi

ORG="$1"
PER_PAGE=100
RESULTS_DIR="trufflehog-results-$ORG"

mkdir -p "$RESULTS_DIR"

# Get total number of public repos
TOTAL_REPOS=$(curl -s "https://api.github.com/orgs/$ORG" | jq '.public_repos')
if [ -z "$TOTAL_REPOS" ] || [ "$TOTAL_REPOS" -eq 0 ]; then
  echo "No public repos found for org: $ORG"
  exit 0
fi

PAGES=$(( (TOTAL_REPOS + PER_PAGE - 1) / PER_PAGE ))
echo "Found $TOTAL_REPOS public repos in $ORG across $PAGES pages."

for ((page=1; page<=PAGES; page++)); do
  echo "Fetching page $page..."
  REPOS=$(curl -s "https://api.github.com/orgs/$ORG/repos?per_page=$PER_PAGE&page=$page" | jq -r '.[].clone_url')

  echo "$REPOS" | xargs -n1 -P5 -I{} bash -c '
    REPO_URL="{}"
    REPO_NAME=$(basename "$REPO_URL" .git)
    OUTPUT_DIR="'$RESULTS_DIR'"
    OUTPUT_FILE="$OUTPUT_DIR/$REPO_NAME.json"
    echo "Scanning $REPO_NAME ..."
    trufflehog github --repo="$REPO_URL" --only-verified --json > "$OUTPUT_FILE"
  '
done

echo "Combining results into single file..."
jq -s '.' "$RESULTS_DIR"/*.json > "$RESULTS_DIR/combined-results.json"

echo "Scan complete! Results are in the folder: $RESULTS_DIR"