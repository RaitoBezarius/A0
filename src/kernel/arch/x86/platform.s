// fn getEflags() u32;
.global getEflags
getEflags:
   pushfq
   popq %rax
   ret

.global getCS
getCS:
   xor %rax, %rax
   mov %cs, %ax
   ret
