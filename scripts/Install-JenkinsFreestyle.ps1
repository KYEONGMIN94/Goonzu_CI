[CmdletBinding()]
param(
    [string]$JenkinsHome = 'D:\Jenkins\JENKINSDATA',
    [string[]]$InheritedJobs = @('Goonzu_Build_Client','Goonzu_Build_Server','Goonzu_patch'),
    [string]$JobName = 'Goonzu_Verify'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryRoot = Split-Path -Parent $scriptRoot
$template = Join-Path $repositoryRoot ('jenkins\jobs\' + $JobName + '\config.xml')
$jobsRoot = Join-Path $JenkinsHome 'jobs'
if (-not (Test-Path -LiteralPath $jobsRoot -PathType Container)) { throw "Jenkins jobs directory is missing: $jobsRoot" }
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) { throw "Jenkins job template is missing: $template" }

foreach ($name in $InheritedJobs) {
    $configPath = Join-Path (Join-Path $jobsRoot $name) 'config.xml'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { continue }
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($configPath)
    $disabled = $xml.SelectSingleNode('/project/disabled')
    if ($null -eq $disabled) {
        $disabled = $xml.CreateElement('disabled')
        $disabled.InnerText = 'true'
        [void]$xml.DocumentElement.AppendChild($disabled)
    }
    else { $disabled.InnerText = 'true' }
    $xml.Save($configPath)
    Write-Output "Disabled=$name"
}

$jobDirectory = Join-Path $jobsRoot $JobName
if (-not (Test-Path -LiteralPath $jobDirectory -PathType Container)) { New-Item -ItemType Directory -Path $jobDirectory -Force | Out-Null }
Copy-Item -LiteralPath $template -Destination (Join-Path $jobDirectory 'config.xml') -Force
Write-Output "Installed=$JobName"
Write-Output 'RestartRequired=True'
