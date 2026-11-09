# Package an explicit list of source and report files; do not bundle local
# device notes, credentials, binaries, the Git directory, or tool installations.
param([string]$ExportDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$resultPath = Join-Path $root 'reports\test-results.json'
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if (-not $result.Passed -or $result.WindowsDiagnosticsExitCode -ne 0 -or
    $result.CTestsExitCode -ne 0 -or $result.WindowsDiagnosticAssertions -le 0 -or
    @($result.CSuites).Count -ne 2 -or
    @($result.CSuites | Where-Object { $_.Failed -ne 0 }).Count -ne 0) {
    throw 'Run test-project.ps1 successfully before packaging the submission.'
}

$paths = @(
    'README.md', 'TEST_RESULTS.md', 'PATH_B_AUDIT.md', 'WINDOWS_TESTING.md',
    'WORKFLOW_REVIEW.md', 'CONTRIBUTING.md', 'NOTICE.md', '.gitattributes',
    'Makefile', 'start.sh', 'start-helpers.sh', 'start-windows.cmd',
    'start-windows.ps1', 'run-tests.cmd', 'test-project.ps1',
    'package-submission.ps1', 'apple-device.ps1', 'GITHUB_INTEGRATION.md',
    'run-iphone.cmd', 'run-iphone.ps1',
    'research/fix-issues-hw-usability.md',
    'reports/test-results.json',
    'docs/DEVICE_TESTING.md', 'docs/assets/hero.svg', 'docs/assets/tests.svg',
    'docs/assets/workflow-demo.png', 'docs/assets/workflow-demo.gif', 'docs/assets/workflow-demo.mp4',
    'scripts/render-demo.py', '.github/workflows/tests.yml', '.github/ISSUE_TEMPLATE/bug_report.yml'
)
foreach ($directory in @('src', 'include', 'tests', 'windows')) {
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $root $directory) -File -Recurse)) {
        if ($file.Extension -in @('.c', '.h', '.sh', '.ps1', '.cs')) {
            $paths += $file.FullName.Substring($root.Length + 1).Replace('\', '/')
        }
    }
}
$paths = @($paths | Sort-Object -Unique)
foreach ($relativePath in $paths) {
    if (-not (Test-Path -LiteralPath (Join-Path $root $relativePath) -PathType Leaf)) {
        throw "Required submission file is missing: $relativePath"
    }
}

if ($ExportDirectory) {
    $exportRoot = [IO.Path]::GetFullPath($ExportDirectory)
    if ((Test-Path -LiteralPath $exportRoot) -and @(Get-ChildItem -LiteralPath $exportRoot -Force).Count -ne 0) {
        throw 'Source export requires a new or empty directory.'
    }
    New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
    foreach ($relativePath in $paths) {
        if ($relativePath.StartsWith('reports/')) { continue }
        $destination = Join-Path $exportRoot $relativePath
        New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $root $relativePath) -Destination $destination
    }
    @('reports/', 'submission/', '*.o', '*.exe', '*.obj', '*.dll', '*.pyc', '__pycache__/',
      'tests/run_tests', 'tests/run_mock_tests', 'tests/chip_db_canary.bin', '.build-flags',
      '.env', '.env.*', '*.pem', '*.key', 'credentials.*', 'secrets.*',
      '.codex/', '.claude/', '.agents/', 'AGENTS.md', 'CLAUDE.md', 'notes/', 'scratchpad/') |
        Set-Content -LiteralPath (Join-Path $exportRoot '.gitignore') -Encoding ASCII
    Write-Host "Clean source export: $exportRoot"
    exit 0
}

$outputDir = Join-Path $root 'submission'
New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
$archivePath = Join-Path $outputDir 'iphone-activation-toolkit.zip'
$stream = [IO.File]::Open($archivePath, [IO.FileMode]::Create)
$archive = $null
try {
    $archive = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create)
    foreach ($relativePath in $paths) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, (Join-Path $root $relativePath), $relativePath,
            [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally {
    if ($null -ne $archive) { $archive.Dispose() }
    $stream.Dispose()
}
$digest = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
"$digest  iphone-activation-toolkit.zip" |
    Set-Content -LiteralPath (Join-Path $outputDir 'SHA256SUMS.txt') -Encoding ASCII
Write-Host "Packaged $($paths.Count) files: $archivePath"
Write-Host "SHA-256: $digest"
