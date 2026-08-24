[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$StagingRoot,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Client','GameServer','ClientGameServer','ServerSuite','All')]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$BuildTargetsPath,

    [Parameter(Mandatory = $true)]
    [string]$DependenciesPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
}

function Test-PathUnderRoot {
    param([string]$Path, [string]$Root)
    $fullPath = Get-FullPath $Path
    $fullRoot = Get-FullPath $Root
    return ($fullPath -eq $fullRoot -or $fullPath.StartsWith(($fullRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase))
}

function Assert-SafeStagingRoot {
    param([string]$Path)
    $full = Get-FullPath $Path
    $forbidden = @(
        'C:\GoonZuWorld',
        'C:\GoonzuWorld',
        'C:\ServerAgent',
        'C:\GoonZuWorldServer',
        'D:\GoonZuWorld'
    )
    foreach ($root in $forbidden) {
        if (Test-PathUnderRoot -Path $full -Root $root) {
            throw "StagingRoot is inside a prohibited live path: $full"
        }
    }
}

function Set-ConfigurationPaths {
    param(
        [string]$ProjectPath,
        [string]$ConfigurationName,
        [string]$OutputDirectory,
        [string]$IntermediateDirectory,
        [string]$LinkOutput
    )

    $encoding = [System.Text.Encoding]::GetEncoding(949)
    $text = [System.IO.File]::ReadAllText($ProjectPath, $encoding)
    $configPattern = '(?s)<Configuration\s+Name="' + [System.Text.RegularExpressions.Regex]::Escape($ConfigurationName) + '".*?</Configuration>'
    $configRegex = New-Object System.Text.RegularExpressions.Regex($configPattern)
    $matches = $configRegex.Matches($text)
    if ($matches.Count -ne 1) {
        throw "Expected exactly one configuration '$ConfigurationName' in $ProjectPath; found $($matches.Count)."
    }

    $match = $matches[0]
    $block = $match.Value
    $outputRegex = New-Object System.Text.RegularExpressions.Regex('OutputDirectory="[^"]*"')
    $intermediateRegex = New-Object System.Text.RegularExpressions.Regex('IntermediateDirectory="[^"]*"')
    if (-not $outputRegex.IsMatch($block) -or -not $intermediateRegex.IsMatch($block)) {
        throw "Output or intermediate directory is missing in $ProjectPath / $ConfigurationName."
    }
    $block = $outputRegex.Replace($block, ('OutputDirectory="' + $OutputDirectory + '"'), 1)
    $block = $intermediateRegex.Replace($block, ('IntermediateDirectory="' + $IntermediateDirectory + '"'), 1)

    $compilerPdb = New-Object System.Text.RegularExpressions.Regex('ProgramDataBaseFileName="[^"]*"')
    if ($compilerPdb.IsMatch($block)) {
        $block = $compilerPdb.Replace($block, ('ProgramDataBaseFileName="' + (Join-Path $IntermediateDirectory '') + '"'), 1)
    }

    if (-not [string]::IsNullOrEmpty($LinkOutput)) {
        $linkRegex = New-Object System.Text.RegularExpressions.Regex('(?s)<Tool\s+Name="VCLinkerTool".*?/>')
        $linkMatch = $linkRegex.Match($block)
        if (-not $linkMatch.Success) { throw "VCLinkerTool is missing in $ProjectPath / $ConfigurationName." }
        $linkBlock = $linkMatch.Value
        $linkOutputRegex = New-Object System.Text.RegularExpressions.Regex('OutputFile="[^"]*"')
        if (-not $linkOutputRegex.IsMatch($linkBlock)) { throw "Linker OutputFile is missing in $ProjectPath / $ConfigurationName." }
        $linkBlock = $linkOutputRegex.Replace($linkBlock, ('OutputFile="' + $LinkOutput + '"'), 1)

        $linkPdbRegex = New-Object System.Text.RegularExpressions.Regex('ProgramDatabaseFile="[^"]*"')
        if ($linkPdbRegex.IsMatch($linkBlock)) {
            $pdbPath = [System.IO.Path]::ChangeExtension($LinkOutput, '.pdb')
            $linkBlock = $linkPdbRegex.Replace($linkBlock, ('ProgramDatabaseFile="' + $pdbPath + '"'), 1)
        }
        $block = $block.Substring(0, $linkMatch.Index) + $linkBlock + $block.Substring($linkMatch.Index + $linkMatch.Length)
    }

    $text = $text.Substring(0, $match.Index) + $block + $text.Substring($match.Index + $match.Length)
    $xml = New-Object System.Xml.XmlDocument
    $xml.LoadXml($text)
    [System.IO.File]::WriteAllText($ProjectPath, $text, $encoding)
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
$resolvedStaging = Get-FullPath $StagingRoot
Assert-SafeStagingRoot -Path $resolvedStaging

if (Test-PathUnderRoot -Path $resolvedStaging -Root $resolvedSource) {
    throw 'StagingRoot must not be inside the source checkout.'
}
if (-not (Test-Path -LiteralPath $BuildTargetsPath -PathType Leaf)) { throw "Missing build target configuration: $BuildTargetsPath" }
if (-not (Test-Path -LiteralPath $DependenciesPath -PathType Leaf)) { throw "Missing dependency configuration: $DependenciesPath" }

$artifactRoot = Join-Path $resolvedStaging 'artifacts'
$buildRoot = Join-Path $resolvedStaging 'build'
$objectRoot = Join-Path $buildRoot 'objects'
$targetRows = Select-TargetRows -Rows @(Import-Csv -Path $BuildTargetsPath) -RequestedTarget $Target
$dependencyRows = @(Import-Csv -Path $DependenciesPath)
if ($targetRows.Count -eq 0) { throw "No build targets were selected for $Target." }

foreach ($directory in @($artifactRoot, $buildRoot, $objectRoot, (Join-Path $artifactRoot 'meta'), (Join-Path $artifactRoot 'logs'))) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

foreach ($dependency in $dependencyRows) {
    $projectPath = Join-Path $resolvedSource ([string]$dependency.Project)
    $outputDirectory = Join-Path $buildRoot ([string]$dependency.OutputSubdirectory)
    $intermediateDirectory = Join-Path $buildRoot ([string]$dependency.IntermediateSubdirectory)
    foreach ($directory in @($outputDirectory, $intermediateDirectory)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    }
    Set-ConfigurationPaths -ProjectPath $projectPath -ConfigurationName ([string]$dependency.ProjectConfiguration) -OutputDirectory $outputDirectory -IntermediateDirectory $intermediateDirectory -LinkOutput ''
}

foreach ($row in $targetRows) {
    $projectPath = Join-Path $resolvedSource ([string]$row.Project)
    $artifactPath = Join-Path $artifactRoot ([string]$row.Artifact)
    $outputDirectory = Split-Path -Parent $artifactPath
    $intermediateDirectory = Join-Path $objectRoot ([string]$row.Name)
    foreach ($directory in @($outputDirectory, $intermediateDirectory)) {
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    }
    Set-ConfigurationPaths -ProjectPath $projectPath -ConfigurationName ([string]$row.ProjectConfiguration) -OutputDirectory $outputDirectory -IntermediateDirectory $intermediateDirectory -LinkOutput $artifactPath
}

$audit = @("Name`tProject`tConfiguration`tOutputDirectory`tIntermediateDirectory`tArtifact")
foreach ($row in $targetRows) {
    $projectPath = Join-Path $resolvedSource ([string]$row.Project)
    $xml = New-Object System.Xml.XmlDocument
    $xml.Load($projectPath)
    $config = @(@($xml.VisualStudioProject.Configurations.Configuration) | Where-Object { $_.Name -eq [string]$row.ProjectConfiguration })
    if ($config.Count -ne 1) { throw "Isolation audit could not find $($row.ProjectConfiguration) in $projectPath." }
    $artifactPath = Join-Path $artifactRoot ([string]$row.Artifact)
    if (-not (Test-PathUnderRoot -Path ([string]$config[0].OutputDirectory) -Root $resolvedStaging)) { throw "Unsafe OutputDirectory in $projectPath." }
    if (-not (Test-PathUnderRoot -Path ([string]$config[0].IntermediateDirectory) -Root $resolvedStaging)) { throw "Unsafe IntermediateDirectory in $projectPath." }
    $linker = @($config[0].Tool | Where-Object { $_.Name -eq 'VCLinkerTool' })
    if ($linker.Count -ne 1 -or -not (Test-PathUnderRoot -Path ([string]$linker[0].OutputFile) -Root $resolvedStaging)) { throw "Unsafe linker output in $projectPath." }
    if ([string]$linker[0].ProgramDatabaseFile -and -not (Test-PathUnderRoot -Path ([string]$linker[0].ProgramDatabaseFile) -Root $resolvedStaging)) { throw "Unsafe linker PDB in $projectPath." }
    $audit += (([string]$row.Name) + "`t" + ([string]$row.Project) + "`t" + ([string]$row.ProjectConfiguration) + "`t" + ([string]$config[0].OutputDirectory) + "`t" + ([string]$config[0].IntermediateDirectory) + "`t" + $artifactPath)
}

[System.IO.File]::WriteAllLines((Join-Path $artifactRoot 'meta\isolation-audit.tsv'), [string[]]$audit, [System.Text.Encoding]::UTF8)
$commitSha = [string](& git -C $resolvedSource rev-parse HEAD)
$marker = @(('Target=' + $Target), ('CommitSha=' + $commitSha.Trim()), ('StagingRoot=' + $resolvedStaging))
[System.IO.File]::WriteAllLines((Join-Path $buildRoot 'isolation.ready'), [string[]]$marker, [System.Text.Encoding]::ASCII)
Write-Output 'Isolation=PASS'
Write-Output "Target=$Target"
Write-Output "Audit=$(Join-Path $artifactRoot 'meta\isolation-audit.tsv')"
