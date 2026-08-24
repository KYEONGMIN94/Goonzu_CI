[CmdletBinding()]
param(
    [string]$ComputerName = 'GOONZU-BUILD',
    [string]$IpAddress = '192.168.1.112',
    [string]$SubnetMask = '255.255.255.0',
    [string]$Gateway = '192.168.1.1',
    [string[]]$DnsServers = @('192.168.1.1')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Assert-WmiResult {
    param([object]$Result, [string]$Operation)
    if ($null -eq $Result) { throw "$Operation returned no WMI result." }
    if ($Result.ReturnValue -ne 0 -and $Result.ReturnValue -ne 1) {
        throw "$Operation failed with WMI return value $($Result.ReturnValue)."
    }
}

$adapters = @(Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled })
if ($adapters.Count -ne 1) { throw "Expected one IP-enabled network adapter; found $($adapters.Count)." }
$adapter = $adapters[0]

Assert-WmiResult -Result ($adapter.EnableStatic(@($IpAddress), @($SubnetMask))) -Operation 'EnableStatic'
Assert-WmiResult -Result ($adapter.SetGateways(@($Gateway), @(1))) -Operation 'SetGateways'
Assert-WmiResult -Result ($adapter.SetDNSServerSearchOrder($DnsServers)) -Operation 'SetDNSServerSearchOrder'

$computer = Get-WmiObject Win32_ComputerSystem
if ($computer.Name -ne $ComputerName) {
    Assert-WmiResult -Result ($computer.Rename($ComputerName)) -Operation 'RenameComputer'
}

Write-Output 'BuildWorkerConfiguration=PASS'
Write-Output "ComputerName=$ComputerName"
Write-Output "IpAddress=$IpAddress"
Write-Output "Gateway=$Gateway"
Write-Output ('DnsServers=' + ($DnsServers -join ','))
Write-Output 'RestartRequired=True'
