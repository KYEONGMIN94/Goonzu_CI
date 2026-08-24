[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$DevenvPath,

    [string]$BuildTargetsPath = '',

    [string]$DependenciesPath = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $scriptRoot
if ([string]::IsNullOrEmpty($BuildTargetsPath)) { $BuildTargetsPath = Join-Path $repositoryRoot 'config\build-targets.csv' }
if ([string]::IsNullOrEmpty($DependenciesPath)) { $DependenciesPath = Join-Path $repositoryRoot 'config\build-dependencies.csv' }

function Resolve-DevenvPath {
    param([string]$RequestedPath)
    if (Test-Path -LiteralPath $RequestedPath -PathType Leaf) { return (Get-Item -LiteralPath $RequestedPath).FullName }
    if ([System.IO.Path]::GetExtension($RequestedPath) -ieq '.com') {
        $fallback = [System.IO.Path]::ChangeExtension($RequestedPath, '.exe')
        if (Test-Path -LiteralPath $fallback -PathType Leaf) { return (Get-Item -LiteralPath $fallback).FullName }
    }
    throw "Visual Studio .NET 2003 executable not found: $RequestedPath"
}

$resolvedSource = (Get-Item -LiteralPath $SourceRoot).FullName
$lowerSource = $resolvedSource.ToLowerInvariant()
foreach ($forbidden in @('c:\goonzuworld','c:\goonzuworldserver','c:\serveragent','d:\goonzuworld')) {
    if ($lowerSource -eq $forbidden -or $lowerSource.StartsWith($forbidden + '\')) {
        throw "Source checkout is inside a prohibited live path: $resolvedSource"
    }
}
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) { throw 'git.exe was not found in PATH.' }
$resolvedDevenv = Resolve-DevenvPath -RequestedPath $DevenvPath
if (-not (Test-Path -LiteralPath $BuildTargetsPath -PathType Leaf)) { throw "Missing build target configuration: $BuildTargetsPath" }
if (-not (Test-Path -LiteralPath $DependenciesPath -PathType Leaf)) { throw "Missing dependency configuration: $DependenciesPath" }

$projects = @()
foreach ($row in @(Import-Csv -LiteralPath $BuildTargetsPath)) {
    $projects += New-Object PSObject -Property @{ Project = [string]$row.Project; Configuration = [string]$row.ProjectConfiguration; Solution = [string]$row.Solution }
}
foreach ($row in @(Import-Csv -LiteralPath $DependenciesPath)) {
    $projects += New-Object PSObject -Property @{ Project = [string]$row.Project; Configuration = [string]$row.ProjectConfiguration; Solution = '' }
}

foreach ($spec in $projects) {
    $projectPath = Join-Path $resolvedSource $spec.Project
    if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) { throw "Missing project: $projectPath" }
    if ($spec.Solution -and -not (Test-Path -LiteralPath (Join-Path $resolvedSource $spec.Solution) -PathType Leaf)) { throw "Missing solution: $($spec.Solution)" }
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($projectPath)
    $configs = @(@($xml.VisualStudioProject.Configurations.Configuration) | Where-Object { $_.Name -eq $spec.Configuration })
    if ($configs.Count -ne 1) { throw "Missing or duplicate configuration '$($spec.Configuration)' in $projectPath" }
}

Write-Output 'Environment=PASS'
Write-Output "SourceRoot=$resolvedSource"
Write-Output "DevenvPath=$resolvedDevenv"
Write-Output "PowerShellVersion=$($PSVersionTable.PSVersion)"
Write-Output "ConfiguredProjects=$($projects.Count)"
