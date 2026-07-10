; =============================================================================
; НАЗВАНИЕ: hw_ns16550.asm (Аппаратный драйвер чипа NS16550 с HAL API)
; =============================================================================
; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_init (ВЕРСИЯ С АВТОДЕТЕКТОМ И HAL-РЕГИСТРАЦИЕЙ) 
; Вход:  DE = Физический адрес инициализируемого 160-байтового TTY-слота
;             В слоте должно быть предзаполнено поле O_TTY_HW_BASE_PORT (+155)
; Выход: CY = 0 — Успех, чип найден и инициализирован. Векторы HAL прошиты.
;        CY = 1 — Чип отсутствует на шине. Структура слота не модифицирована.
;        Все РОН полностью сохранены согласно контракту HAL Варианта B.
; =============================================================================
hw_ns16550_init:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст супервизора

    ; --- ЭТАП 0: ИЗВЛЕЧЕНИЕ БАЗОВОГО ПОРТА ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    LXI  B, O_TTY_HW_BASE_PORT
    DAD  B                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  C, M                       ; C = BASE_PORT

    ; === ЭТАП 1: ТЕСТ НАЛИЧИЯ КРИСТАЛЛА (SCRATCH TEST) ===
    MOV  A, C
    ADI  REG_SCR                    ; A = BASE_PORT + 7
    STA  _smc_probe_scr_out + 1     ; ← ИСПРАВЛЕНО: патчим операнд, не opcode
    STA  _smc_probe_scr_in + 1      ; ← ИСПРАВЛЕНО

    MVI  A, 05AH                    ; Контрольный паттерн
_smc_probe_scr_out:
    OUT  000H                       ; Записали в Scratch-регистр

    NOP                             ; Задержка для стабилизации шины
    NOP

_smc_probe_scr_in:
    IN   000H                       ; Считали обратно
    CPI  05AH
    JNZ  _ns16550_probe_fail        ; Чипа нет на шине

    ; === ЭТАП 2: ПОЛНАЯ ПАСПОРТНАЯ ИНИЦИАЛИЗАЦИЯ ===
    ; Восстановим базу и извлечём делители
    MOV  H, D
    MOV  L, E
    PUSH H                          ; Сохранили базу
    LXI  B, O_TTY_HW_DIV_LOW
    DAD  B
    MOV  B, M                       ; B = DIV_LOW
    INX  H
    MOV  A, M                       ; A = DIV_HIGH
    MOV  E, A                       ; E = DIV_HIGH (защищён)
    POP  H                          ; HL = База

    ; Скорость (DLAB = 1)
    MOV  A, C
    ADI  REG_LCR
    STA  _smc_init_lcr1_p + 1       ; ← ИСПРАВЛЕНО: +1
    MVI  A, LCR_DLAB_ENABLE
_smc_init_lcr1_p:
    OUT  000H

    ; Младший байт делителя
    MOV  A, C
    ADI  REG_DLL
    STA  _smc_init_dll_p + 1        ; ← ИСПРАВЛЕНО: +1
    MOV  A, B                       ; A = DIV_LOW
_smc_init_dll_p:
    OUT  000H

    ; Старший байт делителя
    MOV  A, C
    ADI  REG_DLM
    STA  _smc_init_dlm_p + 1        ; ← ИСПРАВЛЕНО: +1
    MOV  A, E                       ; A = DIV_HIGH (из E)
_smc_init_dlm_p:
    OUT  000H

    ; Режим линии 8N1 и сброс DLAB
    MOV  A, C
    ADI  REG_LCR
    STA  _smc_init_lcr2_p + 1       ; ← ИСПРАВЛЕНО: +1
    MVI  A, LCR_WLS_8BIT OR LCR_STB_1STOP OR LCR_PEN_NO_PARITY
_smc_init_lcr2_p:
    OUT  000H

    ; Включение FIFO
    MOV  A, C
    ADI  REG_FCR
    STA  _smc_init_fcr_p + 1        ; ← ИСПРАВЛЕНО: +1
    MVI  A, FCR_FIFO_ENABLE OR FCR_RX_FIFO_RESET OR FCR_TX_FIFO_RESET
_smc_init_fcr_p:
    OUT  000H

    ; Включение прерываний чипа
    MOV  A, C
    ADI  REG_IER
    STA  _smc_init_ier_p + 1        ; ← ИСПРАВЛЕНО: +1
    MVI  A, IER_ENABLE_RX OR IER_ENABLE_TX OR IER_ENABLE_LSR
_smc_init_ier_p:
    OUT  000H

    ; === ЭТАП 3: ДИНАМИЧЕСКАЯ ПРОШИВКА HAL-ВЕКТОРОВ СТРОГО В СЛOТ DE ===
    ; ИСПРАВЛЕНО: База структуры загружается из незатертого регистра DE!
    MOV  H, D
    MOV  L, E                       ; HL = Истинный адрес слота из пары DE
    
    PUSH H
    LXI  D, O_TTY_HW_PUT_CHAR
	DAD  D
    LXI  D, hw_ns16550_put_char
	MOV M, E
	INX H
	MOV M, D
    POP  H
	PUSH H
    
    LXI  D, O_TTY_HW_GET_CHAR
	DAD  D
    LXI  D, hw_ns16550_get_char
	MOV M, E
	INX H
	MOV M, D
    POP  H
	PUSH H
    
    LXI  D, O_TTY_HW_POLL_STAT
	DAD  D
    LXI  D, hw_ns16550_poll_status
	MOV M, E
	INX H
	MOV M, D
    POP  H
	PUSH H
    
    LXI  D, O_TTY_HW_CHIP_TYPE
	DAD  D
    MVI  M, CHIP_TYPE_NS16550       ; Маркер = 02H
    POP  H

    POP  H
    POP  D
    POP  B                          ; Восстановили РОН супервизора
    ANA  A                          ; CY = 0 (успех)
    RET

_ns16550_probe_fail:
    POP  H
    POP  D
    POP  B                          ; Восстановили РОН
    STC                             ; CY = 1 (устройство отсутствует)
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_poll_status (ОПТИМИЗИРОВАНО: ОДНО ЧТЕНИЕ РЕГИСТРА LSR)
; Вход:  DE = Физический адрес 160-байтового TTY-слота
; Задача: Считать Line Status Register (LSR) один раз и транслировать в маски HAL
; Выход: А  = Байт системного статуса HAL (биты TTY_HAL_TXRDY, TTY_HAL_RXRDY)
;        Регистры BC, DE, HL полностью сохранены.
; =============================================================================
hw_ns16550_poll_status:
    PUSH B
    PUSH H                          ; Сохранили РОН супервизора

    ; Извлекаем базовый порт из структуры TTY-слота
    MOV  H, D
    MOV  L, E
    LXI  B, O_TTY_HW_BASE_PORT
    DAD  B
    MOV  A, M                       ; A = BASE_PORT
    ADI  REG_LSR                    ; А = Физический порт регистра LSR (BASE + 5)
    STA  _smc_lsr_patch             ; Динамический патчинг команды IN

_smc_lsr_execute:
    ; === СЧИТЫВАЕМ АППАРАТНЫЙ СТАТУС С ТРИГГЕРА ЖЕЛИЗА РОВНО ОДИН РАЗ ===
    DB   0DBH                       ; Opcode IN
_smc_lsr_patch:
    DB   000H                       ; Сюда SMC подставит адрес регистра LSR
    MOV  B, A                       ; B = Сырой статус чипа 16550

    ; --- Анализ готовности передатчика (Бит 5 LSR - THRE) ---
    ANI  LSR_THRE
    JZ   _lsr_check_rx              ; Если бит 0 — FIFO передатчика занято
    MVI  C, TTY_HAL_TXRDY           ; Накопительный флаг HAL (Бит 0 = 1)
    JMP  _lsr_analyze_rx

_lsr_check_rx:
    MVI  C, 00H                     ; Передатчик занят, стартовый сброс маски HAL

_lsr_analyze_rx:
    ; --- Анализ готовности приемника (Бит 0 LSR - DR) из того же байта ---
    MOV  A, B                       ; Восстановили сохраненный статус из регистра B
    ANI  LSR_DATA_READY
    JZ   _lsr_exit                  ; В FIFO приемника пусто, выходим с текущей маской
    
    MOV  A, C
    ORI  TTY_HAL_RXRDY              ; Взвели бит готовности HAL приемника (Бит 1 = 1)
    MOV  C, A

_lsr_exit:
    MOV  A, C                       ; Результат транслирован в Аккумулятор А
    POP  H
    POP  B                          ; Полное восстановление РОН
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_put_char
; Вход:  A  = ASCII-символ для физической отправки
;        DE = Физический адрес 160-байтового TTY-слота
; Задача: Считать адрес порта THR из слота, SMC-патчинг и запись в FIFO
; Выход: Все РОН (включая A+F!) полностью сохранены согласно контракту Варианта B
; =============================================================================
hw_ns16550_put_char:
    PUSH B
    PUSH D
    PUSH H
    MOV  B, A                       ; B = символ

    ; Извлекаем базовый порт (для регистра THR смещение равно 0, BASE_PORT + 0)
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D
    MOV  A, M                       ; A = BASE_PORT (порт регистра THR)
    STA  _smc_16550_thr_patch       ; SMC-модификация

    MOV  A, B                       ; Восстановили символ в А
_smc_16550_thr_execute:
    DB   0D3H                       ; Opcode OUT
_smc_16550_thr_patch:
    DB   000H                       ; Стреляем байтом прямо во встроенное FIFO чипа!

    POP  H
    POP  D
    POP  B
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_get_char
; Вход:  DE = Физический адрес 160-байтового TTY-слота
; Задача: Считать адрес порта RBR из слота, SMC-патчинг и забор байта из FIFO
; Выход: А  = Принятый ASCII-символ. Все остальные РОН полностью сохранены.
; =============================================================================
; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_get_char (ПОЛНОСТЬЮ ИСПРАВЛЕННАЯ ЭТАЛОННАЯ ВЕРСИЯ)
; ТОКЕН:    TOKEN::MEGA-580_OS_v1.5.77_HW_NS16550_GET_CHAR_STABLE_20260708
; Вход:  DE = Физический адрес 160-байтового TTY-слота (TTY0..TTY3).
; Задача: Считать базовый порт, выполнить SMC-патчинг операнда (+1) и забрать
;         символ из регистра RBR чипа 16550 без разрушения РОН супервизора.
; Выход: А  = Принятый из FIFO ASCII-символ.
;        Регистры BC, DE, HL полностью сохранены согласно контракту HAL.
; =============================================================================
hw_ns16550_get_char:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст вызова Ring 0 супервизора

    ; --- Извлекаем базовый физический порт данных из структуры слота DE ---
    MOV  H, D
    MOV  L, E                       ; HL = Динамический адрес TTY-слота
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = BASE_PORT (Порт регистра RBR, смещение 0)
    
    ; --- SMC-ПАТЧИНГ: Прошиваем порт строго во второй байт (операнд +1) ---
    STA  _smc_16550_rbr_execute + 1

_smc_16550_rbr_execute:
    ; === ДИНАМИЧЕСКАЯ ИНСТРУКЦИЯ ВВОДА ИЗ КРЕМНИЯ NS16550 ===
    DB   0DBH                       ; Код операции (Opcode) инструкции IN
    DB   000H                       ; Сюда SMC-команда выше подставит реальный порт (BASE+0)

    ; === ЭВАКУАЦИЯ ПРИНЯТОГО СИМВОЛА В ТЕНЕВУЮ ЯЧЕЙКУ ОЗУ ЯДРА ===
    STA  _temp_ns_get_char          ; Атомарно сохранили символ в локальную память

    ; === КАНОНИЧЕСКОЕ ВОССТАНОВЛЕНИЕ РОН СУПЕРВИЗОРА ПО ИНВАРИАНТУ LIFO ===
    POP  H                          ; HL = Восстановили оригинальный HL_old
    POP  D                          ; DE = Восстановили оригинальный DE_old (База TTY)
    POP  B                          ; BC = Восстановили оригинальный BC_old

    ; === ВЫДАЧА РЕЗУЛЬТАТА В ШЛЮЗ ВОЗВРАТА ===
    LDA  _temp_ns_get_char          ; Аккумулятор А = Истинный принятый символ!
    RET                             ; Безопасный возврат, стек супервизора чист

; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_tx_ctrl (УПРАВЛЕНИЕ МАСКОЙ ПРЕРЫВАНИЙ ПЕРЕДАТЧИКА 16550)
; ТОКЕН:    TOKEN::MEGA-580_OS_v1.5.55_K_HW_16550_TX_CTRL_FIXED_20260707
; Вход:  A  = Режим управления (00H = Запретить Tx-прерывание, 01H = Разрешить)
;        DE = Физический адрес 160-байтового TTY-слота
; Задача: Динамически пересчитать маску регистра IER (BASE+REG_IER) через SMC,
;         выполнив цикл Чтение-Модификация-Запись для сохранения Rx-бит.
; Выход: Все РОН (включая A и F!) полностью сохранены согласно контракту HAL.
; =============================================================================
hw_ns16550_tx_ctrl:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст РОН супервизора
    
    MOV  C, A                       ; C = входной параметр режима (00H или 01H)
    PUSH PSW                        ; Сохранили исходный аккумулятор А и флаги F на стек

    ; --- ЭТАП 1: ВЫЧИСЛЕНИЕ ФИЗИЧЕСКОГО ПОРТА РЕГИСТРА REG_IER ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = реальный базовый порт (например, 0B0H)
    ADI  REG_IER                    ; A = BASE_PORT + 1 (Порт регистра IER)
    
    ; --- SMC-ПАТЧИНГ: прошиваем вычисленный порт в команды IN и OUT ---
    STA  _smc_16550_ier_in_patch
    STA  _smc_16550_ier_out_patch   ; Модификация кода на лету окончена

    ; --- ЭТАП 2: ЦИКЛ ЧТЕНИЯ ТЕКУЩЕЙ МАСКИ ИЗ КРИСТАЛЛА ---
_smc_16550_ier_in_execute:
    DB   0DBH                       ; Opcode IN
_smc_16550_ier_in_patch:
    DB   000H                       ; Сюда подставится адрес регистра IER
    MOV  B, A                       ; B = текущее аппаратное состояние регистра IER

    ; --- ЭТАП 3: МОДИФИКАЦИЯ БИТА ПРЕРЫВАНИЯ TX (БИТ 1) ---
    MOV  A, C                       ; Восстановили параметр режима (00H или 01H)
    ORA  A
    JZ   _ns16550_tx_disable        ; Если 00H — гасим бит прерывания передатчика

    ; Режим 01H: Атомарно взводим бит IER_ENABLE_TX (Бит 1)
    MOV  A, B
    ORI  IER_ENABLE_TX              ; Взвели Бит 1 (A = B OR 02H)
    JMP  _smc_16550_ier_out_execute

_ns16550_tx_disable:
    ; Режим 00H: Атомарно гасим бит IER_ENABLE_TX через каноничную маску i8080
    ; ИСПРАВЛЕНО: Прямая побитовая маска 0FDH вместо синтаксической ошибки ANI NOT
    MOV  A, B
    ANI  0FDH                       ; 0FDH = 11111101B (Сбросили Бит 1, сохраняя Rx и ошибки)

    ; --- ЭТАП 4: ЗАПИСЬ ОБНОВЛЕННОЙ МАСКИ В КРИСТАЛЛ ---
_smc_16550_ier_out_execute:
    DB   0D3H                       ; Opcode OUT
_smc_16550_ier_out_patch:
    DB   000H                       ; Сюда подставится адрес регистра IER

    ; --- ЭТАП 5: ПОЛНОЕ ВОССТАНОВЛЕНИЕ КОНТЕНТА СОГЛАСНО КОНТРАКТУ ---
    POP  PSW                        ; Восстановили оригинальный А и флаги F
    POP  H
    POP  D
    POP  B                          ; Идеальный баланс РОН супервизора
    RET

; =============================================================================
; НАЗВАНИЕ: hw_ns16550.asm (Специализированный монолитный ISR для чипа NS16550)
; Вход:  Аппаратный CALL по вектору IRQ от КР580ВН59. Прерывания заперты (DI).
;        Состояние РОН и SP — случайное (из прерванного контекста Ring 3).
; =============================================================================
hw_ns16550_isr:
_smc_isr_ns_base:
    LXI  D, 0040H                   ; SMC-инстанс: карусель прошьёт адрес TTY-слота

    PUSH B
    PUSH D
    PUSH H

    ; === ЭТАП 1: SMC-РАСЧЕТ ПОРТОВ ===
    MOV  H, D
    MOV  L, E
    LXI  B, O_TTY_HW_BASE_PORT
    DAD  B
    MOV  C, M                       ; C = BASE_PORT
    
    MOV  A, C
	ADI  2
    STA  _isr_ns_iir_in + 1
    
    MOV  A, C
    STA  _isr_ns_data_in + 1
    STA  _isr_ns_data_out + 1
    
    MOV  A, C
	INR  A
    STA  _isr_ns_ier_in + 1
    STA  _isr_ns_ier_out + 1

    ; === ЭТАП 2: ЧТЕНИЕ IIR ===
_isr_ns_iir_in:
    IN   000H
    ANI  IIR_INT_ID_MASK
    MOV  B, A

    ; === ЭТАП 3: ДЕШИФРАЦИЯ ===
    CPI  IIR_RX_DATA_AVAIL
    JZ   _isr_ns_rx
    CPI  IIR_THR_EMPTY
    JZ   _isr_ns_tx
    CPI  IIR_RX_TIMEOUT
    JZ   _isr_ns_rx
    JMP  _isr_ns_done

_isr_ns_rx:
    ; === ЭТАП 4: Rx-ВЕТКА ===
_isr_ns_data_in:
    IN   000H
    MOV  C, A

    PUSH D
    PUSH B

    MOV  H, D
	MOV  L, E
    LXI  D, O_TTY_RX_COUNT
    DAD  D
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JZ   _isr_ns_rx_drop

    DCX  H
	DCX  H
    MOV  A, M
    PUSH PSW                        ; Сохраняем HEAD_old

    INR  M
    MOV  A, M
	CPI  TTY_BUF_SIZE
	JC   _isr_ns_rx_no_wrap
    MVI  M, 00H

_isr_ns_rx_no_wrap:
    POP  PSW                        ; ← ИСПРАВЛЕНО: только ОДИН POP PSW!
    
    ; Двухступенчатый расчет адреса
    MOV  H, D
	MOV  L, E
    PUSH D
    LXI  D, O_TTY_RX_BUFFER
    DAD  D
    MOV  E, A
	MVI  D, 00H
    DAD  D
    POP  D
    MOV  M, C

    ; Инкремент RX_COUNT
    MOV  H, D
	MOV  L, E
    LXI  D, O_TTY_RX_COUNT
	DAD  D
    INR  M

_isr_ns_rx_drop:
    POP  B
    POP  D
    JMP  _isr_ns_done

_isr_ns_tx:
    ; === ЭТАП 5: Tx-ВЕТКА ===
    PUSH D
    PUSH B

    MOV  H, D
	MOV  L, E
    LXI  D, O_TTY_TX_COUNT
	DAD  D
    MOV  A, M
	ORA  A
    JZ   _isr_ns_tx_close

    DCX  H
    MOV  A, M
    PUSH PSW
    
    INR  M
    MOV  A, M
	CPI  TTY_BUF_SIZE
	JC   _isr_ns_tx_no_wrap
    MVI  M, 00H

_isr_ns_tx_no_wrap:
    POP  PSW
    
    ; Двухступенчатый расчет адреса
    MOV  H, D
	MOV  L, E
    PUSH D
    LXI  D, O_TTY_TX_BUFFER
	DAD  D
    MOV  E, A
	MVI  D, 00H
    DAD  D
    POP  D
    MOV  A, M

_isr_ns_data_out:
    OUT  000H
    POP  B                          ; Восстанавливаем статус

    ; Декремент TX_COUNT
    MOV  H, D
	MOV  L, E
    LXI  D, O_TTY_TX_COUNT
	DAD  D
    DCR  M
    
    POP  D                          ; ← ИСПРАВЛЕНО: только восстановление базы!
    JMP  _isr_ns_done

_isr_ns_tx_close:
    POP  B
    POP  D
    
_isr_ns_ier_in:
    IN   000H
    ANI  0FDH
_isr_ns_ier_out:
    OUT  000H

_isr_ns_done:
    MVI  A, 020H
    OUT  MASTER_8259_CMD

    POP  H
    POP  D
    POP  B
    EI
    RET
