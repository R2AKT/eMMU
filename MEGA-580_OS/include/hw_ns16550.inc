; =============================================================================
; MEGA-580_OS v1.5.55_HAL - NS16550 CONTROLLER REGISTERS & MASKS
; BUILD DATE: 20260707 | AUTHOR: OS ARCHITECT & DEVICE DRIVER MANAGER
; =============================================================================

; --- Смещения регистров относительно O_TTY_HW_BASE_PORT ---
REG_RBR             EQU 0           ; Receiver Buffer Register (чтение, DLAB=0)
REG_THR             EQU 0           ; Transmitter Holding Register (запись, DLAB=0)
REG_IER             EQU 1           ; Interrupt Enable Register (DLAB=0)
REG_FCR             EQU 2           ; FIFO Control Register (запись)
REG_LCR             EQU 3           ; Line Control Register
REG_MCR             EQU 4           ; Modem Control Register
REG_LSR             EQU 5           ; Line Status Register
REG_DLL             EQU 0           ; Divisor Latch LSB (DLAB=1)
REG_DLM             EQU 1           ; Divisor Latch MSB (DLAB=1)
REG_SCR             EQU 7           ; Scratchpad Register чипа 16550

; --- Биты Line Status Register (REG_LSR) ---
LSR_DATA_READY      EQU 01H         ; Бит 0: Байт принят в FIFO (DR)
LSR_THRE            EQU 20H         ; Бит 5: Буфер передатчика пуст (THRE)
LSR_TEMT            EQU 40H         ; Бит 6: Передатчик полностью пуст (TEMT)

; --- Биты управления Line Control Register (REG_LCR) ---
LCR_WLS_8BIT        EQU 03H         ; Размер слова: 8 бит
LCR_STB_1STOP       EQU 00H         ; Стоп-биты: 1 стоп-бит
LCR_PEN_NO_PARITY   EQU 00H         ; Без четности
LCR_DLAB_ENABLE     EQU 80H         ; Включение защелки делителя частоты (DLAB=1)

; --- Биты управления FIFO Control Register (REG_FCR) ---
FCR_FIFO_ENABLE     EQU 01H         ; Включение FIFO
FCR_RX_FIFO_RESET   EQU 02H         ; Сброс FIFO приемника
FCR_TX_FIFO_RESET   EQU 04H         ; Сброс FIFO передатчика
FCR_RX_TRIGGER_14B  EQU 0C0H        ; Прерывание приемника при заполнении 14 байт

; --- Биты Interrupt Enable Register (REG_IER) ---
IER_DISABLE_ALL     EQU 00H         ; Запретить все прерывания
IER_ENABLE_RX       EQU 01H         ; Разрешить прерывание по приему данных
IER_ENABLE_TX       EQU 02H         ; Разрешить прерывание по освобождению THR

; =============================================================================
; ДОПОЛНЕНИЯ К ns16550_hal.inc
; =============================================================================

; --- Регистр идентификации прерываний (для ISR) ---
REG_IIR             EQU 2           ; Interrupt Identification Register (чтение)
IIR_NO_INT_PENDING  EQU 01H         ; Бит 0 = 1 → нет ожидающего прерывания
IIR_INT_ID_MASK     EQU 0EH         ; Маска источника (биты 1-3)
IIR_RX_DATA_AVAIL   EQU 04H         ; Приём данных (приоритет 2)
IIR_THR_EMPTY       EQU 02H         ; THR пуст (приоритет 3)
IIR_RX_TIMEOUT      EQU 0CH         ; Таймаут FIFO (приоритет 2)

; --- Маски ошибок LSR ---
LSR_OVERRUN_ERR     EQU 02H         ; Переполнение FIFO
LSR_PARITY_ERR      EQU 04H         ; Ошибка чётности
LSR_FRAMING_ERR     EQU 08H         ; Ошибка фрейма
LSR_BREAK_INT       EQU 10H         ; Обнаружен BREAK
LSR_ALL_ERRORS      EQU 0EH         ; Маска всех ошибок

; --- Расширенные IER ---
IER_ENABLE_LSR      EQU 04H         ; Прерывания по ошибкам линии

; --- Делители частоты (для кварца 1.8432 МГц) ---
NS16550_DIV_9600    EQU 000CH
NS16550_DIV_19200   EQU 0006H
NS16550_DIV_38400   EQU 0003H
NS16550_DIV_57600   EQU 0002H
NS16550_DIV_115200  EQU 0001H


