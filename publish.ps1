<#
.SYNOPSIS
    Build the SQL engine image and publish it to Azure Container Registry.

.EXAMPLE
    .\publish.ps1 -Registry myregistry            # build, push immutable tag, move pointer tag
    .\publish.ps1 -Registry myregistry -NoPointer # push immutable tag only
    .\publish.ps1 -Registry myregistry -Revert fork-20261008-134009-0825478c82f9
#>
param(
    [Parameter(Mandatory = $true)][string]$Registry,
    [string]$Repository = "ctd/clintrakdefine/core-rules-engine",
    [string]$PointerTag = "latest-copy-from-fork",
    [string]$Dockerfile = "Dockerfile.source",
    [string]$Revert,
    [switch]$NoPointer,
    [string]$Username,
    [switch]$SkipLogin
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Invoke-Checked {
    param([scriptblock]$Command)
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code ${LASTEXITCODE}: $Command" }
}

$img = "$Registry.azurecr.io/$Repository"

# Uses your existing Azure login; no password is typed or stored.
if ($SkipLogin) {
    Write-Host "Using existing Docker credentials for $Registry.azurecr.io"
} elseif ($Username) {
    $secure = Read-Host "Password for $Username" -AsSecureString
    $plain = [System.Net.NetworkCredential]::new('', $secure).Password
    $plain | docker login "$Registry.azurecr.io" --username $Username --password-stdin
    if ($LASTEXITCODE -ne 0) { throw "docker login failed" }
} else {
    Invoke-Checked { az acr login --name $Registry }
}

if ($Revert) {
    Write-Host "Re-pointing '$PointerTag' at '$Revert'"
    Invoke-Checked {
        az acr import --name $Registry `
            --source "${Repository}:$Revert" `
            --image "${Repository}:$PointerTag" --force
    }
    Write-Host "Done. Verify the digest of '$PointerTag' in the portal."
    return
}

$dirty = git status --porcelain --untracked-files=no
if ($dirty) {
    Write-Warning "Uncommitted changes to tracked files are present; the image will not match the commit sha in its tag."
}

$sha = (git rev-parse --short=12 HEAD).Trim()
$tag = "fork-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$sha"

# Record what the pointer currently targets so it can be reverted.
$previous = az acr repository show-tags --name $Registry --repository $Repository `
    --detail --query "[?name=='$PointerTag'].digest | [0]" -o tsv 2>$null
if ($previous) { Write-Host "Current '$PointerTag' digest (revert target): $previous" }

Invoke-Checked { docker build -f $Dockerfile -t "${img}:$tag" . }
Invoke-Checked { docker push "${img}:$tag" }

if (-not $NoPointer) {
    Invoke-Checked { docker tag "${img}:$tag" "${img}:$PointerTag" }
    Invoke-Checked { docker push "${img}:$PointerTag" }
}

Write-Host ""
Write-Host "Published: ${img}:$tag"
if (-not $NoPointer) { Write-Host "Pointer '$PointerTag' now targets this build." }
