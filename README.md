# A0

A simple x64 [1] microkernel, A/0.

## Basic instructions

## Run the VM

```console
$ zig -Drelease-safe build run
```

## QEMU Monitor Mode

Just do `enter-qemu-monitor` at the root of the repository.

## Where are the artifacts?

In `build/*`

## How to debug kernel state?

(1) Serial console -- TODO: put framebuffer here 🙃
(2) Serial console
(3) QEMU Monitor Mode

### Symbols with GDB

In order to get symbols, you will have to suffer with my personal fork to produce DWARF symbols.

[1]: It is advised to not try to write anymore any x64 operating system until RISC-V has taken over the world.
