; =============================================================================
; MEGA-580_OS // FILE: rtc_nvram.asm // SUBSYSTEM RTC/NVRAM STEP_3
; =============================================================================

; -----------------------------------------------------------------------------
; K_NVRAM_READ_BLOCK
; Последовательное чтение блока данных из NVRAM КР512ВИ1 в ОЗУ Ядра
; Вход: A  - Начальный внутренний адрес NVRAM чипа (от 0x0E)
;       C  - Количество байт для чтения
;       HL - Адрес буфера назначения в памяти ядра Ring 0
; Выход: CY = 0 (Успех), CY = 1 (Ошибка: выход за границы NVRAM)
; -----------------------------------------------------------------------------
k_nvram_read_block:
    DI                             ; Полная атомарность, запрет прерываний таймера
    PUSH B
    PUSH D
    PUSH H

    ; --- Валидация входных параметров ---
    CPI  RTC_NVRAM_BASE            ; Проверка: адрес >= 0x0E?
    JC   nvram_rd_err              ; Если < 0x0E -> Ошибка
    
    MOV  D, A                      ; D = Внутренний адрес (сохраняем)
    ADD  C                         ; A = Начальный адрес + Количество байт
    
    ; ИСПРАВЛЕНО: 0x40 — это первый НЕвалидный адрес (валидные: 0x0E..0x3F).
    ; Поэтому ошибка только если A >= 0x41.
    CPI  041H                      
    JNC  nvram_rd_err              

    ; --- Фиксация контекста итератора ---
    MOV  A, D \ STA k_nvram_saved_addr
    MOV  A, C \ STA k_nvram_saved_count
    SHLD k_nvram_buf_ptr

nvram_rd_loop:
    LDA  k_nvram_saved_count
    ORA  A
    JZ   nvram_rd_success          ; Если все байты прочитаны -> Успех

    ; Чтение байта из КР512ВИ1
    LDA  k_nvram_saved_addr
    OUT  RTC_PORT_ADDR             ; Выставляем внутренний адрес
    IN   RTC_PORT_DATA             ; Читаем байт данных
    MOV  B, A                      ; B = Прочитанный байт

    ; Запись байта в буфер ядра
    LHLD k_nvram_buf_ptr
    MOV  M, B                      ; Сохраняем в память ОЗУ ядра
    INX  H                         ; Двигаем указатель ОЗУ ядра
    SHLD k_nvram_buf_ptr

    ; Модификация каунтеров итератора
    LDA  k_nvram_saved_addr
    INR  A
    STA  k_nvram_saved_addr        ; Инкремент адреса чипа

    LDA  k_nvram_saved_count
    DCR  A
    STA  k_nvram_saved_count       ; Декремент счетчика байт
    JMP  nvram_rd_loop

nvram_rd_success:
    POP  H \ POP  D \ POP  B
    EI                             ; ИСПРАВЛЕНО: Восстанавливаем прерывания перед выходом
    ANA  A                         ; CY = 0 (Сигнал успешного завершения)
    RET

nvram_rd_err:
    POP  H \ POP  D \ POP  B
    EI                             ; ИСПРАВЛЕНО: Восстанавливаем прерывания даже при ошибке
    STC                            ; CY = 1 (Аварийный флаг ошибки)
    RET


; -----------------------------------------------------------------------------
; K_NVRAM_WRITE_BLOCK
; Последовательная запись блока данных из ОЗУ Ядра в NVRAM КР512ВИ1
; Вход: A  - Начальный внутренний адрес NVRAM чипа (от 0x0E)
;       C  - Количество байт для записи
;       HL - Адрес буфера-источника в памяти ядра Ring 0
; Выход: CY = 0 (Успех), CY = 1 (Ошибка: выход за границы NVRAM)
; -----------------------------------------------------------------------------
k_nvram_write_block:
    DI                             ; Защита транзакции шины
    PUSH B
    PUSH D
    PUSH H

    ; --- Валидация входных параметров ---
    CPI  RTC_NVRAM_BASE
    JC   nvram_wr_err
    
    MOV  D, A                      ; D = Внутренний адрес
    ADD  C                         ; A = Адрес + Количество
    
    ; ИСПРАВЛЕНО: Та же логика, что и в чтении. A >= 0x41 является ошибкой.
    CPI  041H                      
    JNC  nvram_wr_err

    ; --- Фиксация контекста итератора ---
    MOV  A, D \ STA k_nvram_saved_addr
    MOV  A, C \ STA k_nvram_saved_count
    SHLD k_nvram_buf_ptr

nvram_wr_loop:
    LDA  k_nvram_saved_count
    ORA  A
    JZ   nvram_wr_success          ; Если все записано -> Успех

    ; Извлечение байта из источника в ядре
    LHLD k_nvram_buf_ptr
    MOV  B, M                      ; B = Байт для записи
    INX  H                         ; Инкремент адреса источника
    SHLD k_nvram_buf_ptr

    ; Запись байта в КР512ВИ1
    LDA  k_nvram_saved_addr
    OUT  RTC_PORT_ADDR             ; Выставляем адрес регистра
    MOV  A, B
    OUT  RTC_PORT_DATA             ; Физически пишем байт в NVRAM

    ; Модификация каунтеров итератора
    LDA  k_nvram_saved_addr
    INR  A
    STA  k_nvram_saved_addr

    LDA  k_nvram_saved_count
    DCR  A
    STA  k_nvram_saved_count
    JMP  nvram_wr_loop

nvram_wr_success:
    POP  H \ POP  D \ POP  B
    EI                             ; ИСПРАВЛЕНО: Восстанавливаем прерывания
    ANA  A                         ; CY = 0
    RET

nvram_wr_err:
    POP  H \ POP  D \ POP  B
    EI                             ; ИСПРАВЛЕНО: Восстанавливаем прерывания
    STC                            ; CY = 1
    RET
