# Upstream Apple device tool integration

Reviewed on 2026-11-09. Repository source, command documentation, licensing,
maintenance metadata, and the available upstream build result were inspected.
Star counts below are a dated popularity snapshot.

| Upstream repository | Stars | Documented capability | Decision |
| --- | ---: | --- | --- |
| [libimobiledevice/libimobiledevice](https://github.com/libimobiledevice/libimobiledevice) | 8,330 | Device enumeration and lockdown information queries | Integrate `idevice_id` and `ideviceinfo` as installed tools |
| [libimobiledevice/libideviceactivation](https://github.com/libimobiledevice/libideviceactivation) | 372 | Apple web-service activation, including interactive forms | Integrate `ideviceactivation activate` as an explicit action |
| [danielpaulus/go-ios](https://github.com/danielpaulus/go-ios) | 2,321 | Device automation and management | Reviewed; not added as a second overlapping dependency |
| [palera1n/palera1n](https://github.com/palera1n/palera1n) | 6,637 | Jailbreak for A8-A11 and T2 devices | Outside the requested A15 device scope |

Sources for the counts and project status are each repository's GitHub metadata:
[libimobiledevice](https://api.github.com/repos/libimobiledevice/libimobiledevice),
[libideviceactivation](https://api.github.com/repos/libimobiledevice/libideviceactivation),
[go-ios](https://api.github.com/repos/danielpaulus/go-ios), and
[palera1n](https://api.github.com/repos/palera1n/palera1n).

## Source review

The selected command interfaces were inspected at these revisions:

- libimobiledevice: `fa0f79190142bc309307967c058f89c1b36eb6b8`.
  [`ideviceinfo` source](https://github.com/libimobiledevice/libimobiledevice/blob/fa0f79190142bc309307967c058f89c1b36eb6b8/tools/ideviceinfo.c)
- libideviceactivation: `9ca1851a499854033bbaf5f1f7c9b13b93cc7c8e`.
  [`ideviceactivation` source](https://github.com/libimobiledevice/libideviceactivation/blob/9ca1851a499854033bbaf5f1f7c9b13b93cc7c8e/tools/ideviceactivation.c)

The latest retrieved libideviceactivation build workflow completed successfully
for the reviewed commit: [upstream build](https://github.com/libimobiledevice/libideviceactivation/actions/runs/41274540329).
The review revisions identify the inspected interfaces; they are not a claim
that an installed executable was built from those revisions.

The tools are called as separate processes. No upstream source or third-party
binary is bundled. Upstream licenses and notices continue to apply to any
separately installed distribution. See the upstream
[libideviceactivation license documentation](https://github.com/libimobiledevice/libideviceactivation#license).

No reviewed candidate supplied a documented A15 Activation Lock removal chain.
The A15-named search result reviewed during this pass advertised a scanner and
external downloads; it was not selected as a dependency. The implementation
here uses the standard activation interfaces described above. Shared validation
status is recorded in [README.md](README.md#validation-scope).

## Automatic setup

`run-iphone.cmd` performs tool setup and the full device workflow in one
execution. The managed installer bootstraps a checksum-verified portable MSYS2
environment under `%LOCALAPPDATA%\tr4mpass-device-tools`, installs signed UCRT
packages, verifies the pinned activation source archive, applies the checked
transport patch, and compiles the native activation tool. It uses a fresh build
directory and supplies the runtime CA bundle. See [README.md](README.md#quick-start).

The local transport patch enables certificate/hostname verification, HTTPS-only
protocols and redirects, and bounded network waits. Its source is
`windows/harden-activation-source.ps1`; installed build metadata is recorded in
`ucrt64/bin/tr4mpass-build.json`. This is a documented modification to the
inspected upstream source.

## Existing tool installations

Install or build the upstream tools using the maintainers' instructions:
[libimobiledevice](https://github.com/libimobiledevice/libimobiledevice#installation--getting-started)
and [libideviceactivation](https://github.com/libimobiledevice/libideviceactivation#installation--getting-started).
The latter project documents Windows among its tested platforms; its latest
tagged release contains a source archive, not a bundled Windows installer.

On Windows, place the executables and their required runtime DLLs in a directory
such as `C:\AppleTools`, or put that directory on PATH. Apple device drivers
and a working USB connection are also required. The C mock-test environment
described in `WINDOWS_TESTING.md` is separate from the managed native runtime.

Required programs:

- `idevice_id.exe` for connected-device selection.
- `ideviceinfo.exe` for `Info`, `State`, and the post-activation check.
- `ideviceactivation.exe` for `Activate`.

## Commands

You do not need to supply an iOS version. Connect the phone in normal mode and
run the information query:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\apple-device.ps1 -Action Info -ToolDirectory C:\AppleTools
```

The JSON summary includes `ProductType`, `ProductVersion`, `HardwareModel`, and
`ActivationState`. It omits the device UDID. The information query uses
`ideviceinfo -s` to avoid automatically initiating pairing. Devices that deny
the query produce an error instead of a guessed model or OS version.

Read the current activation state:

```powershell
.\apple-device.ps1 -Action State -ToolDirectory C:\AppleTools
```

Explicitly start the upstream standard activation flow:

```powershell
.\apple-device.ps1 -Action Activate -ToolDirectory C:\AppleTools
```

Interactive server forms remain in the upstream tool's console. The adapter
does not capture credential input, enable debug logging, or replace the service
URL. A nonzero tool exit is propagated as failure. After a successful command,
the adapter reads `ActivationState` again and requires `Activated` before
reporting success.

When multiple devices are connected, supply `-Udid` to select one. An absent
device, missing executable, failed query, or ambiguous selection produces an
actionable error. The default `Info` action and `State` action never invoke
activation. The Windows USB launcher remains a separate enumeration check.

## Tests

`tests/test_apple_tools.ps1` runs as part of the Windows diagnostic suite.
Tests cover real subprocess output/exit capture, missing dependencies, selection
of a specific device, argument construction, OS-version queries, invalid
identifiers, failed queries, activation failure, and post-activation state
verification. Device responses and activation calls use fixtures. Run the
complete test runner to regenerate [TEST_RESULTS.md](TEST_RESULTS.md).
