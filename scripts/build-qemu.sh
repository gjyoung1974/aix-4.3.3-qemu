#!/usr/bin/env bash
# Build the qemu-system-ppc that can actually boot AIX on the 40p machine.
#
# Needs libgtk-3-dev for the display window ('make boot').
#
# Upstream QEMU (tested: 10.0.13) boots the AIX kernel but never produces a
# console: it runs userspace at 0x10000000 with the MMU on, writes to neither
# UART nor the VGA, and polls forever. Artyom Tarasenko's branch works.
# Its 40p patches (S3 Trio graphics, PCI bus mastering, 53c810 register
# window) were never fully upstreamed.
#
# Nothing is installed system-wide; the binary stays in build/.
set -euo pipefail

REPO=${REPO:-https://github.com/artyom-tarasenko/qemu.git}
BRANCH=${BRANCH:-40p-20190406-aix-boots}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/build/qemu-fork
JOBS=${JOBS:-$(nproc)}

mkdir -p "$ROOT/build"

if [ ! -d "$SRC" ]; then
    echo "==> cloning $BRANCH"
    git clone --depth 1 --branch "$BRANCH" --single-branch "$REPO" "$SRC"
fi

# Local fixes on top of the fork (see patches/README.md). Skipped when a
# patch is already in the tree, so this is safe to rerun.
for p in "$ROOT"/patches/*.patch; do
    [ -e "$p" ] || continue
    if git -C "$SRC" apply --reverse --check "$p" 2>/dev/null; then
        continue
    fi
    echo "==> applying $(basename "$p")"
    git -C "$SRC" apply "$p"
done

# The GTK UI is what 'make boot' draws the S3 framebuffer in; a tree that was
# configured before it was enabled gets reconfigured here.
if [ ! -f "$SRC/config-host.mak" ] || ! grep -q '^CONFIG_GTK=' "$SRC/config-host.mak"; then
    echo "==> configuring"
    # This is 2019-era C. GCC 14 defaults to C23 and makes implicit function
    # declarations and int/pointer conversions hard errors, so demote them.
    (cd "$SRC" && ./configure \
        --target-list=ppc-softmmu \
        --python=/usr/bin/python3 \
        --enable-gtk --disable-vte \
        --disable-sdl --disable-vnc --disable-gnutls \
        --disable-nettle --disable-gcrypt --disable-spice --disable-numa \
        --disable-libxml2 --disable-docs --disable-curses --disable-tpm \
        --disable-glusterfs --disable-opengl --disable-virglrenderer \
        --disable-vhost-user --disable-libssh2 --disable-capstone \
        --disable-tools --disable-werror \
        --extra-cflags="-std=gnu11 \
            -Wno-error=implicit-function-declaration \
            -Wno-error=int-conversion \
            -Wno-error=incompatible-pointer-types")
fi

echo "==> building (-j$JOBS)"
make -C "$SRC" -j "$JOBS"

echo
echo "built: $SRC/ppc-softmmu/qemu-system-ppc"
"$SRC/ppc-softmmu/qemu-system-ppc" --version | head -1
