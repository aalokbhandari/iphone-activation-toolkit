# Run the C software tests using the isolated MSYS2 environment.
param(
    [string]$MsysRoot = (Join-Path $env:LOCALAPPDATA 'tr4mpass-tools\msys64')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash)) {
    throw "MSYS2 test environment missing at $MsysRoot. See WINDOWS_TESTING.md."
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptPath = (Join-Path $repoRoot 'tests\run-msys2.sh').Replace('\', '/')
# Expected negative tests log to stderr. Judge the native process by its
# exit status, so PowerShell does not treat those log lines as exceptions.
$ErrorActionPreference = 'Continue'
& $bash --login $scriptPath
exit $LASTEXITCODE
