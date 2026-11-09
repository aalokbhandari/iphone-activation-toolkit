param(
    [string]$MsysRoot = (Join-Path $env:LOCALAPPDATA 'tr4mpass-tools\msys64')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$reportDir = Join-Path $PSScriptRoot 'reports'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null

function Invoke-ProjectCheck {
    param([string]$Name, [string]$ScriptPath, [string[]]$ExtraArguments = @())

    $stdout = Join-Path $reportDir ($Name + '.stdout.log')
    $stderr = Join-Path $reportDir ($Name + '.stderr.log')
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
        ('"' + $ScriptPath + '"')) + $ExtraArguments
    Write-Host "Running $Name..."
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') `
        -ArgumentList $arguments -WorkingDirectory $PSScriptRoot `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr `
        -WindowStyle Hidden -Wait -PassThru
    $output = Get-Content -LiteralPath $stdout -Raw
    Write-Host "$Name exited with code $($process.ExitCode)."
    [pscustomobject]@{ ExitCode = $process.ExitCode; Output = $output }
}

$windowsCheck = Invoke-ProjectCheck 'windows-tests' (Join-Path $PSScriptRoot 'tests\test_windows.ps1')
$cCheck = Invoke-ProjectCheck 'c-tests' (Join-Path $PSScriptRoot 'windows\test-c.ps1') `
    @('-MsysRoot', ('"' + $MsysRoot + '"'))
$windowsSummary = [regex]::Match([string]$windowsCheck.Output,
    'Windows diagnostic tests passed: (\d+) assertions\.')
$results = @([regex]::Matches([string]$cCheck.Output, 'Results:\s*(\d+) passed,\s*(\d+) failed') |
    ForEach-Object {
        [pscustomobject]@{ Passed = [int]$_.Groups[1].Value; Failed = [int]$_.Groups[2].Value }
    })
$failedAssertions = @($results | Where-Object { $_.Failed -ne 0 }).Count
$passed = ($windowsCheck.ExitCode -eq 0 -and $cCheck.ExitCode -eq 0 -and
           $windowsSummary.Success -and $results.Count -eq 2 -and $failedAssertions -eq 0)
$report = [pscustomobject][ordered]@{
    TestedAtUtc = [DateTime]::UtcNow.ToString('o')
    Passed = $passed
    WindowsDiagnosticsExitCode = $windowsCheck.ExitCode
    WindowsDiagnosticAssertions = $(if ($windowsSummary.Success) { [int]$windowsSummary.Groups[1].Value } else { 0 })
    CTestsExitCode = $cCheck.ExitCode
    CSuites = $results
    DeviceAndNetworkApisMocked = $true
    PhysicalIphoneTested = $false
    VirtualIphoneBooted = $false
    ValidationScope = 'Software tests with mocked device and network APIs'
    Logs = @('reports/windows-tests.stdout.log', 'reports/windows-tests.stderr.log',
             'reports/c-tests.stdout.log', 'reports/c-tests.stderr.log')
}
$report | ConvertTo-Json -Depth 5 |
    Set-Content -LiteralPath (Join-Path $reportDir 'test-results.json') -Encoding UTF8
$summaryLines = @(
    '# Recorded software test results'
    ''
    "Tested at UTC: $($report.TestedAtUtc)"
    ''
    "Overall result: $(if ($passed) { 'PASS' } else { 'FAIL' })"
    ''
    '| Check | Passed assertions | Exit code |'
    '| --- | ---: | ---: |'
    "| Windows diagnostics and complete launcher | $($report.WindowsDiagnosticAssertions) | $($windowsCheck.ExitCode) |"
)
$suiteNames = @('C hardware-independent units', 'C suite with device and network mocks')
for ($i = 0; $i -lt $results.Count; $i++) {
    $suiteLabel = if ($i -lt $suiteNames.Count) { $suiteNames[$i] } else { 'Unexpected C suite' }
    $summaryLines += "| $suiteLabel | $($results[$i].Passed) ($($results[$i].Failed) failed) | $($cCheck.ExitCode) |"
}
$summaryLines += @(
    ''
    'Reproduce with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-project.ps1`.'
    'The C suite requires the local MSYS2 environment described in [WINDOWS_TESTING.md](WINDOWS_TESTING.md).'
    ''
    'Real libplist and OpenSSL are used. Device, USB, recovery, SSH and HTTP APIs are mocked.'
    'The hardware-independent suite skips sections requiring mocks; those run in the second suite.'
    'Upstream tool integration tests simulate device responses and command results.'
    'See [README.md](README.md) for the validation scope and [GITHUB_INTEGRATION.md](GITHUB_INTEGRATION.md) for upstream setup.'
    ''
    'Machine-readable results: `reports/test-results.json`.'
    'Detailed stdout and stderr logs are under `reports/` and are regenerated locally.'
    'Negative test cases intentionally emit error messages; assertion results and process exit codes determine success.'
)
$summaryLines | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'TEST_RESULTS.md') -Encoding UTF8
foreach ($result in $results) {
    Write-Host "C suite: $($result.Passed) passed, $($result.Failed) failed."
}
Write-Host 'Full results: reports/test-results.json'
Write-Host 'Recorded summary: TEST_RESULTS.md'
if (-not $passed) { exit 1 }
exit 0
