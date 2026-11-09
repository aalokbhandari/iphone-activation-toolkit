# tr4mpass: hardware usability research and submission report

Author: Aalok Bhandari

Submission review date: 2026-11-09

Scope: research report, Windows diagnostics, upstream tool integration, and software tests.

## Outcome

This submission includes Windows Apple USB detection, recovery transport
regression coverage, automated C software tests, and an adapter for the upstream
libimobiledevice information and standard activation tools. See the shared
[validation scope](../README.md#validation-scope).

The earlier design proposed six phases of broader work. This report records
what is present, what was tested, and what remains deferred. It replaces the
draft's unsupported completion and verification claims. Existing source
attribution and implementation findings were retained.

## Deliverables and reproduction

| Deliverable | Entry point | Evidence |
| --- | --- | --- |
| Native Windows USB diagnostic | `start-windows.cmd` | Queries Windows PnP, with CIM fallback; writes `reports/windows-check.json` |
| Upstream device tool adapter | `apple-device.ps1` | Reads device and OS information; supports explicit standard activation with a subsequent state query |
| Windows diagnostic tests | `tests/test_windows.ps1` | Fixtures exercise filtering, mode classification, privacy, and query failures |
| C unit and mock suites | `test-project.ps1` or `run-tests.cmd` | Runs both Makefile test targets through the local MSYS2 environment |
| Recorded validation | [TEST_RESULTS.md](../TEST_RESULTS.md) | Generated from actual test output and process exit codes |
| Activation data audit | [PATH_B_AUDIT.md](../PATH_B_AUDIT.md) | Traces ownership, placeholders, handshake assumptions, and trust limitations |
| Environment instructions | [WINDOWS_TESTING.md](../WINDOWS_TESTING.md) | Describes dependencies and the headers-only device test libraries |

From the repository directory, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-windows.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-project.ps1
```

The first command is a read-only Windows enumeration check. It does not invoke
the C bypass engine. A successful scan with no device is a valid diagnostic
result. Failure of both enumeration methods is reported as a query error and
returns a nonzero exit code.

The second command requires the MSYS2 setup described in the environment guide.
It regenerates the JSON result, stdout/stderr logs, and `TEST_RESULTS.md`.
On Linux or macOS with development dependencies, the equivalent C targets are
`make test test-mocks`; those platforms were not tested in this review.

The [GitHub integration review](../GITHUB_INTEGRATION.md) records the inspected
upstream revisions, project scope, installation requirements, and usage. The
`Info` action reads the installed iOS version directly when device access is
available; no version is assumed in advance.

`package-submission.ps1` creates `submission/iphone-activation-toolkit.zip` and
`submission/SHA256SUMS.txt` after a successful recorded test run. Its explicit
file list includes source, launchers, this report, and test results. It excludes
the old draft, local device notes containing identifiers, build artifacts,
credentials, and the MSYS2 installation.

## Verified implementation findings

### Windows diagnostics and privacy

`windows/diagnostics.ps1` filters Apple USB vendor `05AC`, excludes composite
interface duplicates, and rejects malformed product IDs. It recognizes DFU
product ID `1227` and all four recovery IDs `1280` through `1283`. Other IDs
remain explicitly unverified for mode and model.

The saved device summaries contain the friendly name, product ID, mode, and
driver status. Raw instance IDs and their serial components are omitted.
USB visibility does not establish the model, chip, OS version, or activation
state. The report labels the requested model separately and leaves
`ModelVerified` false.

The test suite covers PnP success, successful empty enumeration, CIM fallback,
disconnected-device filtering, failure of both queries, serialization of empty
arrays, preservation of driver errors, and exclusion of fixture serials from
the saved report representation.

### Recovery transport

The existing transport changes in `src/bypass/path_b.c` and
`src/bypass/path_b_identity.c` release the DFU handle before recovery access,
recognize all four recovery product IDs, and validate the live libirecovery
mode before serial reads and writes. A failed read-back returns failure.

`tests/test_path_b_recovery.c` exercises the module entry point with mocks,
checks that recovery calls actually occur after DFU handle release, and covers
invalid states and transport failures. This catches the earlier contradiction
where the next stage rejected the deliberately cleared DFU handle.

These assertions establish software control flow. They do not establish that
DFU_ABORT moves a physical phone to recovery, that recovery accepts a serial
write, or that any reported marker changes fused device identity.

### Activation trust boundary

The executed Path B flow collects activation information but does not use that
information to construct a trusted record. Its record builder contains empty
security fields. The offline handshake copies request data into a locally
constructed response and assumes a prior daemon patch that this flow does not
demonstrate installing. See the detailed [data trace](../PATH_B_AUDIT.md).

A locally generated signature can verify against its matching local public key
without being trusted by an iPhone. Similarly, a mocked service response or a
`PWND:` serial marker establishes no server authorization or code execution.
Apple describes activation as requiring a valid activation certificate before
Setup Assistant proceeds. [Apple Activation Lock security](https://support.apple.com/en-gb/guide/security/sec0f8dfd030/web)

## Corrections to the original research claims

| Original claim | Submission finding and decision |
| --- | --- |
| All A11-and-earlier chips satisfy `CPID <= 0x8015` | Incorrect numeric ordering. The local table includes A7 `0x8960` and A6 `0x8950`. Use explicit table entries and capabilities; a numeric CPID range does not encode chip generation. |
| A real iPhone 13 is an A14 test device | Incorrect model mapping. The local table maps the iPhone 13 family to A15 `0x8110`; A14 `0x8101` includes iPhone 12. No physical model was verified here. |
| Fixing T4-T7 makes Path A reliable | Not established. Software tests cannot establish hardware timing reliability or successful activation. |
| SET_DESCRIPTOR or a serial write supplies the missing A12+ primitive | Unsupported. Neither command acceptance nor a string marker supplies evidence of code execution or trusted activation. The current implementation uses an attempted recovery environment write; the old draft's SET_DESCRIPTOR description does not accurately describe that code. |
| `usbliter8` is a ready integration path with verified addresses and scope | The original repository returned 404 during review, and the original publisher's blog reports that it is unavailable. Third-party copies are research leads. The draft's exact mechanics, addresses, publication date, and complete chip scope are not independently verified here. No exploit was integrated. |
| No public A14+ primitive exists, with no imminent research suggesting otherwise | Too broad and time dependent. The defensible project statement is that this submission contains no validated A14+ BootROM implementation or activation unlock. |
| iOS 26.3 universally enforces MEID/ECID-bound activation records in SEP | The repository note is a local research claim, not independent proof of a universal firmware rule. Its described failures do not establish that mechanism or the cutoff for all devices. Do not publish that claim as confirmed. |
| Around 70 GitHub issues are closed by this work | No issue close-out was performed. No live issue counts or individual closure claims are asserted. |

The unavailable original references were checked on 2026-11-09:
[original usbliter8 repository](https://github.com/prdgmshift/usbliter8),
[publisher blog status](https://ps.tc/pages/blog-usbliter8.html).
Unavailability does not show that an exploit never existed. It limits the
primary evidence available to this review.

## Requested adjacent research checks

The requested source search was run against `src`, `include`, and `tests`:

```powershell
rg -n 'FDR-LOCAL|WebSheet|captive|20687|20698|humbug|VU#|SPTM|TXM' src include tests
```

It returned no matches (ripgrep exit code 1 means no match). This establishes
only absence of those strings, not absence of equivalent behavior. It does not
prove exploit integration, safety, or vulnerability of a device.

| Topic | Evidence and assessment |
| --- | --- |
| FDR-LOCAL | Appears in the separate repository note as an unsuccessful reported experiment. No matching implementation or automated regression was found in the searched directories. No fresh device experiment was performed. |
| WebSheet / captive portal | No matching implementation was found. A setup browser surface is not evidence of an activation certificate or an unlock. |
| CVE-2026-20687 | Apple's iOS 26.4 advisory describes an app-triggered kernel use-after-free with possible kernel memory write or system termination, addressed in that release. It does not establish pre-activation reachability or an Activation Lock bypass. |
| CVE-2026-20698 | The same advisory describes app-triggered kernel memory corruption or system termination, addressed in that release. It supplies no bypass chain for this project. |
| `humbug` / JGoyd report | The linked author report alleges provisioning injection and cites HTTP 200 responses with certificate material. This review did not reproduce its effects. An HTTP response alone does not demonstrate persistent device changes or an activation unlock. |
| VU# | No specific public CERT vulnerability-note identifier was supplied. The JGoyd README reports a tracking reference beginning `VRF#`; that does not establish a published VU# advisory or a confirmed finding. |
| SPTM / TXM | No matching code was found in the searched directories. This project has no demonstrated chain through these protections. |

Sources: [Apple iOS 26.4 security advisory](https://support.apple.com/en-am/126792),
[JGoyd README](https://github.com/JGoyd/iOS-Activation-Flaw),
[author's technical report](https://github.com/JGoyd/iOS-Activation-Flaw/blob/main/Technical%20Write%20Up.md).
The JGoyd material is evidence of what its author claims; it is not treated as
independent confirmation of impact. No requests were sent to the described
Apple backend endpoints during this review.

## Chip and OS support statement

The following describes this repository's research-path implementation state.
The upstream standard activation adapter is independent of the chip database.

| Chip family | CPID examples from local table | Research path state |
| --- | --- | --- |
| A5 Rev B / A6 / A6X | `8947`, `8950`, `8955` | Legacy Path A entries |
| A7-A11 | `8960`, `7000`, `8000`, `8010`, `8015` | Path A source and selected mock tests present |
| A12 / A12Z / A13 | `8020`, `8027`, `8030` | Experimental Path B; required trust data and validated primitive absent |
| A14 / A15 / A16 / A17 Pro | `8101`, `8110`, `8120`, `8130` | Identification entries |
| M1 / M2 | `8103`, `8112` | Identification entries |
| Other chips | Not assessed | Unknown; no support inferred |

The checkra1n project's published scope is iPhone 5s through iPhone X. That
project's support does not validate this repository's implementation.
[checkra1n](https://checkra.in/)

For iOS/iPadOS 15+, Apple documents a signed system volume whose seal is checked
at boot. Ordinary root-volume mutation must not be presented as a persistent
supported change. This submission adds no SSV workaround. For iOS 26.3 and
later, no universal SEP enforcement mechanism is claimed by this review.
[Apple signed system volume security](https://support.apple.com/en-ca/guide/security/secd698747c9/web)

## Disposition of the original design tasks

These are review statuses, not declarations that all six original phases have
been completed. Source inspection and mock tests have separate evidentiary scope.

| Task | Status for this submission | Remaining validation or work |
| --- | --- | --- |
| T1 dependency/header normalization | Existing source present: seven dependency names in both lists; installer branches present | Fresh production builds and distro installs not exercised |
| T2 libplist compatibility | Shim present; current mock build runs with real libplist | Old libplist releases not exercised |
| T3 libirecovery compatibility | Shim present; mocked recovery calls compile against installed headers | Historical API versions and real devices not exercised |
| T4 runtime serial index | Runtime descriptor handling present in `usb_dfu.c` | Direct DFU hardware module excluded from mock suite; physical behavior unverified |
| T5 chip table and canary | Table and canary source present; chip lookup tests run | Canonical gadget audit and production canary target not certified by this test run |
| T6 DFU/recovery transport | Existing software regression fixes covered by mocks | Physical re-enumeration, timing, and device selection unverified |
| T7 checkm8 reset ordering | Hardware validation deferred | No claim of fixed physical exploit reliability |
| T8 environment preflight | Native Windows diagnostic available | Broader WSL/macOS/Linux preflight deferred |
| T9 first-run decision tree | Deferred | Model/iOS/mode questionnaire and helper commands not delivered |
| T10 doctor/error taxonomy | Deferred | No `src/cli/doctor.c` or unified typed error subsystem in this checkout |
| T11 honest documentation | Delivered within scope | Physical support matrix cannot be upgraded without evidence |
| T12 Path B replacement/refusal | Research corrected; production retirement deferred | C Path B remains selectable; Windows launcher reports installed upstream tool availability |
| T13 sealed system volume | Documentation corrected | No daemon patch, SSV workaround, or persistent unlock delivered |
| Phase 6 issue close-out | Deferred | No messages posted and no issues closed |

## Validation and limits

Current counts, timestamps, and exit codes are recorded
in [TEST_RESULTS.md](../TEST_RESULTS.md), which is regenerated on every full run.

Real libplist and OpenSSL are used. Device, USB, recovery, SSH, and HTTP APIs are
mocked in the C integration suite. The first suite intentionally skips sections
that require those mocks. Tests named end-to-end exercise software orchestration
against mocks; they are not physical end-to-end activation tests.

The Windows diagnostic tests are hardware independent. Running the diagnostic
launcher checks host enumeration. Full production builds and multi-distro
compatibility remain follow-up work. Shared device-validation status is
recorded in [README.md](../README.md#validation-scope).

The live Windows diagnostic completed successfully during this review and found
no connected Apple USB device. The restricted sandbox denied PnP/CIM access;
an approved read-only invocation outside it completed the host enumeration.

The deliverable includes source, upstream integration instructions, the evidence
review, and recorded software test results.
