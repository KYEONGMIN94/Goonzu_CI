[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [string]$CiRoot = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrEmpty($CiRoot)) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    $CiRoot = Split-Path -Parent $scriptRoot
}

if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'git.exe was not found in PATH.' }
$resolvedSource = (Get-Item -LiteralPath $SourceRoot).FullName
$resolvedCi = (Get-Item -LiteralPath $CiRoot).FullName
if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource '.git'))) { throw "SourceRoot is not a Git worktree: $resolvedSource" }
if (-not (Test-Path -LiteralPath (Join-Path $resolvedCi '.git'))) { throw "CiRoot is not a Git repository: $resolvedCi" }

$requiredSource = @('.codex\config.toml','AGENTS.md','CONTRIBUTING.md','.github\PULL_REQUEST_TEMPLATE.md')
$requiredCi = @('.codex\config.toml','AGENTS.md','Jenkinsfile','config\build-targets.csv','scripts\Invoke-Preflight.ps1','scripts\Prepare-IsolatedBuild.ps1','scripts\Invoke-GoonzuBuild.ps1')
$missing = @()
foreach ($path in $requiredSource) { if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource $path) -PathType Leaf)) { $missing += ('source:' + $path) } }
foreach ($path in $requiredCi) { if (-not (Test-Path -LiteralPath (Join-Path $resolvedCi $path) -PathType Leaf)) { $missing += ('ci:' + $path) } }
if ($missing.Count -gt 0) { throw ('Required development files are missing: ' + ($missing -join ', ')) }

$sourceConfig = [System.IO.File]::ReadAllText((Join-Path $resolvedSource '.codex\config.toml'))
if ($sourceConfig -notmatch '(?m)^model\s*=\s*"gpt-5\.6-terra"\s*$') { throw 'Source Codex model default is not gpt-5.6-terra.' }
if ($sourceConfig -notmatch '(?m)^model_reasoning_effort\s*=\s*"low"\s*$') { throw 'Source Codex reasoning default is not low.' }

$branch = [string](& git -c ("safe.directory=" + $resolvedSource) -C $resolvedSource branch --show-current)
$gitVersion = [string](& git --version)
Write-Output 'DeveloperEnvironment=PASS'
Write-Output "SourceRoot=$resolvedSource"
Write-Output "CiRoot=$resolvedCi"
Write-Output "GitVersion=$gitVersion"
Write-Output "Branch=$($branch.Trim())"
if ($branch.Trim() -eq 'master') { Write-Warning 'Create a feature/fix/chore branch before editing.' }
Write-Output 'CodexNewTaskDefault=gpt-5.6-terra/low'
Write-Output 'BuildToolchain=Dedicated VS.NET 2003 worker only'
