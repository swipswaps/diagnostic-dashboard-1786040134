#!/usr/bin/env bash
# ============================================================================
# monitor_pages.sh – Waits for Pages build to finish, then opens the site.
# ============================================================================

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== MONITORING PAGES BUILD ==="
echo "Repo: $OWNER/$REPO"
echo "URL: $PAGES_URL"

# ----------------------------------------------------------------------
# Wait for the build to finish (status "built" or "errored").
# ----------------------------------------------------------------------
echo
echo "Waiting for build to complete (checking every 10s)..."
while true; do
    STATUS=$(gh api "repos/$OWNER/$REPO/pages" 2>/dev/null | jq -r '.status')
    echo "$(date -u +%H:%M:%S) – Pages status: $STATUS"
    if [ "$STATUS" = "built" ]; then
        echo "✅ Build completed successfully."
        break
    elif [ "$STATUS" = "errored" ]; then
        echo "❌ Build failed. Check the Pages settings or workflow logs."
        exit 1
    elif [ -z "$STATUS" ] || [ "$STATUS" = "null" ]; then
        echo "⚠️  Pages not enabled or status unknown. Exiting."
        exit 1
    fi
    sleep 10
done

# ----------------------------------------------------------------------
# Wait for the site to become reachable (HTTP 200).
# ----------------------------------------------------------------------
echo
echo "Waiting for site to become reachable (polling every 5s)..."
ATTEMPT=1
while [ $ATTEMPT -le 60 ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL" 2>/dev/null)
    echo "$(date -u +%H:%M:%S) – HTTP $HTTP_CODE (attempt $ATTEMPT)"
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ Site is live!"
        break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    sleep 5
done

if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ Site not reachable after 60 attempts (5 min)."
    exit 1
fi

# ----------------------------------------------------------------------
# Open the site and push a final confirmation log.
# ----------------------------------------------------------------------
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$PAGES_URL"
    echo "Opened $PAGES_URL in your browser."
else
    echo "Open $PAGES_URL manually."
fi

# Push a confirmation log.
CONFIRM_FILE="diagnostics/site_live_$(date -u +%Y%m%d%H%M%S).txt"
echo "Site live at $PAGES_URL" > "$CONFIRM_FILE"
git add "$CONFIRM_FILE"
git commit -m "Confirm Pages live: $PAGES_URL"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$CONFIRM_FILE"
echo
echo "=== CONFIRMATION LOG ==="
echo "$RAW_LINK"

echo "=== MONITORING COMPLETE ==="
