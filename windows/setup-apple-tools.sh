#!/usr/bin/env bash
# Build the reviewed upstream activation tool against native Windows UCRT libs.
set -euo pipefail
export PATH="/ucrt64/bin:/usr/bin:/bin:$PATH"
export PKG_CONFIG_PATH=/ucrt64/lib/pkgconfig
export ACLOCAL_PATH=/ucrt64/share/aclocal
unset PKG_CONFIG_LIBDIR

source_root="$(cygpath -u "$1")"
mkdir -p "$source_root"
# Native Windows curl works with the host's network configuration. Pacman still
# verifies every package signature; this only selects its download transport.
native_curl="$(cygpath -u "$2")"
pacman_config="$source_root/pacman-native-download.conf"
awk -v transport="$native_curl" '/^\[options\]/{print; print "XferCommand = " transport " --fail --location --retry 2 --connect-timeout 15 --max-time 180 -o \"%o\" \"%u\"";next}{print}' \
  /etc/pacman.conf > "$pacman_config"
pacman --config "$pacman_config" -Syu --needed --noconfirm \
  mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-pkgconf \
  mingw-w64-ucrt-x86_64-libimobiledevice mingw-w64-ucrt-x86_64-curl \
  mingw-w64-ucrt-x86_64-libxml2 autoconf automake libtool make curl

source_revision=9ca1851a499854033bbaf5f1f7c9b13b93cc7c8e
source_archive="$source_root/libideviceactivation-$source_revision.tar.gz"
"$native_curl" --fail --location --retry 3 --connect-timeout 15 --max-time 120 \
  "https://codeload.github.com/libimobiledevice/libideviceactivation/tar.gz/$source_revision" \
  --output "$source_archive"
printf '%s  %s\n' f8a13045516bcac7e4e976177e51b9b40a9956fb50d9349b70ba97ba9d40ae7d "$source_archive" | sha256sum -c -
build_root="$(mktemp -d "$source_root/activation-build.XXXXXX")"
tar -xzf "$source_archive" -C "$build_root"
cd "$build_root/libideviceactivation-$source_revision"
printf '1.1.1+git.9ca1851.tr4mpass\n' > .tarball-version
native_powershell="$(dirname "$native_curl")/WindowsPowerShell/v1.0/powershell.exe"
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
"$native_powershell" -NoProfile -ExecutionPolicy Bypass -File "$(cygpath -w "$script_dir/harden-activation-source.ps1")" -SourcePath "$(cygpath -w "$PWD/src/activation.c")"
./autogen.sh --prefix=/ucrt64 --host=x86_64-w64-mingw32 --disable-static
make -j2
make install
cp /ucrt64/etc/ssl/certs/ca-bundle.crt /ucrt64/bin/tr4mpass-ca-bundle.crt
idevice_id --version
ideviceinfo --version
ideviceactivation --version
