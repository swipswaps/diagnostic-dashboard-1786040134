#!/usr/bin/env bash
# ============================================================================
# fix_nojekyll.sh – Add .nojekyll to disable Jekyll processing.
# ============================================================================

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== ADDING .NOJEYKLL TO DISABLE JEKYLL ==="

# Ensure we're in the correct repo.
REPO_DIR="/tmp/$REPO"
if [ ! -d "$REPO_DIR" ]; then
    echo "ERROR: Repo directory $REPO_DIR not found."
    exit 1
fi
cd "$REPO_DIR" || exit 1

# Add .nojekyll file to docs/
touch docs/.nojekyll
git add docs/.nojekyll
git commit -m "Add .nojekyll to disable Jekyll processing"
git push origin main

# Trigger a new build
echo
echo "Triggering new build..."
gh api -X POST "repos/$OWNER/$REPO/pages/builds" 2>&1

# Monitor the build status
echo
echo "Monitoring build status (checking every 10s)..."
while true; do
    STATUS=$(gh api "repos/$OWNER/$REPO/pages" 2>/dev/null | jq -r '.status')
    echo "$(date -u +%H:%M:%S) – Status: $STATUS"
    if [ "$STATUS" = "built" ]; then
        echo "✅ Build succeeded!"
        break
    elif [ "$STATUS" = "errored" ]; then
        echo "❌ Build still errored. Check the logs manually."
        exit 1
    elif [ -z "$STATUS" ] || [ "$STATUS" = "null" ]; then
        echo "⚠️  Pages not enabled or status unknown."
        exit 1
    fi
    sleep 10
done

# Wait for the site to become reachable
echo
echo "Waiting for site to become reachable (polling every 5s)..."
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

# Open the site
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$PAGES_URL"
    echo "Opened $PAGES_URL in your browser."
else
    echo "Open $PAGES_URL manually."
fi

# Push a confirmation log
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
