# Patches applied to the QEMU fork

`scripts/build-qemu.sh` applies every `*.patch` here to `build/qemu-fork`
with `git apply`, skipping ones already in the tree.

## 0001-prep-contiguous-pci-io-linear.patch

`hw/pci-host/prep.c`: in the default (contiguous) I/O mode the 8 MB window
at CPU `0x80000000` masked every address to 16 bits, so PCI I/O ports above
`0xFFFF` aliased onto the ISA range. AIX assigns its PCI Ethernet adapter
`busio 0x10000`; with the mask, every register access from the `kent`
driver landed on the ISA DMA controller at port 0 instead of the card, the
MAC read back as `000000000000`, and opening `en0` failed with
`KENT_ADAP_ERR` (`kent_open.c:513`). PReP Memory Map A defines the window
as linear, which is what the patch makes it.

Mainline QEMU has the same mask; Linux and Open Firmware never place an
I/O BAR above 64 KB, so nothing else noticed.
