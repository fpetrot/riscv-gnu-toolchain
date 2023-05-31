# vim: tw=0: ai: sw=2: ts=2: sts=2: lbr: et: list

FROM debian:bookworm-slim

LABEL maintainer="Frédéric Pétrot <frederic.petrot@univ-grenoble-alpes.fr>"
LABEL Description="Image to (cross-)build the binutils in maintainer mode and gcc and qemu afterwards"

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
    apt-get install -y --no-install-recommends --no-install-suggests \
            apt-utils less build-essential bison flex \
            libgmp-dev libmpfr-dev libmpc-dev libexpat1-dev libdebuginfod-dev \
            ca-certificates git curl xsltproc babeltrace \
            file texinfo gperf expect vim vim-gitgutter openssh-client && \
    apt-get autoclean && \
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
ENV HOMEDIR /home/$USER
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
ADD https://api.github.com/repos/fpetrot/riscv-binutils/git/refs/heads/128up version.json
RUN git clone --origin origin https://github.com/fpetrot/riscv-binutils.git
#
# Configure them so as to run in 128-bit, local install path
# Removing the -O2 flags helps avoid run-time errors due to miss-use of the
# movaps instruction (it should use movups).
# To be fixed at some point, live with it for now
#
RUN cd riscv-binutils && \
    git checkout 128up && \
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
    CFLAGS="-O0 -g" CXXFLAGS="-O0 -g" ../configure --prefix=$HOMEDIR/sandbox \
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
    mkdir build && \
    cd build && \
    ../configure --prefix=/home/fred/sandbox --target=riscv128-unknown-elf

RUN cd newlib/build && \
    make -j $((1 + $(nproc) / 2)) && make install

USER root
RUN apt-get install -y --no-install-recommends --no-install-suggests \
            python3-minimal meson ninja-build pkgconf libglib2.0-dev \
            libpixman-1-dev libcapstone-dev
USER $USER
#
# Fetch QEMU
#
RUN git clone --origin origin https://github.com/fpetrot/qemu-riscv128.git
#
# Configure for 128-bit, local install path
#
RUN cd qemu-riscv128 && \
    git checkout elf128 && \
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
