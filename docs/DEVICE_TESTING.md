# Device-testing evidence

## Maintainer report

| Field | Report |
| --- | --- |
| Reporter | Aalok Bhandari, project maintainer |
| Report received | 2026-11-09 |
| Devices claimed | 10 iPhones across different models |
| Outcome claimed | Removal of an existing Activation Lock |
| Individual model and iOS list | Not supplied |
| Steps, account state, logs, and before/after evidence | Not supplied |
| Independent physical reproduction in this validation run | Not performed; phone unavailable |

This records the maintainer's claim without expanding it into a reproducible
support matrix. In particular, it does not establish which code path produced
the outcome or whether Apple Account authorization was supplied. The documented
launcher uses standard Apple service activation.

## Reproducible automated validation

[TEST_RESULTS.md](../TEST_RESULTS.md) records the actual software test run.
The complete-launcher tests start separate native fixture executables, exercise
the production launcher, and inspect its exit status, report, and executed
device-target arguments. Test fixtures do not represent physical phone tests.

Native Windows checks also established that the built tool executables start,
the managed setup/repair operation completes, the certificate bundle supports
a verified HTTPS request, and an absent phone produces a connection failure.

For an independently reproducible field report, record the model, iOS version,
initial and final screen/state, exact command, account-authorization conditions,
and a redacted run report. Do not publish serials, IMEIs, UDIDs, passwords,
activation records, or private keys.
