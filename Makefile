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

all: vmlinux bbl RPMS/noarch/kernel-headers-$(KERNEL_VERSION)-1.fc$(FEDORA).noarch.rpm

vmlinux: riscv-linux/vmlinux
	cp $^ $@

riscv-linux/vmlinux: riscv-linux/.config
	test $$(uname -m) = "riscv64"
	$(MAKE) -C riscv-linux ARCH=riscv vmlinux

riscv-linux/.config: config riscv-linux/Makefile
	test $$(uname -m) = "riscv64"
	$(MAKE) -C riscv-linux ARCH=riscv defconfig
	cat config >> $@
	$(MAKE) -C riscv-linux ARCH=riscv olddefconfig

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
	mv $(ROOT)/bbl-tmp/riscv64-unknown-elf/bin/bbl $@
	rm -rf $(ROOT)/bbl-tmp

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

upload-kernel: bbl vmlinux
	scp $^ fedorapeople.org:/project/risc-v/disk-images/

clean:
	$(MAKE) -C riscv-linux clean
	rm -f *~
	rm -f vmlinux bbl

# This is for test-booting the kernel against a stage4 disk
# image from https://fedorapeople.org/groups/risc-v/
boot-stage4-in-qemu: stage4-disk.img
	$(MAKE) boot-in-qemu DISK=$<

boot-in-qemu: $(DISK) bbl
	qemu-system-riscv64 \
	    -nographic -machine virt -smp 4 -m 4G \
	    -kernel bbl \
	    -object rng-random,filename=/dev/urandom,id=rng0 \
	    -device virtio-rng-device,rng=rng0 \
	    -append "ro root=/dev/vda" \
	    -drive file=$(DISK),format=raw,if=none,id=hd0 \
	    -device virtio-blk-device,drive=hd0 \
	    -device virtio-net-device,netdev=usernet \
	    -netdev user,id=usernet
