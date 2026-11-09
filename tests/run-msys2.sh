#!/usr/bin/env bash
# Software tests only. The phone, USB services, SSH, and HTTP are mocked.
set -euo pipefail

cd -- "$(dirname -- "$0")/.."
test_prefix="${TR4MPASS_TEST_PREFIX:-/opt/tr4mpass-mocks}"
export PATH="$test_prefix/bin:/usr/bin:/bin:$PATH"
export PKG_CONFIG_PATH="$test_prefix/lib/pkgconfig"

for tool in gcc make pkg-config; do
    if ! command -v "$tool" >/dev/null; then
        printf 'Missing test tool: %s\n' "$tool" >&2
        exit 1
    fi
done

if ! pkg-config --exists libplist-2.0 openssl libusb-1.0 \
    libimobiledevice-1.0 libirecovery-1.0 libssh2 libcurl; then
    printf 'Test dependencies are incomplete under %s. See WINDOWS_TESTING.md.\n' \
        "$test_prefix" >&2
    exit 1
fi

printf 'Running software tests with real libplist and OpenSSL.\n'
printf 'Device, USB, recovery, SSH, and HTTP APIs are mocked.\n'
gcc --version | head -n 1
pkg-config --modversion libplist-2.0 openssl
make test test-mocks CC=gcc
