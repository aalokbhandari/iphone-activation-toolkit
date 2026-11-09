# Exercise the real launcher and native process boundaries using fake .exe tools.
$repoRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $repoRoot ('reports\workflow-fixture-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$fixtureExe = Join-Path $fixtureRoot 'idevice_id.exe'
Add-Type -Path (Join-Path $PSScriptRoot 'fixtures\apple-tool-fixture.cs') -OutputAssembly $fixtureExe -OutputType ConsoleApplication
Copy-Item -LiteralPath $fixtureExe -Destination (Join-Path $fixtureRoot 'ideviceinfo.exe')
Copy-Item -LiteralPath $fixtureExe -Destination (Join-Path $fixtureRoot 'ideviceactivation.exe')

function Invoke-WorkflowFixture {
    param([string]$Scenario, [string[]]$ExtraArguments = @(), [string]$InitialState = 'Unactivated', [switch]$UseDefaultReport)
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'scenario.txt') -Value $Scenario -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $fixtureRoot 'state.txt') -Value $InitialState -Encoding ASCII
    foreach ($name in @('calls.log', 'activated.txt', 'enumerated.txt', 'info-seen.txt', 'verification-seen.txt')) {
        $path = Join-Path $fixtureRoot $name
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    $reportFile = Join-Path $fixtureRoot 'run.json'
    $launcherFile = Join-Path $repoRoot 'run-iphone.ps1'
    $reportArgument = '-ReportPath "{0}"' -f $reportFile
    if ($UseDefaultReport) {
        $copyRoot = Join-Path $fixtureRoot 'Project with spaces'
        New-Item -ItemType Directory -Path (Join-Path $copyRoot 'windows') -Force | Out-Null
        Copy-Item -LiteralPath $launcherFile -Destination $copyRoot
        foreach ($name in @('iphone-workflow.ps1', 'apple-tools.ps1')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot ('windows\' + $name)) -Destination (Join-Path $copyRoot 'windows')
        }
        $launcherFile = Join-Path $copyRoot 'run-iphone.ps1'
        $reportFile = Join-Path $copyRoot 'reports\iphone-run.json'
        $reportArgument = ''
    }
    if (Test-Path -LiteralPath $reportFile) { Remove-Item -LiteralPath $reportFile }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = [Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName = Join-Path $PSHOME 'powershell.exe'
    $process.StartInfo.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -ToolDirectory "{1}" {2} -WaitSeconds 0 -ReadySeconds 0 -VerifySeconds 0 ' -f
        $launcherFile, $fixtureRoot, $reportArgument) + ($ExtraArguments -join ' ')
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(20000)) { $process.Kill(); throw "Fixture $Scenario timed out." }
        $output = $stdout.Result
        $errors = $stderr.Result
        if (-not (Test-Path -LiteralPath $reportFile)) { throw "Fixture $Scenario did not save a report: $output $errors" }
        [pscustomobject]@{
            ExitCode = $process.ExitCode
            Report = (Get-Content -LiteralPath $reportFile -Raw | ConvertFrom-Json)
            Calls = @(Get-Content -LiteralPath (Join-Path $fixtureRoot 'calls.log'))
            Json = (Get-Content -LiteralPath $reportFile -Raw)
            Output = $output
        }
    } finally { $process.Dispose() }
}

$run = Invoke-WorkflowFixture 'normal'
Assert-Equal $run.ExitCode 0 'Complete launcher succeeds with a verified fixture state'
Assert-Equal $run.Report.Success $true 'Save successful run status'
Assert-Equal $run.Report.Outcome 'Activated' 'Report activation outcome'
Assert-Equal $run.Report.Device.ProductVersion '18.1' 'Full launcher reads OS version'
Assert-Equal $run.Report.FinalActivationState 'Activated' 'Verify final device state'
Assert-Equal @($run.Calls | Where-Object { $_ -like 'ideviceactivation|activate|*' }).Count 1 'Only one activation request'
Assert-Equal ($run.Json -match '00008030-0000000000000001') $false 'Full run report omits UDID'
$run.Output -split '\r?\n' | Where-Object { $_ -notmatch '^Run report:' } |
    Set-Content -LiteralPath (Join-Path $repoRoot 'reports\workflow-demo.txt') -Encoding UTF8
$run = Invoke-WorkflowFixture 'normal' -UseDefaultReport
Assert-Equal $run.ExitCode 0 'Default report path works from a project path containing spaces'
Assert-Equal $run.Report.Outcome 'Activated' 'Save default run report without an explicit path'

$run = Invoke-WorkflowFixture 'normal' -InitialState 'Activated'
Assert-Equal $run.Report.Outcome 'AlreadyActivated' 'An already activated device completes immediately'
Assert-Equal @($run.Calls | Where-Object { $_ -like 'ideviceactivation|activate|*' }).Count 0 'Do not reactivate an activated phone'

$run = Invoke-WorkflowFixture 'normal' -ExtraArguments @('-InspectOnly')
Assert-Equal $run.Report.Outcome 'Inspected' 'Inspection mode completes'
Assert-Equal @($run.Calls | Where-Object { $_ -like 'ideviceactivation|*' }).Count 0 'Inspection never invokes activation tool'

foreach ($case in @(
    @('broken-runtime', 'Preflight'), @('no-device', 'Connection'),
    @('enumeration-error', 'Connection'), @('multiple', 'Connection'),
    @('info-error', 'DeviceInfo'), @('activation-rejected', 'Activation'),
    @('unverified', 'Verification')
)) {
    $run = Invoke-WorkflowFixture $case[0]
    Assert-Equal $run.ExitCode 1 "Failure exit for $($case[0])"
    Assert-Equal $run.Report.Success $false "Failure report for $($case[0])"
    Assert-Equal $run.Report.Stage $case[1] "Failure stage for $($case[0])"
    Assert-Equal ([bool]$run.Report.Error) $true "Actionable error for $($case[0])"
}
$run = Invoke-WorkflowFixture 'multiple' -ExtraArguments @('-Udid', '00008030-0000000000000002')
Assert-Equal $run.Report.Outcome 'Activated' 'Explicit selection resolves multiple devices'
Assert-Equal @($run.Calls | Where-Object { $_ -match '\|-u\|00008030-0000000000000001' }).Count 0 'All stages stay on the selected device'

# Retry helpers run in-process with short polling intervals; the real launcher
# above already exercises all transport and process boundaries.
. (Join-Path $repoRoot 'windows\iphone-workflow.ps1')
Set-Content -LiteralPath (Join-Path $fixtureRoot 'scenario.txt') -Value 'connect-later' -Encoding ASCII
if (Test-Path (Join-Path $fixtureRoot 'enumerated.txt')) { Remove-Item -LiteralPath (Join-Path $fixtureRoot 'enumerated.txt') }
$target = Wait-AppleDeviceTarget -ToolDirectory $fixtureRoot -TimeoutSeconds 2 -PollMilliseconds 10
Assert-Equal $target '00008030-0000000000000001' 'Wait for a phone that connects after launch'
Set-Content -LiteralPath (Join-Path $fixtureRoot 'scenario.txt') -Value 'transient-info' -Encoding ASCII
$snapshot = Get-AppleDeviceSnapshot -Udid $target -ToolDirectory $fixtureRoot -TimeoutSeconds 2 -PollMilliseconds 10
Assert-Equal $snapshot.ProductVersion '18.1' 'Retry a transient device information failure'
Set-Content -LiteralPath (Join-Path $fixtureRoot 'scenario.txt') -Value 'delayed-verification' -Encoding ASCII
$state = Wait-AppleActivated -Udid $target -ToolDirectory $fixtureRoot -TimeoutSeconds 2 -PollMilliseconds 10
Assert-Equal $state 'Activated' 'Retry a transient verification disconnect'

$found = Find-AppleToolDirectory -ToolDirectory $fixtureRoot
Assert-Equal $found $fixtureRoot 'Find a complete explicit tool directory'
$missing = Find-AppleToolDirectory -ToolDirectory (Join-Path $fixtureRoot 'absent')
Assert-Equal ([bool]$missing) $false 'Do not silently replace an explicit missing directory'
Assert-Throws { Invoke-AppleToolCapture -ExecutablePath $fixtureExe -ToolArguments @('--hang') -TimeoutSeconds 1 } `
    'timed out' 'Terminate a hung native query within its timeout'

$sourceFixture = Join-Path $fixtureRoot 'transport.c'
Set-Content -LiteralPath $sourceFixture -Value 'curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, 0);' -Encoding ASCII
& (Join-Path $repoRoot 'windows\harden-activation-source.ps1') -SourcePath $sourceFixture
$patchedSource = Get-Content -LiteralPath $sourceFixture -Raw
Assert-Equal ($patchedSource -match 'CURLOPT_SSL_VERIFYPEER, 1L') $true 'Enable TLS peer verification'
Assert-Equal ($patchedSource -match 'CURLOPT_SSL_VERIFYHOST, 2L') $true 'Enable TLS hostname verification'
Assert-Equal ($patchedSource -match 'CURLOPT_REDIR_PROTOCOLS_STR, "https"') $true 'Restrict redirect protocol to HTTPS'
Assert-Equal ($patchedSource -match 'CURLOPT_TIMEOUT, 120L') $true 'Bound activation network requests'
Assert-Throws { & (Join-Path $repoRoot 'windows\harden-activation-source.ps1') -SourcePath $sourceFixture } `
    'source has changed' 'Reject an unexpected transport source instead of silently patching it'
$setupFixture = Join-Path $fixtureRoot 'setup-fixture.ps1'
Set-Content -LiteralPath $setupFixture -Value 'param([string]$MsysRoot); [Console]::Error.WriteLine("Expected setup fixture warning"); exit 0' -Encoding ASCII
Invoke-AppleToolSetup -SetupScript $setupFixture -MsysRoot $fixtureRoot
# Reaching this line demonstrates that stderr warnings did not abort setup.
Set-Content -LiteralPath $setupFixture -Value 'param([string]$MsysRoot); exit 5' -Encoding ASCII
Assert-Throws { Invoke-AppleToolSetup -SetupScript $setupFixture -MsysRoot $fixtureRoot } 'Tool setup failed' 'Propagate a failed setup subprocess'
Write-Host 'Full launcher fixture tests completed.'
