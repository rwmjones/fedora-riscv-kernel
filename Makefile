ROOT            := $(shell pwd)

# We don't normally use cross-compilation, BUT where it's necessary
# these lines can be uncommented to cross-compile riscv-linux/vmlinux ONLY.
#HOST_TOOLS      := $(ROOT)/../fedora-riscv-bootstrap/host-tools/bin
#PATH            := $(HOST_TOOLS):$(PATH)
#export CROSS_COMPILE := riscv64-unknown-linux-gnu-

# Upstream Linux 4.15 has only bare-bones support for RISC-V.  It will
# boot but you won't be able to use any devices.  It's not expected
# that we will have full support for this architecture before 4.17.
# In the meantime we're using the riscv-linux riscv-all branch.
KERNEL_VERSION   = 4.15.0

# The version of Fedora we are building for.
FEDORA           = 27

# NBD server IP address and port or export name.
# If blank, will use a local filesystem (use ROOTFS to
# set /dev/mmcblk0p2 or /dev/sda*, /dev/nvme*)
NBD              = 192.168.0.220:/

# XXX Fix stage4 to use a label.
ROOTFS           = UUID=e06a1845-3577-4e35-92a9-015b3042b3f2

all: vmlinux bbl bbl.u540 RPMS/noarch/kernel-headers-$(KERNEL_VERSION)-1.fc$(FEDORA).noarch.rpm

vmlinux: riscv-linux/vmlinux
	cp $^ $@

riscv-linux/vmlinux: riscv-linux/.config
	test $$(uname -m) = "riscv64"
	$(MAKE) -C riscv-linux ARCH=riscv vmlinux

# Kernel command line has to be embedded in the kernel.
ifeq (,$(NBD))
CMDLINE="root=$(ROOTFS) ro rootwait console=ttySI0"
else
CMDLINE="root=$(ROOTFS) netroot=nbd:$(NBD) rootfstype=ext4 rw rootdelay=5 ip=dhcp rootwait console=ttySI0"
endif

riscv-linux/.config: config riscv-linux/Makefile initramfs.cpio.gz
	test $$(uname -m) = "riscv64"
	$(MAKE) -C riscv-linux ARCH=riscv defconfig
	cat config >> $@
	echo 'CONFIG_CMDLINE_BOOL=y' >> $@
	echo 'CONFIG_CMDLINE=$(CMDLINE)' >> $@
	echo 'CONFIG_INITRAMFS_SOURCE="$(ROOT)/initramfs.cpio.gz"' >> $@
	$(MAKE) -C riscv-linux ARCH=riscv olddefconfig
# 'touch' here is necessary because for some reason kbuild doesn't
# set up dependencies right so that this file is rebuilt if CMDLINE
# changes
	touch riscv-linux/drivers/of/fdt.c

# Note that CONFIG_INITRAMFS_SOURCE requires the initramfs has
# this exact name.
initramfs.cpio.gz:
	@if [ `id -u` -ne 0 ]; then \
	    echo "You must run this rule as root:"; \
	    echo "  sudo make $@"; \
	    exit 1; \
	fi
	rm -f $@-t $@
# NB: dracut does NOT resolve dependencies.  You must (somehow) know
# the list of module dependencies and add them yourself.
ifeq (,$(NBD))
	dracut -m "base" --add rootfs-block $@-t $$(uname -r) --no-kernel --force -v
else
	dracut -m "nbd network base" $@-t $$(uname -r) --no-kernel --force -v
endif
	chmod 0644 $@-t
	mv $@-t $@

# Build bbl with embedded kernel.
bbl: vmlinux
	test $$(uname -m) = "riscv64"
	rm -f $@
	rm -rf riscv-pk/build
	mkdir -p riscv-pk/build
	cd riscv-pk/build && \
	../configure \
	    --prefix=$(ROOT)/bbl-tmp \
	    --with-payload=$(ROOT)/$< \
	    --enable-logo
	cd riscv-pk/build && \
	$(MAKE)
	cd riscv-pk/build && \
	$(MAKE) install
	if test -f $(ROOT)/bbl-tmp/bin/bbl; then \
		mv $(ROOT)/bbl-tmp/bin/bbl $@; \
	elif test -f $(ROOT)/bbl-tmp/riscv64-unknown-elf/bin/bbl; then \
		mv $(ROOT)/bbl-tmp/riscv64-unknown-elf/bin/bbl $@; \
	else \
		exit 1; \
	fi
	rm -rf $(ROOT)/bbl-tmp

# The final bbl binary that can be copied into the boot partition.
bbl.u540: bbl
	objcopy \
	    -O binary \
	    --strip-all \
	    --change-addresses -0x80000000 \
	    $< $@

# Kernel headers RPM.
RPMS/noarch/kernel-headers-$(KERNEL_VERSION)-1.fc$(FEDORA).noarch.rpm: vmlinux kernel-headers.spec
	test $$(uname -m) = "riscv64"
	rm -rf kernel-headers
	mkdir -p kernel-headers/usr
	$(MAKE) -C riscv-linux ARCH=riscv headers_install INSTALL_HDR_PATH=$(ROOT)/kernel-headers/usr
	rpmbuild -ba kernel-headers.spec --define "_topdir $(ROOT)"
	rm -r kernel-headers

kernel-headers.spec: kernel-headers.spec.in
	rm -f $@ $@-t
	sed -e 's,@ROOT@,$(ROOT),g' -e 's,@KERNEL_VERSION@,$(KERNEL_VERSION),g' < $^ > $@-t
	mv $@-t $@

upload-kernel: bbl.u540 readme.u540.txt
	scp $^ fedorapeople.org:/project/risc-v/disk-images/hifive-unleashed/

clean:
	$(MAKE) -C riscv-linux clean
	rm -f *~
	rm -f vmlinux bbl

# Test boot against the NBD server using qemu.
boot-stage4-in-qemu:
	qemu-system-riscv64 \
	    -nographic -machine virt -smp 4 -m 4G \
	    -kernel bbl \
	    -object rng-random,filename=/dev/urandom,id=rng0 \
	    -device virtio-rng-device,rng=rng0 \
	    -device virtio-net-device,netdev=usernet \
	    -netdev user,id=usernet
