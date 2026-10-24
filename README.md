# AIX on QEMU (IBM RS/6000 7020-40P)

Setup for running AIX under QEMU's `40p` (PReP) machine, following
<https://virtuallyfun.com/2019/04/22/installing-aix-on-qemu/>.

## Status

**Verified end to end** on Debian 13: AIX 4.3.3 installs and boots to a root
shell.

```
# uname -a
AIX localhost 3 4 000000004C00
# oslevel
4.3.3.0
```

**You must build the QEMU fork (`make qemu`).** Stock `qemu-system-ppc` from
Debian cannot boot AIX on the 40p machine — see
[Why stock QEMU does not work](#why-stock-qemu-does-not-work).

`Disc01.iso` is the bootable install disc (type-`0x41` PReP boot partition,
which is what `boot cdrom:2` selects). `Disc02`–`Disc04` are data discs with
no boot record; that is normal. Run `make probe` to check any media.

## Requirements

Debian/Ubuntu:

```sh
sudo apt install qemu-utils make git curl python3 \
     build-essential pkg-config libglib2.0-dev libpixman-1-dev zlib1g-dev \
     libgtk-3-dev
```

`libgtk-3-dev` is what gives the QEMU fork its display window, which only
`make of CONSOLE=gui` uses. Without it the firmware prompt and AIX both still
work on the serial console, which is where everything else happens anyway.

The `40p` machine is in mainline QEMU, but mainline still cannot boot AIX on
it, so `make qemu` builds Artyom Tarasenko's fork into `build/`. It takes a
few minutes and installs nothing system-wide.

## Usage

```sh
make check              # verify toolchain, machine type, media
make probe              # check whether an ISO is bootable on 40p
make qemu               # build the QEMU fork (required, a few minutes)
make firmware           # download the Open Firmware ROMs (~1.2 MB)
make disk               # create aix-hdd.qcow2 (8G)
make install            # boot the installer from Disc01.iso
```

`make install` drops you at the firmware prompt. Then:

```
ok  boot cdrom:2
```

(If the installer does not start, try `boot cdrom:2 -i`.)

Install notes, from the guide:

* When the firmware reloads, press `1` to select the console. **Input is not echoed.**
* Choose English, accept the default install type, confirm the disk wipe.
* Expect roughly 10–20 minutes.
* Around 96% the machine reboots back to firmware. That is normal.

Then boot the installed system:

```sh
make boot
```

Everything happens in the terminal you ran it from. At the firmware prompt:

```
ok  boot disk
```

The firmware reboots itself into the right mode, loads AIX, and then goes
quiet for a minute or two. When it does, AIX is asking which device to use as
its console:

```
 ******* Please define the System Console. *******
 Type a 1 and press Enter to use this terminal as the system console.
```

Press `1` and Enter — **your keypress is not echoed.** Then pick `vt100` as
the terminal type.

There is no QEMU window. AIX cannot boot at all while a graphics adapter is
on the bus, so every target that boots AIX is serial-only and refuses
`CONSOLE=gui`; `make of` is the one target that still takes it. See [The
window and the console](#the-window-and-the-console).

Function keys are `ESC` then the digit — F3 is `ESC` `3`. Log in as `root`,
no password.

On the first boot AIX shows the Installation Assistant (a SMIT menu). Pick
**Tasks Completed - Exit to AIX Login** at the bottom to reach a login prompt.

A full install takes 15–20 minutes and writes about 175 MB. The installer
reboots to the firmware around 95%; that is expected, and `boot disk` at the
`ok` prompt continues. Progress can appear frozen for several minutes at a
time without anything being wrong.

### Other targets

| Target | Purpose |
| --- | --- |
| `make boot-serial` | Synonym for `make boot`, kept for muscle memory |
| `make of` | Firmware prompt only, no disk or CD — the one `CONSOLE=gui` target |
| `make cd2` | Boot installed system with `Disc02.iso` in the drive |
| `make swap DISC=Disc03.iso` | Same, with any disc (for post-install filesets) |
| `make probe` | Check which `Disc*.iso` are bootable |
| `make daemon` / `make console` / `make kill` | Run detached with a telnet console |
| `make snapshot NAME=x` / `make info` | qcow2 snapshots |
| `make distclean` | Delete the disk image (prompts first) |

Variables: `CD`, `CD2`..`CD4`, `DISC`, `DISK`, `DISK_SIZE`, `MEM`, `CPUS`, `PORT`, `CONSOLE`.

`CONSOLE` picks where a target's console goes: `stdio` (serial only, the
default), `telnet`, or `gui` (a QEMU window driven by the VGA firmware ROM).
Only `make of` accepts `gui`. Every other target boots AIX, and AIX hangs
when the S3 adapter the window needs is present, so those targets refuse it
rather than hang.

Note: 40p caps RAM below 256MB; `MEM=192` is the working maximum.

**Quit QEMU with `Ctrl-A` `X`** in the terminal, or close the window.

### The window and the console

**AIX will not boot while a graphics adapter is on the PCI bus.** That is why
booting AIX is serial-only here.

The symptom is a QEMU window showing a dark grey screen with a single green
cursor block in the top-left corner that never blinks, while the serial
console stops dead after:

```
Rebooting with command: boot /pci/scsi@1/disk@0,0:1
Boot device: /pci/scsi@1/disk@0,0:1  Arguments:
```

The guest reads ~35 MB off the disk — the kernel and the boot-phase root FS
load fine — then stops reading and stays that way for as long as you leave
it. It is not a crash: see [what it is actually
waiting for](#what-it-is-actually-waiting-for) below.

Holding the firmware ROM constant and toggling only the adapter isolates it:

| ROM | `-vga` | Result |
| --- | --- | --- |
| `q40pofw-serial.rom` | `none` | boots; console prompt on the serial line |
| `q40pofw-serial.rom` | `s3` | hangs, nothing after `Boot device:` |
| `q40pofw-vga.rom` | `s3` | hangs — this was the old `make boot` |

So it is the card's presence, not the VGA ROM and not the window. On every
boot AIX asks which device to use as its console:

```
 ******* Please define the System Console. *******
 Type a 1 and press Enter to use this terminal as the system console.
```

With no display adapter that prompt goes to the serial line and you answer
it. With the S3 present AIX sends it to the display instead — and the
display is where it dies.

**The driver is not missing.** All of it is installed and committed:

```
# lslpp -l | grep -i -E 'graphic|33531188'
devices.graphics.com       4.3.3.25  COMMITTED  Graphics Adapter Common
devices.pci.33531188.rte    4.3.2.0  COMMITTED  GXT110P Graphics Adapter
devices.pci.33531188.X11    4.3.0.0  COMMITTED  AIXwindows GXT110P Graphics
devices.pci.33531188.diag   4.3.3.0  COMMITTED  GXT110P Graphics Adapter
```

and the devices are already in the ODM, `Defined` because on a serial boot
the hardware they describe is not on the bus:

```
# lsdev -C | grep -i -E 'lft|graph'
gxme0  Defined         Graphics Data Transfer Assist Subsystem
iga0   Defined  04-02  GXT110P Graphics Adapter
lft0   Defined         Low Function Terminal Subsystem
```

`devices.pci.33531188` is AIX's name for PCI `5333:8811` — exactly the S3
Trio the fork emulates (`PCI_VENDOR_ID_S3` / `PCI_DEVICE_ID_S3_TRIO` in
`hw/display/s3_vga.c`), which QEMU puts at `04-02`, the slot `iga0` names.
So AIX has the right driver for the right card, and does run it: on a
`-vga s3` boot the screen changes mode (640x480 → 640x272 → 640x480) and a
cursor appears. That is the LFT coming up.

Then it stops.

### What it is actually waiting for

The CPU is **not** deadlocked. It sits in AIX's ordinary idle loop,
alternating between `0x1f90c` and `0x1f918`. A healthy serial boot parked at
the console prompt sits at exactly those same addresses, so the program
counter on its own says nothing: AIX is waiting for input, as it always does
there. The question is only why the input can never come.

**It commits to memory-mapped registers.** The last thing the driver does on
the I/O ports is:

```
CR59 = 0x04, CR5A = 0x00    ; linear aperture base = 0x04000000 (== BAR0)
CR58 = 0x02                 ; linear window control
CR53 = 0x08                 ; enable MMIO   <- last S3 I/O access, ever
```

Earlier in the same trace sit `CR53=0x08` / `CR53=0x00` probe pairs: the
driver testing MMIO by writing a register and reading it back. Nothing in
`hw/display/` implements S3 MMIO — grepping `s3_vga.c` and `vga.c` for
`CR53` or `mmio` comes back empty — so that window is plain video RAM, the
read-back test passes, and the driver concludes MMIO works.

It does not then hammer that window, though. Instrumenting `vga_mem_ops` to
log every access to the `0xa0000` region once `CR53` bit 3 is set records
**nothing at all**, so the driver is not polling a status register in VRAM
either. After `CR53 = 0x08` it simply stops talking to the card.

**The console went to the display, and the serial line was never wired up.**
Interrupt counters at the stall, against a healthy boot parked at its
console prompt:

| | `-vga none` (boots) | `-vga s3` (stalls) |
| --- | --- | --- |
| IRQ 4 (serial) | 178 | *never appears* |
| IRQ 13 (SCSI) | 3529 | 3763 |
| IRQ 0 (timer) | ticking | ticking |
| `pic0` / `pic1` masks | `imr=fb` / `imr=df` | identical |

With a display on the bus AIX picks the LFT and never sets up a serial
console at all — which is why the serial line goes silent at `Boot device:`
and stays silent. The interrupt masks are identical in both cases, so
nothing is being masked off abnormally.

**Keyboard input never reaches the guest.** Sending `1` + Enter three times
through the QEMU monitor leaves IRQ 1 unchanged — `630` before, `630`
after — in the stalled boot and the healthy one alike. The firmware's own
use of the keyboard *does* raise IRQ 1 (that is where the 630 came from), so
the i8042 itself works; it is keystrokes delivered after AIX takes over that
produce nothing.

So: the window shows a cursor and nothing else, AIX waits at a prompt it may
never have managed to print, no keystroke can answer it, and there is no
serial fallback because AIX never opened one.

Making the window real is therefore not an AIX-side task, and not a
one-register fix. It needs S3 MMIO implemented in the fork's device model
*and* the LFT's keyboard path working, with no reference implementation to
copy — mainline QEMU never implemented S3 MMIO either. Until someone does
that work the card has to stay off the bus, which is what the Makefile
enforces.

## Networking

Every target attaches an AMD PCnet card (`NIC_MODEL=pcnet`), which AIX
drives as the IBM PCI Ethernet Adapter (`22100020`), on QEMU user-mode NAT.
No root, bridge or tap setup is needed. Pass `NET=none` to disconnect it.

| | |
|---|---|
| Guest IP | `10.0.2.15/24` |
| Gateway | `10.0.2.2` (also the host) |
| DNS | `10.0.2.3` |
| Telnet in | `telnet 127.0.0.1 2323` (`TELNET_PORT`) |
| SSH in | `ssh -p 2222 root@127.0.0.1` (`SSH_PORT`) |

AIX does not run DHCP by default, so configure it once from the console:

```sh
lsdev -Cc adapter | grep ent # expect: ent0 Available ... IBM PCI Ethernet Adapter (22100020)
mktcpip -h aix -a 10.0.2.15 -m 255.255.255.0 -i en0 -g 10.0.2.2 -n 10.0.2.3 -d local
```

The 4.3.3 install already carries the driver (`devices.pci.22100020.rte`)
and configures `ent0` at boot. `mktcpip` writes the settings to the ODM, so
they persist across reboots.

This needs the fork built with `patches/0001-prep-contiguous-pci-io-linear.patch`
(`make qemu` applies it). Without it AIX reports `ADAPTER ERROR` on `ent0`
and `ifconfig` fails with `0821-510`: the bridge model wrapped the card's
I/O BAR at `0x10000` onto the ISA range. See `patches/README.md`.

User-mode NAT passes TCP and UDP but not ICMP, so `ping` to the outside
fails even when networking works. Test with `host example.com` and
`telnet example.com 80` instead. Do not judge DNS by `nslookup`: the 4.3.3
version reverse-resolves its own server first, slirp answers NXDOMAIN for
`10.0.2.3`, and it quits with "Default servers are not available" although
lookups work. When a name has AAAA records the AIX `telnet` client tries
those first and fails with "A route to the remote host is not available",
since the guest has no IPv6; give it the IPv4 address from `host` instead.
Old AIX clients such as `ftp` and `telnet` reach plain-text services only.
For HTTPS, use the curl built from source (see [HTTPS: OpenSSL and
curl](#https-openssl-and-curl)).

## Development tools (gcc, GNU make)

AIX 4.3.3 ships no C compiler, so nothing can be built from source until a
prebuilt GCC is in place. The installed system has:

| | Source | Gives |
|---|---|---|
| `bos.adt.*` | `Disc01.iso`, `/usr/sys/inst.images/bos.adt` | headers, `as`, `ld`, AIX `make`, `lex`/`yacc`, `dbx` |
| `rpm.rte 3.0.5.36` | AIX Toolbox `INSTALLP/ppc/` | `rpm` (the last build that installs on 4.3.3) |
| GNUPro gcc/g++ `2.9-aix51-020209` | AIX Toolbox `RPMS/ppc/GNUPro/` | `gcc`, `g++` (2.95 era), using the AIX `as`/`ld` |
| make 3.79.1, gettext, sed, gawk, grep, tar, gzip, bzip2, patch, diffutils, m4, bison, flex, findutils, fileutils, textutils, sh-utils, bash, unzip, zlib, info | AIX Toolbox `RPMS/ppc/<name>/*.aix4.3.ppc.rpm` | the GNU userland |
| wget 1.8.1 | same | HTTP/FTP downloads (built without SSL, so no `https://`) |
| perl 5.8.0, prngd 0.9.23 | same | perl (also linked as `/usr/bin/perl`); an entropy daemon on `/dev/egd-pool` |
| vim 6.0.147, emacs 21.1 (`emacs` + `emacs-nox`) | same | editors; vim needs gettext 0.10.39 (0.10.35's libintl lacks `bind_textdomain_codeset`). Emacs is in `/usr/bin` only as `emacs-nox` |
| OpenSSL 1.0.2u | built on the guest, `/usr/local/ssl` | TLS 1.2 (static `libssl.a`/`libcrypto.a`) |
| curl 7.88.1 | built on the guest, `/usr/local` | HTTPS-capable curl and static `libcurl.a`; `/usr/bin/curl` links to it |
| OpenSSH 9.3p2 | built on the guest, `/usr/local`, config in `/etc/ssh` | `sshd` started at boot by SRC, plus `ssh`, `scp`, `sftp` and `ssh-keygen` |

The AIX Toolbox lives at <https://public.dhe.ibm.com/aix/freeSoftware/aixtoolbox/>
and still carries about 890 `.aix4.3` RPMs. Everything goes into
`/opt/freeware`, which links to `/usr/opt/freeware`. `/usr` was grown to make
room, with `chfs -a size=+524288 /usr`, twice.

The GNU tools are in `/opt/freeware/bin` and the AIX ones stay in `/usr/bin`.
Root's `/.profile` puts the GNU directories first, but only for root's login
shell, so system scripts still get the AIX tools they expect. `gmake` is always
GNU make, whatever the PATH.

The gcc RPM's `%post` script needs `perl`, which this install lacks, so it
was done by hand. In `/opt/freeware/GNUPro/Install`, change
`powerpc-ibm-aix5.1.0.0` to `powerpc-ibm-aix4.3.3.0` and set `EXECDIR=` to
empty. Then run `./Install --installdir=/opt/freeware/GNUPro fixincludes`.

C++ links shared only; `-static` fails on 4.3 per the release notes.

### HTTPS: OpenSSL and curl

The Toolbox curl (7.9.3) was built without SSL and sends no SNI, so it
cannot reach modern HTTPS sites. It was removed, and OpenSSL and curl were
built from source on the guest. The sources are in `/usr/local/src`.
OpenSSL 1.0.2u is the newest release that suits gcc 2.9 and the perl 5.8
its `Configure` needs. It does TLS 1.2, but not TLS 1.3.

* **No kernel entropy.** AIX 4.3 has no `/dev/random` or `/dev/urandom`.
  Without an entropy source every handshake fails with `PRNG not seeded`.
  `prngd` fixes this: the RPM registers it with SRC and adds a `prng`
  inittab entry, so it starts at boot. OpenSSL finds its EGD socket at
  `/dev/egd-pool` on its own. Check it with `lssrc -s prngd`.
* **OpenSSL** was configured with
  `./Configure aix-gcc no-asm no-shared no-ssl2 no-ssl3 --prefix=/usr/local/ssl --openssldir=/usr/local/ssl`.
  Two changes were needed for gcc 2.9:
  * In the generated `Makefile`, `-pthread` becomes `-mthreads`, which is
    what gcc 2.9 on AIX understands.
  * In `ssl/s3_cbc.c`, the `rotated_mac` alignment expression is split into
    separate statements, because gcc 2.9 rejects it with "invalid operands
    to binary &".
  `make depend` was skipped because it needs `makedepend`. The CA bundle is
  curl.se's `cacert.pem`, installed as `/usr/local/ssl/cert.pem`.
* **curl 7.88.1.** `include/curl/system.h` needs `defined(_AIX)` added to its
  32-bit gcc list. gcc 2.9 defines none of `__powerpc__`, `__SIZEOF_LONG__`
  or `__LONG_MAX__`, so `curl_off_t` was left undefined. Configured with
  `CONFIG_SHELL=bash ./configure --prefix=/usr/local CC=gcc CFLAGS="-O -mthreads" LDFLAGS=-mthreads --with-openssl=/usr/local/ssl --with-ca-bundle=/usr/local/ssl/cert.pem --disable-shared --disable-ipv6 --disable-ldap --disable-threaded-resolver --without-zlib`
  (plus `--without-*` for libidn2, nghttp2, brotli, zstd, libssh2 and
  librtmp).

### SSH server: OpenSSH 9.3p2

```sh
ssh -p 2222 root@127.0.0.1        # SSH_PORT; forwarded by every boot target
```

IBM never shipped OpenSSH for AIX 4.3, so it is built from source against
the OpenSSL above. 9.3p2 is the last release that accepts OpenSSL 1.0.2,
because 9.4 needs 1.1.1. It still negotiates modern defaults: curve25519
key exchange, ed25519 host keys and chacha20-poly1305. Current clients
connect without any legacy `-o` options.

* **Root login is by key only.** Root has no password, and the default
  `PermitRootLogin prohibit-password` would refuse one anyway. Keys go in
  `/.ssh/authorized_keys`, since root's home is `/`.
* **Service.** `sshd` is an SRC subsystem (`lssrc -s sshd`,
  `stopsrc`/`startsrc -s sshd`). An inittab entry, `sshd:2:once`, placed
  after `rctcpip`, starts it at boot.
* **Privilege separation** runs as user `sshd` in an empty `/var/empty`.
  `mkuser` refuses `/bin/false` as a shell because it is not in
  `/etc/security/login.cfg`. So the account has `ksh` and is locked:
  `login=false rlogin=false su=false account_locked=true`.
* **Build fix.** AIX 4.3's `<utmp.h>` and `<utmpx.h>` both define
  `struct utmp_data`, so every file failed to compile. After `configure`,
  `config.h` was edited to use utmp only: the `HAVE_*UTMPX*`, `*UTX*` and
  `LOGIN_NEEDS_UTMPX` defines were turned into `#undef`, and
  `DISABLE_UTMPX` was defined. Configured with
  `CONFIG_SHELL=bash ./configure --prefix=/usr/local --sysconfdir=/etc/ssh CC=gcc CFLAGS="-O -mthreads" LDFLAGS=-mthreads --with-ssl-dir=/usr/local/ssl --with-zlib=no --with-prngd-socket=/dev/egd-pool --with-privsep-path=/var/empty`.
* **Agent check unavailable.** AIX 4.3 has no `getpeereid()`, so
  `ssh-agent` cannot check who connects to its socket. That only matters
  with untrusted local users.
* **TERM.** AIX 4.3 terminfo has `xterm` but not `xterm-256color`. Root's
  `/.profile` falls back to `xterm` for any `xterm-*` it lacks.

To copy files into the guest, serve them from the host and fetch them with
the AIX `ftp` client, in `passive` mode, from `10.0.2.2`.

## Why stock QEMU does not work

Debian's `qemu-system-ppc` 10.0.13 gets remarkably far and then dies quietly:

```
ok  boot cdrom:2
Boot device: /scsi/disk@2:2  Arguments:
Rebooting in the correct mode for this client program ...
...
Rebooting with command: boot /pci/scsi@1/disk@2,0:2
Boot device: /pci/scsi@1/disk@2,0:2  Arguments:
            <- nothing further, ever, at 100% CPU
```

It is **not** hung in the usual sense. Sampling the guest via the QEMU monitor
shows it running real code:

```
NIP=100205b8  MSR=0000f030     <- PR=1 (user mode), EE=1, IR|DR=1 (MMU on)
NIP=1002050c  MSR=0000f030
NIP=1002062c  MSR=0000f030
```

`0x10000000` is AIX's standard text base for userspace binaries. So the kernel
booted, the MMU is up, and userspace is running — it just polls forever.
Things that were checked and are *not* the cause:

* The CD reads fine; SCSI is working.
* An entire boot produces one guest error and no unimplemented-device accesses.
* Neither UART receives anything, and input to them is ignored.
* The VGA framebuffer only ever contains QEMU's own placeholder text,
  "Guest has not initialized the display (yet)."

AIX comes up with no console at all and waits. The fork fixes it; its 40p
patches were never fully upstreamed. Mainline still carries the marker:

```c
/* XXX: s3-trio at PCI_DEVFN(2, 0) */
pci_vga_init(pci_bus);          /* hw/ppc/prep.c */
```

The real 7020-40P had an S3 graphics adapter, which the fork emulates and
mainline substitutes with a generic VGA. Mainline's `lsi53c810` is also only a
PCI device-ID override of the 53C895A model and still exposes the full `0x400`
register window instead of the real chip's `0x80` — the source comments
"LSI53C810 emulation is incorrect".

On the fork the same boot reaches the console prompt in six languages:

```
Type a 1 and press Enter to use this terminal as the system console.
```

One caveat on that comparison: the mainline runs above had a VGA adapter on
the bus and the fork runs did not, so the two differ by more than the QEMU
build, and [the hang that causes](#the-window-and-the-console) was not known
when this was written. Mainline's trace (`NIP=1002xxxx`, user mode) is a
later stage than console selection, so they are not obviously the same
failure — but mainline deserves a re-test with `-vga none` before this
section is taken as settled.

### Building the fork on a modern toolchain

The fork is 2019-era C and GCC 14 defaults to C23, making implicit function
declarations and int/pointer conversions hard errors. `scripts/build-qemu.sh`
demotes exactly those three to warnings, which is enough — none of the
extensive `--disable` flag-hunting described in older write-ups was needed.

## Appendix: why AIX 3.2.5 media does not work

An earlier set of discs in this directory was AIX **3.2.5 for Micro Channel
RS/6000 (POWER/RIOS)**, and could not boot at all.

QEMU's 40p firmware boots AIX from partition 2 of a PReP partition table (an
MBR with a type-`0x41` entry). The 3.2.5 disc had no partition table; sector 0
began `c9 c2 d4 c1`, which is `IBMA` in EBCDIC — the older RS/6000 IPL record
used before AIX 4. `.partitions cdrom` returned an empty table and every
`boot` variant failed with "The attempt to load a boot image failed."

Two further blockers applied: QEMU has no Micro Channel / POWER (RIOS) target
(the media carried MCA-only drivers such as *Multiprotocol Adapter/A*), and
QEMU removed the PowerPC 601 that even the PowerPC edition of 3.2.5 needs.

## Layout

```
Makefile              build/run targets
scripts/build-qemu.sh clones + builds the QEMU fork (make qemu)
scripts/check-iso.py  media bootability checker (make probe)
firmware/             Open Firmware ROMs (downloaded)
build/qemu-fork/      the QEMU fork source + binary
aix-hdd.qcow2         virtual disk (created)
install.log           console transcript of the installation
```

Both firmware ROMs come from
[artyom-tarasenko/openfirmware](https://github.com/artyom-tarasenko/openfirmware)
release `40p-20190413` and are checksum-pinned in the Makefile:
`q40pofw-serial.rom` for the serial targets, `q40pofw-vga.rom` for the window
that `make boot` opens. The framebuffer works on the fork — the dead one
described above is mainline's generic VGA, not the fork's S3.
