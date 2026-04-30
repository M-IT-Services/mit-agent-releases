# Apply hardening to mit-agent-releases
#
# Run after `gh repo create` and after authenticating with `gh auth login`.
# Requires gh >= 2.40 and admin rights on the repo.

[CmdletBinding()]
param(
    [string]$Owner = 'M-IT-Services',
    [string]$Repo  = 'mit-agent-releases'
)

$ErrorActionPreference = 'Stop'
$full = "$Owner/$Repo"
Write-Host "Hardening $full ..." -ForegroundColor Cyan

# 1. Repo settings: disable wiki/projects, enable vuln alerts + auto-fix.
gh api -X PATCH "/repos/$full" `
    -f has_wiki=false `
    -f has_projects=false `
    -f has_discussions=false `
    -f allow_merge_commit=false `
    -f allow_squash_merge=true `
    -f allow_rebase_merge=false `
    -f delete_branch_on_merge=true `
    -f allow_auto_merge=false | Out-Null

# 2. Secret scanning + push protection (public repos: free).
gh api -X PATCH "/repos/$full" `
    -F security_and_analysis='{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}' | Out-Null

# 3. Vulnerability alerts + Dependabot security updates.
gh api -X PUT "/repos/$full/vulnerability-alerts" | Out-Null
gh api -X PUT "/repos/$full/automated-security-fixes" | Out-Null

# 4. Branch protection on main (require PR review + linear history, no force push).
$bp = @{
    required_status_checks         = $null
    enforce_admins                 = $true
    required_pull_request_reviews  = @{
        required_approving_review_count = 1
        dismiss_stale_reviews           = $true
        require_code_owner_reviews      = $true
    }
    restrictions                   = $null
    required_linear_history        = $true
    allow_force_pushes             = $false
    allow_deletions                = $false
    block_creations                = $false
    required_conversation_resolution = $true
} | ConvertTo-Json -Depth 5

$bp | gh api -X PUT "/repos/$full/branches/main/protection" `
    -H "Accept: application/vnd.github+json" --input - | Out-Null

# 5. Tag protection rule for v* (admins only can create/delete).
gh api -X POST "/repos/$full/tags/protection" -f pattern='v*' | Out-Null

# 6. Restrict GitHub Actions to selected actions only.
gh api -X PUT "/repos/$full/actions/permissions" `
    -f enabled=true -f allowed_actions=selected | Out-Null

gh api -X PUT "/repos/$full/actions/permissions/selected-actions" `
    -F github_owned_allowed=true -F verified_allowed=true | Out-Null

# 7. Default workflow permissions: read-only token, no PR writes.
gh api -X PUT "/repos/$full/actions/permissions/workflow" `
    -f default_workflow_permissions=read `
    -F can_approve_pull_request_reviews=false | Out-Null

Write-Host "Hardening complete." -ForegroundColor Green
Write-Host "Verify in browser: https://github.com/$full/settings"
