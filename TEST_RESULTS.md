# Recorded software test results

Tested at UTC: 2026-11-09T04:47:45.7959955Z

Overall result: PASS

| Check | Passed assertions | Exit code |
| --- | ---: | ---: |
| Windows diagnostics and complete launcher | 121 | 0 |
| C hardware-independent units | 58 (0 failed) | 0 |
| C suite with device and network mocks | 337 (0 failed) | 0 |

Reproduce with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-project.ps1`.
The C suite requires the local MSYS2 environment described in [WINDOWS_TESTING.md](WINDOWS_TESTING.md).

Real libplist and OpenSSL are used. Device, USB, recovery, SSH and HTTP APIs are mocked.
The hardware-independent suite skips sections requiring mocks; those run in the second suite.
Upstream tool integration tests simulate device responses and command results.
See [README.md](README.md) for the validation scope and [GITHUB_INTEGRATION.md](GITHUB_INTEGRATION.md) for upstream setup.

Machine-readable results: `reports/test-results.json`.
Detailed stdout and stderr logs are under `reports/` and are regenerated locally.
Negative test cases intentionally emit error messages; assertion results and process exit codes determine success.
