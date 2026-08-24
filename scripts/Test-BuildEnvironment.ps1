[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$DevenvPath,

    [string]$BuildTargetsPath = '',

    [string]$DependenciesPath = '',

    [Int64]$MinimumFreeBytes = 15000000000
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
if ($MinimumFreeBytes -lt 0) { throw 'MinimumFreeBytes must not be negative.' }

$sourceDriveRoot = [System.IO.Path]::GetPathRoot($resolvedSource)
if ([string]::IsNullOrEmpty($sourceDriveRoot) -or $sourceDriveRoot.Length -lt 2 -or $sourceDriveRoot[1] -ne ':') {
    throw "Source checkout must use a local drive so free space can be verified: $resolvedSource"
}
$sourceDeviceId = $sourceDriveRoot.Substring(0, 2)
$sourceDisk = Get-WmiObject Win32_LogicalDisk -Filter ("DeviceID='" + $sourceDeviceId + "'")
if ($null -eq $sourceDisk) { throw "Unable to inspect free space for source drive: $sourceDeviceId" }
$sourceDriveFreeBytes = [Int64]$sourceDisk.FreeSpace
if ($sourceDriveFreeBytes -lt $MinimumFreeBytes) {
    throw "Insufficient build drive space. Drive=$sourceDeviceId FreeBytes=$sourceDriveFreeBytes RequiredBytes=$MinimumFreeBytes"
}

$projects = @()
foreach ($row in @(Import-Csv -Path $BuildTargetsPath)) {
    $projects += New-Object PSObject -Property @{ Project = [string]$row.Project; Configuration = [string]$row.ProjectConfiguration; Solution = [string]$row.Solution }
}
foreach ($row in @(Import-Csv -Path $DependenciesPath)) {
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
Write-Output "SourceDrive=$sourceDeviceId"
Write-Output "SourceDriveFreeBytes=$sourceDriveFreeBytes"
Write-Output "MinimumFreeBytes=$MinimumFreeBytes"
