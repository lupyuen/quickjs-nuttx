#!/usr/bin/env bash
#  Build QuickJS for Apache NuttX RTOS

## TODO: Set PATH
export PATH="$HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/bin:$PATH"

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
  -isystem ../apps/import/include \
  -isystem ../apps/import/include \
  -D__NuttX__  \
  -I "../apps/include"   \
"

## This one is slooooooow
if [ ! -e ".obj/quickjs.o" ] 
then
  riscv64-unknown-elf-gcc \
    $nuttx_options \
    $qjs_options \
    -o .obj/quickjs.o \
    quickjs.c
fi

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/repl.o \
  nuttx/repl.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/qjscalc.o \
  nuttx/qjscalc.c

## Compile the NuttX App
riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/qjs.o \
  qjs.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/libregexp.o \
  libregexp.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/libunicode.o \
  libunicode.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/cutils.o \
  cutils.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/quickjs-libc.o \
  quickjs-libc.c

riscv64-unknown-elf-gcc \
  $nuttx_options \
  $qjs_options \
  -o .obj/libbf.o \
  libbf.c

## Link the NuttX App
## For riscv-none-elf-ld: "rv64imafdc_zicsr/lp64d"
## For riscv64-unknown-elf-ld: "rv64imafdc/lp64d
riscv64-unknown-elf-ld \
  --oformat elf64-littleriscv \
  -e _start \
  -Bstatic \
  -T../apps/import/scripts/gnu-elf.ld \
  -L../apps/import/libs \
  -L "$HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d" \
  ../apps/import/startup/crt0.o  \
  .obj/qjs.o \
  .obj/repl.o \
  .obj/quickjs.o \
  .obj/libregexp.o \
  .obj/libunicode.o \
  .obj/cutils.o \
  .obj/quickjs-libc.o \
  .obj/libbf.o \
  .obj/qjscalc.o \
  --start-group \
  -lmm \
  -lc \
  -lproxies \
  -lgcc \
  -lm \
  ../apps/libapps.a \
  $HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d/libgcc.a \
  --end-group \
  -o ../apps/bin/qjs

popd
