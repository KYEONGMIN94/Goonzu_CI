[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PackageRoot,
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,
    [Parameter(Mandatory = $true)]
    [string]$PackageName,
    [Parameter(Mandatory = $true)]
    [string]$Version,
    [string]$SourceCommit = '',
    [string]$VmSnapshot = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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

$root = (Get-Item -LiteralPath $PackageRoot).FullName.TrimEnd('\')
if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null }
$rows = @("RelativePath`tLength`tLastWriteTimeUtc`tSHA256")
$files = @(Get-ChildItem -LiteralPath $root -Recurse -Force | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName)
foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length).TrimStart('\')
    $rows += ($relative + "`t" + $file.Length + "`t" + $file.LastWriteTimeUtc.ToString('o') + "`t" + (Get-Sha256 -LiteralPath $file.FullName))
}
$manifestPath = Join-Path $OutputDirectory ($PackageName + '-files.tsv')
[System.IO.File]::WriteAllLines($manifestPath, [string[]]$rows, [System.Text.Encoding]::UTF8)
$manifestHash = Get-Sha256 -LiteralPath $manifestPath
$properties = @(
    'PackageName=' + $PackageName,
    'Version=' + $Version,
    'CreatedUtc=' + (Get-Date).ToUniversalTime().ToString('o'),
    'Root=' + $root,
    'FileCount=' + $files.Count,
    'ManifestSha256=' + $manifestHash,
    'SourceCommit=' + $SourceCommit,
    'VmSnapshot=' + $VmSnapshot
)
[System.IO.File]::WriteAllLines((Join-Path $OutputDirectory ($PackageName + '.properties')), [string[]]$properties, [System.Text.Encoding]::UTF8)
Write-Output 'Manifest=PASS'
Write-Output "Package=$PackageName"
Write-Output "Version=$Version"
Write-Output "FileCount=$($files.Count)"
Write-Output "ManifestSha256=$manifestHash"
