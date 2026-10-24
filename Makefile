# AIX on QEMU -- IBM RS/6000 7020-40P (PReP) emulation
#
#   make firmware   download the Open Firmware ROMs
#   make disk       create the virtual hard disk
#   make install    boot the install CD   (then: boot cdrom:2)
#   make boot       boot the installed OS   (then: boot disk)
#   make of         firmware prompt only, no media
#
# Everything runs on the serial line on stdio, AIX included. CONSOLE=gui
# opens a QEMU window where the firmware draws on the emulated S3 card and
# reads the PS/2 keyboard -- but AIX hangs at console selection whenever that
# card is present, so only 'make of' accepts it. Quit QEMU with Ctrl-A X.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Upstream qemu-system-ppc cannot boot AIX on 40p (see README); 'make qemu'
# builds Artyom Tarasenko's fork, which can.
QEMU_LOCAL := build/qemu-fork/ppc-softmmu/qemu-system-ppc
QEMU_CFG   := build/qemu-fork/config-host.mak
QEMU       ?= $(if $(wildcard $(QEMU_LOCAL)),./$(QEMU_LOCAL),qemu-system-ppc)
MACHINE   ?= 40p
MEM       ?= 192
CPUS      ?= 1

DISK      ?= aix-hdd.qcow2
DISK_SIZE ?= 8G

CD        ?= Disc01.iso
CD2       ?= Disc02.iso
CD3       ?= Disc03.iso
CD4       ?= Disc04.iso
ISOS      := $(wildcard Disc*.iso)

FW_DIR    ?= firmware
FW_REL    ?= 40p-20190413
FW_URL    ?= https://github.com/artyom-tarasenko/openfirmware/releases/download/$(FW_REL)
ROM_SER   := $(FW_DIR)/q40pofw-serial.rom
ROM_VGA   := $(FW_DIR)/q40pofw-vga.rom
SHA_q40pofw-serial.rom := 4a98bca4ab2149e2fe9e7cffb2215c04e2451f30d2e1cff173086908cb94fd17
SHA_q40pofw-vga.rom    := 84b55473bb4445b201b545dc5938fce5be96080182a92ea16c7ce131705bc204

# Console transport: gui (graphical window), stdio (default) or telnet.
# 'make boot' sets gui; pass CONSOLE= on the command line to override it.
CONSOLE   ?= stdio
GUI        = $(filter gui,$(CONSOLE))
PORT      ?= 4441
PIDFILE   := .qemu.pid
LOG       := qemu-console.log

# The vga ROM draws on the S3 framebuffer and reads the PS/2 keyboard; the
# serial ROM drives the UART. Both also echo their output to the serial line.
ROM        = $(if $(GUI),$(ROM_VGA),$(ROM_SER))
VIDEO      = $(if $(GUI),-vga s3,-vga none)

# Networking: an AMD PCnet card (AIX's 22100020 driver) on QEMU user-mode
# NAT. The guest is 10.0.2.15, gateway 10.0.2.2, DNS 10.0.2.3; host ports
# TELNET_PORT and SSH_PORT reach the guest's telnetd and sshd. NET=none
# disconnects it.
NET         ?= user
NIC_MODEL   ?= pcnet
TELNET_PORT ?= 2323
SSH_PORT    ?= 2222
NETOPTS_user = -nic user,model=$(NIC_MODEL),hostfwd=tcp:127.0.0.1:$(TELNET_PORT)-:23,hostfwd=tcp:127.0.0.1:$(SSH_PORT)-:22
NETOPTS_none = -net none
NETOPTS      = $(NETOPTS_$(NET))

BASE = QEMU_AUDIO_DRV=none $(QEMU) -M $(MACHINE) -m $(MEM) -smp $(CPUS) \
       -bios $(ROM) $(VIDEO) $(NETOPTS)

# stdio console, mirrored to $(LOG) so another terminal can 'make watch'.
# mux=on keeps the Ctrl-A escapes (Ctrl-A C = monitor, Ctrl-A X = quit).
STDIO = -chardev stdio,id=con,mux=on,signal=off,logfile=$(LOG) \
        -serial chardev:con -mon chardev=con
SERIAL_stdio  = -display none $(STDIO)
SERIAL_gui    = -display gtk $(STDIO)
SERIAL_telnet = -display none \
                -serial telnet:127.0.0.1:$(PORT),server=on,wait=off
SERIAL = $(SERIAL_$(CONSOLE))

# ---------------------------------------------------------------- help

help:
	@sed -n '/^$$/q; s/^# \{0,1\}//p' $(MAKEFILE_LIST)
	@echo
	@echo "Targets:"
	@grep -E '^[a-z][a-z0-9-]*:.*##' $(MAKEFILE_LIST) \
	  | sed 's/:.*##/\t/' | expand -t24 | sed 's/^/  /'
	@echo
	@echo "Vars: MEM=$(MEM) DISK_SIZE=$(DISK_SIZE) CD=$(CD) CONSOLE=$(CONSOLE) NET=$(NET) TELNET_PORT=$(TELNET_PORT) SSH_PORT=$(SSH_PORT)"

# ---------------------------------------------------------------- setup

check: ## Verify QEMU, machine type and media are present
	@command -v $(QEMU) >/dev/null 2>&1 || test -x $(QEMU) \
	  || { echo "ERROR: $(QEMU) not found (apt install qemu-system-ppc)"; exit 1; }
	@echo "using: $(QEMU)"
	@$(QEMU) --version | head -1
	@test -x $(QEMU_LOCAL) || echo "WARNING: system QEMU cannot boot AIX -- run 'make qemu'"
	@$(QEMU) -M help | grep -q '^$(MACHINE) ' \
	  || { echo "ERROR: machine '$(MACHINE)' unsupported by this QEMU"; exit 1; }
	@echo "machine $(MACHINE): ok"
	@test -n "$(SERIAL)" \
	  || { echo "ERROR: CONSOLE='$(CONSOLE)' -- use gui, stdio or telnet"; exit 1; }
	@test -z "$(GUI)" || test ! -f $(QEMU_CFG) || grep -q '^CONFIG_GTK=' $(QEMU_CFG) \
	  || { echo "ERROR: this QEMU was built without the GTK display"; \
	       echo "       rm $(QEMU_CFG) && make qemu   (needs libgtk-3-dev)"; exit 1; }
	@test -f $(CD) && echo "install media $(CD): ok" || echo "WARNING: $(CD) missing"
	@test -f $(ROM) && echo "firmware $(ROM): ok" || echo "note: run 'make firmware'"

qemu: $(QEMU_LOCAL) ## Build the QEMU fork that can boot AIX (required)
$(QEMU_LOCAL):
	scripts/build-qemu.sh

firmware: $(ROM_SER) $(ROM_VGA) ## Download the 40p Open Firmware ROMs
$(FW_DIR)/%.rom:
	@mkdir -p $(FW_DIR)
	curl -fsSL -o $@.tmp $(FW_URL)/$*.rom
	@echo "$(SHA_$*.rom)  $@.tmp" | sha256sum -c - \
	  || { echo "ERROR: checksum mismatch"; rm -f $@.tmp; exit 1; }
	@mv $@.tmp $@
	@echo "firmware ready: $@"

disk: $(DISK) ## Create the qcow2 hard disk
$(DISK):
	qemu-img create -f qcow2 $@ $(DISK_SIZE)

# ---------------------------------------------------------------- run

install: qemu check firmware disk ## Boot the install CD (at 'ok' type: boot cdrom:2)
	$(no-gui)
	@echo "=== At the 'ok' prompt type:  boot cdrom:2   (or: boot cdrom:2 -i) ==="
	@echo "=== Quit QEMU with Ctrl-A X ==="
	$(BASE) $(SERIAL) -hda $(DISK) -cdrom $(CD)

# Booting AIX is serial-only. With a graphics adapter on the bus it wedges at
# console selection -- grey screen, one green cursor, silent serial line (see
# README). Refuse CONSOLE=gui on those targets rather than hang.
define no-gui
@test -z "$(GUI)" || { echo "ERROR: AIX hangs at console selection when the S3 adapter is present."; echo "       Drop CONSOLE=gui -- only 'make of' can use the window."; exit 1; }
endef

define boot-disk
$(no-gui)
@test -f $(DISK) || { echo "ERROR: $(DISK) missing -- run 'make install' first"; exit 1; }
@echo "=== At the 'ok' prompt type:  boot disk ==="
@echo "=== When it goes quiet, AIX is asking for its console: press 1, Enter ==="
@echo "=== Quit QEMU with Ctrl-A X ==="
$(BASE) $(SERIAL) -hda $(DISK)
endef

boot: CONSOLE = stdio
boot: qemu check firmware ## Boot the installed system on the serial console
	$(boot-disk)

boot-serial: boot ## Synonym for 'boot'

cd2: check firmware ## Boot installed system with Disc02 in the drive
	$(no-gui)
	$(BASE) $(SERIAL) -hda $(DISK) -cdrom $(CD2)

swap: check firmware ## Boot installed system with an arbitrary disc (DISC=Disc03.iso)
	$(no-gui)
	@test -n "$(DISC)" || { echo "usage: make swap DISC=Disc03.iso"; exit 1; }
	$(BASE) $(SERIAL) -hda $(DISK) -cdrom $(DISC)

of: check firmware ## Open Firmware prompt only (no disk, no CD)
	$(BASE) $(SERIAL)

# ------------------------------------------------- telnet console helpers

daemon: check firmware disk ## Start QEMU detached with a telnet console
	@test ! -f $(PIDFILE) || { echo "ERROR: already running (pid $$(cat $(PIDFILE)))"; exit 1; }
	$(BASE) -serial telnet:127.0.0.1:$(PORT),server=on,wait=off -display none \
	  -hda $(DISK) $(if $(wildcard $(CD)),-cdrom $(CD),) \
	  -pidfile $(PIDFILE) -daemonize
	@echo "started; attach with 'make console' (telnet 127.0.0.1 $(PORT))"

console: ## Attach to the console of a 'make daemon' instance
	@if command -v telnet >/dev/null; then telnet 127.0.0.1 $(PORT); \
	 elif command -v nc >/dev/null; then \
	   echo "(using nc; quit with Ctrl-C)"; nc 127.0.0.1 $(PORT); \
	 else echo "ERROR: install telnet or netcat"; exit 1; fi

watch: ## Follow the console log in another terminal
	@touch $(LOG); tail -f $(LOG)

kill: ## Stop a detached instance
	@test -f $(PIDFILE) && kill $$(cat $(PIDFILE)) && rm -f $(PIDFILE) \
	  && echo "stopped" || echo "not running"

# ---------------------------------------------------------------- misc

snapshot: ## Snapshot the disk (NAME=label)
	@test -n "$(NAME)" || { echo "usage: make snapshot NAME=label"; exit 1; }
	qemu-img snapshot -c $(NAME) $(DISK) && qemu-img snapshot -l $(DISK)

info: ## Show disk info and snapshots
	qemu-img info $(DISK)

clean: ## Remove logs and pidfile
	rm -f $(PIDFILE) $(LOG)

distclean: clean ## Also remove the disk image (DESTROYS the installed system)
	@read -p "Delete $(DISK)? [y/N] " a; [[ $$a == [yY] ]] && rm -f $(DISK) || echo "kept"

.PHONY: help check qemu firmware disk install boot boot-serial cd2 swap of daemon console watch kill snapshot info clean distclean

probe: ## Check whether ISOs can boot on 40p (usage: make probe [CD=file.iso])
	@python3 -I scripts/check-iso.py $(if $(ISOS),$(ISOS),$(CD)) || true

.PHONY: probe swap
