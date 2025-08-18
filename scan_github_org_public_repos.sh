#!/bin/bash
# scanpubrepo.sh - Scan all repos (public or private) for a GitHub org/user using TruffleHog
# Requirements:
#   - curl, jq, trufflehog installed
#   - Optional: export GITHUB_TOKEN=xxxxxx

ORG="$1"
SCOPE="$2"  # "public" (default) or "all"
if [ -z "$ORG" ]; then
  echo "Usage: $0 <github-org-or-user> [public|all]"
  exit 1
fi

[ -z "$SCOPE" ] && SCOPE="public"

API_URL="https://api.github.com"
AUTH_HEADER=()
if [ -n "$GITHUB_TOKEN" ]; then
  AUTH_HEADER=(-H "Authorization: token $GITHUB_TOKEN")
  echo "🔑 Using GitHub token authentication (5000/hr limit)."
else
  echo "⚠ No GitHub token provided, using unauthenticated requests (60/hr limit)."
fi

check_rate_limit() {
  local headers remaining reset now wait
  headers=$(curl -sI "${API_URL}/rate_limit" "${AUTH_HEADER[@]}")
  remaining=$(echo "$headers" | grep -i "^x-ratelimit-remaining:" | awk '{print $2}' | tr -d '\r')
  reset=$(echo "$headers" | grep -i "^x-ratelimit-reset:" | awk '{print $2}' | tr -d '\r')

  if [ "$remaining" -eq 0 ] 2>/dev/null; then
    now=$(date +%s)
    wait=$((reset - now))
    if [ "$wait" -gt 0 ]; then
      echo "⏳ Rate limit hit. Waiting $wait seconds (~$((wait/60)) minutes)..."
      sleep "$wait"
    fi
  fi
}

echo "🔍 Fetching repo metadata for $ORG..."
check_rate_limit
meta=$(curl -s "${API_URL}/users/${ORG}" "${AUTH_HEADER[@]}")

if echo "$meta" | jq -e '.message?' >/dev/null 2>&1; then
  echo "❌ Error from GitHub API: $(echo "$meta" | jq -r '.message')"
  exit 1
fi

public_repos=$(echo "$meta" | jq -r '.public_repos // 0')
total_repos=$(echo "$meta" | jq -r '.total_private_repos? // .owned_private_repos? // 0')
total_repos=$((public_repos + total_repos))

if [ "$SCOPE" = "public" ]; then
  scan_count=$public_repos
else
  scan_count=$total_repos
fi

if ! [[ "$scan_count" =~ ^[0-9]+$ ]]; then
  echo "❌ Unexpected response from GitHub API:"
  echo "$meta"
  exit 1
fi

if [ "$scan_count" -eq 0 ]; then
  echo "❌ No repos found for $ORG (scope: $SCOPE)."
  exit 1
fi

pages=$(( (scan_count + 99) / 100 ))
echo "✅ Found $scan_count repos across $pages pages (scope: $SCOPE)."

REPO_LIST=$(mktemp)
for page in $(seq 1 $pages); do
  echo "📥 Fetching page $page..."
  check_rate_limit
  curl -s "${API_URL}/users/${ORG}/repos?per_page=100&page=$page&type=$SCOPE" "${AUTH_HEADER[@]}" \
    | jq -r '.[].full_name' >> "$REPO_LIST"
done

RESULTS="${ORG}_trufflehog_${SCOPE}.json"
echo "[]" > "$RESULTS"

total=$(wc -l < "$REPO_LIST")
count=0

while IFS= read -r repo; do
  count=$((count+1))
  echo "[$count/$total] 🔎 Scanning $repo ..."

  # Run TruffleHog GitHub scan
  if [ -n "$GITHUB_TOKEN" ]; then
    findings=$(trufflehog github --org="$repo" --json --github-token="$GITHUB_TOKEN" || echo "[]")
  else
    findings=$(trufflehog github --org="$repo" --json || echo "[]")
  fi

  jq -s '.[0] + .[1]' "$RESULTS" <(echo "$findings") > tmp.$$
  mv tmp.$$ "$RESULTS"
done < "$REPO_LIST"

rm "$REPO_LIST"
echo "🎉 Scan complete. Results saved in $RESULTS"
