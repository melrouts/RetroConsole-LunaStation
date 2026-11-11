ENTRY(_start)
MEMORY {
    RAM (rwx) : ORIGIN = 0, LENGTH = MAIN_RAM_BYTES
}
PHDRS {
    code PT_LOAD FLAGS(5);
    data PT_LOAD FLAGS(6);
}
SECTIONS {
    .text : {
        KEEP(*(.text.start))
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > RAM :code
    .data : {
        . = ALIGN(4);
        PROVIDE(__global_pointer$ = . + 0x800);
        *(.data .data.* .sdata .sdata.*)
    } > RAM :data
    .bss (NOLOAD) : {
        . = ALIGN(4);
        _bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > RAM :data
    _stack_top = ORIGIN(RAM) + LENGTH(RAM);
    _stack_bottom = _stack_top - STACK_BYTES;
    ASSERT(_bss_end <= _stack_bottom, "Firmware plus BSS overlaps stack")
    /DISCARD/ : { *(.comment) *(.eh_frame*) }
}
