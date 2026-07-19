; =============================================================================
; MEGA-580_OS // FILE: panic.asm // SUBSYSTEM K_PANIC CORE (VALIDATOR FIXED)
; =============================================================================

; -----------------------------------------------------------------------------
; K_PANIC
; Глобальный канонический обработчик фатальных сбоев ядра операционной системы
; Вход: Регистр A = Шестнадцатеричный код паники ядра (из файла panic.inc)
; Выход: Процессор аппаратно изолирован и запечатан в глухой HLT
; -----------------------------------------------------------------------------
; =============================================================================
; MEGA-580_OS // FILE: panic.asm // SUBSYSTEM K_PANIC CORE (VALIDATOR FIXED)
; =============================================================================

; -----------------------------------------------------------------------------
; K_PANIC
; Глобальный канонический обработчик фатальных сбоев ядра операционной системы
; Вход: Регистр A = Шестнадцатеричный код паники ядра (из файла panic.inc)
; Выход: Процессор аппаратно изолирован и запечатан в глухой HLT
; -----------------------------------------------------------------------------
k_panic:
    ; === ШАГ 1: ТОТАЛЬНАЯ АППАРАТНАЯ ИЗОЛЯЦИЯ КРИСТАЛЛА ===
    DI                             ; Намертво запереть прерывания шины КР580ВМ80А [1.3]
    
    MOV  C, A                      ; Эвакуируем входящий код паники в регистр C

    ; === ШАГ 2: БЕЗОПАСНЫЙ СБРОС СТРАНИЧНЫХ РЕГИСТРОВ eMMU ===
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE             ; Аппаратный порт 0x76: принудительно закрыть User RAM
    
    ; === ШАГ 3: ВАЛИДАТОР И СОРТИРОВКА КОДОВ ОШИБОК ЯДРА ===
    MOV  A, C                      ; Проверяем прилетевший код против реестра panic.inc
    
    CPI  PANIC_HW_PIC_FAILURE
    JZ   panic_known_route
    CPI  PANIC_HW_PIT_FAILURE
    JZ   panic_known_route
    CPI  PANIC_TTY_NONE_FOUND
    JZ   panic_known_route
    CPI  PANIC_VFS_INDEX_CORRUPT
    JZ   panic_known_route
    CPI  PANIC_VFS_SYS_FT_CRASH
    JZ   panic_known_route
    CPI  PANIC_RTC_CHIP_CRASH
    JZ   panic_known_route

    ; --- ВЕТКА ПЕРЕХВАТА НЕИЗВЕСТНОЙ ПАНИКИ ---
    MVI  A, 'U'
    CALL panic_tx_monolith
    MVI  A, 'N'
    CALL panic_tx_monolith
    MVI  A, 'K'
    CALL panic_tx_monolith
    MVI  A, 'N'
    CALL panic_tx_monolith
    MVI  A, 'O'
    CALL panic_tx_monolith
    MVI  A, 'W'
    CALL panic_tx_monolith
    MVI  A, 'N'
    CALL panic_tx_monolith
    MVI  A, ':'
    CALL panic_tx_monolith
    MVI  A, ' '
    CALL panic_tx_monolith
    JMP  panic_print_hex_code

panic_known_route:
    ; --- ВЕТКА ПЕЧАТИ ИЗВЕСТНОЙ ПАНИКИ ЯДРА ---
    MVI  A, 'P'
    CALL panic_tx_monolith
    MVI  A, 'A'
    CALL panic_tx_monolith
    MVI  A, 'N'
    CALL panic_tx_monolith
    MVI  A, 'I'
    CALL panic_tx_monolith
    MVI  A, 'C'
    CALL panic_tx_monolith
    MVI  A, ':'
    CALL panic_tx_monolith
    MVI  A, ' '
    CALL panic_tx_monolith

panic_print_hex_code:
    ; Преобразуем сохраненный в регистре C код в два ASCII-символа HEX-кода
    MOV  A, C
    RRC                            ; Выделяем старший полубайт (Subsystem ID)
    RRC
    RRC
    RRC
    ANI  0x0F
    CALL panic_convert_hex         ; Сдвиг до ASCII-символа
    CALL panic_tx_monolith         ; Вывели старшую шестнадцатеричную цифру на UART

    MOV  A, C                      ; Выделяем младший полубайт (POSIX Reason)
    ANI  0x0F
    CALL panic_convert_hex
    CALL panic_tx_monolith         ; Вывели младшую шестнадцатеричную цифру на UART

    ; Выводим замыкающий перевод строки (CRLF)
    MVI  A, 0x0D
    CALL panic_tx_monolith
    MVI  A, 0x0A
    CALL panic_tx_monolith

    ; === ШАГ 4: АБСОЛЮТНОЕ ЗАПЕЧАТЫВАНИЕ КРИСТАЛЛА (ЗАЩИТА ОТ NMI) ===
panic_halt_loop:
    HLT                            ; Физический окончательный стоп КР580ВМ80А [1.3]
    JMP  panic_halt_loop           ; Страховка: если NMI разбудит CPU, он мгновенно уснет снова

; -----------------------------------------------------------------------------
; PANIC_CONVERT_HEX (Внутренний транслятор полубайта в ASCII-код)
; -----------------------------------------------------------------------------
panic_convert_hex:
    CPI  10
    JC   panic_num
    ADI  7                         ; Коррекция смещения для буквенных символов A..F
panic_num:
    ADI  48                        ; Коррекция смещения до числовых символов '0'..'9'
    RET

; -----------------------------------------------------------------------------
; PANIC_TX_MONOLITH (Прямой побайтовый вывод на TTY0, минуя структуры VFS)
; Вход: A = ASCII-символ для отправки
; -----------------------------------------------------------------------------
panic_tx_monolith:
    PUSH PSW                       ; Сохранили выводимый символ на стек ядра
    ; Проваливаемся (fall-through) в цикл ожидания, так как JMP не нужен

panic_panic_tx_wait:
    IN   0xA1                      ; Читаем порт статуса физического UART TTY0 [1.3]
    ANI  0x01                      ; Маскируем бит готовности передатчика (TxRDY)
    JZ   panic_panic_tx_wait       ; Передатчик занят, крутимся в аппаратном поллинге
    POP  PSW                       ; Извлекли символ обратно
    OUT  0xA0                      ; Физически вытолкнули байт в шину данных КР580ВВ51А [1.3]
    RET
