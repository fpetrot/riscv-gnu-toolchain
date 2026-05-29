HOMEDIR=/home/$(USER)
NPROC=$(shell nproc)

.PHONY: binutils gcc build-newlib qemu build-cva6 setup build setup-binutils setup-gcc setup-newlib setup-qemu-riscv128 build-riscvbarelib setup-cva6

setup: version.json setup-binutils setup-gcc setup-newlib setup-qemu-riscv128 128-test setup-cva6 riscvbarelib riscvbareapps
build: binutils gcc build-newlib qemu build-cva6 build-riscvbarelib

version.json:
	curl https://api.github.com/repos/fpetrot/riscv-binutils/git/refs/heads/dev/128 > version.json

riscv-binutils:
	#
	# Fetch binutils sources.
	#
	git clone --origin origin https://github.com/fpetrot/riscv-binutils.git
	#
	# Add upstream repo for rebasing regularly
	#
	cd riscv-binutils && \
		git remote add upstream https://sourceware.org/git/binutils-gdb.git

setup-binutils: riscv-binutils
	#
	# Configure them so as to run in 128-bit, local install path
	# Removing the -O2 flags helps avoid run-time errors due to miss-use of the
	# movaps instruction (it should use movups).
	# To be fixed at some point, live with it for now
	#
	cd riscv-binutils && \
		mkdir build-128up -p && \
		cd build-128up && \
		git checkout dev/128 && \
		CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" ../configure --prefix=$(HOMEDIR)/sandbox \
													   --enable-maintainer-mode \
													   --target=riscv128-unknown-elf

binutils: riscv-binutils
	#
	# Compile them
	# cxx is a killer when all procs are used, so let leave some cpu time for
	# something else
	#
	cd riscv-binutils/build-128up && \
		make -j $(NPROC) && make install

riscv-gcc:
	#
	# Fetch gcc sources.
	#
	git clone --origin origin https://github.com/fpetrot/riscv-gcc.git

	cd riscv-gcc && \
		git remote add upstream https://gcc.gnu.org/git/gcc.git

setup-gcc: riscv-gcc
	#
	# Configure gcc compilation.
	# Strange error on libssp, so disable it
	# Plenty of warning because we're using int128 in unexpected places, but
	# at the end of the day in kind of works, ...
	# Still many cleanups to do, though.
	#
	cd riscv-gcc && \
		git checkout dev/128 && \
		mkdir build -p && \
		cd build && \
		CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" CFLAGS_FOR_TARGET="-mcmodel=medany" ../configure --prefix=$(HOMEDIR)/sandbox \
																						   --target=riscv128-unknown-elf \
																						   --enable-languages=c \
																						   --enable-multilib \
																						   --with-cmodel=medany \
																						   --disable-libssp \
																						   --disable-nls

gcc: riscv-gcc
	#
	# Compile gcc.
	# 
	cd riscv-gcc/build && \
		make -j $(NPROC) && make install


newlib:
	#
	# Let's clone newlib.
	#
	git clone https://github.com/fpetrot/newlib.git
	cd newlib && \
		git remote add upstream https://sourceware.org/git/newlib-cygwin.git 

setup-newlib: newlib
	#
	# Let's configure newlib.
	#
	# This is to be compiled using our newly created gcc
	#
	cd newlib && \
		git checkout dev/128 && \
		mkdir build -p && \
		cd build && \
		CFLAGS="-O0 -g" CXXFLAGS="-march=rv128ima -mabi=llp128" CFLAGS_FOR_TARGET="-mcmodel=medany" \
		../configure --prefix=$(HOMEDIR)/sandbox \
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
		--with-arch=rv128ima \
		--with-abi=llp128 \
		--enable-newlib-io-long-long


build-newlib: newlib
	#
	# Compile newlib.
	# Again many warning, easily explainable because we are really just trying to
	# compile the library and have it kinda work, many things to do still
	#
	cd newlib/build && \
		make -j $(NPROC) && make install

qemu-riscv128:
	#
	# Fetch QEMU
	#
	git clone --origin origin https://github.com/fpetrot/qemu-riscv128.git
	#
	# Add upstream repo for rebasing regularly
	#
	cd qemu-riscv128 && \
		git remote add upstream https://github.com/qemu/qemu

setup-qemu-riscv128: qemu-riscv128
	#
	# Configure for 128-bit, local install path
	#
	cd qemu-riscv128 && \
		git checkout dev/128 && \
		mkdir build-elf128 -p && \
		cd build-elf128 && \
		../configure --prefix=$(HOMEDIR)/sandbox --target-list=riscv64-softmmu \
					 --enable-debug --enable-capstone

qemu: qemu-riscv128
	#
	# Compile it
	#
	cd qemu-riscv128/build-elf128 && \
		ninja && ninja install

128-test:
	#
	# Finally fetch the existing 128-bit tests, as examples
	#
	git clone --origin origin https://github.com/fpetrot/128-test.git

	cd 128-test && \
		git checkout dev/128

cva6:
	#
	# fetch the openhwgroup cva6 core updated to 128-bit
	#
	git clone https://github.com/fpetrot/cva6.git

setup-cva6: cva6
	#
	# Configure for 128-bit, local install path
	#
	cd cva6 && \
		NUM_JOBS=$(NPROC) && \
		git checkout dev/128 && \
		git config --global --add safe.directory /home/$(USER)/cva6 && \
		git submodule update --init --recursive


build-cva6:
	cd cva6 && \
		NUM_JOBS=$(NPROC) && \
		mkdir -p tools/toolchain/ && \
		export RISCV=$(HOMEDIR)/cva6/tools/toolchain && \
		INSTALL_DIR=$$RISCV && \
		cd util/toolchain-builder/ && \
		bash get-toolchain.sh && \
		bash build-toolchain.sh $$INSTALL_DIR

	cd cva6 && \
		NUM_JOBS=$(NPROC) && \
		export RISCV=$(HOMEDIR)/cav6/tools/toolchain && \
		bash verif/regress/install-verilator.sh && \
		cp -rf tools/verilator-* tools/verilator && \
		bash verif/regress/install-spike.sh
	

riscvbarelib:
	#
	# fetch riscvbarelib os
	#
	git clone https://github.com/cfuguet/riscvbarelib.git && \
		cd riscvbarelib/ && \
		git checkout dev/128

build-riscvbarelib: riscvbarelib
	make BSP=$$PWD/bsp/ariane_testharness O=../rv128_ariane_testharness \
		XLEN=128 RISCV_PREFIX=riscv128-unknown-elf- BSP_ATOMIC=1 BSP_COMPRESSED=1 BSP_FLOAT=1 BSP_FPU=1

riscvbareapps:
	#
	# fetch riscvbareapps
	#
	git clone https://github.com/cfuguet/riscvbareapps.git

