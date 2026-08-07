#!/usr/bin/env bash
# ============================================================================
# fix_pages_build.sh – Diagnose and repair a failed GitHub Pages build.
# ============================================================================

set -o pipefail  # Not 'set -e' – we handle failures explicitly.

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
BUILD_ID="1136198969"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== FIXING PAGES BUILD ==="
echo "Repo: $OWNER/$REPO"
echo "Build ID: $BUILD_ID"
echo "URL: $PAGES_URL"

# ----------------------------------------------------------------------
# 1. Fetch the detailed error from the failed build.
# ----------------------------------------------------------------------
echo
echo "=== 1. FETCHING BUILD ERROR ==="
gh api "repos/$OWNER/$REPO/pages/builds/$BUILD_ID" 2>&1 | jq '.' || echo "API call failed."

# Extract error message if present.
ERROR_MSG=$(gh api "repos/$OWNER/$REPO/pages/builds/$BUILD_ID" 2>/dev/null | jq -r '.error.message' 2>/dev/null)
if [ -n "$ERROR_MSG" ] && [ "$ERROR_MSG" != "null" ]; then
    echo "Build error: $ERROR_MSG"
else
    echo "No specific error message in build API – checking workflow logs."
fi

# ----------------------------------------------------------------------
# 2. Check workflow runs and fetch logs.
# ----------------------------------------------------------------------
echo
echo "=== 2. WORKFLOW RUNS ==="
gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 5 2>&1

LATEST_RUN=$(gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -n "$LATEST_RUN" ]; then
    echo
    echo "=== 2a. LATEST WORKFLOW LOG (full) ==="
    gh run view "$LATEST_RUN" --repo "$OWNER/$REPO" --log 2>&1
fi

# ----------------------------------------------------------------------
# 3. Re‑enable Pages with legacy build type (static HTML, no Jekyll).
# ----------------------------------------------------------------------
echo
echo "=== 3. RE‑ENABLING PAGES WITH LEGACY BUILD ==="
gh api -X POST "repos/$OWNER/$REPO/pages" \
    --input - <<< '{"source":{"branch":"main","path":"/docs"},"build_type":"legacy"}' 2>&1 || echo "Re‑enable failed."

# ----------------------------------------------------------------------
# 4. Trigger a new build.
# ----------------------------------------------------------------------
echo
echo "=== 4. TRIGGERING NEW BUILD ==="
gh api -X POST "repos/$OWNER/$REPO/pages/builds" 2>&1 || echo "Trigger failed."

# ----------------------------------------------------------------------
# 5. Monitor the new build status.
# ----------------------------------------------------------------------
echo
echo "=== 5. MONITORING NEW BUILD ==="
ATTEMPT=0
MAX_ATTEMPTS=60  # 10 minutes total (10s intervals)
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    STATUS=$(gh api "repos/$OWNER/$REPO/pages" 2>/dev/null | jq -r '.status')
    echo "$(date -u +%H:%M:%S) – Attempt $ATTEMPT – Pages status: $STATUS"

    if [ "$STATUS" = "built" ]; then
        echo "✅ Build succeeded!"
        break
    elif [ "$STATUS" = "errored" ]; then
        echo "❌ Build failed again. Fetching error..."
        gh api "repos/$OWNER/$REPO/pages/builds" 2>/dev/null | jq '.[0].error' || echo "No error details."
        exit 1
    elif [ "$STATUS" = "null" ] || [ -z "$STATUS" ]; then
        echo "⚠️  Pages not enabled or status unknown."
        exit 1
    fi
    sleep 10
done

if [ "$STATUS" != "built" ]; then
    echo "❌ Build did not succeed within $MAX_ATTEMPTS attempts."
    exit 1
fi

# ----------------------------------------------------------------------
# 6. Wait for the site to become reachable.
# ----------------------------------------------------------------------
echo
echo "=== 6. WAITING FOR SITE TO BE REACHABLE ==="
ATTEMPT=0
while [ $ATTEMPT -lt 60 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL" 2>/dev/null)
    echo "$(date -u +%H:%M:%S) – HTTP $HTTP_CODE (attempt $ATTEMPT)"
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Site is live!"
        break
    fi
    sleep 5
done

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Site not reachable after 60 attempts."
    exit 1
fi

# ----------------------------------------------------------------------
# 7. Open the site and push a confirmation log.
# ----------------------------------------------------------------------
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$PAGES_URL"
    echo "Opened $PAGES_URL in your browser."
else
    echo "Open $PAGES_URL manually."
fi

CONFIRM_FILE="diagnostics/site_live_$(date -u +%Y%m%d%H%M%S).txt"
echo "Site live at $PAGES_URL" > "$CONFIRM_FILE"
git add "$CONFIRM_FILE"
git commit -m "Confirm Pages live: $PAGES_URL"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$CONFIRM_FILE"
echo
echo "=== CONFIRMATION LOG ==="
echo "$RAW_LINK"

echo "=== FIX COMPLETE ==="
