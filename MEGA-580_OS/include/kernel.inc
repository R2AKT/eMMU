#include "kernel_time.inc"
#include "hw.inc"
#include "signals.inc"
#include "pcb.inc"
#include "vfs.inc"
#include "syscall.inc"
#include "tty.inc"
#include "hw_i8251.inc"
#include "hw_ns16550.inc"

; =============================================================================
; Константы подсистемы распределения физической памяти ядра
; =============================================================================
RAM_BITMAP_SIZE    EQU 32           ; 32 байта для карты 256 страниц (256 / 8)
