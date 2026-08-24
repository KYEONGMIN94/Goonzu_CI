[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Client','GameServer','ClientGameServer','ServerSuite','All')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$DevenvPath,

    [Parameter(Mandatory = $true)]
    [string]$StagingRoot,

    [Parameter(Mandatory = $true)]
    [string]$BuildTargetsPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-DevenvPath {
    param([string]$RequestedPath)
    if (Test-Path -LiteralPath $RequestedPath -PathType Leaf) { return (Get-Item -LiteralPath $RequestedPath).FullName }
    if ([System.IO.Path]::GetExtension($RequestedPath) -ieq '.com') {
        $fallback = [System.IO.Path]::ChangeExtension($RequestedPath, '.exe')
        if (Test-Path -LiteralPath $fallback -PathType Leaf) { return (Get-Item -LiteralPath $fallback).FullName }
    }
    throw "Visual Studio .NET 2003 executable not found: $RequestedPath"
}

function Get-Sha256 {
    param([string]$LiteralPath)
    $stream = [System.IO.File]::OpenRead($LiteralPath)
    try {
        $sha = New-Object System.Security.Cryptography.SHA256Managed
        try { return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $sha.Clear() }
    }
    finally { $stream.Close() }
}

function Select-TargetRows {
    param([object[]]$Rows, [string]$RequestedTarget)
    if ($RequestedTarget -eq 'All') { return @($Rows) }
    if ($RequestedTarget -eq 'ClientGameServer') {
        return @($Rows | Where-Object { $_.Target -eq 'Client' -or $_.Target -eq 'GameServer' })
    }
    return @($Rows | Where-Object { $_.Target -eq $RequestedTarget })
}

$resolvedSource = (Get-Item -LiteralPath $SourceRoot).FullName
$resolvedStaging = (Get-Item -LiteralPath $StagingRoot).FullName
$artifactRoot = Join-Path $resolvedStaging 'artifacts'
$logRoot = Join-Path $artifactRoot 'logs'
$metaRoot = Join-Path $artifactRoot 'meta'
$markerPath = Join-Path $resolvedStaging 'build\isolation.ready'

if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'Isolation marker is missing. Run Prepare-IsolatedBuild.ps1 first.' }
$marker = @{}
foreach ($line in @(Get-Content -LiteralPath $markerPath)) {
    $parts = ([string]$line).Split(@('='), 2)
    if ($parts.Count -eq 2) { $marker[$parts[0]] = $parts[1] }
}
if (-not $marker.ContainsKey('Target') -or $marker['Target'] -ne $Target) { throw 'Isolation marker target does not match the requested build.' }
$commitSha = [string](& git -C $resolvedSource rev-parse HEAD)
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve source commit.' }
if (-not $marker.ContainsKey('CommitSha') -or $marker['CommitSha'] -ne $commitSha.Trim()) { throw 'Source commit changed after isolation preparation.' }

$devenv = Resolve-DevenvPath -RequestedPath $DevenvPath
$rows = Select-TargetRows -Rows @(Import-Csv -Path $BuildTargetsPath) -RequestedTarget $Target
if ($rows.Count -eq 0) { throw "No build rows selected for $Target." }
foreach ($directory in @($logRoot, $metaRoot)) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
}

$steps = New-Object System.Collections.ArrayList
$buildStarted = (Get-Date).ToUniversalTime()
try {
    foreach ($row in $rows) {
        $solutionPath = Join-Path $resolvedSource ([string]$row.Solution)
        $artifactPath = Join-Path $artifactRoot ([string]$row.Artifact)
        $logPath = Join-Path $logRoot (([string]$row.Name) + '-build.log')
        if (Test-Path -LiteralPath $artifactPath -PathType Leaf) { Remove-Item -LiteralPath $artifactPath -Force }

        $started = (Get-Date).ToUniversalTime()
        & $devenv $solutionPath '/build' ([string]$row.SolutionConfiguration) '/out' $logPath
        $exitCode = $LASTEXITCODE
        $finished = (Get-Date).ToUniversalTime()
        [void]$steps.Add((([string]$row.Name) + "`t" + $started.ToString('o') + "`t" + $finished.ToString('o') + "`t" + $exitCode + "`t" + $logPath))
        if ($exitCode -ne 0) { throw "Build failed for $($row.Name) with exit code $exitCode. Log: $logPath" }
        if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { throw "Expected artifact was not created: $artifactPath" }
        $artifact = Get-Item -LiteralPath $artifactPath
        if ($artifact.Length -le 0) { throw "Artifact is empty: $artifactPath" }
        if ($artifact.LastWriteTimeUtc -lt $started.AddSeconds(-2)) { throw "Artifact is older than its build step: $artifactPath" }
    }

    $manifest = @("Name`tTarget`tConfiguration`tCommitSha`tPath`tLength`tLastWriteTimeUtc`tSHA256")
    foreach ($row in $rows) {
        $artifactPath = Join-Path $artifactRoot ([string]$row.Artifact)
        $artifact = Get-Item -LiteralPath $artifactPath
        $manifest += (([string]$row.Name) + "`t" + ([string]$row.Target) + "`t" + ([string]$row.SolutionConfiguration) + "`t" + $commitSha.Trim() + "`t" + $artifactPath + "`t" + $artifact.Length + "`t" + $artifact.LastWriteTimeUtc.ToString('o') + "`t" + (Get-Sha256 -LiteralPath $artifactPath))
    }
    [System.IO.File]::WriteAllLines((Join-Path $metaRoot 'artifact-manifest.tsv'), [string[]]$manifest, [System.Text.Encoding]::UTF8)
    $steps.Insert(0, "Name`tStartedUtc`tFinishedUtc`tExitCode`tLogPath")
    [System.IO.File]::WriteAllLines((Join-Path $metaRoot 'build-steps.tsv'), [string[]]$steps, [System.Text.Encoding]::UTF8)
    $success = @('Target=' + $Target, 'CommitSha=' + $commitSha.Trim(), 'StartedUtc=' + $buildStarted.ToString('o'), 'FinishedUtc=' + (Get-Date).ToUniversalTime().ToString('o'))
    [System.IO.File]::WriteAllLines((Join-Path $metaRoot 'build.success'), [string[]]$success, [System.Text.Encoding]::ASCII)
}
catch {
    if ($steps.Count -gt 0) {
        $steps.Insert(0, "Name`tStartedUtc`tFinishedUtc`tExitCode`tLogPath")
        [System.IO.File]::WriteAllLines((Join-Path $metaRoot 'build-steps.tsv'), [string[]]$steps, [System.Text.Encoding]::UTF8)
    }
    [System.IO.File]::WriteAllText((Join-Path $metaRoot 'build.failed.txt'), $_.Exception.ToString(), [System.Text.Encoding]::UTF8)
    throw
}

Write-Output 'Build=PASS'
Write-Output "Target=$Target"
Write-Output "CommitSha=$($commitSha.Trim())"
Write-Output "Manifest=$(Join-Path $metaRoot 'artifact-manifest.tsv')"
