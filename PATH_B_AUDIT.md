# Path B recovery fix and activation data trace

The recovery fix removes an inconsistent transport prerequisite. This audit
records the executed flow and activation data dependencies.

## First failure and regression

`src/bypass/path_b.c:step_reboot_to_recovery()` sends DFU_ABORT, closes
the DFU handle, sets `dev->usb = NULL`, clears `dev->is_dfu_mode`, and
polls for recovery. Previously, `path_b_manipulate_identity()` immediately
rejected the resulting NULL handle before reaching the existing recovery
serial reader.

Identity manipulation now requires the DFU state to have been released.
The recovery serial reader opens libirecovery using the device ECID
(or its existing any-device fallback when ECID is zero), checks
`irecv_get_mode()` for recovery modes 0x1280 through 0x1283, and closes
the connection on completion or validation failure. This validation also
runs before the early return for an existing serial marker. The write
function independently checks the recovery connection again.

`tests/test_path_b_recovery.c` runs the real module entry point through
the transition, then stages a write error to stop before the normal-mode
reboot and activation stages. It asserts that the DFU handle was cleared
and that recovery mode queries, serial reads, and the attempted write
actually happened. A failure return alone would miss the original bug.
Other cases cover all four recovery modes, missing devices, invalid
modes, empty serials, unreleased DFU state, and a mocked write/read-back.
These tests are included in `make test-mocks`.

## Activation data ownership and use

| Value | Producer and inputs | Consumer and lifetime |
| --- | --- | --- |
| `session` | `session_get_info(dev, &session)` calls the device's session-info API. | Passed to `session_drm_handshake`; freed before `step_session_handshake` returns. |
| `response` | `session_drm_handshake(dev, session, &response)` constructs a local dict, copying `HandshakeRequestMessage` into `HandshakeResponseMessage` and adding empty fields. | Copied by `session_create_activation_info`, with `BasebandWaitCount=90` added to the copy sent to the device. The original is also passed to `step_activate` and `session_activate`; freed by `path_b_execute`. |
| `info` | `session_create_activation_info(dev, response, &info)` gets activation information from the device. | Returned to `path_b_execute`. Its contents are never read or used to construct the submitted record; it is freed after either activation failure or completion. |
| `record` | `step_activate(dev, response)` calls `record_build_a12(dev)`. This builder receives neither `info` nor `response`. | Passed with `response` to `session_activate`, which calls `mobileactivation_activate_with_session`. Freed by `step_activate`. |

`record_build_a12()` delegates to `record_build_a12_with_client(dev, NULL)`.
Consequently, Path B does not request live certificate extraction here,
even if `dev->lockdown` is available. Certificate fields are empty
placeholders. `FairPlayKeyData`, `RKCData`, and `SepNonce` are also empty.
The account token is constructed from fields in `dev`.

Receiving `info` successfully proves only that the device API returned
information. There is no transformation of that information into a
trusted activation record in this Path B flow. The separate online flow
in `src/main.c` forwards its activation info to
`session_device_activation_online`; Path B does not call that function.

## Handshake and signatures

`src/activation/session.c:build_offline_handshake()` copies the request
message into the response and supplies empty `FDRBlob` and `serverKP`
data plus an empty `SUInfo` dict. Its acceptance depends on an assumed
prior daemon patch. Path B's executed stages do not demonstrate installing
such a patch. Writing or reading a `PWND:` string is not proof of code
execution, disabled signature verification, or device acceptance.

`src/activation/record.c:set_account_token_signature()` optionally signs
the serialized token node using `TR4MPASS_SIGNING_KEY`. This can establish
a signature verifiable with the matching public key; it does not
establish that the phone trusts that key or the record. The signer unit
tests exercise local key generation, signing, and verification, not the
phone's trust checks. Replacing empty fields with arbitrary bytes would
not supply evidence of valid signatures, certificates, or session data.

## Verification and remaining limits

On this Windows host, the focused C build uses the real `path_b.c`,
`path_b_identity.c`, USB helpers, logger, and existing recovery/USB mocks
with official library headers. Unrelated later stages are fail-fast
stubs in a temporary runner. Before the production fix, the initial
regression run reported 23 passing and 21 failing assertions, including
the missing recovery calls immediately after the transition. After the
fix and additional write/read-back cases, all 56 assertions pass.
The updated integration test and test-runner wiring also passed GCC syntax
checks at that stage. The full suite was not available during the initial
fix; the subsequent submission run below installs the missing test tools.
The syntax check of `record.c` suppresses the old MinGW compiler's format
diagnostic for the existing `%llu` use; the focused transport build uses
`-Wall -Wextra -Werror`, with only host `usleep` deprecation suppressed.

## Submission follow-up

A portable MSYS2 test environment is now installed, with real libplist and
OpenSSL. `test-project.ps1` runs Windows diagnostic tests plus `make test`
and `make test-mocks`; see `TEST_RESULTS.md` for the recorded results.

The transition poll now recognizes all four recovery product IDs. The
read-back-failure branch now returns an error instead of reporting success.
The latter regression was reproduced before the change (58 focused
assertions passed and one failed). Added coverage exercises transitions
through each recovery ID and a connection failure specifically during
read-back. Two mocks also used fields absent from the official library
headers; those incompatible accesses were removed.

The mocks simulate command acceptance and serial read-back. The standard
activation adapter is documented separately in [GITHUB_INTEGRATION.md](GITHUB_INTEGRATION.md).
See [README.md](README.md#validation-scope) for the shared validation scope.
