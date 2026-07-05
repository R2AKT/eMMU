; =============================================================================
; /include/tty.inc - КОНСТАНТЫ И ОПРЕДЕЛЕНИЯ МАССИВА ТЕРМИНАЛОВ (ВЕРСИЯ 1.5.3)
; =============================================================================

; --- ПАРАМЕТРЫ И ОГРАНИЧЕНИЯ ---
MAX_TTY_DEVS       EQU 4            ; 4 идентичных физических TTY консолей (0..3)
UNBOUND_WAIT_PID   EQU 0FFH         ; Маркер отсутствия привязки (0xFF)
TTY_BUF_SIZE       EQU 64           ; Размер кольцевого буфера (64 байта)
TTY_MINOR_BASE     EQU 0            ; Базовый minor для TTY

; --- БИТОВЫЕ МАСКИ ПОДФЛАГОВ POSIX TERMIOS ---
TM_ECHO            EQU 001H         ; ECHO
TM_ICANON          EQU 002H         ; ICANON
TM_ISIG            EQU 004H         ; ISIG
TM_ICRNL           EQU 001H         ; ICRNL
TM_INLCR           EQU 002H         ; INLCR
TM_OPOST           EQU 001H         ; OPOST
TM_ONLCR           EQU 002H         ; ONLCR

; --- ИНДЕКСЫ УПРАВЛЯЮЩИХ СИМВОЛОВ В МАССИВЕ TTY_C_CC (0..7) ---
VEOF               EQU 0            ; Ctrl+D
VEOL               EQU 1            ; \n
VERASE             EQU 2            ; Backspace
VKILL              EQU 3            ; Ctrl+U
VINTR              EQU 4            ; Ctrl+C
VQUIT              EQU 5            ; Ctrl+\
VSTART             EQU 6            ; Ctrl+Q
VSTOP              EQU 7            ; Ctrl+S

; --- ДЕФОЛТНЫЕ ЗНАЧЕНИЯ АТРИБУТОВ ТЕРМИНАЛА ---
DEF_VEOF           EQU 004H         ; Ctrl+D
DEF_VEOL           EQU 00AH         ; \n
DEF_VERASE         EQU 008H         ; Backspace
DEF_VKILL          EQU 015H         ; Ctrl+U
DEF_VINTR          EQU 003H         ; Ctrl+C
DEF_VQUIT          EQU 01CH         ; Ctrl+\
DEF_VSTART         EQU 011H         ; Ctrl+Q
DEF_VSTOP          EQU 013H         ; Ctrl+S

DEF_C_IFLAG        EQU TM_ICRNL     ; CR → NL на входе
DEF_C_OFLAG        EQU TM_OPOST OR TM_ONLCR  ; NL → CR-NL на выходе
DEF_C_LFLAG        EQU TM_ECHO OR TM_ICANON OR TM_ISIG  ; Полный canonical режим

; --- POSIX IOCTL КОМАНДЫ ТЕРМИНАЛА ---
TCGETA             EQU 1            
TCSETA             EQU 2            
TCFLSH             EQU 3            
TIOCGPGRP          EQU 4            
TIOCSPGRP          EQU 5            

TCIFLUSH           EQU 0            
TCOFLUSH           EQU 1            
TCIOFLUSH          EQU 2            

TTY_SIGINT         EQU 2            
TTY_SIGQUIT        EQU 3            
TTY_SIGTSTP        EQU 18           

; --- СМЕЩЕНИЯ ВНУТРИ СТРУКТУРЫ ОДНОГО TTY СЛОТА (160 БАЙТ) ---
TTY_ROW_START      EQU 0
O_TTY_RX_HEAD      EQU TTY_ROW_START     
O_TTY_RX_TAIL      EQU O_TTY_RX_HEAD + 1 
O_TTY_RX_COUNT     EQU O_TTY_RX_TAIL + 1 
O_TTY_RX_BUFFER    EQU O_TTY_RX_COUNT + 1
O_TTY_TX_HEAD      EQU O_TTY_RX_BUFFER + TTY_BUF_SIZE 
O_TTY_TX_TAIL      EQU O_TTY_TX_HEAD + 1 
O_TTY_TX_COUNT     EQU O_TTY_TX_TAIL + 1 
O_TTY_TX_BUFFER    EQU O_TTY_TX_COUNT + 1
O_TTY_C_IFLAG      EQU O_TTY_TX_BUFFER + TTY_BUF_SIZE 
O_TTY_C_OFLAG      EQU O_TTY_C_IFLAG + 1 
O_TTY_C_LFLAG      EQU O_TTY_C_OFLAG + 1 
O_TTY_C_CC         EQU O_TTY_C_LFLAG + 1 
O_TTY_WAIT_PID     EQU O_TTY_C_CC + 8    
O_TTY_WAIT_CODE    EQU O_TTY_WAIT_PID + 1
O_TTY_PGRP         EQU O_TTY_WAIT_CODE + 1
O_TTY_CANON_RAW    EQU O_TTY_PGRP + 1    ; Поле зарезервировано под падинг (дубликат удален)

TTY_STRUCT_SIZE    EQU 160               
