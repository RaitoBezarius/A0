.global loadGDT
loadGDT:
        mov +4(%rsp), %rax
        lgdtq 4(%rax)
        movl %ax, %ds
        movl %ax, %es
        movl %ax, %fs
        movl %ax, %gs
        movl %ax, %ss
        popq %rdi
        mov $0x08, %rax
        pushq %rax
        pushq %rdi
        lretq
