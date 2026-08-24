[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ArtifactPath,

    [Parameter(Mandatory = $true)]
    [string]$Destination,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedSha256,

    [switch]$Approved
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

if (-not $Approved) { throw 'Release approval is required. Re-run the separate release action with -Approved.' }
if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) { throw "Client artifact not found: $ArtifactPath" }
if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { throw "Release destination is unavailable: $Destination" }

$actualHash = Get-Sha256 -LiteralPath $ArtifactPath
if ($actualHash -ne $ExpectedSha256.ToUpperInvariant()) { throw "Artifact SHA-256 mismatch. Expected $ExpectedSha256, got $actualHash." }
$source = Get-Item -LiteralPath $ArtifactPath
$publishedPath = Join-Path $Destination $source.Name
Copy-Item -LiteralPath $source.FullName -Destination $publishedPath -Force
$published = Get-Item -LiteralPath $publishedPath
if ($published.Length -ne $source.Length) { throw "Published file size mismatch: $publishedPath" }
$publishedHash = Get-Sha256 -LiteralPath $publishedPath
if ($publishedHash -ne $actualHash) { throw "Published file hash mismatch: $publishedPath" }

Write-Output 'Publish=PASS'
Write-Output "Published=$publishedPath"
Write-Output "SHA256=$publishedHash"
