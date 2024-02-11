# Porting QuickJS JavaScript Engine to Apache NuttX RTOS

Let's port [QuickJS JavaScript Engine](https://bellard.org/quickjs/quickjs.html) to Apache NuttX RTOS! (64-bit RISC-V QEMU, Kernel Mode)

_Why are we doing this?_

[QuickJS supports POSIX](https://bellard.org/quickjs/quickjs.html#os-module) open(), read(), ...

So we might run the JavaScript Interpreter on NuttX to control NuttX Devices, REPL-style! (Like blinking the LED Driver)

(But ioctl() is missing, maybe we can extend QuickJS?)

# Compile QuickJS for NuttX

From the [Makefile Log](nuttx/make.log)...

```bash
## Build qjs.o
gcc \
  -g \
  -Wall \
  -MMD \
  -MF .obj/qjs.o.d \
  -Wno-array-bounds \
  -Wno-format-truncation \
  -fwrapv  \
  -D_GNU_SOURCE \
  -DCONFIG_VERSION=\"2024-01-13\" \
  -DCONFIG_BIGNUM \
  -O2 \
  -c \
  -o .obj/qjs.o \
  qjs.c

## Omitted: Build a bunch of other binaries

## Link them together
gcc \
  -g \
  -rdynamic \
  -o qjs \
  .obj/qjs.o \
  .obj/repl.o \
  .obj/quickjs.o \
  .obj/libregexp.o \
  .obj/libunicode.o \
  .obj/cutils.o \
  .obj/quickjs-libc.o \
  .obj/libbf.o \
  .obj/qjscalc.o \
  -lm \
  -ldl \
  -lpthread
```

Let's do the same for NuttX. From [tcc-riscv32-wasm](https://github.com/lupyuen/tcc-riscv32-wasm) we know that NuttX builds NuttX Apps like this...

```bash
$ cd ../apps
$ make --trace import

## Compile hello app
## For riscv-none-elf-gcc: "-march=rv64imafdc_zicsr_zifencei"
## For riscv64-unknown-elf-gcc: "-march=rv64imafdc"
riscv-none-elf-gcc \
  -c \
  -fno-common \
  -Wall \
  -Wstrict-prototypes \
  -Wshadow \
  -Wundef \
  -Wno-attributes \
  -Wno-unknown-pragmas \
  -Wno-psabi \
  -fno-common \
  -pipe  \
  -Os \
  -fno-strict-aliasing \
  -fomit-frame-pointer \
  -ffunction-sections \
  -fdata-sections \
  -g \
  -mcmodel=medany \
  -march=rv64imafdc_zicsr_zifencei \
  -mabi=lp64d \
  -isystem apps/import/include \
  -isystem apps/import/include \
  -D__NuttX__  \
  -I "apps/include"   \
  hello_main.c \
  -o  hello_main.c.workspaces.bookworm.apps.examples.hello.o

## Link hello app
## For riscv-none-elf-ld: "rv64imafdc_zicsr/lp64d"
## For riscv64-unknown-elf-ld: "rv64imafdc/lp64d
riscv-none-elf-ld \
  --oformat elf64-littleriscv \
  -e _start \
  -Bstatic \
  -Tapps/import/scripts/gnu-elf.ld \
  -Lapps/import/libs \
  -L "xpack-riscv-none-elf-gcc-13.2.0-2/lib/gcc/riscv-none-elf/13.2.0/rv64imafdc_zicsr/lp64d" \
  apps/import/startup/crt0.o  \
  hello_main.c.workspaces.bookworm.apps.examples.hello.o \
  --start-group \
  -lmm \
  -lc \
  -lproxies \
  -lgcc apps/libapps.a xpack-riscv-none-elf-gcc-13.2.0-2/lib/gcc/riscv-none-elf/13.2.0/rv64imafdc_zicsr/lp64d/libgcc.a \
  --end-group \
  -o  apps/bin/hello
```

We'll do the same for QuickJS (and worry about the Makefile later).

Here's our Build Script for QuickJS NuttX: [nuttx/build.sh](nuttx/build.sh)

But `repl.c` and `qjscalc.c` are missing! They are generated by the QuickJS Compiler! From [nuttx/make.log](nuttx/make.log)

```bash
./qjsc -c -o repl.c -m repl.js
./qjsc -fbignum -c -o qjscalc.c qjscalc.js
```

Let's borrow them from the QuickJS Build: [nuttx/repl.c](nuttx/repl.c) and [nuttx/qjscalc.c](nuttx/qjscalc.c)

_What's inside the files?_

Some JavaScript Bytecode. Brilliant! From [nuttx/repl.c](nuttx/repl.c)

```c
/* File generated automatically by the QuickJS compiler. */
#include <inttypes.h>
const uint32_t qjsc_repl_size = 16280;
const uint8_t qjsc_repl[16280] = {
 0x02, 0xa5, 0x03, 0x0e, 0x72, 0x65, 0x70, 0x6c,
 0x2e, 0x6a, 0x73, 0x06, 0x73, 0x74, 0x64, 0x04,
```

# Fix the Missing Functions

The NuttX Linking fails. The missing functions...

- POSIX Functions (popen, pclose, pipe2, symlink, ...): We'll stub them out: [nuttx/stub.c](nuttx/stub.c)

- Dynamic Linking (dlopen, dlsym, dlclose): Don't need Dynamic Linking for fib.so, point.so

- Atomic Functions (__atomic_fetch_add_2, ...): We patched them: [nuttx/arch_atomic.c](nuttx/arch_atomic.c) [(Why are they missing)](https://github.com/apache/nuttx/issues/10642)

- Math Functions (pow, floor, trunc, ...): Link with `-lm`

```text
+ riscv64-unknown-elf-ld --oformat elf64-littleriscv -e _start -Bstatic -T../apps/import/scripts/gnu-elf.ld -L../apps/import/libs -L riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d ../apps/import/startup/crt0.o .obj/qjs.o .obj/repl.o .obj/quickjs.o .obj/libregexp.o .obj/libunicode.o .obj/cutils.o .obj/quickjs-libc.o .obj/libbf.o .obj/qjscalc.o --start-group -lmm -lc -lproxies -lgcc ../apps/libapps.a riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d/libgcc.a --end-group -o ../apps/bin/qjs

riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_pow':
quickjs-nuttx/quickjs.c:12026: undefined reference to `pow'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `is_safe_integer':
quickjs-nuttx/quickjs.c:11108: undefined reference to `floor'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `time_clip':
quickjs-nuttx/quickjs.c:49422: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_fcvt1':
quickjs-nuttx/quickjs.c:11430: undefined reference to `fesetround'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:11432: undefined reference to `fesetround'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_ecvt1':
quickjs-nuttx/quickjs.c:11346: undefined reference to `fesetround'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:11348: undefined reference to `fesetround'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `set_date_fields':
quickjs-nuttx/quickjs.c:49435: undefined reference to `fmod'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:49438: undefined reference to `floor'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `JS_ComputeMemoryUsage':
quickjs-nuttx/quickjs.c:6209: undefined reference to `round'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:6213: undefined reference to `round'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:6215: undefined reference to `round'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:6218: undefined reference to `round'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_strtod':
quickjs-nuttx/quickjs.c:10071: undefined reference to `pow'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `JS_ToUint8ClampFree':
quickjs-nuttx/quickjs.c:10991: undefined reference to `lrint'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `JS_NumberIsInteger':
quickjs-nuttx/quickjs.c:11144: undefined reference to `floor'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_Date_UTC':
quickjs-nuttx/quickjs.c:49722: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `set_date_field':
quickjs-nuttx/quickjs.c:49499: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_date_setYear':
quickjs-nuttx/quickjs.c:50109: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_math_hypot':
quickjs-nuttx/quickjs.c:43061: undefined reference to `hypot'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_fmax':
quickjs-nuttx/quickjs.c:42949: undefined reference to `fmax'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_fmin':
quickjs-nuttx/quickjs.c:42935: undefined reference to `fmin'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `JS_ToBigIntFree':
quickjs-nuttx/quickjs.c:12143: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_atomics_op':
quickjs-nuttx/quickjs.c:55149: undefined reference to `__atomic_fetch_add_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55218: undefined reference to `__atomic_fetch_add_2'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55165: undefined reference to `__atomic_fetch_and_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55166: undefined reference to `__atomic_fetch_and_2'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55204: undefined reference to `__atomic_fetch_or_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55167: undefined reference to `__atomic_fetch_or_2'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55167: undefined reference to `__atomic_fetch_sub_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55168: undefined reference to `__atomic_fetch_sub_2'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55168: undefined reference to `__atomic_fetch_xor_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55169: undefined reference to `__atomic_fetch_xor_2'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55169: undefined reference to `__atomic_exchange_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55170: undefined reference to `__atomic_exchange_2'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55183: undefined reference to `__atomic_compare_exchange_1'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:55189: undefined reference to `__atomic_compare_exchange_2'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_atomics_store':
quickjs-nuttx/quickjs.c:55287: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_date_constructor':
quickjs-nuttx/quickjs.c:49674: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_function_bind':
quickjs-nuttx/quickjs.c:38439: undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o: in function `js_binary_arith_slow':
quickjs-nuttx/quickjs.c:13543: undefined reference to `fmod'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:13497: undefined reference to `fmod'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs.c:13526: undefined reference to `fmod'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x58): undefined reference to `fabs'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x78): undefined reference to `floor'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x98): undefined reference to `ceil'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0xd8): undefined reference to `sqrt'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0xf8): undefined reference to `acos'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x118): undefined reference to `asin'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x138): undefined reference to `atan'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x158): undefined reference to `atan2'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x178): undefined reference to `cos'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x198): undefined reference to `exp'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x1b8): undefined reference to `log'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x1f8): undefined reference to `sin'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x218): undefined reference to `tan'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x238): undefined reference to `trunc'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x278): undefined reference to `cosh'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x298): undefined reference to `sinh'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x2b8): undefined reference to `tanh'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x2d8): undefined reference to `acosh'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x2f8): undefined reference to `asinh'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x318): undefined reference to `atanh'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x338): undefined reference to `expm1'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x358): undefined reference to `log1p'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x378): undefined reference to `log2'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x398): undefined reference to `log10'
riscv64-unknown-elf-ld: .obj/quickjs.o:(.rodata.js_math_funcs+0x3b8): undefined reference to `cbrt'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_std_popen':
quickjs-nuttx/quickjs-libc.c:942: undefined reference to `popen'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_std_file_finalizer':
quickjs-nuttx/quickjs-libc.c:807: undefined reference to `pclose'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_os_pipe':
quickjs-nuttx/quickjs-libc.c:3113: undefined reference to `pipe2'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_os_readlink':
quickjs-nuttx/quickjs-libc.c:2746: undefined reference to `readlink'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_new_message_pipe':
quickjs-nuttx/quickjs-libc.c:1635: undefined reference to `pipe2'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_std_file_close':
quickjs-nuttx/quickjs-libc.c:1050: undefined reference to `pclose'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_os_symlink':
quickjs-nuttx/quickjs-libc.c:2725: undefined reference to `symlink'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_std_urlGet':
quickjs-nuttx/quickjs-libc.c:1361: undefined reference to `popen'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `http_get_header_line':
quickjs-nuttx/quickjs-libc.c:1299: undefined reference to `pclose'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_std_urlGet':
quickjs-nuttx/quickjs-libc.c:1442: undefined reference to `pclose'
riscv64-unknown-elf-ld: .obj/quickjs-libc.o: in function `js_module_loader_so':
quickjs-nuttx/quickjs-libc.c:479: undefined reference to `dlopen'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs-libc.c:490: undefined reference to `dlsym'
riscv64-unknown-elf-ld: quickjs-nuttx/quickjs-libc.c:495: undefined reference to `dlclose'
```

After fixing the missing functions, QuickJS compiles OK for NuttX yay!

# QuickJS Crashes on NuttX

_Does QuickJS run on NuttX?_

We tested with our Expect Script: [nuttx/qemu.exp](nuttx/qemu.exp). The latest NuttX Log is always at [qemu.log](nuttx/qemu.log)

Nope NuttX crashes...

```text
+ qemu-system-riscv64 -semihosting -M virt,aclint=on -cpu rv64 -smp 8 -bios none -kernel nuttx -nographic
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> qjs
load_absmodule: Successfully loaded module /system/bin/qjs
exec_module: Executing qjs
exec_module: Initialize the user heap (heapsize=528384)
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c0006484, MTVAL: 00000008c0203b88
riscv_exception: PANIC!!! Exception = 000000000000000d
_assert: Current Version: NuttX  12.4.0-RC0 f8b0b06 Feb  9 2024 14:19:24 risc-v
_assert: Assertion failed panic: at file: common/riscv_exception.c:85 task: /system/bin/init process: /system/bin/init 0xc000004a
up_dump_register: EPC: 00000000c0006484
up_dump_register: A0: 00000000c02005d0 A1: 00000000c006b4e0 A2: 0000000000000074 A3: ffffffff00000000
up_dump_register: A4: 00000007fffffff8 A5: 00000008c0203b88 A6: ffffffffae012bc6 A7: 0000000000000000
up_dump_register: T0: 0000000080007474 T1: fffffffffc000000 T2: 00000000000001ff T3: 00000000c0207c40
up_dump_register: T4: 00000000c0207c38 T5: 0000000000000009 T6: 000000000000002a
up_dump_register: S0: 00000000c0201fc0 S1: ffffffffffffffff S2: 0000000003472fe9 S3: 00000000c02005d0
up_dump_register: S4: 0000000000000005 S5: 00000000c006b4e0 S6: 000000003fffffff S7: 000000007fffffff
up_dump_register: S8: 0000000040000000 S9: ffffffffc0000000 S10: 0000000000000000 S11: 0000000000000000
up_dump_register: SP: 00000000c0202220 FP: 00000000c0201fc0 TP: 0000000000000000 RA: 00000000c001b32c
```

We look up the disassembly: [nuttx/qjs.S](nuttx/qjs.S)

EPC c0006484 is here...

```text
quickjs-nuttx/quickjs.c:2876
static JSAtom __JS_FindAtom(JSRuntime *rt, const char *str, size_t len,
                            int atom_type) { ...
        p = rt->atom_array[i];
    c0006476:	0609b783          	ld	a5,96(s3)
    c000647a:	02049693          	slli	a3,s1,0x20
    c000647e:	01d6d713          	srli	a4,a3,0x1d
    c0006482:	97ba                	add	a5,a5,a4
    c0006484:	6380                	ld	s0,0(a5)
```

_Why is it accessing MTVAL 8_c020_3b88? Maybe the `8` prefix shouldn't be there?_

Seems to be crashing while searching for the JavaScript Atom for a String.

Maybe we shouldn't borrow the bytecode [nuttx/repl.c](nuttx/repl.c) and [nuttx/qjscalc.c](nuttx/qjscalc.c) from another platform? (Debian x64)

Let's [disable BIGNUM and qjscalc.c](https://github.com/lupyuen/quickjs-nuttx/commit/fe3b62c84c66f7a50daa548d4f74adfcdbbee3cd).

To disable [nuttx/repl.c](nuttx/repl.c), we run QuickJS Non-Interactively, without REPL: [nuttx/qemu.exp](nuttx/qemu.exp)

```bash
qjs -e console.log(123)
```

It still crashes...

```text
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c0006232, MTVAL: 00000008c0209718
riscv_exception: PANIC!!! Exception = 000000000000000d
_assert: Current Version: NuttX  12.4.0-RC0 f8b0b06 Feb  9 2024 14:19:24 risc-v
_assert: Assertion failed panic: at file: common/riscv_exception.c:85 task: /system/bin/init process: /system/bin/init 0xc000004a
up_dump_register: EPC: 00000000c0006232
up_dump_register: A0: 00000000c02005d0 A1: 00000000c0062868 A2: 0000000000000067 A3: ffffffff00000000
up_dump_register: A4: 00000007fffffff8 A5: 00000008c0209718 A6: 0000000000000003 A7: 0000000000000000
up_dump_register: T0: 0000000080007474 T1: fffffffffc000000 T2: 00000000000001ff T3: 00000000c020b8a0
up_dump_register: T4: 00000000c020b898 T5: 0000000000000009 T6: 000000000000002a
up_dump_register: S0: 00000000c0201f90 S1: ffffffffffffffff S2: 00000000398dc555 S3: 00000000c02005d0
up_dump_register: S4: 0000000000000012 S5: 00000000c0062868 S6: 000000003fffffff S7: 000000007fffffff
up_dump_register: S8: 0000000040000000 S9: ffffffffc0000000 S10: 0000000000000000 S11: 0000000000000000
up_dump_register: SP: 00000000c0202440 FP: 00000000c0201f90 TP: 0000000000000000 RA: 00000000c0019fa4
```

EPC c0006232 in [qjs.S](nuttx/qjs.S) says...

```text
quickjs-nuttx/quickjs.c:2876
static JSAtom __JS_FindAtom(JSRuntime *rt, const char *str, size_t len,
                            int atom_type) { ...
        p = rt->atom_array[i];
    c0006224:	0609b783          	ld	a5,96(s3)
    c0006228:	02049693          	slli	a3,s1,0x20
    c000622c:	01d6d713          	srli	a4,a3,0x1d
    c0006230:	97ba                	add	a5,a5,a4
    c0006232:	6380                	ld	s0,0(a5)
```

Same old place! Similar MTVAL! 8_c020_9718

Might be a problem with the JavaScript Atom Tagging? The `8` prefix might be a tag? [quickjs.h](quickjs.h)

TODO: Is QuickJS built correctly for 64-bit pointers?

_Where exactly in main() are we crashing?_

JS_NewCFunction3 seems to crash the second time we call it.

TODO: Are we running low on App Text / Data / Heap? According to Linker Map [nuttx/qjs.map](nuttx/qjs.map), we're using 486 KB of App Text (Code).

```text
$ riscv64-unknown-elf-size ../apps/bin/qjs
   text    data     bss     dec     hex filename
 486371     260      94  486725   76d45 ../apps/bin/qjs
```

[NuttX Config](https://github.com/apache/nuttx/blob/master/boards/risc-v/qemu-rv/rv-virt/configs/knsh64/defconfig#L39-L40) says we have 128 pages of App Text. Assuming 8 KB per page, that's 1 MB of App Text.

TODO: Why does hash_string8 hang? Stack problems?

TODO: Memory Corruption? Now `printf` seems to crash with Mutex problems

# Atom Sentinel becomes 0xFFFF_FFFF

We discover that the Atom Sentinel has become 0xFFFF_FFFF (instead of 0), causing crashes while searching the Atom List for an Atom...

```text
__JS_FindAtom: e
00000000C0203DE0
__JS_FindAtom: f
00000000C0201F60
__JS_FindAtom: h
00000000C0201F6C
__JS_FindAtom: i
00000000FFFFFFFF
```

So we stop the Atom Search when we see Sentinel 0xFFFF_FFFF...

- [__JS_FindAtom](https://github.com/lupyuen/quickjs-nuttx/commit/b9a53eca9a177ddeb7a4972c3ccf1388db606feb#diff-45f1ae674139f993bf8a99c382c1ba4863272a6fec2f492d76d7ff1b2cfcfbe2)

- [__JS_NewAtom](https://github.com/lupyuen/quickjs-nuttx/commit/42eb9be1547dd42bf4eebf1e21b1be6732f95f7d#diff-45f1ae674139f993bf8a99c382c1ba4863272a6fec2f492d76d7ff1b2cfcfbe2)

# Heap Errors and STDIO Weirdness

Now it halts inside the NuttX Mutex for printf...

```text
__JS_FindAtom: 0
asIntN
__JS_FindAtom: a
__JS_FindAtom: b
__JS_FindAtom: c
__JS_FindAtom: d
mm_malloc: Allocated 0xc0211b70, size 32
mm_malloc: Allocated 0xc0212030, size 112
mm_free: Freeing 0xc0211b20
mm_malloc: Allocated 0xc0209790, size 160
mm_free: Freeing 0xc0209710
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c005321c, MTVAL: 0000000000000168
```

From here...

```text
bool nxmutex_is_hold(FAR mutex_t *mutex)
{
    c0053216:	1141                	addi	sp,sp,-16
    c0053218:	e406                	sd	ra,8(sp)
    c005321a:	e022                	sd	s0,0(sp)
/Users/Luppy/riscv/nuttx/libs/libc/misc/lib_mutex.c:149
  return mutex->holder == _SCHED_GETTID();
    c005321c:	4d00                	lw	s0,24(a0)
    c005321e:	3b1030ef          	jal	ra,c0056dce <gettid>
```

TODO: Why is the Mutex corrupted?

We [change all puts() to write()](https://github.com/lupyuen/quickjs-nuttx/commit/b8df93e209abd594dc6e843bbb1941ddae91350d#diff-93a38cdf6b6645fff66fa78773011a5330ea9ed48cc1f70f4c65a6f6b707e246), which doesn't use Mutex.

Now we see Heap Free Error...

```text
mm_free: Freeing 0xc0214e10
JS_CreateProperty: e
JS_CreateProperty: f
JS_CreateProperty: g
mm_free: Freeing 0xc0214c80
mm_free: Freeing 0xc0214e80
mm_free: Freeing 0xc0214c50
mm_free: Freeing 0xc0215080
mm_free: Freeing 0xc0200da0
mm_free: Freeing 0xc0201920
_assert: Current Version: NuttX  12.4.0-RC0 f8b0b06 Feb 10 2024 12:50:34 risc-v
_assert: Assertion failed : at file: mm_heap/mm_free.c:112 task: qjs process: qjs 0xc000339e
up_dump_register: EPC: 0000000080001faa
up_dump_register: A0:+ true
```

TODO: What is this Heap Free Error? [Sanity check against double-frees](https://github.com/apache/nuttx/blob/master/mm/mm_heap/mm_free.c#L109-L112)

After cleaning up the logs: We get another corrupted printf Mutex....

```text
__JS_FindAtom: 0
toString
JS_DefineProperty: a
JS_CreateProperty: a
JS_DefineProperty: a
JS_CreateProperty: a
mm_free: Freeing 0xc0214c90
mm_malloc: Allocated 0xc0215250, size 48
mm_malloc: Allocated 0xc0214c90, size 64
mm_free: Freeing 0xc0215250
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c0055e9c, MTVAL: 0000000000000223
```

From here...

```text
/Users/Luppy/riscv/nuttx/libs/libc/stream/lib_stdoutstream.c:157
   * opened in binary mode.  In binary mode, the newline has no special
   * meaning.
   */

#ifndef CONFIG_STDIO_DISABLE_BUFFERING
  if (handle->fs_bufstart != NULL && (handle->fs_oflags & O_TEXT) != 0)
    c0055e9c:	6db8                	ld	a4,88(a1)
/Users/Luppy/riscv/nuttx/libs/libc/stream/lib_stdoutstream.c:164
      stream->common.flush = stdoutstream_flush;
    }
  else
#endif
```

STDIO Buffer is corrupted! We disable STDIO Buffering for now: `make menuconfig` > Library Routines > Standard C I/O > Disable STDIO Buffering

Now we are back to STDIO Mutex problem...

```text
__JS_FindAtom: 0
toString
JS_DefineProperty: a
JS_CreateProperty: a
JS_DefineProperty: a
JS_CreateProperty: a
mm_free: Freeing 0xc0214bc0
mm_malloc: Allocated 0xc0215180, size 48
mm_malloc: Allocated 0xc0214bc0, size 64
mm_free: Freeing 0xc0215180
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c0053044, MTVAL: 000000000000012b
```

From here...

```text
/Users/Luppy/riscv/nuttx/libs/libc/misc/lib_mutex.c:148
bool nxmutex_is_hold(FAR mutex_t *mutex) {
    c005303e:	1141                	addi	sp,sp,-16
    c0053040:	e406                	sd	ra,8(sp)
    c0053042:	e022                	sd	s0,0(sp)
/Users/Luppy/riscv/nuttx/libs/libc/misc/lib_mutex.c:149
  return mutex->holder == _SCHED_GETTID();
    c0053044:	4d00                	lw	s0,24(a0)
    c0053046:	047030ef          	jal	ra,c005688c <gettid>
```

Which comes from fprintf(). So we [change fprintf() to write()](https://github.com/lupyuen/quickjs-nuttx/commit/28b001034e18e23b58825e942b8a70e18a98fa84#diff-95fe784bea3e0fbdf30ba834b1a74b538090f4d70f4f8770ef397ef68ec37aa3) because it doesn't use Mutex.

# Unexpected Character in QuickJS

Now we see...

```text
js_dump_obj: SyntaxError: unexpected character
__JS_FindAtom: 0
stack
js_dump_obj:     at <cmdline>:1
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c000697c, MTVAL: 00000008c0212088
```

_What is this unexpected character?_

We [log the unexpected character](https://github.com/lupyuen/quickjs-nuttx/commit/6435e45d09016a8b9fbc29fdae707c59d876e20e#diff-45f1ae674139f993bf8a99c382c1ba4863272a6fec2f492d76d7ff1b2cfcfbe2). And we see our old friend FF...

```text
__JS_FindAtom: __loadScript
mm_malloc: Allocated 0xc0214d80, size 560
__JS_FindAtom: <cmdline>
mm_malloc: Allocated 0xc0214bc0, size 48
mm_malloc: Allocated 0xc0214bf0, size 32
next_token: c0=00000000000000FF
next_token: c=00000000000000FF
next_token: c2=FFFFFFFFFFFFFFFF
```

# Malloc Problems in NuttX

We [logged the calls to malloc](https://github.com/lupyuen/quickjs-nuttx/commit/571b0487ed86d00cfaa15e0a3e5ff1e370844c55#diff-45f1ae674139f993bf8a99c382c1ba4863272a6fec2f492d76d7ff1b2cfcfbe2)...

```c
void *js_malloc(JSContext *ctx, size_t size)
{
    void *ptr;
_d("js_malloc: a="); _d(debug_expr); _d("\n"); ////
    ptr = js_malloc_rt(ctx->rt, size);
_d("js_malloc: b="); _d(debug_expr); _d("\n"); ////
    if (unlikely(!ptr)) {
_d("js_malloc: b="); _d(debug_expr); _d("\n"); ////
        JS_ThrowOutOfMemory(ctx);
        return NULL;
    }
_d("js_malloc: d="); _d(debug_expr); _d("\n"); ////
    return ptr;
}
```

Something strange happens...

```text
js_malloc: a=console.log(123)
js_def_malloc: a=console.log(123)
js_def_malloc: b=console.log(123)
mm_malloc: Allocated 0xc0205580, size 112
js_def_malloc: c=
js_def_malloc: d=
```

NuttX malloc() erased our JavaScript from the Command-Line Arg!

Why? We [switched to our own barebones malloc](https://github.com/lupyuen/quickjs-nuttx/commit/3283e9f16631f6d9f1babbe2e0cd5cba635f34e0) for testing.

But nope doesn't work.

We [copied the Command-Line Arg to Local Buffer](https://github.com/lupyuen/quickjs-nuttx/commit/a4e0b308089c69ce08439a7812fbe1a8836dfc6e#diff-93a38cdf6b6645fff66fa78773011a5330ea9ed48cc1f70f4c65a6f6b707e246). Works much better!

# NuttX Stack is Full of QuickJS

Let's increase the Stack Size, it's 100% full...

```text
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c0006d52, MTVAL: ffffffffffffffff
...
dump_tasks:    PID GROUP PRI POLICY   TYPE    NPX STATE   EVENT      SIGMASK          STACKBASE  STACKSIZE      USED   FILLED    COMMAND
dump_tasks:   ----   --- --- -------- ------- --- ------- ---------- ---------------- 0x802002b0      2048      2040    99.6%!   irq
dump_task:       0     0   0 FIFO     Kthread - Ready              0000000000000000 0x80206010      3056      1856    60.7%    Idle_Task
dump_task:       1     1 100 RR       Kthread - Waiting Semaphore  0000000000000000 0x8020a050      1968       704    35.7%    lpwork 0x802015f0 0x80201618
dump_task:       2     2 100 RR       Task    - Waiting Semaphore  0000000000000000 0xc0202040      3008       744    24.7%    /system/bin/init
dump_task:       3     3 100 RR       Task    - Running            0000000000000000 0xc0202050      1968      1968   100.0%!   qjs }¼uq¦ü®઄²äÅ
```

We follow these steps to [increase Stack Size](https://github.com/lupyuen/nuttx-star64#increase-stack-size): `make menuconfig` > Library Routines > Program Execution Options > Default task_spawn Stack Size. Set to 8192

Here are all the settings we changed so far...

```bash
CONFIG_POSIX_SPAWN_DEFAULT_STACKSIZE=8192
## Remove CONFIG_SYSLOG_TIMESTAMP=y
```

QuickJS on NuttX QEMU prints 123 correctly yay! [nuttx/qemu.log](nuttx/qemu.log)

```text
$ qemu-system-riscv64 -semihosting -M virt,aclint=on -cpu rv64 -smp 8 -bios none -kernel nuttx -nographic

ABC
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> qjs -e console.log(123) 
123
nsh>
```

But QuickJS nteractive Mode REPL fails. Need to increase stack some more. We see our old friend 8_c021_8308, which appears when we run out of stack

```text
$ qemu-system-riscv64 -semihosting -M virt,aclint=on -cpu rv64 -smp 8 -bios none -kernel nuttx -nographic

ABC
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> qjs
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c0006484, MTVAL: 00000008c0218308
```

We increase Stack from 8 KB to 16 KB (looks too little?)...

```bash
CONFIG_POSIX_SPAWN_DEFAULT_STACKSIZE=16384
```

Oops too much (I think)...

```text
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> qjs -e console.log(123) 
_assert: Current Version: NuttX  12.4.0-RC0 f8b0b06-dirty Feb 11 2024 08:30:16 risc-v
_assert: Assertion failed : at file: common/riscv_createstack.c:89 task: /system/bin/init process: /system/bin/init 0xc000004a
```

Which comes from [riscv_createstack.c](https://github.com/apache/nuttx/blob/master/arch/risc-v/src/common/riscv_createstack.c#L82-L89)

```c
int up_create_stack(struct tcb_s *tcb, size_t stack_size, uint8_t ttype) {
#ifdef CONFIG_TLS_ALIGNED
  /* The allocated stack size must not exceed the maximum possible for the
   * TLS feature.
   */
  DEBUGASSERT(stack_size <= TLS_MAXSTACK);
```

We increase CONFIG_TLS_LOG2_MAXSTACK from 13 to 14:
- Library Routines > Thread Local Storage (TLS) > Maximum stack size (log2)
- Set to 14

Stack is still full. Increase Stack some more...

```text
→ qemu-system-riscv64 -semihosting -M virt,aclint=on -cpu rv64 -smp 8 -bios none -kernel nuttx -nographic
ABC
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> qjs
riscv_exception: EXCEPTION: Load page fault. MCAUSE: 000000000000000d, EPC: 00000000c005cc8c, MTVAL: 0000000000040129
...
SIGMASK          STACKBASE  STACKSIZE      USED   FILLED    COMMAND
dump_tasks:   ----   --- --- -------- ------- --- ------- ---------- ---------------- 0x802002b0      2048      2040    99.6%!   irq
dump_task:       0     0   0 FIFO     Kthread - Ready              0000000000000000 0x80206010      3056      1440    47.1%    Idle_Task
dump_task:       1     1 100 RR       Kthread - Waiting Semaphore  0000000000000000 0x8020c050      1968       704    35.7%    lpwork 0x802015f0 0x80201618
dump_task:       2     2 100 RR       Task    - Waiting Semaphore  0000000000000000 0xc0204040      3008       744    24.7%    /system/bin/init
dump_task:       3     3 100 RR       Task    - Running            0000000000000000 0xc0204030     16336     16320    99.9%!   qjs
```

We increase the Stack to 64 KB...

```bash
CONFIG_POSIX_SPAWN_DEFAULT_STACKSIZE=65536
CONFIG_TLS_LOG2_MAXSTACK=16
```

QuickJS Interactive Mode REPL finally works OK on NuttX QEMU (64-bit RISC-V) yay!

```text
$ qemu-system-riscv64 -semihosting -M virt,aclint=on -cpu rv64 -smp 8 -bios none -kernel nuttx -nographic

ABC
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> qjs
QuickJS - Type "\h" for help
qjs > console.log(123)
123
undefined
qjs > 
```

POSIX `open()` works OK too!

```text
NuttShell (NSH) NuttX-12.4.0-RC0
nsh> ls /system/bin/init
 /system/bin/init
nsh> qjs
QuickJS - Type "\h" for help
qjs > os.open("/system/bin/init", os.O_RDONLY)
3
qjs > os.open("/system/bin/init", os.O_RDONLY)
4
qjs > os.open("/system/bin/init", os.O_RDONLY)
5
```

We update our Expect Script for Automated Testing of QuickJS Interactive Mode REPL: [nuttx/qemu.exp](nuttx/qemu.exp)

```bash
## Wait for the prompt and enter this command
expect "nsh> "
send -s "qjs \r"

expect "qjs > "
send -s "console.log(123) \r"

expect "qjs > "
send -s "os.open('/system/bin/init', os.O_RDONLY) \r"

## Wait at most 30 seconds
set timeout 30

## Check the response...
expect {
  ## If we see this message, exit normally
  "qjs >" { exit 0 }

  ## If timeout, exit with an error
  timeout { exit 1 }
}
```
