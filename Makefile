SANDBOX=$(shell pwd)/sandbox
XLEN=128
MARCH=rv$(XLEN)ima
MABI=llp$(XLEN)
# By default, test everything in the testsuites.
CHECK=check

# If REF is defined, we are building a reference toolchain. Add a suffix to build dirs.
ifdef REF
REF_SUFFIX=-ref
endif

# Suffix used in the name of build directories
BUILD=$(XLEN)$(REF_SUFFIX)

.PHONY: help binutils gcc build-newlib qemu build-cva6 build setup-binutils check-binutils compare-binutils setup-gcc check-gcc compare-gcc setup-newlib setup-qemu build-riscvbarelib setup-cva6 create-container dk

help:
	@awk 'BEGIN {FS = ":.*##!"; printf "Usage: make \033[32m<commande>\033[0m \
	\nRules per \033[36mcategories :\n"} \
	/^[a-zA-Z0-9_-]+:.*##!/ { printf "  \033[32m%-20s\033[0m %s\n", $$1, $$2 } \
	/^##@/ { printf "\n\033[36m%s\033[0m\n", substr($$0, 5) } \
	END { printf "\n\033[35mXLEN=64\033[0m can be used on each commands to build the same tool in 64bits, or in 32bits. \
	\n\033[35mCHECK=check-xxx\033[0m can be used on check commands to test a specific testsuite (check-gcc, check-ld, ...). \
	\n\nExample: \033[33mmake check-binutils XLEN=64 CHECK=check-ld -j$$(nproc)\033[0m\n\n" }' $(MAKEFILE_LIST)

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
	rm riscv-binutils/build-$(BUILD) -rf
	rm riscv-gcc/build-$(XLEN) -rf
	rm newlib/build-$(XLEN) -rf
	rm qemu-riscv/build -rf
	rm rv$(XLEN)_ariane_testharness -rf
	$(MAKE) -C 128-test clean

version.json:
	curl https://api.github.com/repos/fpetrot/riscv-binutils/git/refs/heads/dev/128 > version.json

# Build a custom specifier to print int128_t using printf
printf_128.o: printf_128.c
	$(CC) -c $^ -o $@

##@ Binutils

riscv-binutils: ##! Fetch binutils sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/riscv-binutils.git

	cd riscv-binutils && \
		git remote add upstream https://sourceware.org/git/binutils-gdb.git

setup-binutils: riscv-binutils printf_128.o ##! Configure binutils compilation.
	@#
	@# Configure them so as to run in 128-bit, local install path
	@# Removing the -O2 flags helps avoid run-time errors due to miss-use of the
	@# movaps instruction (it should use movups).
	@# To be fixed at some point, live with it for now
	@#
	cd riscv-binutils && \
		mkdir build-$(BUILD) -p && \
		cd build-$(BUILD) && \
		CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" \
		LDFLAGS="$(PWD)/printf_128.o" ../configure --prefix=$(SANDBOX) \
												   --enable-maintainer-mode \
												   --target=riscv$(XLEN)-unknown-elf

binutils: printf_128.o ##! Compile binutils.
	$(MAKE) -C riscv-binutils/build-$(BUILD) && $(MAKE) -C riscv-binutils/build-$(BUILD) install

check-binutils: ##! Run the riscv binutils testsuite.
	$(MAKE) -C riscv-binutils/build-$(BUILD) $(CHECK) -k

compare-binutils: ##! Compare binutils testsuite between upstream 64bits and patched 128bits. This require a 64bits toolchain built using XLEN=64 on the binutils upstream/master branch.
	$(MAKE) check-binutils XLEN=64 > before.log
	$(MAKE) check-binutils > after.log
	./riscv-gcc/contrib/compare_tests before.log after.log

##@ GCC

riscv-gcc: ##! Fetch gcc sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/riscv-gcc.git

	cd riscv-gcc && \
		git remote add upstream https://gcc.gnu.org/git/gcc.git

# When targeting gcc 64 or 32bits, only build multilib for rv64 and not rv128, because the associated binutils don't support elf128
# The generator arguments come from the file riscv-gcc/gcc/config/riscv/t-elf-multilib
MULTILIB_LIST_32_64_BITS = --with-multilib-generator="rv32i-ilp32--c rv32im-ilp32--c rv32iac-ilp32-- rv32imac-ilp32-- rv32imafc-ilp32f-rv32imafdc- rv64imac-lp64-- rv64imafdc-lp64d--"
ifeq ($(XLEN),32)
MULTILIB_LIST = $(MULTILIB_LIST_32_64_BITS)
else ifeq ($(XLEN),64)
MULTILIB_LIST = $(MULTILIB_LIST_32_64_BITS)
else
MULTILIB_LIST =
endif

setup-gcc: riscv-gcc printf_128.o ##! Configure gcc compilation.
	@#
	@# Strange error on libssp, so disable it
	@# Plenty of warning because we're using int128 in unexpected places, but
	@# at the end of the day in kind of works, ...
	@# Still many cleanups to do, though.
	@#
	cd riscv-gcc && \
		mkdir build-$(XLEN) -p && \
		cd build-$(XLEN) && \
		CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" \
		CFLAGS_FOR_TARGET="-mcmodel=medany" LDFLAGS="$(PWD)/printf_128.o" ../configure --prefix=$(SANDBOX) \
																					   --target=riscv$(XLEN)-unknown-elf \
																					   --enable-languages=c \
																					   --enable-multilib \
																					   $(MULTILIB_LIST) \
																					   --with-cmodel=medany \
																					   --disable-libssp \
																					   --disable-nls

gcc: riscv-gcc printf_128.o ##! Compile gcc.
	$(MAKE) -C riscv-gcc/build-$(XLEN) && $(MAKE) -C riscv-gcc/build-$(XLEN) install

check-gcc: ##! Run the riscv gcc testsuite in QEMU simulator.
	$(MAKE) -C riscv-gcc/build-$(XLEN) $(CHECK) -k RUNTESTFLAGS="--target_board=riscv$(XLEN)-sim $(RUNTESTFLAGS)"

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
		CFLAGS="-O2 -g" CXXFLAGS="-march=$(MARCH) -mabi=$(MABI)" CFLAGS_FOR_TARGET="-mcmodel=medany" \
		../configure --prefix=$(SANDBOX) \
					 --target=riscv$(XLEN)-unknown-elf \
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

qemu-riscv: ##! Fetch qemu sources and add upstream repo for rebasing regularly.
	git clone -b dev/128 --origin origin https://github.com/fpetrot/qemu-riscv128.git qemu-riscv

	cd qemu-riscv && \
		git remote add upstream https://github.com/qemu/qemu

setup-qemu: qemu-riscv ##! Configure qemu compilation.
	@#
	@# Configure for 128-bit, local install path
	@#
	cd qemu-riscv && \
		mkdir build -p && \
		cd build && \
		../configure --prefix=$(SANDBOX) --target-list=riscv64-softmmu \
					 --enable-debug --enable-capstone

qemu: ##! Compile qemu.
	cd qemu-riscv/build && \
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
			XLEN=$(XLEN) RISCV_PREFIX=riscv$(XLEN)-unknown-elf- BSP_ATOMIC=1 BSP_COMPRESSED=1 BSP_FLOAT=1 QEMU=1

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
