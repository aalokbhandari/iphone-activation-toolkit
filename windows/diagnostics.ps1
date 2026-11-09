Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'apple-tools.ps1')

function ConvertTo-AppleUsbSummary {
    param([object[]]$Devices = @())

    foreach ($device in $Devices) {
        $id = [string]$device.InstanceId
        # Composite interfaces repeat the same physical device. Only include
        # the parent USB entry. A USB vendor ID cannot establish the model.
        if ($id -notmatch '^USB\\VID_05AC&PID_([0-9A-F]{4})(?:\\|&)' -or
            $id -match '&MI_[0-9A-F]{2}') {
            continue
        }
        $pidHex = $Matches[1].ToUpperInvariant()
        $mode = switch ($pidHex) {
            '1227' { 'DFU'; break }
            { $_ -in @('1280', '1281', '1282', '1283') } { 'Recovery'; break }
            default { 'Apple USB device (mode and model unverified)' }
        }
        [pscustomobject][ordered]@{
            Name = [string]$device.FriendlyName
            ProductId = $pidHex
            Mode = $mode
            DriverStatus = [string]$device.Status
        }
    }
}

function Get-AppleUsbScan {
    try {
        $devices = @(Get-PnpDevice -PresentOnly -ErrorAction Stop |
            Where-Object { $_.InstanceId -like 'USB\VID_05AC*' })
        return [pscustomobject]@{
            Succeeded = $true
            Devices = @(ConvertTo-AppleUsbSummary -Devices $devices)
            Error = $null
        }
    } catch {
        # Some Windows installations lack the PnpDevice module. Do not
        # report "no phone" if both enumeration methods actually fail.
        $pnpError = $_.Exception.Message
        try {
            $devices = @(Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
                Where-Object { $_.PNPDeviceID -like 'USB\VID_05AC*' -and
                    $_.Present -eq $true } |
                ForEach-Object {
                    [pscustomobject]@{
                        InstanceId = $_.PNPDeviceID
                        FriendlyName = $_.Name
                        Status = $_.Status
                    }
                })
            return [pscustomobject]@{
                Succeeded = $true
                Devices = @(ConvertTo-AppleUsbSummary -Devices $devices)
                Error = $null
            }
        } catch {
            return [pscustomobject]@{
                Succeeded = $false
                Devices = @()
                Error = "PnP: $pnpError; CIM: $($_.Exception.Message)"
            }
        }
    }
}

function New-WindowsSupportReport {
    param([Parameter(Mandatory = $true)]$UsbScan)

    $activationInstalled = $false
    $infoInstalled = $false
    try { $activationInstalled = [bool](Resolve-AppleTool -Name ideviceactivation) } catch { }
    try { $infoInstalled = [bool](Resolve-AppleTool -Name ideviceinfo) } catch { }

    [pscustomobject][ordered]@{
        CheckedAt = [DateTime]::UtcNow.ToString('o')
        RequestedModel = 'iPhone 13 Pro Max'
        RequestedChip = 'A15 Bionic'
        ModelVerified = $false
        IosVersion = $null
        WindowsVersion = [Environment]::OSVersion.VersionString
        UsbScanSucceeded = $UsbScan.Succeeded
        UsbScanError = $UsbScan.Error
        AppleUsbDevices = @($UsbScan.Devices)
        ActivationBackend = 'libimobiledevice/libideviceactivation'
        ActivationToolInstalled = $activationInstalled
        DeviceInfoToolInstalled = $infoInstalled
        IntegrationGuide = 'GITHUB_INTEGRATION.md'
        SupportUrl = 'https://support.apple.com/en-us/108934'
    }
}
