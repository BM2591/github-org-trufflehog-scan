#!/usr/bin/env bash
set -euo pipefail

ORG="$1"
FINAL_RESULTS="trufflehog_all_results.txt"

> "$FINAL_RESULTS"

# Fetch all public repos from org
PAGE=1
while :; do
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/orgs/$ORG/repos?per_page=100&page=$PAGE")
    else
        RESPONSE=$(curl -s "https://api.github.com/orgs/$ORG/repos?per_page=100&page=$PAGE")
    fi

    # Stop if error
    if echo "$RESPONSE" | jq -e 'has("message")' >/dev/null 2>&1; then
        echo "❌ GitHub API error: $(echo "$RESPONSE" | jq -r '.message')"
        exit 1
    fi

    REPOS=$(echo "$RESPONSE" | jq -r '.[].html_url')
    [[ -z "$REPOS" ]] && break

    for REPO in $REPOS; do
        echo "🔍 Scanning $REPO ..."
        echo "===== Results for $REPO =====" >> "$FINAL_RESULTS"
        trufflehog github --repo="$REPO" --results=verified,unknown >> "$FINAL_RESULTS" 2>&1 || true
        echo -e "\n" >> "$FINAL_RESULTS"
    done

    ((PAGE++))
done

echo "✅ All scans finished. Combined results saved in $FINAL_RESULTS"
