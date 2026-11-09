[CmdletBinding()]
param([string]$MsysRoot = (Join-Path $env:LOCALAPPDATA 'tr4mpass-device-tools\msys64'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
    $toolsHome = Split-Path -Parent $MsysRoot
    if ((Split-Path -Leaf $MsysRoot) -ne 'msys64') { throw 'For automatic setup, -MsysRoot must end in msys64.' }
    New-Item -ItemType Directory -Path $toolsHome -Force | Out-Null
    $archiveName = 'msys2-base-x86_64-20260927.tar.xz'
    $expectedHash = 'ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322'
    $archivePath = Join-Path $toolsHome $archiveName
    $existingArchive = Join-Path $env:LOCALAPPDATA ('tr4mpass-tools\' + $archiveName)
    if ((Test-Path -LiteralPath $existingArchive) -and
        (Get-FileHash -LiteralPath $existingArchive -Algorithm SHA256).Hash.ToLowerInvariant() -eq $expectedHash) {
        Copy-Item -LiteralPath $existingArchive -Destination $archivePath
    } elseif (-not (Test-Path -LiteralPath $archivePath) -or
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        Write-Host 'Downloading the official portable MSYS2 bootstrap...'
        & (Join-Path ([Environment]::SystemDirectory) 'curl.exe') --fail --location --retry 2 --connect-timeout 15 --max-time 300 `
            ('https://github.com/msys2/msys2-installer/releases/download/2026-09-27/' + $archiveName) --output $archivePath
        if ($LASTEXITCODE -ne 0) { throw 'The official MSYS2 download failed. Check the internet connection and retry.' }
    }
    if ((Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        throw 'MSYS2 bootstrap checksum mismatch. Extraction was stopped.'
    }
    Write-Host 'Extracting the verified portable tool environment...'
    & (Join-Path ([Environment]::SystemDirectory) 'tar.exe') -xf $archivePath -C $toolsHome
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract the MSYS2 bootstrap.' }
    $existingCache = Join-Path $env:LOCALAPPDATA 'tr4mpass-tools\msys64\var\cache\pacman\pkg'
    $newCache = Join-Path $MsysRoot 'var\cache\pacman\pkg'
    if (Test-Path -LiteralPath $existingCache) {
        New-Item -ItemType Directory -Path $newCache -Force | Out-Null
        Get-ChildItem -LiteralPath $existingCache -File |
            Where-Object { $_.Name -match '\.pkg\.tar\.(?:zst|xz)(?:\.sig)?$' } |
            Copy-Item -Destination $newCache
    }
}
$sourceRoot = Join-Path (Split-Path -Parent $MsysRoot) 'sources'
$setupScript = (Join-Path $PSScriptRoot 'setup-apple-tools.sh').Replace('\', '/')
Write-Host 'Installing official MSYS2 packages and building the reviewed upstream activation tool...'
$ErrorActionPreference = 'Continue'
for ($attempt = 1; $attempt -le 2; $attempt++) {
    & $bash --login $setupScript ($sourceRoot.Replace('\', '/')) ((Join-Path ([Environment]::SystemDirectory) 'curl.exe').Replace('\', '/'))
    if ($LASTEXITCODE -eq 0) { break }
    if ($attempt -eq 2) { throw 'Upstream tool setup failed. See the preceding build output and README.md troubleshooting guide.' }
    Write-Host 'Restarting the setup shell once; a fresh MSYS2 core update can require this.'
}
Write-Host "Native device tools installed in $(Join-Path $MsysRoot 'ucrt64\bin')."
$buildRecord = [ordered]@{
    BuiltAtUtc = [DateTime]::UtcNow.ToString('o')
    Source = 'https://github.com/libimobiledevice/libideviceactivation'
    Commit = '9ca1851a499854033bbaf5f1f7c9b13b93cc7c8e'
    SourceArchiveSha256 = 'f8a13045516bcac7e4e976177e51b9b40a9956fb50d9349b70ba97ba9d40ae7d'
    TlsPeerAndHostnameVerification = $true
    HttpsOnlyRedirects = $true
    ConnectTimeoutSeconds = 15
    RequestTimeoutSeconds = 120
}
$buildRecord | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $MsysRoot 'ucrt64\bin\tr4mpass-build.json') -Encoding UTF8
exit 0
