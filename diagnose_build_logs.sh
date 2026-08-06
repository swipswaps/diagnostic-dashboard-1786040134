#!/usr/bin/env bash
# ============================================================================
# diagnose_build_logs.sh – Switch Pages to workflow mode and fetch full logs.
# ============================================================================

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== DIAGNOSING PAGES BUILD LOGS ==="
REPO_DIR="/tmp/$REPO"
cd "$REPO_DIR" || { echo "Repo not found at $REPO_DIR"; exit 1; }

# ----------------------------------------------------------------------
# 1. Update workflow with proper permissions.
# ----------------------------------------------------------------------
echo "Updating workflow with permissions..."
cat > .github/workflows/pages.yml <<'YAMLEOF'
name: Deploy Pages

on:
  push:
    branches: [ main ]

# Required for Pages deployment.
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
          path: './'   # Upload the entire root – index.html is there.
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
YAMLEOF

git add .github/workflows/pages.yml
git commit -m "Add permissions to Pages workflow"
git push origin main

# ----------------------------------------------------------------------
# 2. Switch Pages to workflow build type.
# ----------------------------------------------------------------------
echo "Switching Pages to workflow build type..."
gh api -X POST "repos/$OWNER/$REPO/pages" \
    --input - <<< '{"source":{"branch":"main","path":"/"},"build_type":"workflow"}' 2>&1 || echo "Switch failed (maybe already set)."

# ----------------------------------------------------------------------
# 3. Trigger a new build.
# ----------------------------------------------------------------------
echo "Triggering new build..."
gh api -X POST "repos/$OWNER/$REPO/pages/builds" 2>&1

# ----------------------------------------------------------------------
# 4. Wait for workflow run and fetch logs.
# ----------------------------------------------------------------------
echo "Waiting for workflow run to start..."
ATTEMPT=0
while [ $ATTEMPT -lt 30 ]; do
    ATTEMPT=$((ATTEMPT + 1))
    RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
    if [ -n "$RUN_ID" ]; then
        echo "Found workflow run: $RUN_ID"
        break
    fi
    echo "Waiting for workflow to trigger (attempt $ATTEMPT)..."
    sleep 10
done

if [ -z "$RUN_ID" ]; then
    echo "No workflow run found after 30 attempts. Checking Pages status..."
    gh api "repos/$OWNER/$REPO/pages" | jq '.'
    exit 1
fi

# ----------------------------------------------------------------------
# 5. Fetch and print the full workflow logs.
# ----------------------------------------------------------------------
echo
echo "=== FULL WORKFLOW LOGS ==="
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log

# ----------------------------------------------------------------------
# 6. Also save the logs to a file and push.
# ----------------------------------------------------------------------
LOG_FILE="diagnostics/workflow_log_$(date -u +%Y%m%d%H%M%S).txt"
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log > "$LOG_FILE"
git add "$LOG_FILE"
git commit -m "Add workflow logs for run $RUN_ID"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$LOG_FILE"
echo
echo "=== RAW LOG LINK ==="
echo "$RAW_LINK"

# ----------------------------------------------------------------------
# 7. Check if the deployment succeeded.
# ----------------------------------------------------------------------
echo
echo "Checking deployment status..."
STATUS=$(gh api "repos/$OWNER/$REPO/pages" | jq -r '.status')
echo "Pages status: $STATUS"
if [ "$STATUS" = "built" ]; then
    echo "✅ Build succeeded!"
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
    echo "HTTP status: $HTTP_CODE"
    if [ "$HTTP_CODE" = "200" ]; then
        echo "Site is live!"
        xdg-open "$PAGES_URL" 2>/dev/null
    fi
else
    echo "❌ Build status: $STATUS – check the workflow logs for details."
fi

echo "=== DIAGNOSIS COMPLETE ==="
