#!/usr/bin/env bash
#  Build QuickJS for Apache NuttX RTOS

## TODO: Set PATH
export PATH="$HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/bin:$PATH"

# target=riscv
target=ox64

set -e  #  Exit when any command fails
set -x  #  Echo commands

pushd ..
mkdir -p .obj

## GCC Options for QuickJS
qjs_options=" \
  -Wno-array-bounds \
  -Wno-format-truncation \
  -fwrapv  \
  -D_GNU_SOURCE \
  -DCONFIG_VERSION=\"2024-01-13\" \
  -DCONFIG_BIGNUM \
"

## GCC Options for NuttX
## For riscv-none-elf-gcc: "-march=rv64imafdc_zicsr_zifencei"
## For riscv64-unknown-elf-gcc: "-march=rv64imafdc"
nuttx_options=" \
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
  -march=rv64imafdc \
  -mabi=lp64d \
  -isystem $HOME/$target/apps/import/include \
  -isystem $HOME/$target/apps/import/include \
  -D__NuttX__  \
  -I "$HOME/$target/apps/include"   \
"

## Compile the NuttX App
riscv64-unknown-elf-gcc \
  $nuttx_options \
  -o .obj/stub.o \
  nuttx/stub.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  -o .obj/arch_atomic.o \
  nuttx/arch_atomic.c

## This one is slooooooow
# if [ ! -e ".obj/quickjs.o" ] 
# then
  riscv64-unknown-elf-gcc \
    $nuttx_options \
    $qjs_options \
    -o .obj/quickjs.o \
    quickjs.c
# fi

if [ ! -e ".obj/repl.o" ] 
then
  riscv64-unknown-elf-gcc \
    $nuttx_options \
    $qjs_options \
    -o .obj/repl.o \
    nuttx/repl.c
fi

if [ ! -e ".obj/qjscalc.o" ] 
then
  riscv64-unknown-elf-gcc \
    $nuttx_options \
    $qjs_options \
    -o .obj/qjscalc.o \
    nuttx/qjscalc.c
fi

# if [ ! -e ".obj/qjs.o" ] 
# then
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/qjs.o \
  qjs.c
# fi

if [ ! -e ".obj/libregexp.o" ] 
then
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/libregexp.o \
  libregexp.c
fi

if [ ! -e ".obj/libunicode.o" ] 
then
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/libunicode.o \
  libunicode.c
fi

if [ ! -e ".obj/cutils.o" ] 
then
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/cutils.o \
  cutils.c
fi

# if [ ! -e ".obj/quickjs-libc.o" ] 
# then
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/quickjs-libc.o \
  quickjs-libc.c
# fi

if [ ! -e ".obj/libbf.o" ] 
then
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/libbf.o \
  libbf.c
fi

riscv64-unknown-elf-ld \
  --oformat elf64-littleriscv \
  -r \
  -e main \
  -T /Users/Luppy/ox64/nuttx/binfmt/libelf/gnu-elf.ld \
  -r \
  -e _start \
  -Bstatic \
  -T/Users/Luppy/ox64/apps/import/scripts/gnu-elf.ld \
  -L/Users/Luppy/ox64/apps/import/libs \
  -L "/Users/Luppy/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/bin/../lib/gcc/riscv64-unknown-elf/10.2.0/../../../../riscv64-unknown-elf/lib/rv64imafdc/lp64d" \
  -L "/Users/Luppy/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/bin/../lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d" \
  /Users/Luppy/ox64/apps/import/startup/crt0.o  \
  .obj/qjs.o \
  .obj/repl.o \
  .obj/quickjs.o \
  .obj/libregexp.o \
  .obj/libunicode.o \
  .obj/cutils.o \
  .obj/quickjs-libc.o \
  .obj/libbf.o \
  .obj/qjscalc.o \
  .obj/arch_atomic.o \
  .obj/stub.o \
  --start-group \
  -lmm \
  -lc \
  -lproxies \
  -lm \
  -lgcc /Users/Luppy/ox64/apps/libapps.a \
  /Users/Luppy/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/bin/../lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d/libgcc.a \
  --end-group \
  -o $HOME/$target/apps/bin/qjs \
  -Map nuttx/qjs.map

## Link the NuttX App
## For riscv-none-elf-ld: "rv64imafdc_zicsr/lp64d"
## For riscv64-unknown-elf-ld: "rv64imafdc/lp64d
# riscv64-unknown-elf-ld \
#   --oformat elf64-littleriscv \
#   -e _start \
#   -Bstatic \
#   -T$HOME/$target/apps/import/scripts/gnu-elf.ld \
#   -L$HOME/$target/apps/import/libs \
#   -L "$HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d" \
#   $HOME/$target/apps/import/startup/crt0.o  \
#   .obj/qjs.o \
#   .obj/repl.o \
#   .obj/quickjs.o \
#   .obj/libregexp.o \
#   .obj/libunicode.o \
#   .obj/cutils.o \
#   .obj/quickjs-libc.o \
#   .obj/libbf.o \
#   .obj/qjscalc.o \
#   .obj/arch_atomic.o \
#   .obj/stub.o \
#   --start-group \
#   -lmm \
#   -lc \
#   -lproxies \
#   -lgcc \
#   -lm \
#   $HOME/$target/apps/libapps.a \
#   $HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d/libgcc.a \
#   --end-group \
#   -o $HOME/$target/apps/bin/qjs \
#   -Map nuttx/qjs.map

## Show the size
riscv64-unknown-elf-size $HOME/$target/apps/bin/qjs

## Dump the disassembly
riscv64-unknown-elf-objdump \
  -t -S --demangle --line-numbers --wide \
  $HOME/$target/apps/bin/qjs \
  >nuttx/qjs-$target.S \
  2>&1

## Test with QEMU
pushd ../nuttx

../quickjs-nuttx/nuttx/qemu.exp || true
../quickjs-nuttx/nuttx/qemu.exp \
  | tr -d "\r" \
  >../quickjs-nuttx/nuttx/qemu.log

# (sleep 10 ; pkill qemu) &
# qemu-system-riscv64 \
#   -semihosting \
#   -M virt,aclint=on \
#   -cpu rv64 \
#   -smp 8 \
#   -bios none \
#   -kernel nuttx \
#   -nographic

## Return to quickjs-nuttx
popd

popd
