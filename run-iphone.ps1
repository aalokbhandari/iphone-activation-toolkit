[CmdletBinding()]
param(
    [string]$ToolDirectory,
    [string]$MsysRoot,
    [ValidatePattern('^(?:[A-Fa-f0-9]{40}|[A-Fa-f0-9]{8}-[A-Fa-f0-9]{16})$')][string]$Udid,
    [ValidateRange(0, 3600)][int]$WaitSeconds = 120,
    [ValidateRange(0, 600)][int]$ReadySeconds = 30,
    [ValidateRange(0, 600)][int]$VerifySeconds = 30,
    [switch]$InspectOnly,
    [switch]$SkipToolSetup,
    [switch]$RepairTools,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'windows\iphone-workflow.ps1')
if ([string]::IsNullOrWhiteSpace($ReportPath)) { $ReportPath = Join-Path $PSScriptRoot 'reports\iphone-run.json' }
$report = [ordered]@{
    StartedAtUtc = [DateTime]::UtcNow.ToString('o')
    FinishedAtUtc = $null
    Success = $false
    Stage = 'Setup'
    Outcome = 'Pending'
    Mode = $(if ($InspectOnly) { 'Inspect' } else { 'StandardActivation' })
    Device = $null
    ToolVersions = $null
    ActivationExitCode = $null
    FinalActivationState = $null
    Error = $null
}
$workflowExit = 1
try {
    if ($RepairTools -and ($SkipToolSetup -or $ToolDirectory)) { throw '-RepairTools cannot be combined with -SkipToolSetup or -ToolDirectory.' }
    if (-not $MsysRoot) {
        $MsysRoot = Join-Path $env:LOCALAPPDATA 'tr4mpass-device-tools\msys64'
    }
    $resolvedDirectory = Find-AppleToolDirectory -ToolDirectory $ToolDirectory -InspectOnly:$InspectOnly -MsysRoot $MsysRoot
    if ($RepairTools) { $resolvedDirectory = $null }
    if (-not $resolvedDirectory) {
        if ($ToolDirectory -or $SkipToolSetup) { throw 'A complete device tool set was not found. Check -ToolDirectory or run again without -SkipToolSetup.' }
        Invoke-AppleToolSetup -SetupScript (Join-Path $PSScriptRoot 'windows\setup-apple-tools.ps1') -MsysRoot $MsysRoot
        $resolvedDirectory = Find-AppleToolDirectory -InspectOnly:$InspectOnly -MsysRoot $MsysRoot
        if (-not $resolvedDirectory) { throw 'Setup completed but the native device tools are missing.' }
    }
    Invoke-IphoneWorkflow -Udid $Udid -ToolDirectory $resolvedDirectory -InspectOnly:$InspectOnly `
        -WaitSeconds $WaitSeconds -ReadySeconds $ReadySeconds -VerifySeconds $VerifySeconds -Report $report
    $workflowExit = 0
} catch {
    $report['Success'] = $false
    $report['Outcome'] = 'Failed'
    $report['Error'] = $_.Exception.Message
    Write-Host "Workflow failed at $($report['Stage']): $($report['Error'])"
} finally {
    $report['FinishedAtUtc'] = [DateTime]::UtcNow.ToString('o')
    try {
        $fullReportPath = [IO.Path]::GetFullPath($ReportPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $fullReportPath) -Force | Out-Null
        $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $fullReportPath -Encoding UTF8
        Write-Host "Run report: $fullReportPath"
    } catch {
        Write-Host "Could not save the run report: $($_.Exception.Message)"
        $workflowExit = 1
    }
}
exit $workflowExit
