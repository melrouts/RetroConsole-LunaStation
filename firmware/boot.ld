ENTRY(_start)
__update_staging = 0x100;
MEMORY {
    CODE (rx) : ORIGIN = BOOT_BASE, LENGTH = BOOT_CODE_BYTES
    DATA (rw) : ORIGIN = BOOT_BASE + BOOT_CODE_BYTES, LENGTH = BOOT_RAM_BYTES - BOOT_CODE_BYTES
}
PHDRS {
    code PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
SECTIONS {
    .text : {
        KEEP(*(.text.start))
        *(.text .text.* .rodata .rodata.*)
    } > CODE :code
    .data : {
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.data .data.* .sdata .sdata.*)
    } > DATA :data
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DATA :data
    _stack_top = ORIGIN(DATA) + LENGTH(DATA);
    _stack_bottom = _stack_top - STACK_BYTES;
    ASSERT(_bss_end <= _stack_bottom, "Boot BSS overlaps boot stack")
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
