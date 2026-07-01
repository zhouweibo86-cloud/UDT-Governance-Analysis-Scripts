param(
    [string]$Workspace = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$panel = Join-Path $Workspace 'data\input\user_supplied\panel_with_proxy.csv'

& (Join-Path $PSScriptRoot 'build_trust_panel.ps1') `
    -Workspace $Workspace `
    -ExistingPanel $panel

& (Join-Path $PSScriptRoot 'build_analysis_dataset.ps1') `
    -Workspace $Workspace

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Node.js 20 or later is required. Install dependencies with: npm install'
}

Push-Location $Workspace
try {
    node (Join-Path $PSScriptRoot 'analysis_and_figures.mjs')
}
finally {
    Pop-Location
}
