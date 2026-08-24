[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,
    [Parameter(Mandatory = $true)]
    [string]$CommitSha,
    [Parameter(Mandatory = $true)]
    [string]$EvidenceDirectory,
    [string]$Context = 'Goonzu isolated build',
    [string]$TargetUrl = '',
    [string]$GhPath = 'gh.exe',
    [switch]$Approved
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not $Approved) { throw 'GitHub status publication requires -Approved.' }
$successPath = Join-Path $EvidenceDirectory 'build.success'
$manifestPath = Join-Path $EvidenceDirectory 'artifact-manifest.tsv'
if (-not (Test-Path -LiteralPath $successPath -PathType Leaf)) { throw "Missing build success evidence: $successPath" }
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing artifact manifest: $manifestPath" }

$success = @{}
foreach ($line in @(Get-Content -LiteralPath $successPath)) {
    $value = [string]$line
    $separator = $value.IndexOf('=')
    if ($separator -gt 0) { $success[$value.Substring(0, $separator)] = $value.Substring($separator + 1) }
}
if (-not $success.ContainsKey('CommitSha') -or $success['CommitSha'] -ne $CommitSha) { throw 'Build evidence commit does not match CommitSha.' }
if (-not $success.ContainsKey('Target') -or $success['Target'] -ne 'All') { throw 'Only an All-target build may publish the required status.' }

$manifest = @(Import-Csv -Path $manifestPath -Delimiter "`t")
if ($manifest.Count -ne 8) { throw "Expected eight artifact rows; found $($manifest.Count)." }
$manifestCommits = @($manifest | ForEach-Object { [string]$_.CommitSha } | Sort-Object -Unique)
if ($manifestCommits.Count -ne 1 -or $manifestCommits[0] -ne $CommitSha) { throw 'Artifact manifest commit does not match CommitSha.' }

$arguments = @(
    'api',
    '--method', 'POST',
    ('repos/' + $Repository + '/statuses/' + $CommitSha),
    '-f', 'state=success',
    '-f', ('context=' + $Context),
    '-f', 'description=All 8 isolated VS2003 targets passed'
)
if (-not [string]::IsNullOrEmpty($TargetUrl)) { $arguments += @('-f', ('target_url=' + $TargetUrl)) }
& $GhPath @arguments
if ($LASTEXITCODE -ne 0) { throw "GitHub status publication failed with exit code $LASTEXITCODE." }

Write-Output 'GitHubBuildStatus=PASS'
Write-Output "Repository=$Repository"
Write-Output "CommitSha=$CommitSha"
Write-Output "Context=$Context"
