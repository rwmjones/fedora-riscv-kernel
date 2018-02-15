ROOT            := $(shell pwd)

# XXX Fix this so we have a local copy of the cross-compiling host tools.
HOST_TOOLS      := $(ROOT)/../fedora-riscv-bootstrap/host-tools/bin
PATH            := $(HOST_TOOLS):$(PATH)

# Upstream Linux 4.15 has only bare-bones support for RISC-V.  It will
# boot but you won't be able to use any devices.  It's not expected
# that we will have full support for this architecture before 4.17.
# In the meantime we're using the riscv-linux riscv-all branch.
KERNEL_VERSION   = 4.15.0

# The version of Fedora we are building for.
FEDORA           = 27

all: vmlinux bbl RPMS/noarch/kernel-headers-$(KERNEL_VERSION)-1.fc$(FEDORA).noarch.rpm

vmlinux: riscv-linux/vmlinux
	cp $^ $@

riscv-linux/vmlinux: riscv-linux/.config
	$(MAKE) -C riscv-linux ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- vmlinux

riscv-linux/.config: config riscv-linux/Makefile
	$(MAKE) -C riscv-linux ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- defconfig
	cat config >> $@
	$(MAKE) -C riscv-linux ARCH=riscv CROSS_COMPILE=riscv64-unknown-linux-gnu- olddefconfig

# Build bbl with embedded kernel.
bbl: vmlinux
	rm -rf riscv-pk/build
	mkdir -p riscv-pk/build
	cd riscv-pk/build && \
	RISCV=$(HOST_TOOLS) \
	../configure --prefix=$(ROOT)/bbl-tmp --host=riscv64-unknown-linux-gnu --with-payload=$(ROOT)/$<
	cd riscv-pk/build && \
	RISCV=$(HOST_TOOLS) \
	$(MAKE)
	cd riscv-pk/build && \
	RISCV=$(HOST_TOOLS) \
	$(MAKE) install
	mv $(ROOT)/bbl-tmp/riscv64-unknown-elf/bin/bbl $@
	rm -rf $(ROOT)/bbl-tmp

# Kernel headers RPM.
RPMS/noarch/kernel-headers-$(KERNEL_VERSION)-1.fc$(FEDORA).noarch.rpm: vmlinux kernel-headers.spec
	rm -rf kernel-headers
	mkdir -p kernel-headers/usr
	$(MAKE) -C riscv-linux ARCH=riscv headers_install INSTALL_HDR_PATH=$(ROOT)/kernel-headers/usr
	rpmbuild -ba kernel-headers.spec --define "_topdir $(ROOT)"
	rm -r kernel-headers

kernel-headers.spec: kernel-headers.spec.in
	rm -f $@ $@-t
	sed -e 's,@ROOT@,$(ROOT),g' -e 's,@KERNEL_VERSION@,$(KERNEL_VERSION),g' < $^ > $@-t
	mv $@-t $@

upload-kernel: bbl vmlinux
	scp $^ fedorapeople.org:/project/risc-v/disk-images/

clean:
	rm -f *~
	rm -f vmlinux bbl

# This is for test-booting the kernel against a stage4 disk
# image from https://fedorapeople.org/groups/risc-v/
boot-stage4-in-qemu: stage4-disk.img
	$(MAKE) boot-in-qemu DISK=$<

boot-in-qemu: $(DISK) bbl
	qemu-system-riscv64 \
	    -nographic -machine virt -m 2G \
	    -kernel bbl \
	    -append "console=ttyS0 ro root=/dev/vda init=/init" \
	    -device virtio-blk-device,drive=hd0 \
	    -drive file=$(DISK),format=raw,id=hd0 \
	    -device virtio-net-device,netdev=usernet \
	    -netdev user,id=usernet$${TELNET:+,hostfwd=tcp::10000-:23}
