#!/usr/bin/env python3
"""Report whether an AIX ISO can boot on QEMU's 40p (PReP) machine.

The q40p Open Firmware boots AIX via 'boot cdrom:2', i.e. partition 2 of a
PReP partition table (MBR with a type-0x41 entry). AIX 4.x media has one.
Pre-4.x media uses the older RS/6000 IPL record ('IBMA' in EBCDIC at sector 0)
and cannot be booted this way.
"""
import struct, sys

EBCDIC = {0xc9: "I", 0xc2: "B", 0xd4: "M", 0xc1: "A"}


def iso_root(f):
    f.seek(16 * 2048)
    pvd = f.read(2048)
    if pvd[1:6] != b"CD001":
        return None
    r = pvd[156:190]
    return struct.unpack("<I", r[2:6])[0], struct.unpack("<I", r[10:14])[0]


def find_toc(f):
    loc = iso_root(f)
    if not loc:
        return None
    ext, ln = loc
    f.seek(ext * 2048)
    data = f.read(ln)
    i = 0
    while i < len(data):
        L = data[i]
        if L == 0:
            i = (i // 2048 + 1) * 2048
            continue
        r = data[i:i + L]
        name = r[33:33 + r[32]].decode("latin1")
        if name.startswith(".TOC"):
            e = struct.unpack("<I", r[2:6])[0]
            s = struct.unpack("<I", r[10:14])[0]
            f.seek(e * 2048)
            return f.read(s).decode("latin1", "replace")
        i += L
    return None


def check(path):
    print(f"=== {path} ===")
    with open(path, "rb") as f:
        sec0 = f.read(2048)

        ipl = "".join(EBCDIC.get(b, ".") for b in sec0[:4]) == "IBMA"
        mbr = sec0[510:512] == b"\x55\xaa"
        prep = [i for i in range(4) if sec0[446 + 16 * i + 4] == 0x41]

        f.seek(16 * 2048)
        print(f"  ISO9660              : {'yes' if f.read(2048)[1:6] == b'CD001' else 'no'}")
        print(f"  RS/6000 IPL record   : {'yes (IBMA)' if ipl else 'no'}")
        print(f"  MBR signature (55aa) : {'yes' if mbr else 'no'}")
        print(f"  PReP partition (0x41): {'yes, partition ' + str(prep) if prep else 'no'}")

        toc = find_toc(f)
        if toc:
            import re
            m = re.search(r"^bos\.(obj|rte) +(\d+\.\d+)", toc, re.M)
            if m:
                print(f"  base OS fileset      : bos.{m.group(1)} {m.group(2)}")
            mca = len(re.findall(r"Adapter/A", toc))
            if mca:
                print(f"  Micro Channel hints  : {mca} 'Adapter/A' filesets")

        print()
        if prep and mbr:
            print("  VERDICT: bootable -- at the 'ok' prompt run:  boot cdrom:2")
            return 0
        if ipl:
            print("  VERDICT: NOT bootable on QEMU 40p.")
            print("  This is pre-AIX-4 media using the old RS/6000 IPL record.")
            print("  The 40p Open Firmware needs a PReP partition table (AIX 4.x).")
            return 1
        print("  VERDICT: no boot record found -- this is probably a data/extra disc.")
        return 1


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: check-iso.py ISO [ISO...]")
    sys.exit(max(check(p) for p in sys.argv[1:]))
