.global syscall_entry
syscall_entry:
  swapgs

  mov %rsp, %rdi
  call doSyscall

  mov %rsp, %rcx
  mov %rsp, %r11
  swapgs
  sysretq
