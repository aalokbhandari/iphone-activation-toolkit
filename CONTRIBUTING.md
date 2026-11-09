# Contributing

Start with a reproducible failure and the stage shown in `reports/iphone-run.json`.
Include the Windows version, iPhone model, iOS version, exact command, and
redacted error. Never include device identifiers, passwords, keys, certificates,
or complete activation records.

Run the hardware-independent Windows tests:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test_windows.ps1
```

Run `make test test-mocks` on Linux with the development libraries installed.
On the configured Windows development environment, `test-project.ps1` combines
both C suites with the Windows workflow tests.

Changes to the launcher should include a meaningful regression in
`tests/test_iphone_workflow.ps1`. Its native fixtures run the real launcher;
they must remain clearly distinguished from physical-device testing.

Source bootstrap changes must keep archive/checksum verification and package
signature verification. Update the recorded source revision, hash, transport
patch check, documentation, and build metadata together.

Keep device-target selection explicit and retain upstream attribution. Do not
mark a chip/OS combination supported from a marketing name or a successful mock.
