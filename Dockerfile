# vim: tw=0: ai: sw=2: ts=2: sts=2: lbr: et: list

FROM debian:stable-slim

LABEL maintainer="Frédéric Pétrot <frederic.petrot@univ-grenoble-alpes.fr>"
LABEL Description="Image to (cross-)build the binutils in maintainer mode and gcc and qemu afterwards."

#
# Set environment
#
# Compile stuff in /root/src,
# install non packaged dependencies in /opt/tools
ENV ROOTSRCS=/root/src
ENV INSTPATH=/opt/tools

#
# Dependencies
#
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-install-suggests \
        autoconf \
        automake \
        autotools-dev \
        autogen \
        bison \
        build-essential \
        ca-certificates \
        ccache \
        cmake \
        curl \
        expect \
        file \
        flex \
        gawk \
        gperf \
        git \
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
        perl \
        python3 \
        texinfo \
        xsltproc \
        wget && \
    apt-get clean && \
    mkdir -p $INSTPATH $ROOTSRCS

#
# Qemu needs some specific stuff
#
RUN apt-get install -y --no-install-recommends --no-install-suggests \
            python3-minimal python3-venv meson ninja-build pkgconf libglib2.0-dev \
            libpixman-1-dev libcapstone-dev libfdt-dev
#
# We unfortunately need to debug our stuff, so let us install gdb
#
RUN apt-get install -y --no-install-recommends --no-install-suggests \
            gdb

# Dependencies to run tests
RUN apt-get install -y --no-install-recommends --no-install-suggests \
            python3-pytest python3-pytest-xdist python3-matplotlib

#
# According to binutils README-maintainer-mode, we need
# autoconf 2.69
# automake 1.15.1
# libtool 2.2.6
# gettext 0.16.1
# dejagnu 1.5.3
# All from https://ftp.gnu.org/gnu/
#

RUN mkdir -p $INSTPATH $ROOTSRCS
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

# Add the riscv simulator file for dejagnu runtest
COPY riscv64-sim.exp /opt/tools/share/dejagnu/baseboards/riscv64-sim.exp
COPY riscv128-sim.exp /opt/tools/share/dejagnu/baseboards/riscv128-sim.exp

# Built binaries will be here
ENV PATH="/work/sandbox/bin:$PATH"
WORKDIR /work
