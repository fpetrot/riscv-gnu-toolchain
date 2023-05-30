# ELF128 Application Binary Interface Specification Proposal for the RISC-V 128-bit Extension

This is a tentative to write down what we actually did to produce 128-bit objects and executables with the RISC-V cross-dev toolchain and run them into QEMU.
The sources on which this document is based are Linux `/usr/include/elf.h`, QEMU `include/elf.h` and `man elf` on my linux laptop.


## Elf128 C Language Data Model

For an explanation about the C Language Data Model and its consequences, see [64-bit and Data Size Neutrality](https://unix.org/whitepapers/64bit.html)

The RISC-V specification defines the ILP32[fd] and LP64[fd] ABIs for `xlen=32` and `xlen=64` respectively.
To be consistant with these choices, we propose to use an LLP128[fd] when `xlen=128`.

To summarize:

| Data Type | ILP32 |  LP64 | LLP64 |
| -----     | ----  |  ---- | ----  |
| char      | 8     |  8    | 8     |
| short     | 16    |  16   | 16    |
| int32     |       |       |       |
| int       | 32    |  32   | 32    |
| long      | 32    |  64   | 64    |
| long long | 64    |  64   | 128   |
| pointer   | 32    |  64   | 128   |

## Data Representation

This is a direct consequence of the choice of the Data Model.

**128-Bit Data Types**

| Name             | Size   | Alignment   | Purpose                    |
| --------------   | ------ | ----------- | -------------------------- |
| `Elf128_Addr`    | `16`   | `16`        | Unsigned program address   |
| `Elf128_Off`     | `16`   | `16`        | Unsigned file offset       |
| `Elf128_Half`    | `2`    | `2`         | Unsigned medium integer    |
| `Elf128_Word`    | `4`    | `4`         | Unsigned integer           |
| `Elf128_Sword`   | `4`    | `4`         | Signed integer             |
| `Elf128_Xword`   | `8`    | `8`         | Unsigned long integer      |
| `Elf128_Sxword`  | `8`    | `8`         | Signed long integer        |
| `Elf128_Xxword`  | `16`   | `16`        | Unsigned long long integer |
| `Elf128_Sxxword` | `16`   | `16`        | Signed long long integer   |
| `unsigned char`  | `1`    | `1`         | Unsigned small integer     |


## ELF Header

Similarly to the choices done when defining elf64 based on elf32, we move a few fields around to ensure proper (16-bytes) alignment of the 128-bit fields.
It is not as issue that the structure itself is not 16-bytes aligned.

    #define EI_NIDENT 16

    typedef struct {
            unsigned char   e_ident[EI_NIDENT];
            Elf128_Half     e_type;
            Elf128_Half     e_machine;
            Elf128_Word     e_version;
            Elf128_Word     e_flags;
            Elf128_Half     e_ehsize;
            Elf128_Half     e_phentsize;
            Elf128_Addr     e_entry;
            Elf128_Off      e_phoff;
            Elf128_Off      e_shoff;
            Elf128_Half     e_phnum;
            Elf128_Half     e_shentsize;
            Elf128_Half     e_shnum;
            Elf128_Half     e_shstrndx;
    } Elf128_Ehdr;


### ELF Possible classes

EI_CLASS

| Name         | Value | Meaning         |
| ----         | ----  | ----            |
| ELFCLASSNONE | 0     | Invalid class   |
| ELFCLASS32   | 1     | 32-bit objects  |
| ELFCLASS64   | 2     | 64-bit objects  |
| ELFCLASS128  | 3     | 128-bit objects |

## ELF Section Header

    typedef struct {
        Elf128_Word   sh_name;
        Elf128_Word   sh_type;
        Elf128_Xxword sh_flags;
        Elf128_Addr   sh_addr;
        Elf128_Off    sh_offset;
        Elf128_Xxword sh_size;
        Elf128_Word   sh_link;
        Elf128_Word   sh_info;
        Elf128_Xxword sh_addralign;
        Elf128_Xxword sh_entsize;
    } Elf128_Shdr;

    typedef struct {
        Elf128_Word   ch_type;
        Elf128_Word   ch_reserved[3];
        Elf128_Xxword ch_size;
        Elf128_Xxword ch_addralign;
    } Elf64_Chdr;

Notes:

* We never used or even tested compressed objects or executables, so it is here only for completness,
* It seems that the compressed header `ch_type` field must be the first one in the structure (which leads to padding in the elf64 case).
  We followed the same road for elf128, even though it seems strange (putting it at the end would remove the need for padding),
* I don't quite understand (unless alignment is an issue for that structure) why the type of `ch_addralign` is the largest of the Data Model.

## ELF Symbol Table

    typedef struct {
        Elf128_Word   st_name;
        unsigned char st_info;
        unsigned char st_other;
        Elf128_Half   st_shndx;
        Elf128_Xword  st_reserved;
        Elf128_Addr   st_value;
        Elf128_Xxword st_size;
    } Elf128_Sym;

Notes:

* We had to add a 64-bit `st_reserved` field because of the 16-byte alignment constraint of the following field.
  This is not ideal, but we couldn't find any better alternative,
* The macros for manipulating `st_info` and `st_other` are identical for all Data Models.

## ELF Relocation

    typedef struct {
        Elf128_Addr   r_offset;
        Elf128_Xxword r_info;
    } Elf128_Rel;
    
    typedef struct {
        Elf128_Addr    r_offset;
        Elf128_Xxword  r_info;
        Elf128_Sxxword r_addend;
    } Elf128_Rela;
    

Note:

* Currently the 128-bit relocations are handled as the 64-bit ones, which is far from ideal, but is a start.
  There is a discrepency in the `ELF128_R_SYM`, `ELF128_R_TYPE`, and `ELF128_R_INFO` macros between the binutils and QEMU, but it did not trigger a bug yet.
  Fingers crossed!

## ELF Program Header

    typedef struct {
        Elf128_Word p_type;
        Elf128_Word p_flags;
        Elf128_Xword p_reserved;
        Elf128_Off p_offset;
        Elf128_Addr p_vaddr;
        Elf128_Addr p_paddr;
        Elf128_Xxword p_filesz;
        Elf128_Xxword p_memsz;
        Elf128_Xxword p_align;
    } Elf128_Phdr;

* Similarly to other structures, we had to add a 64-bit `st_reserved` field to satisfy the 16-byte alignment constraint of the following fields.

## ELF Dynamic Section

    typedef struct {
        Elf128_Sxxword d_tag;
        union {
            Elf128_Xxword d_val;
            Elf128_Addr d_ptr;
        } d_un;
    } Elf128_Dyn;

    extern Elf32_Dyn    _DYNAMIC[];

Note:

* We never reached a point at which we could run an actual OS, so we never used/tested dynamically linking.
