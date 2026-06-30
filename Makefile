SANDBOX=$(shell pwd)/sandbox
XLEN=128
MARCH=rv$(XLEN)ima
MABI=llp$(XLEN)

.PHONY: help binutils gcc build-newlib qemu build-cva6 setup build setup-binutils setup-gcc setup-newlib setup-qemu build-riscvbarelib setup-cva6 create-container dk

help:
	@awk 'BEGIN {FS = ":.*##!"; printf "Usage: make \033[32m<commande>\033[0m \
	\nRules per \033[36mcategories :\n"} \
	/^[a-zA-Z0-9_-]+:.*##!/ { printf "  \033[32m%-20s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[36m%s\033[0m\n", substr($$0, 5) } \
	END { printf "\n\033[35mXLEN=64\033[0m can be used on each commands to build the same tool in 64bits.\n" }' $(MAKEFILE_LIST)

##@ General

build: version.json ##! Fetch, configure and compile every components.
	$(MAKE) setup-binutils && $(MAKE) binutils
	$(MAKE) setup-gcc && $(MAKE) gcc
	$(MAKE) setup-newlib && $(MAKE) build-newlib
	$(MAKE) setup-qemu && $(MAKE) qemu
	$(MAKE) riscvbarelib && $(MAKE) build-riscvbarelib
	$(MAKE) riscvbareapps
	$(MAKE) 128-test

clean: ##! Cleanup everything.
	rm $(SANDBOX) -rf
	rm riscv-binutils/build-$(XLEN) -rf
	rm riscv-gcc/build-$(XLEN) -rf
	rm newlib/build-$(XLEN) -rf
	rm qemu-riscv128/build -rf
	rm rv$(XLEN)_ariane_testharness -rf
	$(MAKE) -C 128-test clean

version.json:
	curl https://api.github.com/repos/fpetrot/riscv-binutils/git/refs/heads/dev/128 > version.json

##@ Binutils

riscv-binutils: ##! Fetch binutils sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/riscv-binutils.git

	cd riscv-binutils && \
		git remote add upstream https://sourceware.org/git/binutils-gdb.git

setup-binutils: riscv-binutils ##! Configure binutils compilation.
	@#
	@# Configure them so as to run in 128-bit, local install path
	@# Removing the -O2 flags helps avoid run-time errors due to miss-use of the
	@# movaps instruction (it should use movups).
	@# To be fixed at some point, live with it for now
	@#
	cd riscv-binutils && \
		mkdir build-$(XLEN) -p && \
		cd build-$(XLEN) && \
		CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" ../configure --prefix=$(SANDBOX) \
													   --enable-maintainer-mode \
													   --target=riscv$(XLEN)-unknown-elf

binutils: ##! Compile binutils.
	$(MAKE) -C riscv-binutils/build-$(XLEN) && $(MAKE) -C riscv-binutils/build-$(XLEN) install

##@ GCC

riscv-gcc: ##! Fetch gcc sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/riscv-gcc.git

	cd riscv-gcc && \
		git remote add upstream https://gcc.gnu.org/git/gcc.git

setup-gcc: riscv-gcc ##! Configure gcc compilation.
	@#
	@# Strange error on libssp, so disable it
	@# Plenty of warning because we're using int128 in unexpected places, but
	@# at the end of the day in kind of works, ...
	@# Still many cleanups to do, though.
	@#
	cd riscv-gcc && \
		mkdir build-$(XLEN) -p && \
		cd build-$(XLEN) && \
		CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" CFLAGS_FOR_TARGET="-mcmodel=medany" ../configure --prefix=$(SANDBOX) \
																						   --target=riscv$(XLEN)-unknown-elf \
																						   --enable-languages=c \
																						   --enable-multilib \
																						   --with-cmodel=medany \
																						   --disable-libssp \
																						   --disable-nls

gcc: riscv-gcc ##! Compile gcc.
	$(MAKE) -C riscv-gcc/build-$(XLEN) && $(MAKE) -C riscv-gcc/build-$(XLEN) install

check-gcc: ##! Run the riscv gcc testsuite in QEMU simulator.
	$(MAKE) -C riscv-gcc/build-$(XLEN) check-gcc -k RUNTESTFLAGS="--target_board=riscv-sim riscv.exp"

compare-gcc: ##! Compare gcc testsuite between upstream 64bits and patched 128bits. This require a 64bits toolchain built using XLEN=64 on the gcc upstream/master branch.
	$(MAKE) check-gcc XLEN=64 > before.log
	$(MAKE) check-gcc > after.log
	./riscv-gcc/contrib/compare_tests before.log after.log

##@ Newlib

newlib: ##! Fetch newlib sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 https://github.com/fpetrot/newlib.git

	cd newlib && \
		git remote add upstream https://sourceware.org/git/newlib-cygwin.git 

setup-newlib: newlib ##! Configure newlib compilation.
	@#
	@# This is to be compiled using our newly created gcc
	@#
	cd newlib && \
		mkdir build-$(XLEN) -p && \
		cd build-$(XLEN) && \
		CFLAGS="-O0 -g" CXXFLAGS="-march=$(MARCH) -mabi=$(MABI)" CFLAGS_FOR_TARGET="-mcmodel=medany" \
		../configure --prefix=$(SANDBOX) \
					 --target=riscv128-unknown-elf \
					 --enable-newlib-reent-small \
					 --enable-newlib-nano-malloc \
					 --enable-newlib-global-atexit \
					 --enable-lite-exit \
					 --enable-multilib \
					 --disable-newlib-fvwrite-in-streamio \
					 --disable-newlib-fseek-optimization \
					 --disable-newlib-wide-orient \
					 --disable-newlib-unbuf-stream-opt \
					 --disable-newlib-supplied-syscalls \
					 --disable-nls \
					 --disable-newlib-multithread \
					 --with-arch=$(MARCH) \
					 --with-abi=$(MABI) \
					 --enable-newlib-io-long-long


build-newlib: newlib ##! Compile newlib.
	@#
	@# Again many warning, easily explainable because we are really just trying to
	@# compile the library and have it kinda work, many things to do still
	@#
	$(MAKE) -C newlib/build-$(XLEN) && $(MAKE) -C newlib/build-$(XLEN) install

##@ QEMU

qemu-riscv128: ##! Fetch qemu sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/qemu-riscv128.git

	cd qemu-riscv128 && \
		git remote add upstream https://github.com/qemu/qemu

setup-qemu: qemu-riscv128 ##! Configure qemu compilation.
	@#
	@# Configure for 128-bit, local install path
	@#
	cd qemu-riscv128 && \
		mkdir build -p && \
		cd build && \
		../configure --prefix=$(SANDBOX) --target-list=riscv64-softmmu \
					 --enable-debug --enable-capstone

qemu: ##! Compile qemu.
	cd qemu-riscv128/build && \
		ninja && ninja install

##@ Tests

128-test: ##! Fetch the existing 128-bit tests, as examples.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/128-test.git

check: 128-test ##! Run tests using the toolchain.
	$(MAKE) -C 128-test check

##@ RiscvBarelib

riscvbarelib: ##! Fetch riscvbarelib os sources.
	git clone -b dev/128 https://github.com/cfuguet/riscvbarelib.git

build-riscvbarelib: riscvbarelib ##! Compile riscvbarelib.
	$(MAKE) -C riscvbarelib BSP=bsp/ariane_testharness O=../rv$(XLEN)_ariane_testharness \
			XLEN=$(XLEN) RISCV_PREFIX=riscv128-unknown-elf- BSP_ATOMIC=1 BSP_COMPRESSED=1 BSP_FLOAT=1 QEMU=1

riscvbareapps: ##! Fetch riscvbareapps examples.
	git clone https://github.com/cfuguet/riscvbareapps.git

$(SANDBOX):
	mkdir $(SANDBOX) -p

##@ Docker

create-image: $(SANDBOX) ##! Create the docker image used to compile everything.
	USER_ID=$(shell id -u) \
		GROUP_ID=$(shell id -g) \
		docker compose build

dk: $(SANDBOX) ##! Run the docker container.
	USER_ID=$(shell id -u) \
		GROUP_ID=$(shell id -g) \
		docker compose run --rm --name riscv128-toolchain riscv128-toolchain
