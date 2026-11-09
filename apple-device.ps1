[CmdletBinding()]
param(
    [ValidateSet('Info', 'State', 'Activate')][string]$Action = 'Info',
    [string]$Udid,
    [string]$ToolDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows\apple-tools.ps1')
try {
    Invoke-AppleDeviceAction -Action $Action -Udid $Udid -ToolDirectory $ToolDirectory |
        ConvertTo-Json -Depth 3 | Write-Output
    exit 0
} catch {
    Write-Host "Apple device operation failed: $($_.Exception.Message)"
    exit 1
}
