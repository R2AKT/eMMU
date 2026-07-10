#include "kernel_time.inc"
#include "hw.inc"
#include "signals.inc"
#include "pcb.inc"
#include "vfs.inc"
#include "chrdev.inc"
#include "syscall.inc"
#include "tty.inc"
#include "hw_i8251.inc"
#include "hw_ns16550.inc"
#include "chrdev.inc"
#include "devices.inc"
#include "lp.inc"

; =============================================================================
; Константы подсистемы распределения физической памяти ядра
; =============================================================================
RAM_BITMAP_SIZE    EQU 32           ; 32 байта для карты 256 страниц (256 / 8)
