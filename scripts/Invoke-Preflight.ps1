[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [string]$BaseRevision = 'origin/master',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [switch]$RequireClean
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
& (Join-Path $scriptRoot 'Get-ChangeImpact.ps1') -SourceRoot $SourceRoot -BaseRevision $BaseRevision -OutputDirectory $OutputDirectory
if ($LASTEXITCODE -ne 0) { throw 'Change-impact analysis failed.' }

$results = New-Object System.Collections.ArrayList
$failures = New-Object System.Collections.ArrayList
function Add-Result {
    param([string]$Check, [string]$Status, [string]$Detail)
    [void]$results.Add(($Check + "`t" + $Status + "`t" + $Detail))
    if ($Status -eq 'FAIL') { [void]$failures.Add(($Check + ': ' + $Detail)) }
}

$resolvedSource = (Get-Item -LiteralPath $SourceRoot).FullName
$gitPrefix = @('-c', ("safe.directory=" + $resolvedSource), '-C', $resolvedSource)
try {
    $required = @(
        'GoonZuWorld\GoonZuWorld.sln',
        'GoonZuWorld\BeTheRich.vcproj',
        'AdminSystem\MasterServer\MasterServer.sln',
        'AdminSystem\ServerAgent\ServerAgent.sln',
        'DBManager\AccountDBManager\AccountDBManager.sln',
        'DBManager\GameDBManager_World\GameDBManager.sln',
        'Server\AuthServer\AuthServer.sln',
        'Server\FrontServer\FrontServer.sln'
    )
    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $resolvedSource $_) -PathType Leaf) })
    if ($missing.Count -eq 0) { Add-Result 'RequiredProjects' 'PASS' ($required.Count.ToString() + ' files') }
    else { Add-Result 'RequiredProjects' 'FAIL' ($missing -join ', ') }

    $status = @(& git @gitPrefix status --porcelain)
    if ($RequireClean -and $status.Count -ne 0) { Add-Result 'CleanWorktree' 'FAIL' ($status -join ' | ') }
    elseif ($status.Count -eq 0) { Add-Result 'CleanWorktree' 'PASS' 'clean' }
    else { Add-Result 'CleanWorktree' 'INFO' ($status.Count.ToString() + ' local changes included') }

    $diffCheck = @(& git @gitPrefix diff --check ("$BaseRevision...HEAD") -- 2>&1)
    $diffExit = $LASTEXITCODE
    $workingCheck = @(& git @gitPrefix diff --check -- 2>&1)
    $workingExit = $LASTEXITCODE
    if ($diffExit -eq 0 -and $workingExit -eq 0) { Add-Result 'WhitespaceErrors' 'PASS' 'none' }
    else { Add-Result 'WhitespaceErrors' 'FAIL' (($diffCheck + $workingCheck) -join ' | ') }

    $added = @(& git @gitPrefix diff --name-only --diff-filter=A ("$BaseRevision...HEAD") --)
    $added += @(& git @gitPrefix diff --cached --name-only --diff-filter=A --)
    $added += @(& git @gitPrefix ls-files --others --exclude-standard)
    $forbiddenExtensions = @('.exe','.dll','.pdb','.obj','.pch','.ilk','.ncb','.suo','.user','.aps','.log')
    $forbidden = @()
    foreach ($path in @($added | Sort-Object -Unique)) {
        if ($forbiddenExtensions -contains [System.IO.Path]::GetExtension([string]$path).ToLowerInvariant()) {
            $forbidden += [string]$path
        }
        if ([string]$path -match '(?i)(password|secret|credential|token).*(\.txt|\.json|\.xml|\.ini|\.config)$') {
            $forbidden += [string]$path
        }
    }
    if ($forbidden.Count -eq 0) { Add-Result 'ForbiddenNewFiles' 'PASS' 'none' }
    else { Add-Result 'ForbiddenNewFiles' 'FAIL' (($forbidden | Sort-Object -Unique) -join ', ') }

    $changedTable = Import-Csv -Path (Join-Path $OutputDirectory 'changed-files.tsv') -Delimiter "`t"
    $mergeMarkers = @()
    $textExtensions = @('.c','.cc','.cpp','.h','.hpp','.rc','.sln','.vcproj','.ps1','.bat','.cmd','.md','.toml','.yml','.yaml','.txt','.csv')
    foreach ($row in @($changedTable)) {
        if ($null -eq $row -or $null -eq $row.PSObject.Properties['Path']) { continue }
        $fullPath = Join-Path $resolvedSource ([string]$row.Path)
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { continue }
        if ($textExtensions -notcontains [System.IO.Path]::GetExtension($fullPath).ToLowerInvariant()) { continue }
        if ((Get-Item -LiteralPath $fullPath).Length -gt 5242880) { continue }
        $matches = @(Get-Content -LiteralPath $fullPath | Select-String -Pattern '^(<<<<<<<|=======|>>>>>>>)')
        if ($matches.Count -gt 0) { $mergeMarkers += [string]$row.Path }
    }
    if ($mergeMarkers.Count -eq 0) { Add-Result 'MergeMarkers' 'PASS' 'none' }
    else { Add-Result 'MergeMarkers' 'FAIL' (($mergeMarkers | Sort-Object -Unique) -join ', ') }
}
finally {}

$results.Insert(0, "Check`tStatus`tDetail")
[System.IO.File]::WriteAllLines((Join-Path $OutputDirectory 'preflight.tsv'), [string[]]$results, [System.Text.Encoding]::UTF8)

if ($failures.Count -gt 0) {
    throw ('Preflight failed: ' + ($failures -join '; '))
}

Write-Output 'Preflight=PASS'
Write-Output ("Evidence=" + (Join-Path $OutputDirectory 'preflight.tsv'))
