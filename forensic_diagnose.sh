#!/usr/bin/env bash
# ============================================================================
# forensic_diagnose.sh – Deep forensic diagnostics for GitHub Pages workflow.
# ============================================================================

set -o pipefail

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== FORENSIC DIAGNOSE ==="
echo "Working directory: $(pwd)"

# ----------------------------------------------------------------------
# 1. Verify we are in the correct repo.
# ----------------------------------------------------------------------
if ! git remote get-url origin 2>/dev/null | grep -q "$REPO"; then
    echo "❌ Not in the correct repo. Please run from the repo root."
    exit 1
fi
echo "✅ Repo verified."

# ----------------------------------------------------------------------
# 2. Check workflow file existence and content.
# ----------------------------------------------------------------------
echo
echo "=== WORKFLOW FILE ==="
if [ -f ".github/workflows/pages.yml" ]; then
    echo "✅ Workflow file exists. Content:"
    cat .github/workflows/pages.yml
else
    echo "❌ Workflow file missing. Creating..."
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
    git commit -m "Add workflow file"
    git push origin main
fi

# ----------------------------------------------------------------------
# 3. List all workflow runs (including failed ones).
# ----------------------------------------------------------------------
echo
echo "=== ALL WORKFLOW RUNS (pages.yml) ==="
gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 10 --all 2>&1 || echo "No runs found (or API error)."

# ----------------------------------------------------------------------
# 4. Get the latest workflow run ID (if any).
# ----------------------------------------------------------------------
RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 1 --json databaseId,status,conclusion -q '.[0].databaseId' 2>/dev/null)
if [ -n "$RUN_ID" ]; then
    echo
    echo "=== LATEST WORKFLOW RUN: $RUN_ID ==="
    gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log || echo "Could not fetch logs."
else
    echo "❌ No workflow runs found at all."
fi

# ----------------------------------------------------------------------
# 5. Check Pages API status and build errors.
# ----------------------------------------------------------------------
echo
echo "=== PAGES API STATUS ==="
PAGES_RESPONSE=$(gh api "repos/$OWNER/$REPO/pages" 2>&1)
echo "$PAGES_RESPONSE" | jq '.'

PAGES_STATUS=$(echo "$PAGES_RESPONSE" | jq -r '.status // "unknown"')
PAGES_ERROR=$(echo "$PAGES_RESPONSE" | jq -r '.error // "none"')
echo "Pages status: $PAGES_STATUS"
echo "Pages error: $PAGES_ERROR"

# ----------------------------------------------------------------------
# 6. Check if there are any Pages builds (legacy).
# ----------------------------------------------------------------------
echo
echo "=== PAGES BUILDS (legacy) ==="
gh api "repos/$OWNER/$REPO/pages/builds" 2>&1 | jq '.'

# ----------------------------------------------------------------------
# 7. If no workflow run, trigger a new build via API or workflow_dispatch.
# ----------------------------------------------------------------------
if [ -z "$RUN_ID" ]; then
    echo
    echo "⚠️  No workflow runs found. Attempting to trigger via API..."
    
    # Try to trigger a Pages build via API (if Pages is enabled).
    echo "Triggering Pages build via API..."
    gh api -X POST "repos/$OWNER/$REPO/pages/builds" 2>&1 | jq '.'
    
    # Also try to trigger the workflow via workflow_dispatch if it supports it.
    echo "Attempting workflow_dispatch (if the workflow supports it)..."
    gh workflow run pages.yml --repo "$OWNER/$REPO" --ref main 2>&1 || echo "workflow_dispatch failed (may not be supported)."
    
    # Push a dummy commit to force a trigger.
    echo "Pushing dummy commit to trigger..."
    touch dummy_$(date +%s).txt
    git add .
    git commit -m "Trigger workflow"
    git push origin main
fi

# ----------------------------------------------------------------------
# 8. Monitor for the workflow run.
# ----------------------------------------------------------------------
echo
echo "=== MONITORING WORKFLOW (checking every 10s) ==="
MAX_ATTEMPTS=20
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 1 --json databaseId,status,conclusion -q '.[0].databaseId' 2>/dev/null)
    if [ -n "$RUN_ID" ]; then
        echo "[$(date -u +%H:%M:%S)] Found run: $RUN_ID"
        break
    fi
    echo "[$(date -u +%H:%M:%S)] No workflow run yet (attempt $ATTEMPT)"
    sleep 10
done

if [ -z "$RUN_ID" ]; then
    echo "❌ No workflow run after $MAX_ATTEMPTS attempts."
    echo "Final Pages status: $PAGES_STATUS"
    echo "Final Pages error: $PAGES_ERROR"
    echo "Check manually: https://github.com/$OWNER/$REPO/actions"
    echo "Check Pages settings: https://github.com/$OWNER/$REPO/settings/pages"
    exit 1
fi

# ----------------------------------------------------------------------
# 9. Fetch and display the full workflow logs.
# ----------------------------------------------------------------------
echo
echo "=== FULL WORKFLOW LOGS (run $RUN_ID) ==="
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log

# ----------------------------------------------------------------------
# 10. Save logs and push.
# ----------------------------------------------------------------------
LOG_FILE="diagnostics/forensic_workflow_$(date -u +%Y%m%d%H%M%S).txt"
gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log > "$LOG_FILE"
git add "$LOG_FILE"
git commit -m "Add forensic workflow logs"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$LOG_FILE"
echo
echo "=== RAW LOG LINK ==="
echo "$RAW_LINK"

# ----------------------------------------------------------------------
# 11. Final status.
# ----------------------------------------------------------------------
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
echo
echo "=== FINAL STATUS ==="
echo "Pages status: $PAGES_STATUS"
echo "HTTP: $HTTP_CODE"
if [ "$PAGES_STATUS" = "built" ] && [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Site is live!"
    xdg-open "$PAGES_URL" 2>/dev/null
else
    echo "❌ Site not live. Check the logs above."
fi

echo "=== FORENSIC DIAGNOSE COMPLETE ==="
