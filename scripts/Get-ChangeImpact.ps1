[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [string]$BaseRevision = 'origin/master',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Test-Prefix {
    param([string]$Path, [string]$Prefix)
    return $Path.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-PathCategory {
    param([string]$Path)

    $normalized = $Path.Replace('\', '/')
    if ((Test-Prefix $normalized '.codex/') -or
        (Test-Prefix $normalized '.github/') -or
        (Test-Prefix $normalized 'docs/') -or
        $normalized -eq 'AGENTS.md' -or
        $normalized -eq 'CONTRIBUTING.md' -or
        $normalized -eq 'README.md' -or
        $normalized -eq '.gitignore' -or
        $normalized -eq '.gitattributes') {
        return 'None'
    }

    if (Test-Prefix $normalized 'GoonZuWorld/Client/') { return 'Client' }
    if (Test-Prefix $normalized 'GoonZuWorld/Server/') { return 'GameServer' }
    if ((Test-Prefix $normalized 'AdminSystem/') -or
        (Test-Prefix $normalized 'DBManager/') -or
        (Test-Prefix $normalized 'Server/')) {
        return 'ServerSuite'
    }
    if ((Test-Prefix $normalized 'GoonZuWorld/common/') -or
        (Test-Prefix $normalized 'GoonZuWorld/CommonLogic/') -or
        (Test-Prefix $normalized 'NLib/') -or
        (Test-Prefix $normalized 'NStatistics/') -or
        (Test-Prefix $normalized 'NetworkLib/') -or
        $normalized -eq 'GProject.sln') {
        return 'All'
    }
    if ($normalized -eq 'GoonZuWorld/GoonZuWorld.sln' -or
        $normalized -eq 'GoonZuWorld/BeTheRich.vcproj') {
        return 'ClientGameServer'
    }

    return 'All'
}

function Add-Paths {
    param([hashtable]$Set, [object[]]$Paths)
    foreach ($path in @($Paths)) {
        $value = [string]$path
        if (-not [string]::IsNullOrEmpty($value)) {
            $Set[$value.Replace('\', '/')] = $true
        }
    }
}

$resolvedSource = (Get-Item -LiteralPath $SourceRoot).FullName
if (-not (Test-Path -LiteralPath (Join-Path $resolvedSource '.git'))) {
    throw "SourceRoot is not a Git worktree: $resolvedSource"
}
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$gitPrefix = @('-c', ("safe.directory=" + $resolvedSource), '-C', $resolvedSource)
try {
    & git @gitPrefix rev-parse --verify $BaseRevision 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Base revision does not exist: $BaseRevision"
    }

    $commitSha = [string](& git @gitPrefix rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve HEAD.' }

    $paths = @{}
    Add-Paths -Set $paths -Paths @(& git @gitPrefix diff --name-only --diff-filter=ACMRTUXB ("$BaseRevision...HEAD") --)
    Add-Paths -Set $paths -Paths @(& git @gitPrefix diff --name-only --diff-filter=ACMRTUXB --)
    Add-Paths -Set $paths -Paths @(& git @gitPrefix diff --cached --name-only --diff-filter=ACMRTUXB --)
    Add-Paths -Set $paths -Paths @(& git @gitPrefix ls-files --others --exclude-standard)

    $hasClient = $false
    $hasGameServer = $false
    $hasServerSuite = $false
    $forceAll = $false
    $rows = @("Path`tCategory")

    foreach ($path in @($paths.Keys | Sort-Object)) {
        $category = Get-PathCategory -Path $path
        $rows += ($path + "`t" + $category)
        if ($category -eq 'Client') { $hasClient = $true }
        elseif ($category -eq 'GameServer') { $hasGameServer = $true }
        elseif ($category -eq 'ServerSuite') { $hasServerSuite = $true }
        elseif ($category -eq 'ClientGameServer') { $hasClient = $true; $hasGameServer = $true }
        elseif ($category -eq 'All') { $forceAll = $true }
    }

    if ($forceAll -or (($hasClient -or $hasGameServer) -and $hasServerSuite)) {
        $target = 'All'
    }
    elseif ($hasClient -and $hasGameServer) { $target = 'ClientGameServer' }
    elseif ($hasClient) { $target = 'Client' }
    elseif ($hasGameServer) { $target = 'GameServer' }
    elseif ($hasServerSuite) { $target = 'ServerSuite' }
    else { $target = 'None' }

    [System.IO.File]::WriteAllLines((Join-Path $OutputDirectory 'changed-files.tsv'), [string[]]$rows, [System.Text.Encoding]::UTF8)
    $properties = @(
        'BuildTarget=' + $target,
        'ChangedFileCount=' + $paths.Count,
        'BaseRevision=' + $BaseRevision,
        'CommitSha=' + $commitSha.Trim()
    )
    [System.IO.File]::WriteAllLines((Join-Path $OutputDirectory 'impact.properties'), [string[]]$properties, [System.Text.Encoding]::ASCII)

    Write-Output "BuildTarget=$target"
    Write-Output "ChangedFileCount=$($paths.Count)"
    Write-Output "CommitSha=$($commitSha.Trim())"
}
finally {}
