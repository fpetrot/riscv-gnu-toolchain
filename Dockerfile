# vim: tw=0: ai: sw=2: ts=2: sts=2: lbr: et: list

FROM debian:stable-slim

LABEL maintainer="Frédéric Pétrot <frederic.petrot@univ-grenoble-alpes.fr>"
LABEL Description="Image to (cross-)build the binutils in maintainer mode and gcc and qemu afterwards and also cva6 processor"

#
# Set environment
#
# Compile stuff in /root/src,
# install non packaged dependencies in /opt/tools,
# and do the rest as user fred
ENV ROOTSRCS=/root/src
ENV INSTPATH=/opt/tools
ENV USER=fred

#
# Dependencies
#
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests \
        apt-utils \
        autoconf \
        automake \
        autotools-dev \
        autogen \
        babeltrace \
        bc \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        cmake \
        curl \
        device-tree-compiler \
        expect \
        file \
        flex \
        gawk \
        gperf \
        git \
        gtkwave \
        help2man \
        less \
        libdebuginfod-dev \
        libexpat1-dev \
        libfl-dev \
        libfl2 \
        libgmp-dev \
        libgoogle-perftools-dev \
        libmpc-dev \
        libmpfr-dev \
        libgmp-dev \
        libsystemc \
        libsystemc-dev \
        libtool \
        numactl \
        openssh-client \
        perl \
        procps \
        python3 \
        texinfo \
        vim \
        vim-gitgutter \
        wget \
        xsltproc \
        z3 \
        zlib1g \
        zlib1g-dev && \
    apt-get clean && \
    mkdir -p $INSTPATH $ROOTSRCS

#
# According to binutils README-maintainer-mode, we need
# autoconf 2.69
# automake 1.15.1
# libtool 2.2.6
# gettext 0.16.1
# dejagnu 1.5.3
# All from https://ftp.gnu.org/gnu/
#

WORKDIR $ROOTSRCS

RUN curl --remote-name-all \
         https://ftp.gnu.org/gnu/autoconf/autoconf-2.69.tar.xz \
         https://ftp.gnu.org/gnu/automake/automake-1.15.1.tar.xz \
         https://ftp.gnu.org/gnu/libtool/libtool-2.2.6b.tar.lzma \
         https://ftp.gnu.org/gnu/gettext/gettext-0.16.1.tar.gz \
         https://ftp.gnu.org/gnu/dejagnu/dejagnu-1.5.3.tar.gz

RUN tar xf autoconf-2.69.tar.xz && \
    tar xf automake-1.15.1.tar.xz && \
    tar xf libtool-2.2.6b.tar.lzma && \
    tar xf gettext-0.16.1.tar.gz && \
    tar xf dejagnu-1.5.3.tar.gz

ENV PATH=$INSTPATH/bin:$PATH

RUN cd autoconf-2.69 && \
    ./configure --prefix=$INSTPATH && \
    make -j $(nproc) && make install && \
    cd ../automake-1.15.1 && \
    ./configure --prefix=$INSTPATH && \
    make -j $(nproc) && make install && \
    cd ../libtool-2.2.6b && \
    ./configure --prefix=$INSTPATH && \
    make -j $(nproc) && make install && \
    cd ../gettext-0.16.1 && \
    ./configure --prefix=$INSTPATH && \
    make -j $(nproc) && make install && \
    cd ../dejagnu-1.5.3 && \
    ./configure --prefix=$INSTPATH && \
    make -j $(nproc) && make install

#
# Create a user so that development and installation
# takes place in a non-root environment
#
RUN useradd -ms /bin/bash $USER
USER $USER
ENV HOMEDIR=/home/$USER
WORKDIR $HOMEDIR

#
# Give access for external ssh key so that the docker image can be shared
# while being able to use git with ssh
# FIMXE: I could not have that work, back onto https then
#RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts
#RUN --mount=type=ssh ssh -A -v -l git github.com

#
# Fetch the binutils sources
# Since we are working on them, ensure they are repulled if necessary
#
ADD https://api.github.com/repos/fpetrot/riscv-binutils/git/refs/heads/dev/128 version.json
RUN git clone --origin origin https://github.com/fpetrot/riscv-binutils.git
#
# Configure them so as to run in 128-bit, local install path
# Removing the -O2 flags helps avoid run-time errors due to miss-use of the
# movaps instruction (it should use movups).
# To be fixed at some point, live with it for now
#
RUN cd riscv-binutils && \
    git checkout dev/128 && \
    mkdir build-128up && \
    cd build-128up && \
    CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" ../configure --prefix=$HOMEDIR/sandbox \
                                                   --enable-maintainer-mode \
                                                   --target=riscv128-unknown-elf
#
# Compile them
# cxx is a killer when all procs are used, so let leave some cpu time for
# something else
#
RUN cd riscv-binutils/build-128up && \
    make -j $((1 + $(nproc) / 2)) && make install
#
# Add upstream repo for rebasing regularly
#
RUN cd riscv-binutils && \
    git remote add upstream https://sourceware.org/git/binutils-gdb.git

#
# Fetch gcc and compile it
# Strange error on libssp, so disable it
# Plenty of warning because we're using int128 in unexpected places, but
# at the end of the day in kind of works, ...
# Still many cleanups to do, though.
#
RUN git clone --origin origin https://github.com/fpetrot/riscv-gcc.git
RUN cd riscv-gcc && \
    git checkout dev/128 && \
    mkdir build && \
    cd build && \
    CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" CFLAGS_FOR_TARGET="-mcmodel=medany" ../configure --prefix=$HOMEDIR/sandbox \
                                                   --target=riscv128-unknown-elf \
                                                   --enable-languages=c \
                                                   --enable-multilib \
                                                   --with-cmodel=medany \
                                                   --disable-libssp \
                                                   --disable-nls
RUN cd riscv-gcc/build && \
    make -j $((1 + $(nproc) / 2)) && make install

RUN cd riscv-gcc && \
    git remote add upstream https://gcc.gnu.org/git/gcc.git

#
# Let's clone newlib and compile it
# Again many warning, easily explainable because we are really just trying to
# compile the library and have it kinda work, many things to do still
#
# This is to be compiled using our newly created gcc
#
ENV PATH="/home/fred/sandbox/bin:$PATH"

RUN git clone https://github.com/fpetrot/newlib.git

RUN cd newlib && \
    git checkout dev/128 && \
    mkdir build && \
    cd build && \
    CFLAGS="-O0 -g" CXXFLAGS="-march=rv128ima -mabi=llp128" CFLAGS_FOR_TARGET="-mcmodel=medany" \
    ../configure --prefix=$HOMEDIR/sandbox \
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

RUN cd newlib/build && \
    make -j $((1 + $(nproc) / 2)) && make install

RUN cd newlib && \
    git remote add upstream https://sourceware.org/git/newlib-cygwin.git 

USER root
RUN apt-get install -y --no-install-recommends --no-install-suggests \
            python3-minimal python3-venv meson ninja-build pkgconf libglib2.0-dev \
            libpixman-1-dev libcapstone-dev libfdt-dev
USER $USER
#
# Fetch QEMU
#
RUN git clone --origin origin https://github.com/fpetrot/qemu-riscv128.git
#
# Configure for 128-bit, local install path
#
RUN cd qemu-riscv128 && \
    git checkout dev/128 && \
    mkdir build-elf128 && \
    cd build-elf128 && \
    ../configure --prefix=$HOMEDIR/sandbox --target-list=riscv64-softmmu \
                 --enable-debug --enable-capstone
#
# Compile it
#
RUN cd qemu-riscv128/build-elf128 && \
    ninja && ninja install

#
# Add upstream repo for rebasing regularly
#
RUN cd qemu-riscv128 && \
    git remote add upstream https://github.com/qemu/qemu

#
# Finally fetch the existing 128-bit tests, as examples
#
RUN git clone --origin origin https://github.com/fpetrot/128-test.git

RUN cd 128-test && \
    git checkout dev/128
#
# fetch the openhwgroup cva6 core updated to 128-bit
#
RUN git clone https://github.com/fpetrot/cva6.git


#
# fetch riscvbarelib os
#
RUN git clone https://github.com/cfuguet/riscvbarelib.git && \
    cd riscvbarelib/ && \
    git checkout dev/128 && \
    make BSP=$PWD/bsp/ariane_testharness O=../rv128_ariane_testharness \
    XLEN=128 RISCV_PREFIX=riscv128-unknown-elf- BSP_ATOMIC=1 BSP_COMPRESSED=1 BSP_FLOAT=1 BSP_FPU=1

#
# fetch riscvbareapps
#
RUN git clone https://github.com/cfuguet/riscvbareapps.git


#
# Configure for 128-bit, local install path
#
RUN cd cva6 && \
    git checkout dev/128 && \
    git config --global --add safe.directory /home/fred/cva6 && \
    git submodule update --init --recursive

RUN cd cva6 && \
    mkdir -p tools/toolchain/ && \
    export RISCV=$HOMEDIR/cva6/tools/toolchain && \
    INSTALL_DIR=$RISCV && \
    cd util/toolchain-builder/ && \
    bash get-toolchain.sh && \
    bash build-toolchain.sh $INSTALL_DIR

RUN cd cva6 && \
    export RISCV=$HOMEDIR/cav6/tools/toolchain && \
    bash verif/regress/install-verilator.sh && \
    cp -r tools/verilator* tools/verilator && \
    bash verif/regress/install-spike.sh


#
# We unfortunately need to debug our stuff, so let us install gdb
#
USER root
RUN apt-get install -y --no-install-recommends --no-install-suggests \
            gdb
#
# Let's have some simple configuration, in particular autoindent that follows
# GNU's or QEMU coding standards
#
# escape=\
USER $USER
RUN echo "set -o vi" >> $HOMEDIR/.bashrc
RUN echo "export LESSCHARSET=utf-8" >> $HOMEDIR/.bashrc
RUN echo "export PATH=\$HOME/sandbox/bin:\$PATH" >> $HOMEDIR/.bashrc
RUN echo "export RISCV=\$HOME/cva6/tools/toolchain:\$PATH" >> $HOMEDIR/.bashrc
RUN echo "source \$VIMRUNTIME/defaults.vim" >> $HOMEDIR/.vimrc
RUN echo "map ; ." >> $HOMEDIR/.vimrc
RUN echo "set mouse=" >> $HOMEDIR/.vimrc
RUN echo "function! GnuIndent()" >> $HOMEDIR/.vimrc
RUN echo "setlocal cinoptions=>4,n-2,{2,^-2,:2,=2,g0,h2,p5,t0,+2,(0,u0,w1,m1" >> $HOMEDIR/.vimrc
RUN echo "setlocal shiftwidth=2" >> $HOMEDIR/.vimrc
RUN echo "setlocal tabstop=8" >> $HOMEDIR/.vimrc
RUN echo "endfunction" >> $HOMEDIR/.vimrc
RUN echo "function! QemuIndent()" >> $HOMEDIR/.vimrc
RUN echo "setlocal shiftwidth=4" >> $HOMEDIR/.vimrc
RUN echo "setlocal expandtab" >> $HOMEDIR/.vimrc
RUN echo "endfunction" >> $HOMEDIR/.vimrc
RUN echo "au BufRead */qemu-*/*.{c,cpp,h} call QemuIndent()" >> $HOMEDIR/.vimrc
