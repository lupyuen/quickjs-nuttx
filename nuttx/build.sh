#!/usr/bin/env bash
#  Build QuickJS for Apache NuttX RTOS

## TODO: Set PATH
export PATH="$HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/bin:$PATH"

set -e  #  Exit when any command fails
set -x  #  Echo commands

pushd ..
mkdir -p .obj

## Compile the NuttX App
## For riscv-none-elf-gcc: "-march=rv64imafdc_zicsr_zifencei"
## For riscv64-unknown-elf-gcc: "-march=rv64imafdc"
riscv64-unknown-elf-gcc \
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
  \
  -Wno-array-bounds \
  -Wno-format-truncation \
  -fwrapv  \
  -D_GNU_SOURCE \
  -DCONFIG_VERSION=\"2024-01-13\" \
  -DCONFIG_BIGNUM \
  -o .obj/qjs.o \
  qjs.c

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
  --start-group \
  -lmm \
  -lc \
  -lproxies \
  -lgcc \
  ../apps/libapps.a \
  $HOME/riscv64-unknown-elf-toolchain-10.2.0-2020.12.8-x86_64-apple-darwin/lib/gcc/riscv64-unknown-elf/10.2.0/rv64imafdc/lp64d/libgcc.a \
  --end-group \
  -o  ../apps/bin/qjs
popd
