#!/usr/bin/env bash
# ============================================================================
# diagnose_pages.sh – Forensic diagnostics for GitHub Pages deployment.
# Complies with userPreferences rules #1, #7, #8, #9, #16, #28, #30, #38,
# #39, #41, #47, #49, #50, #51, #52, #53, #54, #55, #56.
# ============================================================================

# ----------------------------------------------------------------------
# Capture all output to a timestamped log file.
# ----------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIAG_DIR="$REPO_ROOT/diagnostics"
mkdir -p "$DIAG_DIR" || { echo "Cannot create $DIAG_DIR"; exit 1; }
DIAG_FILE="$DIAG_DIR/pages_forensic_$(date -u +%Y%m%d%H%M%S).txt"
exec > >(tee -a "$DIAG_FILE") 2>&1

echo "=== FORENSIC DIAGNOSTICS: $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
echo "Report: $DIAG_FILE"

# ----------------------------------------------------------------------
# Rule #8: Logging function.
# ----------------------------------------------------------------------
log_result() {
    local operation="$1" success="$2" detail="$3"
    local ts status
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    if [ "$success" = "true" ]; then status="SUCCESS"; else status="FAILURE"; fi
    echo "[$ts] [$status] $operation: $detail" >&2
}

# ----------------------------------------------------------------------
# Step 1: Determine repo owner and name dynamically.
# ----------------------------------------------------------------------
OWNER=$(gh api user -q .login 2>/dev/null || echo "unknown")
REPO_NAME=$(basename "$(git remote get-url origin 2>/dev/null | sed 's/.*\/\(.*\)\.git$/\1/')" 2>/dev/null || echo "unknown")
if [ "$OWNER" = "unknown" ] || [ "$REPO_NAME" = "unknown" ]; then
    log_result "repo_discovery" "false" "Could not determine owner/repo. Using fallback."
    # Attempt to guess from git config.
    OWNER=$(git config --get remote.origin.url | sed -n 's/.*[:/]\([^/]*\)\/[^/]*\.git$/\1/p')
    REPO_NAME=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
fi
log_result "repo_discovery" "true" "Owner: $OWNER, Repo: $REPO_NAME"

PAGES_URL="https://$OWNER.github.io/$REPO_NAME"

# ----------------------------------------------------------------------
# Step 2: Check Pages API status.
# ----------------------------------------------------------------------
echo
echo "=== 2. PAGES API STATUS ==="
gh api "repos/$OWNER/$REPO_NAME/pages" 2>&1 || echo "API call failed (maybe Pages not enabled?)"

# ----------------------------------------------------------------------
# Step 3: List recent Pages builds.
# ----------------------------------------------------------------------
echo
echo "=== 3. RECENT PAGES BUILDS ==="
gh api "repos/$OWNER/$REPO_NAME/pages/builds" 2>&1 || echo "No builds found or API error."

# ----------------------------------------------------------------------
# Step 4: Check GitHub Actions workflow runs.
# ----------------------------------------------------------------------
echo
echo "=== 4. WORKFLOW RUNS (pages.yml) ==="
gh run list --repo "$OWNER/$REPO_NAME" --workflow "pages.yml" --limit 5 2>&1 || echo "No workflow runs found."

# If there is a recent run, show its logs (first 50 lines).
LATEST_RUN=$(gh run list --repo "$OWNER/$REPO_NAME" --workflow "pages.yml" --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null)
if [ -n "$LATEST_RUN" ]; then
    echo
    echo "=== 4a. LATEST WORKFLOW LOG (first 50 lines) ==="
    gh run view "$LATEST_RUN" --repo "$OWNER/$REPO_NAME" --log 2>&1 | head -50
fi

# ----------------------------------------------------------------------
# Step 5: Verify docs/ folder contents.
# ----------------------------------------------------------------------
echo
echo "=== 5. DOCS FOLDER CONTENTS (from git) ==="
git ls-tree -r main --name-only 2>/dev/null | grep -E '^docs/' || echo "No docs/ folder in main branch."

# ----------------------------------------------------------------------
# Step 6: HTTP headers from the Pages URL.
# ----------------------------------------------------------------------
echo
echo "=== 6. HTTP RESPONSE HEADERS ==="
curl -I -s "$PAGES_URL" 2>&1 || echo "curl failed."

# ----------------------------------------------------------------------
# Step 7: Force a new build via API (optional, but helpful).
# ----------------------------------------------------------------------
echo
echo "=== 7. REQUESTING A NEW BUILD (if Pages is enabled) ==="
gh api -X POST "repos/$OWNER/$REPO_NAME/pages/builds" 2>&1 || echo "Build request failed (maybe Pages not enabled)."

# ----------------------------------------------------------------------
# Step 8: Check if Pages source is correctly set.
# ----------------------------------------------------------------------
echo
echo "=== 8. CURRENT PAGES SOURCE CONFIGURATION ==="
gh api "repos/$OWNER/$REPO_NAME/pages" 2>/dev/null | jq '.source' 2>/dev/null || echo "Could not parse source."

# ----------------------------------------------------------------------
# Step 9: Push the diagnostic report to GitHub and print the raw link.
# ----------------------------------------------------------------------
echo
echo "=== 9. PUSHING DIAGNOSTIC REPORT ==="
git add "$DIAG_FILE" 2>&1 || log_result "git_add_diag" "false" "Failed to add $DIAG_FILE"
git commit -m "Add forensic Pages diagnostic report $(basename "$DIAG_FILE")" 2>&1 || log_result "git_commit_diag" "false" "Commit failed (no changes?)"
git push origin main 2>&1 || log_result "git_push_diag" "false" "Push failed."
RAW_LINK="https://raw.githubusercontent.com/$OWNER/$REPO_NAME/main/$(basename "$DIAG_DIR")/$(basename "$DIAG_FILE")"
echo
echo "=== RAW LOG LINK ==="
echo "$RAW_LINK"

log_result "diagnosis_complete" "true" "Report pushed. Raw link: $RAW_LINK"
echo "=== DIAGNOSTICS COMPLETE ==="
