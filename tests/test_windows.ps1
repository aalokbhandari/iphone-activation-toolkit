# Hardware-independent checks; no Pester installation required.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\diagnostics.ps1')
$script:assertions = 0

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -cne $Expected) {
        throw "$Message - expected '$Expected', got '$Actual'"
    }
    $script:assertions++
}

$fixtures = @(
    [pscustomobject]@{ InstanceId = 'USB\VID_05AC&PID_1227\private-serial'; FriendlyName = 'Apple DFU'; Status = 'OK' }
    [pscustomobject]@{ InstanceId = 'USB\VID_05AC&PID_1281\private-serial'; FriendlyName = 'Apple Recovery'; Status = 'OK' }
    [pscustomobject]@{ InstanceId = 'usb\vid_05ac&pid_12a8\private-serial'; FriendlyName = 'Apple USB'; Status = 'Error' }
    [pscustomobject]@{ InstanceId = 'USB\VID_05AC&PID_12A8&MI_00\private-serial'; FriendlyName = 'Duplicate interface'; Status = 'OK' }
    [pscustomobject]@{ InstanceId = 'USB\VID_1234&PID_1227\other'; FriendlyName = 'Other vendor'; Status = 'OK' }
    [pscustomobject]@{ InstanceId = 'USB\VID_05AC&PID_12270\other'; FriendlyName = 'Malformed'; Status = 'OK' }
)
$devices = @(ConvertTo-AppleUsbSummary -Devices $fixtures)
Assert-Equal $devices.Count 3 'Filter vendor IDs, malformed IDs and duplicate interfaces'
Assert-Equal $devices[0].Mode 'DFU' 'DFU mode'
Assert-Equal $devices[1].Mode 'Recovery' 'Recovery mode'
Assert-Equal $devices[2].ProductId '12A8' 'Case-insensitive USB IDs'
Assert-Equal $devices[2].Mode 'Apple USB device (mode and model unverified)' 'Unknown model stays unverified'
Assert-Equal $devices[2].DriverStatus 'Error' 'Preserve driver errors'
Assert-Equal (($devices | ConvertTo-Json) -match 'private-serial') $false 'Do not save serials'
Assert-Equal @(ConvertTo-AppleUsbSummary -Devices @()).Count 0 'Empty device list'

foreach ($recoveryId in @('1280', '1281', '1282', '1283')) {
    $fixture = [pscustomobject]@{
        InstanceId = "USB\VID_05AC&PID_$recoveryId\private-serial"
        FriendlyName = 'Recovery fixture'
        Status = 'OK'
    }
    $summary = @(ConvertTo-AppleUsbSummary -Devices @($fixture))
    Assert-Equal $summary.Count 1 "Recovery $recoveryId is included"
    Assert-Equal $summary[0].Mode 'Recovery' "Recovery $recoveryId mode"
    Assert-Equal $summary[0].ProductId $recoveryId "Recovery $recoveryId product ID"
}

# Replace only the Windows queries, keeping real scan and report logic.
function Get-PnpDevice {
    param([switch]$PresentOnly, $ErrorAction)
    if ($script:failPnp) { throw 'PnP query unavailable' }
    if ($script:emptyPnp) { return }
    $fixtures
}
function Get-CimInstance {
    param($ClassName, $ErrorAction)
    if ($script:failCim) { throw 'CIM query unavailable' }
    [pscustomobject]@{ PNPDeviceID = 'USB\VID_05AC&PID_1282\private'; Name = 'Present'; Status = 'OK'; Present = $true }
    [pscustomobject]@{ PNPDeviceID = 'USB\VID_05AC&PID_1227\private'; Name = 'Disconnected'; Status = 'OK'; Present = $false }
}
$script:failPnp = $false
$script:failCim = $false
$script:emptyPnp = $false
$scan = Get-AppleUsbScan
Assert-Equal $scan.Succeeded $true 'PnP query succeeds'
Assert-Equal $scan.Devices.Count 3 'PnP filtering'
$report = New-WindowsSupportReport -UsbScan $scan
$serialized = $report | ConvertTo-Json -Depth 5
Assert-Equal ($serialized -match 'private-serial|VID_05AC') $false 'Report excludes raw USB identifiers'
Assert-Equal $report.ModelVerified $false 'USB presence does not identify a model'
Assert-Equal @($report.AppleUsbDevices).Count 3 'Report preserves detected devices'

$script:emptyPnp = $true
$scan = Get-AppleUsbScan
Assert-Equal $scan.Succeeded $true 'An empty successful scan is not a query failure'
Assert-Equal $scan.Devices.Count 0 'No devices in an empty successful scan'
Assert-Equal $scan.Error $null 'No error in an empty successful scan'
$script:emptyPnp = $false

$script:failPnp = $true
$scan = Get-AppleUsbScan
Assert-Equal $scan.Succeeded $true 'CIM fallback succeeds'
Assert-Equal $scan.Devices.Count 1 'CIM excludes disconnected devices'
Assert-Equal $scan.Devices[0].Mode 'Recovery' 'CIM mode detection'

$script:failCim = $true
$scan = Get-AppleUsbScan
Assert-Equal $scan.Succeeded $false 'Query errors are not reported as an absent phone'
Assert-Equal $scan.Devices.Count 0 'No invented devices on query failure'
Assert-Equal ($scan.Error -match 'PnP:.*CIM:') $true 'Preserve both query failure reasons'
$report = New-WindowsSupportReport -UsbScan $scan
Assert-Equal $report.ModelVerified $false 'Requested model is not a detected model'
Assert-Equal $report.UsbScanSucceeded $false 'Report preserves query failure'
Assert-Equal $report.ActivationBackend 'libimobiledevice/libideviceactivation' 'Report identifies the actual upstream backend'
$roundTrip = $report | ConvertTo-Json -Depth 5 | ConvertFrom-Json
Assert-Equal @($roundTrip.AppleUsbDevices).Count 0 'Empty arrays survive report serialization'
. (Join-Path $PSScriptRoot 'test_apple_tools.ps1')
. (Join-Path $PSScriptRoot 'test_iphone_workflow.ps1')
Write-Host "Windows diagnostic tests passed: $script:assertions assertions."
