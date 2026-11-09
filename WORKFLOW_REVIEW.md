# Workflow engineering review

Reviewed 2026-11-09. The following scores are a project self-review, not an
external audit or a measured hardware-success percentage.

| Area | Rating | Basis |
| --- | --- | --- |
| Workflow engineering | 8/10 | One launcher, bounded queries, explicit stages, one device target, final-state verification, and complete-process fixture coverage |
| Research and approach selection | 8/10 | Primary-source interfaces, pinned activation source, verified bootstrap/archive checksums, and separation of claims from demonstrated behavior |
| First-run reproducibility | 8/10 | Portable per-user bootstrap and actual native build exercised; Windows drivers, internet access, and platform-specific access remain external prerequisites |
| Physical model coverage | Unscored | No phone was available for this validation; the separate ten-device maintainer claim lacks a reproducible device matrix |

## Improvements implemented

1. **Inspect first.** Read model, OS version, and state rather than guessing a chip or firmware from a requested model.
2. **Pin the target.** Every later read and activation uses the same selected UDID. Multiple devices never trigger an arbitrary choice.
3. **Skip unnecessary activation.** An already activated device completes without another server request.
4. **Retry the reversible queries.** Delayed attachment, briefly inaccessible information, and transient verification disconnects are handled within configured budgets.
5. **Do not retry activation automatically.** Submit one activation command and surface rejection; avoid repeatedly sending state-changing requests.
6. **Verify the outcome.** A successful command exit is followed by a device-side state query. Unverified state is a failure.
7. **Make startup failures early.** Run native version checks before phone operations, and provide a repair option for the managed tool environment.
8. **Secure the transport.** The inspected upstream source disabled TLS peer verification. The managed build enables peer/hostname verification, supplies a CA bundle, restricts requests/redirects to HTTPS, and bounds network waits.
9. **Test the actual launcher.** Separate fixture executables exercise process startup, argument passing, reports, failure stages, and the default-path behavior.

The TLS change is a small, checked local patch applied after verifying the
upstream source archive. It does not modify activation credentials or Apple's
authorization rules. Source mismatch stops the patch/build.
[Inspected upstream transport](https://github.com/libimobiledevice/libideviceactivation/blob/9ca1851a499854033bbaf5f1f7c9b13b93cc7c8e/src/activation.c)

## Modern alternatives and logical feasibility

| Approach | Primary-source capability | Assessment for this project |
| --- | --- | --- |
| Apple Devices on Windows | Apple's supported device connection and management path | Preferred prerequisite and practical driver/connectivity reference; the custom launcher cannot replace required Apple authorization |
| libideviceactivation | Session activation through Apple's service, with interactive forms | Selected native backend; its interface is documented and its local build is exercised |
| pymobiledevice3 | Modern cross-platform device management, discovery, developer services, and activation-related services | A credible future backend if Python deployment is desired; adding it now would duplicate the selected backend and multiply setup/testing paths |
| go-ios | Cross-platform device automation | Useful for broader automation; its documented management scope does not by itself prove Activation Lock removal |
| Dopamine | Version/chip-constrained rootless jailbreak | A jailbreak app's documented support does not establish a pre-activation path to run it or an activation certificate; unknown iOS prevents assuming compatibility |
| palera1n | A8-A11/T2 jailbreak | Does not supply the requested A15 implementation |
| usbliter8 claims and mirrors | A12/A13-related BootROM research leads; original cited resources were unavailable in the earlier review | No reviewed, integrated A15 activation chain was established; popularity or a mirror is not device-side proof |

Sources: [Apple connection guide](https://support.apple.com/en-us/108643),
[libideviceactivation](https://github.com/libimobiledevice/libideviceactivation),
[pymobiledevice3](https://github.com/doronz88/pymobiledevice3),
[go-ios](https://github.com/danielpaulus/go-ios),
[Dopamine 3.x README](https://github.com/opa334/Dopamine/blob/3.x/README.md),
[palera1n](https://github.com/palera1n/palera1n).

The logical gap matters: evidence of USB visibility, kernel execution, a
jailbreak, or an HTTP success response does not imply that the device obtained
and accepted activation authorization. A stronger claim needs a demonstrated
chain across those boundaries. This review does not infer that chain from
repository stars or from unsupported cross-generation assumptions.

The implemented approach favors a small number of well-defined operations with
observable outcomes. The [device evidence ledger](docs/DEVICE_TESTING.md)
records the maintainer report separately from automated validation.
