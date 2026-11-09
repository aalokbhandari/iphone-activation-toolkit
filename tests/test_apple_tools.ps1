# Dot-sourced by test_windows.ps1. Exercise device selection, upstream command
# construction, and post-activation state checks without contacting a phone.
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\apple-tools.ps1')

function Assert-Throws([scriptblock]$Operation, [string]$Expected, [string]$Message) {
    $caughtMessage = $null
    try { & $Operation | Out-Null } catch { $caughtMessage = $_.Exception.Message }
    Assert-Equal ([bool]($caughtMessage -and $caughtMessage -like "*$Expected*")) $true $Message
}

# Check dependency resolution before replacing process boundaries.
Assert-Throws { Resolve-AppleTool -Name idevice_id -ToolDirectory (Join-Path $PSScriptRoot 'no-tools-installed') } `
    'Missing idevice_id.exe' 'Missing dependency has an actionable error'
$nativeFixture = Invoke-AppleToolCapture -ExecutablePath (Join-Path $PSHOME 'powershell.exe') `
    -ToolArguments @('-NoProfile', '-Command', 'Write-Output', 'query-fixture')
Assert-Equal $nativeFixture.ExitCode 0 'Native capture preserves successful exit code'
Assert-Equal $nativeFixture.Output 'query-fixture' 'Native capture reads actual subprocess stdout'
$nativeFailure = Invoke-AppleToolCapture -ExecutablePath (Join-Path $PSHOME 'powershell.exe') `
    -ToolArguments @('-NoProfile', '-Command', 'exit', '7')
Assert-Equal $nativeFailure.ExitCode 7 'Native capture preserves failed exit code'
Assert-Throws { Invoke-AppleToolCapture -ExecutablePath (Join-Path $PSHOME 'powershell.exe') `
    -ToolArguments @('invalid;argument') } 'Invalid native tool argument' 'Reject command metacharacters'

$script:deviceOne = '00008030-0000000000000001'
$script:deviceTwo = '00008030-0000000000000002'
$script:deviceList = $script:deviceOne
$script:queryExit = 0
$script:queryValue = $null
$script:activationExit = 0
$script:activationCalls = 0
$script:deviceState = 'Unactivated'
$script:toolCalls = @()

function Resolve-AppleTool {
    param([string]$Name, [string]$ToolDirectory)
    return $Name
}
function Invoke-AppleToolCapture {
    param([string]$ExecutablePath, [string[]]$ToolArguments)
    $script:toolCalls += [pscustomobject]@{ Tool = $ExecutablePath; Arguments = $ToolArguments }
    $output = $script:deviceList
    if ($ExecutablePath -eq 'ideviceinfo') {
        $output = switch ($ToolArguments[-1]) {
            ProductType { 'iPhone14,3' }
            ProductVersion { '18.1' }
            HardwareModel { 'D64AP' }
            ActivationState { $script:deviceState }
            default { throw 'Unexpected query key' }
        }
        if ($null -ne $script:queryValue) { $output = $script:queryValue }
    }
    [pscustomobject]@{ ExitCode = $script:queryExit; Output = $output; Error = '' }
}
function Invoke-AppleActivationNative {
    param([string]$ExecutablePath, [string]$Udid)
    $script:activationCalls++
    $script:activatedTarget = $Udid
    return $script:activationExit
}

$info = Invoke-AppleDeviceAction -Action Info
Assert-Equal $info.ProductVersion '18.1' 'Read OS version from the device'
Assert-Equal $info.ProductType 'iPhone14,3' 'Read product type from the device'
Assert-Equal $info.HardwareModel 'D64AP' 'Read board model from the device'
Assert-Equal $info.ActivationState 'Unactivated' 'Read actual activation state'
Assert-Equal (($info | ConvertTo-Json) -match $script:deviceOne) $false 'Summary excludes UDID'
Assert-Equal $script:activationCalls 0 'Info never activates'
Assert-Equal $script:toolCalls[0].Tool 'idevice_id' 'Enumerate with upstream tool'
Assert-Equal ($script:toolCalls[1].Arguments -join ' ') "-s -u $script:deviceOne -k ProductType" 'Use targeted simple query'

$state = Invoke-AppleDeviceAction -Action State
Assert-Equal $state.ActivationState 'Unactivated' 'State query result'
Assert-Equal $script:activationCalls 0 'State never activates'

$script:deviceList = ''
Assert-Throws { Invoke-AppleDeviceAction } 'No normal-mode' 'Diagnose missing phone'
$script:deviceList = "$script:deviceOne`n$script:deviceTwo"
Assert-Throws { Invoke-AppleDeviceAction } 'Multiple devices' 'Do not pick an arbitrary phone'
Invoke-AppleDeviceAction -Action State -Udid $script:deviceTwo | Out-Null
Assert-Equal $script:toolCalls[-1].Arguments[2] $script:deviceTwo 'Target the selected phone'
Assert-Throws { Invoke-AppleDeviceAction -Udid ('a' * 40) } 'not connected' 'Reject absent selected device'
Assert-Throws { Invoke-AppleDeviceAction -Udid '--service' } 'Invalid device identifier' 'Reject option injection'
$script:deviceList = '--service'
Assert-Throws { Invoke-AppleDeviceAction } 'invalid identifier' 'Reject malformed enumeration'
$script:deviceList = $script:deviceOne
$script:queryExit = 2
Assert-Throws { Invoke-AppleDeviceAction } 'enumeration failed' 'Propagate enumeration failure'
$script:queryExit = 0
$script:queryValue = ''
Assert-Throws { Invoke-AppleDeviceAction } 'Could not read ProductType' 'Reject empty device data'
$script:queryValue = "invalid`ndata"
Assert-Throws { Invoke-AppleDeviceAction } 'Could not read ProductType' 'Reject multiline query errors'
$script:queryValue = $null

$script:activationExit = 2
Assert-Throws { Invoke-AppleDeviceAction -Action Activate } 'reported failure' 'Propagate activation tool rejection'
$script:activationExit = 0
Assert-Throws { Invoke-AppleDeviceAction -Action Activate } 'does not report Activated' 'Exit zero alone is not activation success'
$script:deviceState = 'Activated'
$activated = Invoke-AppleDeviceAction -Action Activate
Assert-Equal $activated.ActivationState 'Activated' 'Verify post-activation state'
Assert-Equal $script:activatedTarget $script:deviceOne 'Activation uses the selected device'
