#!/usr/bin/env bash
# ============================================================================
# create_and_fix.sh – Create the repo in a clean subdirectory and fix Pages.
# ============================================================================

set -o pipefail

OWNER="swipswaps"
REPO="diagnostic-dashboard-1786040134"
PAGES_URL="https://$OWNER.github.io/$REPO"

echo "=== CREATE AND FIX ==="
echo "Current directory: $(pwd)"

# ----------------------------------------------------------------------
# 1. Check if we are already in the repo.
# ----------------------------------------------------------------------
if [ -d ".git" ] && git remote get-url origin 2>/dev/null | grep -q "$REPO"; then
    echo "✅ Already in the correct repo."
else
    echo "⚠️  Not in the repo. Creating subdirectory and cloning..."
    # If the subdirectory already exists, clean it.
    if [ -d "$REPO" ]; then
        echo "Subdirectory $REPO already exists. Removing..."
        rm -rf "$REPO"
    fi
    git clone "https://github.com/$OWNER/$REPO.git" "$REPO" || {
        echo "❌ Clone failed. Check permissions and network."
        exit 1
    }
    cd "$REPO" || exit 1
    echo "✅ Cloned into $(pwd)"
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
# 6. List all workflow runs.
# ----------------------------------------------------------------------
echo
echo "=== ALL WORKFLOW RUNS ==="
gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 10 --all 2>&1 || echo "No runs found."

# ----------------------------------------------------------------------
# 7. Get latest run.
# ----------------------------------------------------------------------
RUN_ID=$(gh run list --repo "$OWNER/$REPO" --workflow "pages.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -n "$RUN_ID" ]; then
    echo
    echo "=== LATEST WORKFLOW RUN: $RUN_ID ==="
    gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log
else
    echo "❌ No workflow runs found."
fi

# ----------------------------------------------------------------------
# 8. Check Pages status.
# ----------------------------------------------------------------------
echo
echo "=== PAGES API STATUS ==="
PAGES_RESPONSE=$(gh api "repos/$OWNER/$REPO/pages" 2>&1)
echo "$PAGES_RESPONSE" | jq '.'

PAGES_STATUS=$(echo "$PAGES_RESPONSE" | jq -r '.status // "unknown"')
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PAGES_URL")
echo "Pages status: $PAGES_STATUS"
echo "HTTP: $HTTP_CODE"

# ----------------------------------------------------------------------
# 9. Save logs and push.
# ----------------------------------------------------------------------
LOG_FILE="diagnostics/final_fix_$(date -u +%Y%m%d%H%M%S).txt"
if [ -n "$RUN_ID" ]; then
    gh run view "$RUN_ID" --repo "$OWNER/$REPO" --log > "$LOG_FILE"
else
    echo "No workflow run found" > "$LOG_FILE"
fi
git add "$LOG_FILE"
git commit -m "Add final fix logs" || echo "No changes"
git push origin main

RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO/main/$LOG_FILE"
echo
echo "=== RAW LOG LINK ==="
echo "$RAW_LINK"

if [ "$PAGES_STATUS" = "built" ] && [ "$HTTP_CODE" = "200" ]; then
    echo "✅ Site is live!"
    xdg-open "$PAGES_URL" 2>/dev/null
else
    echo "❌ Site not live. Check the logs above."
fi

echo "=== CREATE AND FIX COMPLETE ==="
