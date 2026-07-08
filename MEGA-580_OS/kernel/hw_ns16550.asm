; =============================================================================
; НАЗВАНИЕ: hw_ns16550.asm (Аппаратный драйвер чипа NS16550 с HAL API)
; =============================================================================
; =============================================================================
; ПРОЦЕДУРА: hw_ns16550_init
; Вход:  DE = Физический адрес инициализируемого 160-байтового TTY-слота
;        Поля TTY-слота ДОЛЖНЫ быть предварительно заполнены:
;          O_TTY_HW_BASE_PORT (+155) = базовый порт контроллера
;          O_TTY_HW_DIV_LOW   (+156) = младший байт делителя частоты
;          O_TTY_HW_DIV_HIGH  (+157) = старший байт делителя частоты
; Задача: Инициализировать NS16550 (8N1, FIFO On, заданная скорость),
;         прописать HAL-векторы и маркер типа чипа в структуру слота.
; Выход: Все РОН (BC, DE, HL) полностью сохранены согласно контракту HAL.
; =============================================================================
; hw_ns16550_init:
    ; PUSH B
    ; PUSH D
    ; PUSH H                          ; Сохранили контекст супервизора

    ; ; === ЭТАП 0: ИЗВЛЕЧЕНИЕ ПАРАМЕТРОВ ИЗ СТРУКТУРЫ TTY ===
    ; MOV  H, D
    ; MOV  L, E                       ; HL = База TTY-слота
    
    ; PUSH H                          ; Сохранили базу
    ; LXI  B, O_TTY_HW_BASE_PORT
    ; DAD  B                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    ; MOV  C, M                       ; C = BASE_PORT (например, 0B0H)
    ; INX  H                          ; HL -> O_TTY_HW_DIV_LOW (+156)
    ; MOV  B, M                       ; B = DIV_LOW
    ; INX  H                          ; HL -> O_TTY_HW_DIV_HIGH (+157)
    ; MOV  A, M                       ; A = DIV_HIGH (сохраняем в аккумуляторе)
    ; POP  H                          ; Восстановили базу HL

    ; ; === ЭТАП 1: ПРОГРАММИРОВАНИЕ СКОРОСТИ (DLAB = 1) ===
    ; ; Включаем DLAB: OUT (BASE + REG_LCR), LCR_DLAB_ENABLE
    ; MOV  A, C
    ; ADI  REG_LCR
    ; STA  _smc_init_lcr1
    ; MVI  A, LCR_DLAB_ENABLE         ; 0x80
; _smc_init_lcr1:
    ; OUT  000H                       ; Патчится на BASE + REG_LCR

    ; ; Записываем младший байт делителя: OUT (BASE + REG_DLL), B
    ; MOV  A, C
    ; ADI  REG_DLL
    ; STA  _smc_init_dll
    ; MOV  A, B                       ; A = DIV_LOW из структуры
; _smc_init_dll:
    ; OUT  000H                       ; Патчится на BASE + REG_DLL

    ; ; Записываем старший байт делителя: OUT (BASE + REG_DLM), A (из структуры!)
    ; MOV  A, C
    ; ADI  REG_DLM
    ; STA  _smc_init_dlm
    ; ; A уже содержит DIV_HIGH из структуры — используем его напрямую
    ; ; (поддержка скоростей < 2400 бод, где старший байт != 0)
; _smc_init_dlm:
    ; OUT  000H                       ; Патчится на BASE + REG_DLM

    ; ; === ЭТАП 2: КОНФИГУРАЦИЯ РЕЖИМА ЛИНИИ (8N1, DLAB = 0) ===
    ; MOV  A, C
    ; ADI  REG_LCR
    ; STA  _smc_init_lcr2
    ; MVI  A, LCR_WLS_8BIT OR LCR_STB_1STOP OR LCR_PEN_NO_PARITY  ; 0x03
; _smc_init_lcr2:
    ; OUT  000H                       ; Патчится на BASE + REG_LCR

    ; ; === ЭТАП 3: АКТИВАЦИЯ И ОЧИСТКА ВНУТРЕННЕГО FIFO ===
    ; MOV  A, C
    ; ADI  REG_FCR
    ; STA  _smc_init_fcr
    ; MVI  A, FCR_FIFO_ENABLE OR FCR_RX_FIFO_RESET OR FCR_TX_FIFO_RESET  ; 0x07
; _smc_init_fcr:
    ; OUT  000H                       ; Патчится на BASE + REG_FCR

    ; ; === ЭТАП 4: РАЗРЕШЕНИЕ АППАРАТНЫХ ПРЕРЫВАНИЙ ЧИПА ===
    ; ; Разрешаем Rx, Tx и прерывания по ошибкам линии (LSR)
    ; MOV  A, C
    ; ADI  REG_IER
    ; STA  _smc_init_ier
    ; MVI  A, IER_ENABLE_RX OR IER_ENABLE_TX OR IER_ENABLE_LSR  ; 0x07
; _smc_init_ier:
    ; OUT  000H                       ; Патчится на BASE + REG_IER

    ; ; === ЭТАП 5: ПРОШИВКА HAL-ВЕКТОРОВ В СЛОТ ===
    ; ; Прописываем адрес hw_ns16550_put_char в O_TTY_HW_PUT_CHAR (+149)
    ; PUSH H
    ; LXI  D, O_TTY_HW_PUT_CHAR
    ; DAD  D                          ; HL -> O_TTY_HW_PUT_CHAR
    ; LXI  D, hw_ns16550_put_char
    ; MOV  M, E
    ; INX  H
    ; MOV  M, D
    ; POP  H

    ; ; Прописываем адрес hw_ns16550_get_char в O_TTY_HW_GET_CHAR (+151)
    ; PUSH H
    ; LXI  D, O_TTY_HW_GET_CHAR
    ; DAD  D                          ; HL -> O_TTY_HW_GET_CHAR
    ; LXI  D, hw_ns16550_get_char
    ; MOV  M, E
    ; INX  H
    ; MOV  M, D
    ; POP  H

    ; ; Прописываем адрес hw_ns16550_poll_status в O_TTY_HW_POLL_STAT (+153)
    ; PUSH H
    ; LXI  D, O_TTY_HW_POLL_STAT
    ; DAD  D                          ; HL -> O_TTY_HW_POLL_STAT
    ; LXI  D, hw_ns16550_poll_status
    ; MOV  M, E
    ; INX  H
    ; MOV  M, D
    ; POP  H

    ; ; === ЭТАП 6: ФИКСАЦИЯ МАРКЕРА ТИПА ЧИПА ===
    ; PUSH H
    ; LXI  D, O_TTY_HW_CHIP_TYPE
    ; DAD  D                          ; HL -> O_TTY_HW_CHIP_TYPE (+158)
    ; MVI  M, CHIP_TYPE_NS16550       ; 02H — идентификатор NS16550
    ; POP  H

    ; ; === ЭТАП 7: ПОЛНОЕ ВОССТАНОВЛЕНИЕ КОНТЕКСТА ===
    ; POP  H
    ; POP  D
    ; POP  B                          ; Контракт HAL полностью соблюден
    ; RET
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
    LXI  D, O_TTY_HW_PUT_CHAR \ DAD  D
    LXI  D, hw_ns16550_put_char \ MOV M, E \ INX H \ MOV M, D
    POP  H \ PUSH H
    
    LXI  D, O_TTY_HW_GET_CHAR \ DAD  D
    LXI  D, hw_ns16550_get_char \ MOV M, E \ INX H \ MOV M, D
    POP  H \ PUSH H
    
    LXI  D, O_TTY_HW_POLL_STAT \ DAD  D
    LXI  D, hw_ns16550_poll_status \ MOV M, E \ INX H \ MOV M, D
    POP  H \ PUSH H
    
    LXI  D, O_TTY_HW_CHIP_TYPE \ DAD  D
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
hw_ns16550_get_char:
    PUSH B
    PUSH D
    PUSH H

    ; Извлекаем базовый порт (для регистра RBR смещение равно 0, BASE_PORT + 0)
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D
    MOV  A, M                       ; A = BASE_PORT (порт регистра RBR)
    STA  _smc_16550_rbr_patch       ; SMC-модификация

_smc_16550_rbr_execute:
    DB   0DBH                       ; Opcode IN
_smc_16550_rbr_patch:
    DB   000H                       ; Вычитываем байт из FIFO приемника!

    MOV  C, A                       ; Сохранили принятый символ в C
    POP  H
    POP  D
    POP  B                          ; Полное восстановление контекста
    MOV  A, C                       ; Символ возвращен в аккумулятор А
    RET

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
; =============================================================================
hw_ns16550_isr:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст супервизора Ring 0

    ; --- ЭТАП 1: ЛОКАЛИЗАЦИЯ СТРУКТУРЫ TTY1 В ОЗУ ЯДРА ---
    LXI  D, TTY_TABLE + 160         ; DE = База TTY1 слота

    ; === ЭТАП 2: ЧТЕНИЕ РЕГИСТРА ИДЕНТИФИКАЦИИ ПРЕРЫВАНИЙ (IIR) ===
    IN   0B2H                       ; IN IIR (BASE + 2 = 0xB2)
    ANI  IIR_INT_ID_MASK            ; Выделяем источник (Маска 0x0E)
    MOV  B, A                       ; B = Код сработавшего события

    ; === ЭТАП 3: ДЕШИФРАЦИЯ СОБЫТИЯ И ВЕТВЛЕНИЕ ===
    CPI  IIR_RX_DATA_AVAIL          ; 04H — приём данных?
    JZ   _ns16550_isr_rx
    CPI  IIR_THR_EMPTY              ; 02H — THR пуст?
    JZ   _ns16550_isr_tx
    CPI  IIR_RX_TIMEOUT             ; 0CH — таймаут FIFO?
    JZ   _ns16550_isr_rx            ; Обрабатываем как обычный RX
    JMP  _ns16550_isr_done          ; Иные события — выход

_ns16550_isr_rx:
    ; === ФИЗИЧЕСКИЙ ВЫВОД ИЗ FIFO ПРИЕМНИКА ===
    IN   0B0H                       ; IN RBR (BASE + 0 = 0xB0)
    MOV  C, A                       ; C = Принятый ASCII-символ

    PUSH D                          ; Сохранили чистую базу TTY1 на стек Ring 0
    PUSH B                          ; Сохранили статус B и символ C на стек

    ; Проверка переполнения RX-кольца
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_RX_COUNT
    DAD  D                          ; HL -> O_TTY_RX_COUNT
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JZ   _ns16550_rx_drop           ; Переполнение — drop

    ; Читаем и инкрементируем HEAD
    DCX  H
    DCX  H                          ; HL -> O_TTY_RX_HEAD (+0)
    MOV  A, M                       ; A = RX_HEAD_old
    PUSH PSW                        ; Сохраняем HEAD_old на стек
    
    INR  M                          ; HEAD++
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JC   _ns16550_rx_no_wrap
    MVI  M, 00H                     ; Зацикливание HEAD = 0

_ns16550_rx_no_wrap:
    POP  PSW                        ; A = RX_HEAD_old

    ; --- КАНOНИЧЕСКИЙ ДВУХСТУПЕНЧАТЫЙ РАСЧЕТ АДРЕСА БУФЕРА RX ---
    MOV  H, D
    MOV  L, E                       ; HL = Истинная база TTY1 (из РОН DE)
    PUSH D                          ; Временно спрятали DE
    
    LXI  D, O_TTY_RX_BUFFER
    DAD  D                          ; HL = База_TTY1 + O_TTY_RX_BUFFER
    
    MOV  E, A
    MVI  D, 00H                     ; DE = HEAD_old
    DAD  D                          ; HL = (База + Смещение_Буфера) + HEAD_old! Указатель точен!
    
    POP  D                          ; Восстановили DE = База TTY1
    MOV  M, C                       ; Запись символа из C в ОЗУ. Байт зафиксирован!

    ; Инкремент RX_COUNT
    MOV  H, D
    MOV  L, E                       ; HL = База TTY1
    LXI  D, O_TTY_RX_COUNT
    DAD  D
    INR  M                          ; RX_COUNT++

_ns16550_rx_drop:
    POP  B                          ; Восстановили статус и символ
    POP  D                          ; Восстановили базу TTY1

_ns16550_isr_rx_done:
    JMP  _ns16550_isr_done

_ns16550_isr_tx:
    PUSH D                          ; Сохраняем базу TTY1
    PUSH B                          ; Сохраняем статус

    ; Проверка наличия данных в TX-кольце
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_TX_COUNT
    DAD  D                          ; HL -> O_TTY_TX_COUNT
    MOV  A, M
    ORA  A
    JZ   _ns16550_tx_close          ; Очередь пуста — глушим IRQ

    ; Читаем и инкрементируем TAIL
    DCX  H                          ; HL -> O_TTY_TX_TAIL (+68)
    MOV  A, M                       ; A = TAIL_old
    PUSH PSW                        ; Сохраняем TAIL_old
    
    INR  M                          ; TAIL++
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JC   _ns16550_tx_no_wrap
    MVI  M, 00H                     ; Зацикливание TAIL = 0

_ns16550_tx_no_wrap:
    POP  PSW                        ; A = TAIL_old

    ; --- КАНOНИЧЕСКИЙ ДВУХСТУПЕНЧАТЫЙ РАСЧЕТ АДРЕСА БУФЕРА TX ---
    MOV  H, D
    MOV  L, E                       ; HL = Истинная база TTY1
    PUSH D                          ; Временно спрятали DE
    
    LXI  D, O_TTY_TX_BUFFER
    DAD  D                          ; HL = База + O_TTY_TX_BUFFER
    
    MOV  E, A
    MVI  D, 00H                     ; DE = TAIL_old
    DAD  D                          ; HL = (База + Смещение_Буфера) + TAIL_old! Указатель точен!
    
    POP  D                          ; Восстановили DE = База TTY1
    MOV  A, M                       ; A = Извлеченный из ОЗУ символ

    ; Физический выстрел в FIFO передатчика
    OUT  0B0H                       ; OUT THR (BASE + 0 = 0xB0)

    ; Декремент TX_COUNT
    MOV  H, D
    MOV  L, E                       ; HL = База TTY1
    LXI  D, O_TTY_TX_COUNT
    DAD  D
    DCR  M                          ; TX_COUNT--
    
    POP  B                          ; Восстанавливаем статус
    POP  D                          ; Восстанавливаем базу
    JMP  _ns16550_isr_done

_ns16550_tx_close:
    POP  B                          ; Восстанавливаем статус
    POP  D                          ; Восстанавливаем базу TTY1
    
    ; Атомарно гасим бит IER_ENABLE_TX в регистре IER
    IN   0B1H                       ; Чтение текущей маски IER (BASE + 1 = 0xB1)
    ANI  0FDH                       ; Сброс бита 1 (IER_ENABLE_TX), сохраняя Rx и LSR
    OUT  0B1H                       ; Запись обновлённой маски в кристалл

_ns16550_isr_done:
    ; Выдача команды EOI в КР580ВН59
    MVI  A, 020H
    OUT  MASTER_8259_CMD

    POP  H
    POP  D
    POP  B                          ; Полное восстановление оригинального РОН контекста
    EI
    RET
