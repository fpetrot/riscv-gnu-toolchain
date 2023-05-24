128-bit RISC-V GNU Cross Development Environment
================================================

This repo contains the necessary stuff to built a 128-bit RISC-V GNU Cross Development Environment.
It support, with bugs, the usual cross-development tools and allows to compile and test simple bare metal programs for now.

This was a kind of a fork of https://github.com/riscv-collab/riscv-gnu-toolchain done in May 2022.
But now that almost all riscv specific stuff has been upstreamed, there is no clear reason to (try to) maintain this stuff that is in essence a set of moving pointers.

To make things easier (...) it is now under the form of a docker file that fetches the rights repositories and builds the whole stuff.
All tools sources are kept, since this docker is meant to be used for development.

The docker image contains a native gdb since there are still many bugs floating around, along with vim and a base configuration file for proper indentation in QEMU and in the Gnu tools, so you might get started quickly.
Note that bash is configured in vi mode, so you can remember what life was before the internet.

For gcc, available ABI options are llp128, llp128f, llp128d 128-bit support is experimental, known issues are:

-   soft floating point operations have erratic behaviour, support for 128-bit words is not done
-   hard floating points moves (fmv) are currently seen as illegal by qemu (I believe I patched this but I am not sure anymore)
-   gdb somtimes crashs in case of memory accesse
-   newlib has not been tested yet, this may not work
-   linux configuration is not supported
-   musl configuration is not supported

Seems useful to compile with:

- `-mcmodel=medany` to avoid overflow on the 20-bit offsets used here and there
- `-fno-builtin` as we did not handle well the memcpy and memset builtins, and weird behavior occurs when they are used

Note that although vanilla QEMU supports the 128-bit instructions, it still lives with elf64 as the natural executable format even for 128-bit executables.
The `elf128` branch of our QEMU fork parses the elf128 format we defined and that is generated by this toolchain and sends gdb the proper information for debugging 128-bit executables too.

All of that is within the docker, along with our 128-bit unit tests.
Check the makefiles and qemu invocation there for example.

Building and using the docker image
=========================

```
$ docker build . -t rv128
$ docker run --name dev/128 -tid rv128 bash
$ docker attach dev/128
# And if you need several shells in the container, with, e.g. tmux
$ docker exec -it /dev/128 bash
```

`scp` is available, so you can copy from the host your `.gitconfig` and `.ssh` directories to access the git repos at will.
This is not the recommended use of docker, but I find it pretty adapted to the need.
