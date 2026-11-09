# Native Windows diagnostic entry point. Does not run the bypass engine.
# Requires Windows PowerShell 5.1 or later; no WSL or administrator access.
[CmdletBinding()]
param(
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows\diagnostics.ps1')

try {
    if ([string]::IsNullOrWhiteSpace($ReportPath)) {
        $ReportPath = Join-Path $PSScriptRoot 'reports\windows-check.json'
    }
    Write-Host ''
    Write-Host 'tr4mpass - Windows device and support check'
    Write-Host 'Requested device: iPhone 13 Pro Max (A15 Bionic)'
    Write-Host ''

    $scan = Get-AppleUsbScan
    $report = New-WindowsSupportReport -UsbScan $scan
    if (-not $scan.Succeeded) {
        Write-Host "USB detection failed: $($scan.Error)"
    } elseif ($scan.Devices.Count -eq 0) {
        Write-Host 'Windows currently detects no connected Apple USB device.'
        Write-Host 'Connect the iPhone with a data cable and run this check again.'
    } else {
        foreach ($device in $scan.Devices) {
            Write-Host "Detected: $($device.Name) - $($device.Mode)"
            Write-Host "  USB product ID: $($device.ProductId); driver status: $($device.DriverStatus)"
        }
        Write-Host 'USB detection does not verify the phone model or iOS version.'
    }

    Write-Host ''
    Write-Host "Activation backend: $($report.ActivationBackend)"
    Write-Host "  ideviceactivation found: $($report.ActivationToolInstalled)"
    Write-Host "  ideviceinfo found: $($report.DeviceInfoToolInstalled)"
    Write-Host ''
    Write-Host 'Read device model and iOS version with apple-device.ps1 -Action Info.'
    Write-Host "Tool setup and usage: $($report.IntegrationGuide)"

    $fullReportPath = [IO.Path]::GetFullPath($ReportPath)
    $reportDirectory = Split-Path -Parent $fullReportPath
    if (-not (Test-Path -LiteralPath $reportDirectory)) {
        New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 5 |
        Set-Content -LiteralPath $fullReportPath -Encoding UTF8
    Write-Host ''
    Write-Host "Local report saved: $fullReportPath"
    Write-Host 'This check did not change the phone. The C bypass engine was not run.'
    if (-not $scan.Succeeded) { exit 1 }
    exit 0
} catch {
    Write-Host "Windows check failed: $($_.Exception.Message)"
    exit 1
}
