<#
.SYNOPSIS
  Nastaví GitHub secrets pro deploy na VPS (organizační nebo per-repo).

.DESCRIPTION
  Vyžaduje GitHub CLI (gh) a přihlášení: gh auth login
  Instalace gh: winget install GitHub.cli

  Organizační secrets (výchozí):
    .\setup-org-secrets.ps1 -SshHost 1.2.3.4 -SshUser deploy -KeyPath ~\.ssh\deploy_key

  POZOR: Na GitHub Free plánu fungují organizační secrets jen pro VEŘEJNÁ repa.
  Pro privátní repa na Free plánu použijte per-repo režim:
    .\setup-org-secrets.ps1 -Scope repos -Repos tankovani,life360 -SshHost 1.2.3.4 -SshUser deploy -KeyPath ~\.ssh\deploy_key

  Per-repo proměnnou DEPLOY_PATH nastavte zvlášť pro každé repo:
    gh variable set DEPLOY_PATH --repo davidfronek/tankovani --body "/opt/tankovani"
#>
param(
    [string]$Org = "davidfronek",
    [ValidateSet("org", "repos")]
    [string]$Scope = "org",
    [string[]]$Repos = @(),
    [Parameter(Mandatory)] [string]$SshHost,
    [string]$SshUser = "root",
    [Parameter(Mandatory)] [string]$KeyPath,
    [string]$SshPort = "22",
    # Viditelnost org secrets: all | private | selected
    [string]$Visibility = "all"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Write-Error "GitHub CLI (gh) není nainstalované. Spusťte: winget install GitHub.cli"
}

$KeyPath = (Resolve-Path $KeyPath).Path
if (-not (Test-Path $KeyPath)) {
    Write-Error "Soubor s privátním klíčem nenalezen: $KeyPath"
}
$privateKey = Get-Content $KeyPath -Raw

function Set-DeploySecrets {
    param([string[]]$TargetArgs)
    gh secret set SSH_HOST @TargetArgs --body $SshHost
    gh secret set SSH_USER @TargetArgs --body $SshUser
    gh secret set SSH_PORT @TargetArgs --body $SshPort
    $privateKey | gh secret set SSH_PRIVATE_KEY @TargetArgs
}

if ($Scope -eq "org") {
    Write-Host "Nastavuji organizační secrets pro org '$Org' (visibility: $Visibility)..."
    Set-DeploySecrets -TargetArgs @("--org", $Org, "--visibility", $Visibility)
}
else {
    if ($Repos.Count -eq 0) {
        Write-Error "V režimu -Scope repos zadejte -Repos (např. -Repos tankovani,life360)."
    }
    foreach ($repo in $Repos) {
        $full = "$Org/$repo"
        Write-Host "Nastavuji secrets pro repo $full..."
        Set-DeploySecrets -TargetArgs @("--repo", $full)
    }
}

Write-Host ""
Write-Host "Hotovo. Nastavené secrets: SSH_HOST, SSH_USER, SSH_PORT, SSH_PRIVATE_KEY."
