# Note we cannot just choose these at random.  We must use versions
# which are compatible with the qemu / hardware we are using and the
# privspec.
KERNEL_VERSION   = 4.1.26
KERNEL_BRANCH    = linux-4.1.y-riscv

kdir             = linux-$(KERNEL_VERSION)

all: vmlinux

vmlinux: $(kdir)/vmlinux
	cp $^ $@

$(kdir)/vmlinux: $(kdir)/.config
	$(MAKE) -C $(kdir) ARCH=riscv64 vmlinux

$(kdir)/.config: config $(kdir)/Makefile
	$(MAKE) -C $(kdir) ARCH=riscv64 defconfig
	cat config >> $@
	$(MAKE) -C $(kdir) ARCH=riscv64 olddefconfig

$(kdir)/Makefile: riscv-linux
	rm -rf $(kdir) $(kdir)-t
	cp -a $< $(kdir)-t
	cd $(kdir)-t && git fetch
	cd $(kdir)-t && git checkout -f -t origin/$(KERNEL_BRANCH)
	cd $(kdir)-t && make mrproper
# So we can build with ARCH=riscv64:
# https://github.com/palmer-dabbelt/riscv-gentoo-infra/blob/master/patches/linux/0001-riscv64_makefile.patch
	cd $(kdir)-t && patch -p1 < ../0001-riscv64_makefile.patch
# Fix infinite loop when clearing memory
# https://github.com/riscv/riscv-linux/commit/77148ef248f72bb96b5cacffc0a69bca445de214
	cd $(kdir)-t && patch -p1 < ../0001-Fix-infinite-loop-in-__clear_user.patch
	mv $(kdir)-t $(kdir)

riscv-linux:
	rm -rf $@ $@-t
	git clone https://github.com/riscv/riscv-linux $@-t
	mv $@-t $@

clean:
	rm -f *~
	rm -f vmlinux
	rm -rf $(kdir)

# This is for test-booting the kernel against a stage4 disk
# image from https://fedorapeople.org/groups/risc-v/
boot-stage4-in-qemu: stage4-disk.img
	$(MAKE) boot-in-qemu DISK=$<

boot-in-qemu: $(DISK) $(vmlinux)
	qemu-system-riscv -m 4G -kernel /usr/bin/bbl \
	    -append vmlinux \
	    -drive file=$(DISK),format=raw -nographic
