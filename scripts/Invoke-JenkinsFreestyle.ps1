[CmdletBinding()]
param(
    [string]$SourceRepository = 'https://github.com/KYEONGMIN94/Goonzu_Build.git',
    [string]$SourceBranch = 'master',
    [string]$BaseRevision = 'origin/master',
    [ValidateSet('Auto','Client','GameServer','ClientGameServer','ServerSuite','All')]
    [string]$BuildTarget = 'All',
    [string]$DevenvPath = 'C:\Program Files (x86)\Microsoft Visual Studio .NET 2003\Common7\IDE\devenv.com'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Assert-DirectChild {
    param([string]$Path, [string]$Parent, [string]$ExpectedName)
    $fullPath = Get-FullPath $Path
    $fullParent = Get-FullPath $Parent
    if ([System.IO.Path]::GetDirectoryName($fullPath) -ne $fullParent -or [System.IO.Path]::GetFileName($fullPath) -ne $ExpectedName) {
        throw "Refusing generated-directory operation outside the Jenkins workspace: $fullPath"
    }
}

function Reset-GeneratedDirectory {
    param([string]$Workspace, [string]$Name)
    $path = Join-Path $Workspace $Name
    Assert-DirectChild -Path $path -Parent $Workspace -ExpectedName $Name
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Invoke-Native {
    param([string]$FilePath, [string[]]$Arguments, [string]$Description)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Description failed with exit code $LASTEXITCODE." }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ciRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrEmpty($env:WORKSPACE)) { throw 'WORKSPACE is not set by Jenkins.' }
$workspace = Get-FullPath $env:WORKSPACE
if ((Get-FullPath $ciRoot) -ne $workspace) { throw "The Goonzu_CI checkout must be the Jenkins workspace root: $workspace" }
if (-not (Test-Path -LiteralPath (Join-Path $workspace '.git') -PathType Container)) { throw 'Jenkins workspace is not a Git checkout.' }

$sourceRoot = Reset-GeneratedDirectory -Workspace $workspace -Name 'src'
$null = Reset-GeneratedDirectory -Workspace $workspace -Name 'build'
$artifactRoot = Reset-GeneratedDirectory -Workspace $workspace -Name 'artifacts'

Invoke-Native -FilePath 'git.exe' -Arguments @('clone','--no-checkout',$SourceRepository,$sourceRoot) -Description 'Source clone'
Invoke-Native -FilePath 'git.exe' -Arguments @('-C',$sourceRoot,'fetch','--prune','origin') -Description 'Source fetch'
Invoke-Native -FilePath 'git.exe' -Arguments @('-C',$sourceRoot,'checkout','--detach',('origin/' + $SourceBranch)) -Description 'Source checkout'
Invoke-Native -FilePath 'git.exe' -Arguments @('-C',$sourceRoot,'status','--porcelain') -Description 'Source status'

$targetsPath = Join-Path $ciRoot 'config\build-targets.csv'
$dependenciesPath = Join-Path $ciRoot 'config\build-dependencies.csv'
& (Join-Path $scriptRoot 'Test-BuildEnvironment.ps1') -SourceRoot $sourceRoot -DevenvPath $DevenvPath -BuildTargetsPath $targetsPath -DependenciesPath $dependenciesPath

$metaRoot = Join-Path $artifactRoot 'meta'
& (Join-Path $scriptRoot 'Invoke-Preflight.ps1') -SourceRoot $sourceRoot -BaseRevision $BaseRevision -OutputDirectory $metaRoot -RequireClean

$resolvedTarget = $BuildTarget
if ($BuildTarget -eq 'Auto') {
    $impact = @{}
    foreach ($line in @(Get-Content -LiteralPath (Join-Path $metaRoot 'impact.properties'))) {
        $pair = ([string]$line).Split(@('='), 2)
        if ($pair.Count -eq 2) { $impact[$pair[0]] = $pair[1] }
    }
    if (-not $impact.ContainsKey('BuildTarget')) { throw 'Preflight did not produce BuildTarget.' }
    $resolvedTarget = [string]$impact['BuildTarget']
}

if ($resolvedTarget -eq 'None') {
    Write-Output 'Build=SKIPPED'
    Write-Output 'Target=None'
    exit 0
}

& (Join-Path $scriptRoot 'Prepare-IsolatedBuild.ps1') -SourceRoot $sourceRoot -StagingRoot $workspace -Target $resolvedTarget -BuildTargetsPath $targetsPath -DependenciesPath $dependenciesPath
& (Join-Path $scriptRoot 'Invoke-GoonzuBuild.ps1') -SourceRoot $sourceRoot -Target $resolvedTarget -DevenvPath $DevenvPath -StagingRoot $workspace -BuildTargetsPath $targetsPath

Write-Output 'JenkinsFreestyle=PASS'
Write-Output "Target=$resolvedTarget"
