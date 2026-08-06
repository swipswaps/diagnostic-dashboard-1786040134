#!/usr/bin/env bash
# ============================================================================
# fix_pages_root.sh – Copy files to root and set Pages source to '/'.
# ============================================================================

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== FIXING PAGES WITH ROOT SOURCE ==="
REPO_DIR="/tmp/$REPO"
cd "$REPO_DIR" || { echo "Repo not found at $REPO_DIR"; exit 1; }

# ----------------------------------------------------------------------
# 1. Ensure docs/ has index.html and .nojekyll.
# ----------------------------------------------------------------------
echo "Verifying docs/ contents..."
ls -la docs/

# ----------------------------------------------------------------------
# 2. Copy docs/ contents to the root (as a fallback).
# ----------------------------------------------------------------------
echo "Copying docs/ contents to root..."
cp docs/index.html ./
cp docs/static/style.css ./static/ 2>/dev/null || mkdir -p static && cp docs/static/style.css static/
touch .nojekyll
git add index.html static/style.css .nojekyll
git commit -m "Add root-level index.html and .nojekyll" || echo "No changes to commit."
git push origin main

# ----------------------------------------------------------------------
# 3. Re‑enable Pages with source: '/'.
# ----------------------------------------------------------------------
echo "Re‑enabling Pages with root source..."
gh api -X POST "repos/$OWNER/$REPO/pages" \
    --input - <<< '{"source":{"branch":"main","path":"/"}}' 2>&1 || echo "Re‑enable failed (maybe already set)."

# ----------------------------------------------------------------------
# 4. Trigger a new build.
# ----------------------------------------------------------------------
echo "Triggering new build..."
gh api -X POST "repos/$OWNER/$REPO/pages/builds" 2>&1

# ----------------------------------------------------------------------
# 5. Monitor build status.
# ----------------------------------------------------------------------
echo "Monitoring build status (checking every 10s)..."
ATTEMPT=0
while [ $ATTEMPT -lt 60 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    STATUS=$(gh api "repos/$OWNER/$REPO/pages" 2>/dev/null | jq -r '.status')
    echo "$(date -u +%H:%M:%S) – Attempt $ATTEMPT – Status: $STATUS"
    if [ "$STATUS" = "built" ]; then
        echo "✅ Build succeeded!"
        break
    elif [ "$STATUS" = "errored" ]; then
        echo "❌ Build failed. Fetching latest build error..."
        gh api "repos/$OWNER/$REPO/pages/builds" 2>/dev/null | jq '.[0].error'
        echo "Check the build logs manually at:"
        echo "https://github.com/$OWNER/$REPO/settings/pages"
        exit 1
    elif [ -z "$STATUS" ] || [ "$STATUS" = "null" ]; then
        echo "⚠️  Pages not enabled or status unknown."
        exit 1
    fi
    sleep 10
done

# ----------------------------------------------------------------------
# 6. Wait for site to be reachable.
# ----------------------------------------------------------------------
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
    echo "Check the Pages settings manually:"
    echo "https://github.com/$OWNER/$REPO/settings/pages"
    exit 1
fi

# ----------------------------------------------------------------------
# 7. Open and confirm.
# ----------------------------------------------------------------------
xdg-open "$PAGES_URL" 2>/dev/null && echo "Opened in browser."

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
