# Adapter for the documented libimobiledevice command-line tools.
Set-StrictMode -Version Latest

function Resolve-AppleTool {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('idevice_id', 'ideviceinfo', 'ideviceactivation')][string]$Name,
        [string]$ToolDirectory
    )
    if ($ToolDirectory) {
        $candidate = Join-Path $ToolDirectory ($Name + '.exe')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return [IO.Path]::GetFullPath($candidate)
        }
    } else {
        $command = Get-Command ($Name + '.exe') -CommandType Application -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
        foreach ($directory in @(
            $env:TR4MPASS_APPLE_TOOLS,
            (Join-Path $env:LOCALAPPDATA 'tr4mpass-device-tools\msys64\ucrt64\bin'),
            (Join-Path $env:LOCALAPPDATA 'tr4mpass-tools\msys64\ucrt64\bin'),
            'C:\msys64\ucrt64\bin'
        )) {
            if ($directory -and (Test-Path -LiteralPath (Join-Path $directory ($Name + '.exe')) -PathType Leaf)) {
                return (Join-Path $directory ($Name + '.exe'))
            }
        }
    }
    throw "Missing $Name.exe. Install the upstream libimobiledevice tools and use -ToolDirectory. See GITHUB_INTEGRATION.md."
}

function Invoke-AppleToolCapture {
    param([string]$ExecutablePath, [string[]]$ToolArguments,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 20)
    # All supported arguments are fixed option/key names or validated UDIDs.
    foreach ($argument in $ToolArguments) {
        if ($argument -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid native tool argument.' }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $ExecutablePath
    $process.StartInfo.Arguments = $ToolArguments -join ' '
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        if (-not $process.Start()) { throw 'Could not start the Apple device tool.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill()
            $process.WaitForExit()
            throw 'Apple device query timed out. Check the USB connection and Apple device services.'
        }
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $stdout.Result.Trim()
            Error = $stderr.Result.Trim()
        }
    } finally { $process.Dispose() }
}

function Invoke-AppleActivationNative {
    param(
        [string]$ExecutablePath,
        [ValidatePattern('^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})$')][string]$Udid
    )
    # Keep interactive Apple server forms in the console. Do not log credentials.
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = $ExecutablePath
    $process.StartInfo.Arguments = "activate -u $Udid"
    $process.StartInfo.UseShellExecute = $false
    $caBundle = Join-Path (Split-Path -Parent $ExecutablePath) 'tr4mpass-ca-bundle.crt'
    if (Test-Path -LiteralPath $caBundle -PathType Leaf) {
        $process.StartInfo.EnvironmentVariables['TR4MPASS_CA_BUNDLE'] = $caBundle
    }
    try {
        if (-not $process.Start()) { throw 'Could not start the upstream activation tool.' }
        $process.WaitForExit()
        return $process.ExitCode
    } finally { $process.Dispose() }
}

function Get-AppleConnectedDeviceIds {
    param([string]$ToolDirectory)
    $tool = Resolve-AppleTool -Name idevice_id -ToolDirectory $ToolDirectory
    $result = Invoke-AppleToolCapture -ExecutablePath $tool -ToolArguments @('-l')
    if ($result.ExitCode -ne 0) {
        throw 'Device enumeration failed. Check the Apple USB driver and usbmuxd service.'
    }
    $ids = @($result.Output -split '\r?\n' | ForEach-Object { $_.Trim() } |
        Where-Object { $_ } | Select-Object -Unique)
    foreach ($id in $ids) {
        if ($id -notmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})$') {
            throw 'Device enumeration returned an invalid identifier.'
        }
    }
    return $ids
}

function Get-AppleDeviceTarget {
    param([string]$Udid, [string]$ToolDirectory)
    $ids = @(Get-AppleConnectedDeviceIds -ToolDirectory $ToolDirectory)
    if ($ids.Count -eq 0) {
        throw 'No normal-mode Apple device is available. Connect the phone, then check the USB driver and trust prompt.'
    }
    if ($Udid) {
        if ($Udid -notin $ids) { throw 'The selected device is not connected.' }
        return $Udid
    }
    if ($ids.Count -ne 1) { throw 'Multiple devices are connected. Select one explicitly with -Udid.' }
    return $ids[0]
}

function Get-AppleDeviceValue {
    param([string]$Udid, [string]$Key, [string]$ToolDirectory)
    $tool = Resolve-AppleTool -Name ideviceinfo -ToolDirectory $ToolDirectory
    $result = Invoke-AppleToolCapture -ExecutablePath $tool -ToolArguments @('-s', '-u', $Udid, '-k', $Key)
    if ($result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Output) -or
        $result.Output -match '[\r\n]') {
        throw "Could not read $Key from the device. Check the USB connection and device access."
    }
    return $result.Output
}

function Invoke-AppleDeviceAction {
    param(
        [ValidateSet('Info', 'State', 'Activate')][string]$Action = 'Info',
        [string]$Udid,
        [string]$ToolDirectory
    )
    if ($Udid -and $Udid -notmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})$') {
        throw 'Invalid device identifier.'
    }
    $target = Get-AppleDeviceTarget -Udid $Udid -ToolDirectory $ToolDirectory
    $result = [ordered]@{ Action = $Action }
    if ($Action -eq 'Info') {
        foreach ($key in @('ProductType', 'ProductVersion', 'HardwareModel')) {
            $result[$key] = Get-AppleDeviceValue -Udid $target -Key $key -ToolDirectory $ToolDirectory
        }
    }
    if ($Action -eq 'Activate') {
        $tool = Resolve-AppleTool -Name ideviceactivation -ToolDirectory $ToolDirectory
        $activationExitCode = Invoke-AppleActivationNative -ExecutablePath $tool -Udid $target
        if ($activationExitCode -ne 0) {
            throw 'The upstream activation tool reported failure. Review the Apple server response shown above.'
        }
    }
    $state = Get-AppleDeviceValue -Udid $target -Key ActivationState -ToolDirectory $ToolDirectory
    $result['ActivationState'] = $state
    if ($Action -eq 'Activate' -and $state -cne 'Activated') {
        throw 'The activation command completed, but the device does not report Activated.'
    }
    # Deliberately omit the selected UDID from the public summary.
    return [pscustomobject]$result
}
