; =============================================================================
; НАЗВАНИЕ: tty_isr.asm (Центральный обработчик прерываний UART ядра)
; ТОКЕН:    TOKEN::MEGA-580_OS_v1.5.56_HW_UART_ENTRY_STABLE_BUILD_20260707
; =============================================================================

; =============================================================================
; ОБРАБОТЧИК: hw_uart_entry
; Вход:  Аппаратный перепад линии ВН59 (Прерывания заперты процессором DI)
; Задача: Централизованно обслужить комбинированное прерывание (Rx/Tx) активного
;         терминала через абстрактные HAL-инварианты 160-байтового слота.
; Выход: РОН полностью восстановлены.
; =============================================================================
hw_uart_entry:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст Ring 0 планировщика

    ; Шаг 1: Локализовали физический адрес 160-байтового TTY-слота для TTY0
    ; (В многопортовой версии здесь будет вычисляться смещение по номеру IR-линии)
    LXI  D, TTY_TABLE               ; DE = База TTY0
    
_tty_isr_core_execute:
    ; === Шаг 2: КОСВЕННЫЙ ОПРОС СТАТУСА ЧИПА ЧЕРЕЗ HAL ===
    MOV  H, D
    MOV  L, E                       ; HL = База TTY
    PUSH D                          ; Сохранили базу TTY на стеке
    LXI  D, O_TTY_HW_POLL_STAT
    DAD  D                          ; HL -> O_TTY_HW_POLL_STAT (+153)
    MOV  E, M
    INX  H
    MOV  D, M                       ; DE = Физический адрес hw_*_poll_status драйвера
    POP  H                          ; HL = Восстановили базу TTY-слота
    
    PUSH H                          ; Сохранили базу TTY перед вызовом
    LXI  H, _tty_isr_stat_ret
    PUSH H
    XCHG                            ; HL = Функция статуса, DE = База TTY
    PCHL                            ; Вызов драйвера (Выход: А = HAL-маска статуса)

_tty_isr_stat_ret:
    POP  H                          ; HL = Восстановили базу TTY-слота
    MOV  B, A                       ; B = Накопленные маски HAL (TTY_HAL_TXRDY / RXRDY)

    ; === Шаг 3: ОБРАБОТКА АСИНХРОННОГО ПРИЕМА (Rx) ===
    MOV  A, B
    ANI  TTY_HAL_RXRDY              ; В чипе готов байт для чтения?
    JZ   _tty_isr_handle_tx         ; Если 0 — переходим к проверке передатчика

    ; В кремнии есть символ! Вызываем O_TTY_HW_GET_CHAR (+151)
    MOV  D, H
    MOV  E, L                       ; DE = База TTY
    PUSH B                          ; Cохранили маску статуса HAL
    PUSH D                          ; Сохранили базу TTY
    LXI  B, O_TTY_HW_GET_CHAR
    DAD  B                          ; HL -> O_TTY_HW_GET_CHAR
    MOV  E, M
    INX  H
    MOV  D, M                       ; DE = Физический адрес hw_*_get_char
    POP  H                          ; HL = Восстановили базу TTY-слота
    
    PUSH H                          ; Сохранили базу TTY перед вызовом
    LXI  H, _tty_isr_get_ret
    PUSH H
    XCHG                            ; HL = Функция забора, DE = База TTY
    PCHL                            ; Вызов драйвера (Выход: А = ASCII-символ)

_tty_isr_get_ret:
    MOV  C, A                       ; C = принятый из кремния символ
    POP  H                          ; HL = Восстановили базу TTY-слота
    POP  B                          ; B = Восстановили маску статуса HAL
    
    ; --- Абстрактная ОЗУ-логика укладки символа C в кольцевой буфер приема ---
    PUSH B                          ; Сохранили маску статуса
    PUSH H                          ; Сохранили базу TTY
    LXI  D, O_TTY_RX_COUNT
    DAD  D                          ; HL -> O_TTY_RX_COUNT (+2)
    MOV  A, M
    CPI  TTY_BUF_SIZE               ; Очередь приема ОЗУ полна (64 байта)?
    POP  H                          ; HL = База TTY
    JZ   _tty_isr_rx_drop           ; Полна — пассивный сброс (защита ОЗУ Ring 0)

    ; Читаем RX_HEAD (+0) для записи
    MOV  E, M                       ; E = Индекс RX_HEAD
    INR  M                          ; RX_HEAD++
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JC   _tty_isr_rx_no_wrap
    MVI  M, 00H                     ; Циклим RX_HEAD = 0

_tty_isr_rx_no_wrap:
    PUSH H                          ; Сохранили базу TTY
    LXI  D, O_TTY_RX_BUFFER
    DAD  D                          ; HL -> O_TTY_RX_BUFFER (+3)
    MVI  D, 00H                     ; DE = 0000h + RX_HEAD_old
    DAD  D                          ; HL = O_TTY_RX_BUFFER + RX_HEAD
    MOV  M, C                       ; АТОМАРНО уложили символ в ОЗУ ядра!
    
    POP  H                          ; HL = База TTY
    PUSH H
    LXI  D, O_TTY_RX_COUNT
    DAD  D
    INR  M                          ; Инкремент общего счетчика RX_COUNT++
    POP  H                          ; HL = База TTY

_tty_isr_rx_drop:
    POP  B                          ; B = Восстановили маску статуса HAL

_tty_isr_handle_tx:
    ; === Шаг 4: ОБРАБОТКА АСИНХРОННОЙ ПЕРЕДАЧИ (Tx) ===
    MOV  A, B
    ANI  TTY_HAL_TXRDY              ; Передатчик чипа готов принять байт?
    JZ   _tty_isr_done              ; Если нет — прерывание полностью обслужено

    ; Проверяем, есть ли данные в кольце вывода ОЗУ Ring 0
    PUSH H                          ; Сохранили базу TTY
    LXI  D, O_TTY_TX_COUNT
    DAD  D                          ; HL -> O_TTY_TX_COUNT (+69)
    MOV  A, M
    ORA  A                          ; TX_COUNT == 0?
    POP  H                          ; HL = База TTY
    JZ   _tty_isr_tx_close_line     ; Данных в ОЗУ нет! Глушим линию прерывания

    ; Данные есть! Извлекаем символ по указателю TX_TAIL (+68)
    PUSH H
    LXI  D, O_TTY_TX_TAIL
    DAD  D                          ; HL -> O_TTY_TX_TAIL
    MOV  E, M                       ; E = Индекс TX_TAIL
    INR  M                          ; TX_TAIL++
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JC   _tty_isr_tx_no_wrap
    MVI  M, 00H                     ; Циклим TX_TAIL = 0

_tty_isr_tx_no_wrap:
    POP  H                          ; HL = База TTY
    PUSH H
    LXI  D, O_TTY_TX_BUFFER
    DAD  D                          ; HL -> O_TTY_TX_BUFFER (+70)
    MVI  D, 00H                     ; DE = 0000h + TX_TAIL_old
    DAD  D                          ; HL = O_TTY_TX_BUFFER + TX_TAIL
    MOV  A, M                       ; А = Таргетный символ для отправки
    MOV  C, A                       ; C = Сохранили символ
    
    POP  H                          ; HL = База TTY
    
    ; Вызываем O_TTY_HW_PUT_CHAR драйвера чипа (+149)
    MOV  D, H
    MOV  E, L                       ; DE = База TTY
    MOV  A, C                       ; A = Выводимый символ
    PUSH H                          ; Сохранили базу TTY
    LXI  B, O_TTY_HW_PUT_CHAR
    DAD  B                          ; HL -> O_TTY_HW_PUT_CHAR
    MOV  E, M
    INX  H
    MOV  D, M                       ; DE = Физический адрес hw_*_put_char
    POP  H                          ; HL = База TTY
    
    PUSH H
    LXI  H, _tty_isr_put_ret
    PUSH H
    XCHG                            ; HL = Функция вывода, DE = База TTY
    PCHL                            ; Физический выстрел в кремний!

_tty_isr_put_ret:
    POP  H                          ; HL = Восстановили базу TTY
    
    ; Декрементируем счетчик TX_COUNT
    PUSH H
    LXI  D, O_TTY_TX_COUNT
    DAD  D
    DCR  M                          ; TX_COUNT--
    POP  H                          ; HL = База TTY
    JMP  _tty_isr_done

_tty_isr_tx_close_line:
    ; Очередь ОЗУ пуста — вызываем менеджер подавления шторма прерываний чипа
    PUSH H
    LXI  D, O_TTY_HW_CHIP_TYPE
    DAD  D
    MOV  A, M                       ; А = тип контроллера (01H или 02H)
    POP  H                          ; HL = База TTY
    
    CPI  CHIP_TYPE_I8251            ; Это ВВ51?
    JNZ  _isr_tx_ctrl_16550
    
    ; Чип ВВ51: глушим прерывание
    MVI  A, 00H                     ; Режим: Отключить TxEN
    MOV  D, H
    MOV  E, L                       ; DE = База TTY
    CALL hw_i8251_tx_ctrl           ; Вызов SMC-драйвера ВВ51А
    JMP  _tty_isr_done

_isr_tx_ctrl_16550:
    ; Чип 16550: глушим прерывание
    MVI  A, 00H                     ; Режим: Сбросить IER_ENABLE_TX
    MOV  D, H
    MOV  E, L                       ; DE = База TTY
    CALL hw_ns16550_tx_ctrl         ; Вызов SMC-драйвера 16550

_tty_isr_done:
    ; Выдача команды EOI в контроллер прерываний КР580ВН59
    MVI  A, 020H
    OUT  MASTER_8259_CMD            
    
    POP  H
    POP  D
    POP  B                          ; Идеальный баланс регистров Ring 0
    EI                              ; Разрешили прерывания перед выходом
    RET
