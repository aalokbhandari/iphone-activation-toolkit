# One workflow, one selected device, and an explicit final state check.
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'apple-tools.ps1')

function Invoke-AppleToolSetup {
    param([string]$SetupScript, [string]$MsysRoot)
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $process.StartInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -MsysRoot "{1}"' -f $SetupScript, $MsysRoot
    $process.StartInfo.UseShellExecute = $false
    try {
        if (-not $process.Start()) { throw 'Could not start device tool setup.' }
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) { throw 'Tool setup failed. Review the build output and README.md first-time setup guide.' }
    } finally { $process.Dispose() }
}

function Find-AppleToolDirectory {
    param([string]$ToolDirectory, [switch]$InspectOnly, [string]$MsysRoot)
    $required = @('idevice_id', 'ideviceinfo')
    if (-not $InspectOnly) { $required += 'ideviceactivation' }
    if ($ToolDirectory) {
        $candidates = @($ToolDirectory)
    } else {
        $candidates = @($env:TR4MPASS_APPLE_TOOLS)
        if ($MsysRoot) { $candidates += Join-Path $MsysRoot 'ucrt64\bin' }
        $candidates += @((Join-Path $env:LOCALAPPDATA 'tr4mpass-device-tools\msys64\ucrt64\bin'), (Join-Path $env:LOCALAPPDATA 'tr4mpass-tools\msys64\ucrt64\bin'), 'C:\msys64\ucrt64\bin')
        foreach ($name in $required) {
            $command = Get-Command ($name + '.exe') -CommandType Application -ErrorAction SilentlyContinue
            if ($command) { $candidates += Split-Path -Parent $command.Source }
        }
    }
    foreach ($candidate in @($candidates | Where-Object { $_ } | Select-Object -Unique)) {
        $complete = $true
        foreach ($name in $required) {
            if (-not (Test-Path -LiteralPath (Join-Path $candidate ($name + '.exe')) -PathType Leaf)) { $complete = $false }
        }
        if ($complete) { return [IO.Path]::GetFullPath($candidate) }
    }
    return $null
}

function Wait-AppleDeviceTarget {
    param([string]$Udid, [string]$ToolDirectory, [int]$TimeoutSeconds = 120, [int]$PollMilliseconds = 1000)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        $ids = @(Get-AppleConnectedDeviceIds -ToolDirectory $ToolDirectory)
        if ($Udid) {
            if ($Udid -in $ids) { return $Udid }
        } elseif ($ids.Count -eq 1) {
            return $ids[0]
        } elseif ($ids.Count -gt 1) {
            throw 'Multiple devices are connected. Select one explicitly with -Udid.'
        }
        if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($true)
    throw 'Connection timed out. Connect the selected iPhone in normal mode, check its data cable and Apple Devices driver, then retry.'
}

function Get-AppleDeviceSnapshot {
    param([string]$Udid, [string]$ToolDirectory, [int]$TimeoutSeconds = 30, [int]$PollMilliseconds = 1000)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $snapshot = [ordered]@{}
            foreach ($key in @('ProductType', 'ProductVersion', 'HardwareModel', 'ActivationState')) {
                $snapshot[$key] = Get-AppleDeviceValue -Udid $Udid -Key $key -ToolDirectory $ToolDirectory
            }
            return [pscustomobject]$snapshot
        } catch {
            if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                throw 'Device information is not accessible. Keep the same phone connected in normal mode; unlock it and accept Trust if offered, then retry.'
            }
        }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($true)
}

function Wait-AppleActivated {
    param([string]$Udid, [string]$ToolDirectory, [int]$TimeoutSeconds = 30, [int]$PollMilliseconds = 1000)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    do {
        try {
            $state = Get-AppleDeviceValue -Udid $Udid -Key ActivationState -ToolDirectory $ToolDirectory
            if ($state -ceq 'Activated') { return $state }
        } catch {
            # A brief reconnect during the final state query is retryable.
        }
        if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ($true)
    throw 'The device did not report Activated within the verification timeout. Check the Apple server response and the phone screen.'
}

function Invoke-IphoneWorkflow {
    param(
        [string]$Udid, [string]$ToolDirectory, [switch]$InspectOnly,
        [int]$WaitSeconds = 120, [int]$ReadySeconds = 30, [int]$VerifySeconds = 30,
        [int]$PollMilliseconds = 1000,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$Report
    )
    try {
        if ($Udid -and $Udid -notmatch '^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})$') {
            throw 'Invalid device identifier.'
        }
        $Report['Stage'] = 'Preflight'
        Write-Host '[1/5] Checking device tools and runtime libraries...'
        $required = @('idevice_id', 'ideviceinfo')
        if (-not $InspectOnly) { $required += 'ideviceactivation' }
        $versions = [ordered]@{}
        foreach ($name in $required) {
            $executable = Resolve-AppleTool -Name $name -ToolDirectory $ToolDirectory
            $version = Invoke-AppleToolCapture -ExecutablePath $executable -ToolArguments @('--version')
            if ($version.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($version.Output)) {
                throw "$name could not start correctly. Check its runtime DLLs or rerun tool setup."
            }
            $versions[$name] = $version.Output
        }
        $Report['ToolVersions'] = $versions
        $Report['Stage'] = 'Connection'
        Write-Host '[2/5] Waiting for the selected iPhone in normal mode...'
        $target = Wait-AppleDeviceTarget -Udid $Udid -ToolDirectory $ToolDirectory -TimeoutSeconds $WaitSeconds -PollMilliseconds $PollMilliseconds
        $Report['Stage'] = 'DeviceInfo'
        Write-Host '[3/5] Reading model, installed iOS version, and activation state...'
        $device = Get-AppleDeviceSnapshot -Udid $target -ToolDirectory $ToolDirectory -TimeoutSeconds $ReadySeconds -PollMilliseconds $PollMilliseconds
        $Report['Device'] = $device
        Write-Host "Detected $($device.ProductType), iOS $($device.ProductVersion); state: $($device.ActivationState)"
        if ($InspectOnly) {
            $Report['Outcome'] = 'Inspected'
        } elseif ($device.ActivationState -ceq 'Activated') {
            Write-Host '[4/5] Device is already activated; no server request is needed.'
            $Report['Outcome'] = 'AlreadyActivated'
        } else {
            $Report['Stage'] = 'Activation'
            Write-Host '[4/5] Starting standard Apple server activation. Follow any server prompts.'
            $tool = Resolve-AppleTool -Name ideviceactivation -ToolDirectory $ToolDirectory
            $activationExit = Invoke-AppleActivationNative -ExecutablePath $tool -Udid $target
            $Report['ActivationExitCode'] = $activationExit
            if ($activationExit -ne 0) {
                throw 'The upstream activation tool reported failure. Review the Apple server response shown above.'
            }
            $Report['Stage'] = 'Verification'
            Write-Host '[5/5] Verifying the final state on the same device...'
            $Report['FinalActivationState'] = Wait-AppleActivated -Udid $target -ToolDirectory $ToolDirectory -TimeoutSeconds $VerifySeconds -PollMilliseconds $PollMilliseconds
            $Report['Outcome'] = 'Activated'
        }
        if ($Report['Outcome'] -ne 'Activated') { $Report['FinalActivationState'] = $device.ActivationState }
        $Report['Success'] = $true
        $Report['Stage'] = 'Complete'
        Write-Host "Workflow complete: $($Report['Outcome'])."
    } catch {
        $Report['Success'] = $false
        $Report['Outcome'] = 'Failed'
        $Report['Error'] = $_.Exception.Message
        throw
    }
}
