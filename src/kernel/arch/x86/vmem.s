.global setupPaging

setupPaging:
        mov +4(%esp), %rax
        mov %rax, %cr3

        mov %cr4, %rax
        or $0b10010000, %rax
        mov %rax, %cr4

        // Enable Paging.
        mov %cr0, %rax
        orl $(1 << 31), %eax
        mov %rax, %cr0

        ret
