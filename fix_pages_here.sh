#!/usr/bin/env bash
# ============================================================================
# fix_pages_here.sh – Run in the current directory (no /tmp, no ~).
# ============================================================================

set -o pipefail

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== FIX PAGES (CURRENT DIRECTORY) ==="
echo "Working directory: $(pwd)"

# ----------------------------------------------------------------------
# 1. Ensure we are in the correct repo (clone if missing).
# ----------------------------------------------------------------------
if [ -d ".git" ] && git remote get-url origin 2>/dev/null | grep -q "$REPO"; then
    echo "✅ Already in the correct repo."
else
    echo "⚠️  Not in the correct repo. Cloning into current directory..."
    git clone "https://github.com/$OWNER/$REPO.git" . || {
        echo "❌ Clone failed. Check permissions and network."
        exit 1
    }
fi

# ----------------------------------------------------------------------
# 2. Ensure Pages is enabled and set to workflow build type.
# ----------------------------------------------------------------------
echo "Checking Pages status..."
if ! gh api "repos/$OWNER/$REPO/pages" &>/dev/null; then
    echo "Pages not enabled. Creating..."
    gh api -X POST "repos/$OWNER/$REPO/pages" \
        --input - <<< '{"source":{"branch":"main","path":"/"},"build_type":"workflow"}' | jq '.'
fi

echo "Forcing workflow build type..."
gh api -X PUT "repos/$OWNER/$REPO/pages" \
    --input - <<< '{"source":{"branch":"main","path":"/"},"build_type":"workflow"}' | jq '.'

# ----------------------------------------------------------------------
# 3. Verify configuration.
# ----------------------------------------------------------------------
CONFIG=$(gh api "repos/$OWNER/$REPO/pages" | jq '{source: .source, build_type: .build_type}')
echo "Config: $CONFIG"
if echo "$CONFIG" | grep -q '"build_type": "workflow"'; then
    echo "✅ Build type is workflow."
else
    echo "❌ Build type NOT workflow. Please check manually."
    exit 1
fi

# ----------------------------------------------------------------------
# 4. Ensure workflow file is correct.
# ----------------------------------------------------------------------
mkdir -p .github/workflows
cat > .github/workflows/pages.yml <<'YAMLEOF'
name: Deploy Pages

on:
  push:
    branches: [ main ]

permissions:
  pages: write
  id-token: write

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Pages
        uses: actions/configure-pages@v4
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: './'
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
YAMLEOF

git add .github/workflows/pages.yml
git commit -m "Ensure workflow file is correct" || echo "No changes"
git push origin main

# ----------------------------------------------------------------------
# 5. Push a dummy commit to trigger workflow.
# ----------------------------------------------------------------------
echo "Pushing dummy commit..."
touch trigger_$(date +%s).txt
git add .
git commit -m "Trigger workflow"
git push origin main

# ----------------------------------------------------------------------
# 6. Monitor workflow run.
# ----------------------------------------------------------------------
echo "Monitoring workflow run (checking every 10s)..."
MAX_ATTEMPTS=30
ATTEMPT=0
RUN_ID=""
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 1 --json databaseId,status,conclusion -q '.[0].databaseId' 2>/dev/null)
    if [ -n "$RUN_ID" ]; then
        echo "[$(date -u +%H:%M:%S)] Found run: $RUN_ID"
        break
    fi
    echo "[$(date -u +%H:%M:%S)] No workflow run yet (attempt $ATTEMPT)..."
    sleep 10
done

if [ -z "$RUN_ID" ]; then
    echo "❌ No workflow run after $MAX_ATTEMPTS attempts."
    echo "Check Actions tab: https://github.com/$OWNER/$REPO/actions"
    echo "Check Pages settings: https://github.com/$OWNER/$REPO/settings/pages"
    exit 1
fi

# ----------------------------------------------------------------------
# 7. Fetch and display the full workflow logs.
# ----------------------------------------------------------------------
echo
echo "=== FULL WORKFLOW LOGS ==="
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log

# ----------------------------------------------------------------------
# 8. Save logs and push.
# ----------------------------------------------------------------------
LOG_FILE="diagnostics/final_workflow_$(date -u +%Y%m%d%H%M%S).txt"
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log > "$LOG_FILE"
git add "$LOG_FILE"
git commit -m "Add final workflow logs"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$LOG_FILE"
echo
echo "=== RAW LOG LINK ==="
echo "$RAW_LINK"

# ----------------------------------------------------------------------
# 9. Final status.
# ----------------------------------------------------------------------
STATUS=$(gh api "repos/$OWNER/$REPO/pages" | jq -r '.status')
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
echo
echo "=== FINAL STATUS ==="
echo "Pages status: $STATUS"
echo "HTTP: $HTTP_CODE"
if [ "$STATUS" = "built" ] && [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Site is live!"
    xdg-open "$PAGES_URL" 2>/dev/null
else
    echo "❌ Site not live. Check the logs above."
    echo "The raw log link above contains the full workflow output."
fi

echo "=== FIX COMPLETE ==="
