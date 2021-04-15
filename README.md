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

(4) GDB, see next part.

### Symbols with GDB

In order to get symbols on the kernel, you will have to suffer with my personal fork to produce DWARF symbols.

Otherwise, if you use `sgdb` for symbolicated GDB, you will obtain OVMF symbols automatically. `fsgdb` for fast symbolicated GDB is also available.
`fsgdb` just ignore the changes and will not generate a new GDB script, it's fine for OVMF, but for the kernel, each change might relocate the kernel, so it will break your kernel's symbols.

### Debugging this kernel -- some tips

- Entering into QEMU monitor mode is nice, you can do `gdbserver` in case the `target remote :1234` attachment timeouts.
- Hardware assisted breakpoints will work better than software ones.
- `info registers` is nice in GDB.
- `-s` enables you to make it so the VM waits for you at the startup on GDB.
- `set osabi none` will fix any issue with remote attachment due to PE format.


[1]: It is advised to not try to write anymore any x64 operating system until RISC-V has taken over the world.
