<#
.SYNOPSIS
  Publish a M-IT Agent MSI to GitHub Releases with SHA-256 sidecar.

.DESCRIPTION
  Validates the MSI, computes SHA-256, writes a sidecar checksum file,
  creates an annotated git tag (if missing) and publishes a GitHub release
  with both files attached. Idempotent: reuses an existing release/tag.

.PARAMETER Version
  Semantic version, e.g. 1.0.8 (without leading 'v').

.PARAMETER MsiPath
  Path to the locally-built MitAgent-<version>.msi.

.PARAMETER NotesFile
  Optional path to a markdown release-notes file. If absent, GitHub
  generates notes automatically from commit history.

.PARAMETER Draft
  Publish as draft (does not appear publicly until manually released).

.EXAMPLE
  .\publish-release.ps1 -Version 1.0.8 -MsiPath C:\build\MitAgent-1.0.8.msi
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+(\+[0-9A-Za-z\.\-]+)?$')]
  [string] $Version,

  [Parameter(Mandatory)] [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
  [string] $MsiPath,

  [string] $NotesFile,

  [switch] $Draft
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# --- Sanity checks -----------------------------------------------------
$expectedName = "MitAgent-$Version.msi"
$msiName = Split-Path -Leaf $MsiPath
if ($msiName -ne $expectedName) {
  throw "MSI filename '$msiName' does not match expected '$expectedName'."
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI 'gh' is not installed or not on PATH."
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git is not installed or not on PATH."
}

# Must run from inside the repository
$repoRoot = & git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
  throw "Not inside a git repository."
}

Push-Location $repoRoot
try {
  # --- Compute SHA-256 -------------------------------------------------
  Write-Host "Computing SHA-256 of $MsiPath..."
  $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $MsiPath).Hash.ToLower()
  Write-Host "SHA-256: $hash"

  $shaFile = Join-Path -Path (Split-Path -Parent $MsiPath) -ChildPath "$msiName.sha256"
  Set-Content -LiteralPath $shaFile -Value $hash -Encoding ascii -NoNewline
  Write-Host "Wrote $shaFile"

  # --- Tag -------------------------------------------------------------
  $tag = "v$Version"
  $existingTag = & git tag --list $tag
  if (-not $existingTag) {
    Write-Host "Creating annotated tag $tag..."
    & git tag -a $tag -m "Release $tag" | Out-Null
    & git push origin $tag | Out-Null
  } else {
    Write-Host "Tag $tag already exists — reusing."
  }

  # --- Release ---------------------------------------------------------
  $existingRelease = & gh release view $tag --json tagName 2>$null
  if (-not $existingRelease) {
    Write-Host "Creating GitHub release $tag..."
    $args = @('release', 'create', $tag, $MsiPath, $shaFile,
              '--title', "M-IT Agent $Version",
              '--verify-tag')
    if ($NotesFile) {
      $args += @('--notes-file', $NotesFile)
    } else {
      $args += '--generate-notes'
    }
    if ($Draft) { $args += '--draft' }
    & gh @args
  } else {
    Write-Host "Release $tag already exists — uploading/replacing assets..."
    & gh release upload $tag $MsiPath $shaFile --clobber
  }

  Write-Host ""
  Write-Host "Done. Update Odoo system parameters:"
  Write-Host "  mit_agent.target_agent_version = $Version"
  Write-Host "  mit_agent.update_msi_url       = https://github.com/M-IT-Services/mit-agent-releases/releases/download/$tag/$msiName"
  Write-Host "  mit_agent.update_sha256        = $hash"
}
finally {
  Pop-Location
}
