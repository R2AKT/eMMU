; =============================================================================
; /include/tty.inc - КОНСТАНТЫ, ОПРЕДЕЛЕНИЯ И HAL-РАСШИРЕНИЕ (ВЕРСИЯ 1.5.52_HAL)
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

; --- ДЕФOЛТНЫЕ ЗНАЧЕНИЯ АТРИБУТОВ ТЕРМИНАЛА ---
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

; =============================================================================
; СМЕЩЕНИЯ ВНУТРИ СТРУКТУРЫ ОДНОГО TTY СЛОТА (СТРОГО 160 БАЙТ)
; =============================================================================
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
O_TTY_CANON_RAW    EQU O_TTY_PGRP + 1    ; +148 [1 B] Технологический паддинг/зазор

; --- ИНКРЕМЕНТ СЛОЯ АППАРАТНОЙ АБСТРАКЦИИ (HAL) ВНУТРИ СУПЕРВИЗОРСКОГО РЕЗЕРВА ---
O_TTY_HW_PUT_CHAR  EQU O_TTY_PGRP + 2    ; +149 [2 B] Физический адрес процедуры hw_put_char
O_TTY_HW_GET_CHAR  EQU O_TTY_HW_PUT_CHAR + 2 ; +151 [2 B] Физический адрес процедуры hw_get_char
O_TTY_HW_POLL_STAT EQU O_TTY_HW_GET_CHAR + 2 ; +153 [2 B] Физический адрес процедуры hw_poll_status

; --- ТЕХНОЛОГИЧЕСКИЕ ПАРАМЕТРЫ ФИЗИЧЕСКИХ ЧИПОВ UART ---
O_TTY_HW_BASE_PORT EQU O_TTY_HW_POLL_STAT + 2 ; +155 [1 B] Базовый порт ввода-вывода контроллера
O_TTY_HW_DIV_LOW   EQU O_TTY_HW_BASE_PORT + 1 ; +156 [1 B] Младший байт делителя частоты
O_TTY_HW_DIV_HIGH  EQU O_TTY_HW_DIV_LOW + 1   ; +157 [1 B] Старший байт делителя частоты
O_TTY_HW_CHIP_TYPE EQU O_TTY_HW_DIV_HIGH + 1  ; +158 [1 B] Маркер типа чипа (01H=ВВ51, 02H=16550)

; Оставшийся свободный хвост до выравнивания: +159 [1 B] (Глубокий резерв ядра)

; --- МАСКИ И АППАРАТНЫЙ СТАТУС HAL ---
; Регистр А после исполнения O_TTY_HW_POLL_STAT обязан возвращать данные биты:
TTY_HAL_TXRDY      EQU 01H          ; Бит 0: Передатчик UART аппаратно готов принять байт
TTY_HAL_RXRDY      EQU 02H          ; Бит 1: Приемник UART аппаратно содержит байт для чтения

; Идентификаторы поддерживаемых контроллеров
CHIP_TYPE_I8251    EQU 01H          ; Микросхема КР580ВВ51А + КР580ВИ53
CHIP_TYPE_NS16550  EQU 02H          ; Микросхема NS16550 / 16550A

TTY_STRUCT_SIZE    EQU 160          ; КАНOНИЧНЫЙ ИНВАРИАНТ СОХРАНЕН БЕЗ СДВИГОВ!

; =============================================================================
;; Пример: TTY0 использует КР580ВВ51А
;LXI  H, TTY_TABLE
;LXI  D, O_TTY_HW_PUT_CHAR
;DAD  D
;LXI  B, hw_i8251_put_char
;MOV  M, C
;INX  H
;MOV  M, B
;
;; Пример: TTY1 использует NS16550
;LXI  H, TTY_TABLE + 160
;LXI  D, O_TTY_HW_PUT_CHAR
;DAD  D
;LXI  B, hw_16550_put_char
;MOV  M, C
;INX  H
;MOV  M, B
; =============================================================================
