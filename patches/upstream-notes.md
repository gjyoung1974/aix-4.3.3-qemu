# Upstreaming the Raven I/O window fix

QEMU's contribution policy (`docs/devel/code-provenance.rst`, "Use of
AI-generated content") declines any contribution believed to include or
derive from AI-generated content, and its `AGENTS.md` tells agents to
refuse to prepare upstream changes. Debugging and analysis are allowed as
long as their output is not part of the contribution. The notes below are
that analysis. The patch and its commit message have to be written by the
person who signs the DCO, so none of that is prepared here, and the
`0001-prep-contiguous-pci-io-linear.patch` next to this file (written with
Claude for the local fork build) must not be sent upstream as is.

## The bug

`hw/pci-host/raven.c`, `raven_io_address()` (lines 113-115 at commit
`8967b2f`, 2026-10-20):

```c
    if (s->contiguous_map == 0) {
        /* 64 KB contiguous space for IOs */
        addr &= 0xFFFF;
    } else {
```

`pci_io_non_contiguous` is an 8 MB region overlaid at priority 1 on the
linear `pci-io` window at `PCI_IO_BASE_ADDR` (`0x80000000`). In the default
contiguous mode it masks the offset to 16 bits before reading `pci_io_as`,
so any PCI I/O port in `0x10000..0x7FFFFF` is redirected onto the ISA
block at the bottom of the window. The same code exists in QEMU 10.0.13
and in the 2019 40p fork, so it predates the raven.c refactoring.

PReP Memory Map A defines CPU `0x80000000..0xBF7FFFFF` as a linear map of
PCI I/O `0x00000000..0x3F7FFFFF`; the 8 MB "non-contiguous" spread applies
only when the mode bit is set. Check the exact section in the PowerPC
Reference Platform Specification 1.1 before citing it.

## How it shows

AIX 4.3.3 on the 40p assigns `busio 0x10000` to its PCI Ethernet adapter
(`22100020`, driven by `pcnet` in QEMU). With `-trace 'pcnet_*,pci_cfg_*'`:

```
pci_cfg_write pcnet 03:0 @0x10 <- 0x10000      # BAR0
pci_cfg_write pcnet 03:0 @0x4  <- 0x145        # I/O + bus master enable
pci_update_mappings_add ... 00:03.0 0,0x10000+0x20
```

and after that not a single `pcnet_ioport_read/write` event, while the
driver logged `KENT_ADAP_ERR` (`kent_open.c:513`) on every open and read
its MAC as `00:00:00:00:00:00`. Removing the mask (fork build) made the
adapter work; TCP in both directions, DNS and an HTTP fetch verified.

`info mtree` on mainline shows the layout:

```
0000000080000000-00000000807fffff (prio 1, i/o): pci-io-non-contiguous
0000000080000000-00000000bf7fffff (prio 0, i/o): pci-io
  0000000080000000-0000000080000007 (prio 0, i/o): dma-chan
  ...
```

Nothing else noticed because Linux, NetBSD and OpenBIOS keep PCI I/O BARs
below 64 KB on this machine.

## Testing

`build/qemu-mainline` is a shallow clone at `8967b2f`, configured with
`--target-list=ppc-softmmu --disable-docs --disable-werror`, built in
`build/qemu-mainline/build`. The source tree is unmodified;
`qemu-system-ppc` there was built with the mask removed (for the test runs
below) and `qemu-system-ppc.unpatched` is the untouched build. Rebuilding
produces the untouched version again.

The 40p functional tests (`tests/functional/ppc/test_40p.py`: factory
firmware + NetBSD 4.0 floppy, OpenBIOS + NetBSD 7.1.2, OpenBIOS + Linux
sandalfoot) run with:

```sh
cd build/qemu-mainline/build
MESON_BUILD_ROOT=$PWD PYTHONPATH=../tests/functional \
QEMU_TEST_ALLOW_UNTRUSTED_CODE=1 QEMU_TEST_QEMU_BINARY=$PWD/qemu-system-ppc \
pyvenv/bin/python3 ../tests/functional/ppc/test_40p.py
```

(`QEMU_TEST_ALLOW_UNTRUSTED_CODE` enables the factory-firmware test; the
assets land in `~/.cache/qemu/download`.) `scripts/checkpatch.pl` is the
style check. OpenBIOS still reaches its serial prompt with the mask gone,
which exercises the ISA UART through the same overlay.

## Submitting

- Maintainer: Hervé Poussineau <hpoussin@reactos.org>; list
  `qemu-ppc@nongnu.org`; patches go to `qemu-devel@nongnu.org` by email
  (`git send-email` or `git-publish`), not as GitLab/GitHub merge requests.
- `Signed-off-by:` is the DCO statement that you authored the change and
  can take responsibility for all of it.
- Reviewers cannot boot AIX on mainline, so the case rests on the spec
  text, the trace above, and the functional tests still passing.
