# Windows testing

The Windows diagnostic launcher runs with PowerShell 5.1 and does not need
extra software. Double-click `start-windows.cmd`.

For all software tests, run `run-tests.cmd` or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test-project.ps1
```

The runner returns a nonzero exit code if a suite fails or the expected C
results are missing. It writes separate output/error logs and
`reports/test-results.json`. Expected errors from negative test cases are
kept in the logs; they are not counted as test failures unless an assertion
or the test process fails.

## Installed test environment

A portable MSYS2 installation is available at:

```text
%LOCALAPPDATA%\tr4mpass-tools\msys64
```

It does not change the system PATH or install phone drivers. The initial
MSYS2 archive was downloaded from the official release and checked against
its published SHA-256 digest:

```text
msys2-base-x86_64-20260927.tar.xz
ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322
```

The installed tools include GCC, make, pkgconf, OpenSSL development files,
libcurl/libssh2 headers, and the autotools needed to build libplist.
Libplist 2.6.0 was built from its official release into
`/opt/tr4mpass-mocks`. Public libimobiledevice 1.3.0, libirecovery 1.2.1,
and libusb 1.0.27 headers are installed in that same test prefix.

The USB and device pkg-config entries in this prefix supply **headers
only**. Their implementations are replaced by the repository's mocks.
This is a software test environment, not a native Windows build of the
hardware bypass engine. Real libplist and OpenSSL are linked and run.

If MSYS2 is installed elsewhere, pass its root explicitly:

```powershell
.\test-project.ps1 -MsysRoot 'C:\path\to\msys64'
```

`tests/run-msys2.sh` runs the two standard Makefile test targets. The MSYS2
installation and source downloads stay outside the submission folder.

## Rebuilding on another machine

The portable environment is installed on this machine and is not bundled
with the source archive. For a fresh Windows setup, install MSYS2, then
install these packages in its MSYS shell:

```sh
pacman -Syu
pacman -S gcc make pkgconf openssl-devel libssh2-devel libcurl-devel \
  libzstd-devel autoconf automake libtool
```

Build the official libplist release with
`./configure --prefix=/opt/tr4mpass-mocks --without-cython`, followed by
`make` and `make install`. Add the official public device/USB headers and
their headers-only pkg-config entries to that prefix as described above.
Alternatively, a Linux development environment with the normal library
development packages can run `make test test-mocks` directly.

## Device testing

No virtual or physical iPhone is used by these tests. Apple's Simulator is
a Mac/Xcode application-testing tool and does not reproduce every physical
device feature. See [Apple's simulator documentation](https://developer.apple.com/documentation/Xcode/running-your-app-on-simulated-or-physical-devices).
See the [validation scope](README.md#validation-scope) and
[upstream tool integration](GITHUB_INTEGRATION.md) for device-operation setup.
