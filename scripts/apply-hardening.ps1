# Apply hardening to mit-agent-releases
#
# Run after `gh repo create` and after authenticating with `gh auth login`.
# Requires gh >= 2.40 and admin rights on the repo.

[CmdletBinding()]
param(
    [string]$Owner = 'M-IT-Services',
    [string]$Repo  = 'mit-agent-releases'
)

$ErrorActionPreference = 'Continue'
$full = "$Owner/$Repo"
Write-Host "Hardening $full ..." -ForegroundColor Cyan

function Step([string]$Label, [scriptblock]$Block) {
    Write-Host "-> $Label" -ForegroundColor Yellow
    & $Block
    if ($LASTEXITCODE -ne 0) { Write-Host "   FAILED (exit $LASTEXITCODE)" -ForegroundColor Red }
    else { Write-Host "   ok" -ForegroundColor Green }
}

# 1. Repo settings: disable wiki/projects/discussions, restrict merge styles.
#    -F gives typed booleans; -f sends strings (which the API rejects for booleans).
Step 'Repo settings' {
    gh api -X PATCH "/repos/$full" `
        -F has_wiki=false `
        -F has_projects=false `
        -F has_discussions=false `
        -F allow_merge_commit=false `
        -F allow_squash_merge=true `
        -F allow_rebase_merge=false `
        -F delete_branch_on_merge=true `
        -F allow_auto_merge=false --silent
}

# 2. Secret scanning + push protection (public repos: free).
$secJson = '{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}'
Step 'Secret scanning + push protection' {
    $secJson | gh api -X PATCH "/repos/$full" -H "Accept: application/vnd.github+json" --input - --silent
}

# 3. Vulnerability alerts + Dependabot security updates.
Step 'Vulnerability alerts' {
    gh api -X PUT "/repos/$full/vulnerability-alerts" --silent
}
Step 'Automated security fixes (Dependabot)' {
    gh api -X PUT "/repos/$full/automated-security-fixes" --silent
}

# 4. Branch protection on main (require PR review + linear history, no force push).
$bp = @{
    required_status_checks           = $null
    enforce_admins                   = $true
    required_pull_request_reviews    = @{
        required_approving_review_count = 1
        dismiss_stale_reviews           = $true
        require_code_owner_reviews      = $false
    }
    restrictions                     = $null
    required_linear_history          = $true
    allow_force_pushes               = $false
    allow_deletions                  = $false
    block_creations                  = $false
    required_conversation_resolution = $true
} | ConvertTo-Json -Depth 5 -Compress

Step 'Branch protection on main' {
    $bp | gh api -X PUT "/repos/$full/branches/main/protection" `
        -H "Accept: application/vnd.github+json" --input - --silent
}

# 5. Tag protection ruleset for v* (replaces deprecated /tags/protection endpoint).
$tagRule = @{
    name        = 'Protect release tags'
    target      = 'tag'
    enforcement = 'active'
    conditions  = @{ ref_name = @{ include = @('refs/tags/v*'); exclude = @() } }
    rules       = @(
        @{ type = 'deletion' },
        @{ type = 'non_fast_forward' },
        @{ type = 'update' },
        @{ type = 'creation' }
    )
} | ConvertTo-Json -Depth 6 -Compress

Step 'Tag protection ruleset (v*)' {
    # Idempotent: skip if a ruleset with the same name already exists.
    $existing = gh api "/repos/$full/rulesets" --jq '.[] | select(.name=="Protect release tags") | .id' 2>$null
    if ($existing) {
        Write-Host "   ruleset already exists (id=$existing), skipping create"
        return
    }
    $tagRule | gh api -X POST "/repos/$full/rulesets" `
        -H "Accept: application/vnd.github+json" --input - --silent
}

# 6. Restrict GitHub Actions to selected actions only.
Step 'Actions permissions = selected' {
    gh api -X PUT "/repos/$full/actions/permissions" `
        -F enabled=true -f allowed_actions=selected --silent
}
Step 'Selected actions: github + verified' {
    gh api -X PUT "/repos/$full/actions/permissions/selected-actions" `
        -F github_owned_allowed=true -F verified_allowed=true --silent
}

# 7. Default workflow permissions: read-only token, no PR writes.
Step 'Workflow default permissions = read' {
    gh api -X PUT "/repos/$full/actions/permissions/workflow" `
        -f default_workflow_permissions=read `
        -F can_approve_pull_request_reviews=false --silent
}

Write-Host "`nHardening complete." -ForegroundColor Green
Write-Host "Verify in browser: https://github.com/$full/settings"
