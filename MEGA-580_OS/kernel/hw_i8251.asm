;HAL-функции для КР580ВВ51А: hw_i8251_poll_status, hw_i8251_put_char, hw_i8251_get_char
; -----------------------------------------------------------------------------
; Инициализация USART КР580ВВ51А (9600,8N1, фактор K=16)
; -----------------------------------------------------------------------------
; =============================================================================
; ПРОЦЕДУРА: hw_i8251_init (ПОЛНАЯ ВЕРСИЯ С ДВУХЧИПОВЫМ АВТОДЕТЕКТОМ ВВ51+ВИ53)
; Вход:  DE = Физический адрес обрабатываемого TTY-слота (TTY0..TTY3).
; Выход: CY = 0 — Успех, ОБА чипа (ВВ51 и ВИ53) найдены и инициализированы.
;        CY = 1 — Отсутствует ВВ51 или отсутствует/неисправен ВИ53.
; =============================================================================
hw_i8251_init:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст супервизора Ring 0

    ; --- ЭТАП 0: ДИНАМИЧЕСКОЕ ИЗВЛЕЧЕНИЕ ПАРАМЕТРОВ ИЗ СЛOТА ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    
    PUSH H
    LXI  B, O_TTY_HW_BASE_PORT
    DAD  B                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  C, M                       ; C = BASE_PORT данных чипа
    
    INX  H                          ; HL -> O_TTY_HW_DIV_LOW (+156)
    MOV  B, M                       ; B = DIV_LOW
    
    INX  H                          ; HL -> O_TTY_HW_DIV_HIGH (+157)
    MOV  A, M                       ; A = DIV_HIGH
    MOV  E, A                       ; E = DIV_HIGH
    POP  H                          ; HL = База TTY-слота

    ; --- ЭТАП 1: ВЫЧИСЛЕНИЕ АДРЕСОВ ПОРТОВ И SMC-ПАТЧИНГ ---
    ; 1.1: Командный порт ВВ51А (BASE_PORT + 1)
    MOV  A, C \ INR  A
    STA  _smc_prb_51_cmd + 1
	STA  _smc_prb_51_rst1 + 1
	STA  _smc_prb_51_rst2 + 1
    STA  _smc_prb_51_rst3 + 1
	STA  _smc_prb_51_int_rst + 1
	STA  _smc_prb_51_mode + 1
    STA  _smc_prb_51_start + 1

    ; 1.2: Управляющий порт КР580ВИ53 (BASE_PORT + 5)
    MOV  A, C
	ADI  5
    STA  _smc_prb_pit_cmd0 + 1
	STA  _smc_prb_pit_cmd1 + 1
    STA  _smc_prb_pit_test_cmd + 1
	STA  _smc_prb_pit_latch_cmd + 1

    ; 1.3: Порт Канала 0 ВИ53 (BASE_PORT + 2)
    MOV  A, C \ ADI  2
    STA  _smc_prb_pit_ch0_l + 1
	STA  _smc_prb_pit_ch0_h + 1
    STA  _smc_prb_pit_test_w_l + 1
	STA  _smc_prb_pit_test_w_h + 1
    STA  _smc_prb_pit_test_r_l + 1
	STA  _smc_prb_pit_test_r_h + 1

    ; 1.4: Порт Канала 1 ВИ53 (BASE_PORT + 3)
    MOV  A, C
	ADI  3
    STA  _smc_prb_pit_ch1_l + 1
	STA  _smc_prb_pit_ch1_h + 1

    ; === ЭТАП 1.1: АППАРАТНЫЙ АВТОДЕТЕКТ КР580ВВ51А ===
_smc_prb_51_cmd:
    IN   000H                       ; Читаем статус ВВ51
    CPI  0FFH
    JZ   _i8251_probe_fail_exit     ; Линия пуста — ВВ51 нет!

    ; === ЭТАП 1.2: АППАРАТНЫЙ АВТОДЕТЕКТ КР580ВИ53 (NEW!) ===
    ; Программируем Канал 0: Старший/Младший байт, Режим 0, Двоичный счет (0x30)
    MVI  A, 030H
_smc_prb_pit_test_cmd:
    OUT  000H                       ; Отправили приказ в управляющий порт ВИ53
    
    ; Записываем тестовое число 0xAA55 в Канал 0
    MVI  A, 055H                    ; Младший байт
_smc_prb_pit_test_w_l:
    OUT  000H
    MVI  A, 0AAH                    ; Старший байт
_smc_prb_pit_test_w_h:
    OUT  000H

    ; Команда Latch Counter для Канала 0 (0x00)
    XRA  A
_smc_prb_pit_latch_cmd:
    OUT  000H                       ; Фиксируем рантайм-значение триггера счетчика

    ; Считываем обратно и верифицируем младший байт
_smc_prb_pit_test_r_l:
    IN   000H
    CPI  055H                       
    JNZ  _i8251_probe_fail_exit     ; Не совпало — ВИ53 отсутствует или неисправен!

    ; Считываем обратно и верифицируем старший байт
_smc_prb_pit_test_r_h:
    IN   000H
    CPI  0AAH
    JNZ  _i8251_probe_fail_exit     ; Не совпало — ВИ53 отсутствует!

    ; === ОБА ЧИПА НАЙДЕНЫ И ОПРАШЕНЫ УСПЕШНО — ЗАПУСКАЕМ РАБОЧИЙ РЕЖИМ ===
    ; Инициализация ВВ51А
    XRA  A
_smc_prb_51_rst1:
    OUT  000H
_smc_prb_51_rst2:
	OUT 000H
_smc_prb_51_rst3:
	OUT 000H
    MVI  A, I8251_CMD_RESET
_smc_prb_51_int_rst:
	OUT 000H
	NOP
    MVI  A, I8251_MODE_8N1_X16
_smc_prb_51_mode:
	OUT 000H
	NOP
    MVI  A, I8251_CMD_START
_smc_prb_51_start:
	OUT 000H

    ; Рабочая перепрошивка ВИ53 на заданную в структуре скорость (Режим 3)
    MVI  A, PIT_CW_CH0_M3
_smc_prb_pit_cmd0:
	OUT 000H
    MOV  A, B
_smc_prb_pit_ch0_l:
	OUT 000H
    MOV  A, E
_smc_prb_pit_ch0_h:
	OUT 000H

    MVI  A, PIT_CW_CH1_M3
_smc_prb_pit_cmd1:
	OUT 000H
    MOV  A, B
_smc_prb_pit_ch1_l:
	OUT 000H
    MOV  A, E
_smc_prb_pit_ch1_h:
	OUT 000H

    ; === ЭТАП 2: ПРОШИВКА HAL-ВЕКТОРОВ В СЛОТ DE ===
    MOV  H, D
	MOV  L, E
    PUSH H
    LXI  D, O_TTY_HW_PUT_CHAR
	DAD  D
	LXI D, hw_i8251_put_char
	MOV M, E
	INX H
	MOV M, D
    POP  H
	PUSH H
    LXI  D, O_TTY_HW_GET_CHAR
	DAD  D
	LXI D, hw_i8251_get_char
	MOV M, E
	INX H
	MOV M, D
    POP  H
	PUSH H
    LXI  D, O_TTY_HW_POLL_STAT
	DAD  D
	LXI D, hw_i8251_poll_status
	MOV M, E
	INX H
	MOV M, D
    POP  H
	PUSH H
    LXI  D, O_TTY_HW_CHIP_TYPE
	DAD  D
	MVI M, CHIP_TYPE_I8251
    POP  H

    POP  H
	POP  D
	POP  B        ; Восстановили оригинальный контекст
    ANA  A                          ; CY = 0 (Полный успех детекта)
    RET

_i8251_probe_fail_exit:
    POP  H
	POP  D
	POP  B        ; Восстановили РОН супервизора
    STC                             ; CY = 1 (Авария: ВВ51 или ВИ53 не прошел тест!)
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_i8251_poll_status (ИСПРАВЛЕННАЯ ДИНАМИЧЕСКАЯ ВЕРСИЯ)
; Вход:  DE = Физический адрес 160-байтового TTY-слота (TTY0..TTY3)
; Задача: Считать аппаратный статус чипа ОДИН РАЗ по SMC-порту и вернуть маску HAL
; Выход: А  = Байт системного статуса HAL (биты TTY_HAL_TXRDY, TTY_HAL_RXRDY)
;        Регистры BC, DE, HL полностью сохранены согласно контракту HAL.
; =============================================================================
hw_i8251_poll_status:
    PUSH B
    PUSH H                          ; Сохранили РОН супервизора

    ; --- Извлекаем базовый порт из переданной структуры DE ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    LXI  B, O_TTY_HW_BASE_PORT
    DAD  B                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = BASE_PORT данных чипа
    INR  A                          ; A = BASE_PORT + 1 (Порт команд/статуса ВВ51А)
    
    ; --- SMC-ПАТЧИНГ: Прошиваем вычисленный порт строго в операнд (+1) ---
    STA  _smc_stat_51_patch + 1

_smc_stat_51_execute:
    ; === СЧИТЫВАЕМ АППАРАТНЫЙ СТАТУС С КРЕМНИЯ РОВНО ОДИН РАЗ ===
    DB   0DBH                       ; Opcode IN
_smc_stat_51_patch:
    DB   000H                       ; Сюда SMC динамически подставит порт команд (BASE+1)
    MOV  B, A                       ; B = Зафиксированный сырой статус чипа ВВ51А

    ; --- АНАЛИЗ БИТА TXRDY (Бит 0 чипа -> Бит 0 HAL) ---
    ANI  I8251_STAT_TXRDY           ; Изолируем бит готовности передатчика
    JZ   _poll_51_check_rx          ; Передатчик занят — на проверку приема
    MVI  C, TTY_HAL_TXRDY           ; C = 01H (Взвели бит TXRDY в маске HAL)
    JMP  _poll_51_analyze_rx
    
_poll_51_check_rx:
    MVI  C, 00H                     ; Передатчик занят, стартовый сброс накопленной маски

_poll_51_analyze_rx:
    ; --- АНАЛИЗ БИТА RXRDY (Бит 1 чипа -> Бит 1 HAL) из ТОГО ЖЕ байта B ---
    MOV  A, B                       ; Восстановили сырой статус из кэша
    ANI  I8251_STAT_RXRDY           ; Изолируем бит готовности приемника
    JZ   _poll_51_exit              ; Данных в FIFO чипа нет — выходим
    
    MOV  A, C                       ; Извлекли накопленную маску HAL
    ORI  TTY_HAL_RXRDY              ; Атомарно взвели Бит 1 (A = A OR 02H)
    MOV  C, A

_poll_51_exit:
    MOV  A, C                       ; Итоговый системный HAL-статус передан в А
    POP  H
    POP  B                          ; Полное восстановление РОН
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_i8251_put_char (ИСПРАВЛЕННАЯ ДИНАМИЧЕСКАЯ ВЕРСИЯ)
; Вход:  A  = ASCII-символ для физической отправки
;        DE = Физический адрес 160-байтового TTY-слота (TTY0..TTY3)
; Задача: Прочитать порт из слота, SMC-патчинг операнда (+1) и отправка байта
; Выход: Все РОН полностью сохранены (включая DE) согласно контракту HAL.
; =============================================================================
hw_i8251_put_char:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст вызова Ring 0
    
    MOV  B, A                       ; B = Временно спрятали выводимый символ

    ; --- Извлекаем базовый порт из структуры TTY-слота ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = реальный физический порт данных чипа (BASE_PORT+0)
    
    ; --- SMC-ПАТЧИНГ: Прошиваем порт строго в операнд (+1) ---
    STA  _smc_put_51_patch + 1

    MOV  A, B                       ; Восстановили символ в аккумулятор
_smc_put_51_execute:
    DB   0D3H                       ; Opcode OUT
_smc_put_51_patch:
    DB   000H                       ; Сюда SMC подставит порт данных (BASE+0)

    POP  H
    POP  D
    POP  B                          ; Восстановили РОН
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_i8251_get_char (ВАРИАНТ B: с сохранением DE)
; Вход:  DE = Физический адрес 160-байтового TTY-слота
; Задача: Прочитать адрес порта из слота, SMC-патчинг и приём байта
; Выход: А  = Принятый ASCII-символ
;        Все остальные РОН полностью сохранены (включая DE — ИСПРАВЛЕНО!)
; =============================================================================
hw_i8251_get_char:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст вызова Ring 0

    ; --- Извлекаем базовый порт из структуры TTY ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = реальный физический порт данных чипа
    
    ; --- SMC-ПАТЧИНГ: прошиваем порт строго в операнд (+1) ---
    STA  _smc_get_51_patch + 1

    ; === Динамическая инструкция IN ===
    DB   0DBH                       ; Opcode IN
_smc_get_51_patch:
    DB   000H                       ; Патчится SMC-кодом выше

    ; === A теперь содержит принятый ASCII-символ ===
    ; Сохраняем символ во временную ячейку памяти ядра
    STA  _temp_get_char             ; ← КРИТИЧЕСКИЙ ФИКС: сохраняем в память

    ; === Каноническое восстановление РОН по LIFO ===
    POP  H                          ; HL = Восстановили оригинальный HL_old
    POP  D                          ; DE = Восстановили оригинальный DE_old
    POP  B                          ; BC = Восстановили оригинальный BC_old

    ; === Возврат символа в аккумулятор ===
    LDA  _temp_get_char             ; ← КРИТИЧЕСКИЙ ФИКС: восстанавливаем символ в A
    RET

; =============================================================================
; ПРОЦЕДУРА: hw_i8251_tx_ctrl (ИСПРАВЛЕННАЯ ДИНАМИЧЕСКАЯ ВЕРСИЯ)
; Вход:  A  = Режим управления (00H = Отключить TxEN, 01H = Включить TxEN)
;        DE = Физический адрес 160-байтового TTY-слота (TTY0..TTY3)
; Задача: Рассчитать порт команд (BASE+1), SMC-патчинг операнда (+1) и выдача слова.
; Выход: Все РОН (включая А и F!) полностью сохранены согласно контракту HAL.
; =============================================================================
hw_i8251_tx_ctrl:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили контекст РОН
    
    MOV  C, A                       ; C = Входной параметр режима (00H или 01H)
    PUSH PSW                        ; Сохранили исходный аккумулятор А и флаги F

    ; --- Извлекаем адрес базового порта из структуры TTY ---
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота
    LXI  D, O_TTY_HW_BASE_PORT
    DAD  D                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = реальный порт данных (BASE_PORT+0)
    INR  A                          ; A = порт команд (BASE_PORT + 1)
    
    ; --- SMC-ПАТЧИНГ: Прошиваем порт строго в операнд (+1) ---
    STA  _smc_ctrl_51_patch + 1

    ; --- Формируем управляющее слово для БИС ---
    MOV  A, C                       ; Восстановили параметр режима
    ORA  A
    JZ   _tx_ctrl_51_disable        ; Если 00H — глушим передатчик

    ; Режим 01H: Включаем передатчик (TxEN=1, RxEN=1, RTS/DTR активны)
    MVI  A, I8251_CMD_START         ; 027H
    JMP  _smc_ctrl_51_execute

_tx_ctrl_51_disable:
    ; Режим 00H: Выключаем передатчик (TxEN=0, RxEN=1, RTS/DTR active)
    MVI  A, 026H                    ; 00100110b

_smc_ctrl_51_execute:
    DB   0D3H                       ; Opcode OUT
_smc_ctrl_51_patch:
    DB   000H                       ; Сюда SMC подставит порт команд (BASE+1)

    POP  PSW                        ; Восстановили оригинальный А и флаги F
    POP  H
    POP  D
    POP  B                          ; Полное восстановление РОН
    RET

; =============================================================================
; НАЗВАНИЕ: hw_i8251_isr (АБСОЛЮТНО ДИНАМИЧЕСКАЯ МНОГОПОРТОВАЯ ВЕРСИЯ)
; ТОКЕН:    TOKEN::MEGA-580_OS_v1.5.65_HW_I8251_ISR_DYNAMIC_STABLE_20260708
; Вход:  DE = Истинный физический адрес активного TTY-слота (Передан из hw_uart_entry).
;        Прерывания заперты (DI). Стек в Ring 0.
; =============================================================================
hw_i8251_isr:
    PUSH B
    PUSH D
    PUSH H                          ; Спасли контекст Ring 0 планировщика

    ; === ЭТАП 0: ДИНАМИЧЕСКИЙ SMC-РАСЧЕТ ПОРТОВ ТЕКУЩЕЙ КОНСОЛИ ===
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота, переданная в DE
    LXI  B, O_TTY_HW_BASE_PORT
    DAD  B                          ; HL -> O_TTY_HW_BASE_PORT (+155)
    MOV  A, M                       ; A = BASE_PORT данных чипа (0xA0, 0xB0...)
    MOV  C, A                       ; C = BASE_PORT данные (например, 0xA0)
    INR  A                          ; A = BASE_PORT + 1 (Порт команд/статуса, например, 0xA1)
    
    ; Прошиваем порты чипа строго в операнды (+1) текущих инструкций ISR
    STA  _isr_51_cmd_in + 1
    STA  _isr_51_cmd_out + 1
    MOV  A, C                       ; A = BASE_PORT данные
    STA  _isr_51_data_in + 1
    STA  _isr_51_data_out + 1      ; Динамическая SMC-настройка ISR завершена!

    ; === ЭТАП 1: ЧТЕНИЕ АППАРАТНОГО СТАТУСА (РОВНО ОДИН РАЗ) ===
_isr_51_cmd_in:
    IN   000H                       ; Считали статус. Патчится на (BASE+1)
    MOV  B, A                       ; B = кэш сырого статуса чипа

    ; === ЭТАП 2: Rx-ВЕТКА (ПРИЕМ ASCII-СИМВОЛА) ===
    MOV  A, B
    ANI  I8251_STAT_RXRDY
    JZ   _isr_51_rx_done

_isr_51_data_in:
    IN   000H                       ; Вычитываем принятый байт. Патчится на (BASE+0)
    MOV  C, A                       ; C = Принятый символ

    PUSH D                          ; Сохраняем динамическую базу TTY-слота
    PUSH B                          ; Сохраняем статус (B) и символ (C)

    ; Проверка переполнения кольца ОЗУ
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_RX_COUNT          
    DAD  D
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JZ   _isr_51_rx_drop            ; Полон — сброс байта

    ; Читаем и инкрементируем HEAD
    DCX  H
    DCX  H                          ; HL -> O_TTY_RX_HEAD (+0)
    MOV  A, M                       ; A = RX_HEAD_old
    PUSH PSW                        ; Сохраняем HEAD_old на стек

    INR  M                          ; RX_HEAD++
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JC   _isr_51_rx_no_wrap
    MVI  M, 00H                     ; Зациклили HEAD = 0

_isr_51_rx_no_wrap:
    POP  PSW                        ; A = RX_HEAD_old
    
    ; Двухступенчатый DAD-расчет адреса записи в буфер ОЗУ
    MOV  H, D
    MOV  L, E                       ; HL = База TTY-слота из РОН DE
    PUSH D                          ; Временно спрятали DE
    
    LXI  D, O_TTY_RX_BUFFER
    DAD  D                          ; HL = База + O_TTY_RX_BUFFER
    
    MOV  E, A
    MVI  D, 00H                     ; DE = HEAD_old
    DAD  D                          ; HL = (База + O_TTY_RX_BUFFER) + HEAD_old
    
    POP  D                          ; Восстановили DE = База TTY-слота
    MOV  M, C                       ; Запись символа из C в ОЗУ. Байт зафиксирован!

    ; Инкремент RX_COUNT
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_RX_COUNT
    DAD  D
    INR  M                          ; RX_COUNT++

_isr_51_rx_drop:
    POP  B                          ; Восстановили статус и символ
    POP  D                          ; Восстановили базу TTY-слота

_isr_51_rx_done:
    ; === ЭТАП 3: Tx-ВЕТКА (ОТПРАВКА ASCII-СИМВОЛА) ===
    MOV  A, B                       ; Восстановили статус из кэша
    ANI  I8251_STAT_TXRDY
    JZ   _isr_51_tx_done

    ; Проверка наличия символов в ОЗУ-очереди вывода
    PUSH D                          ; Сохраняем базу
    PUSH B                          ; Сохраняем статус
    
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_TX_COUNT
    DAD  D
    MOV  A, M
    ORA  A
    JZ   _isr_51_tx_close           ; Очередь пуста — глушим линию прерывания чипа

    ; Очередь не пуста — читаем и инкрементируем TAIL
    DCX  H                          ; HL -> O_TTY_TX_TAIL (+68)
    MOV  A, M                       ; A = TAIL_old
    PUSH PSW                        ; Сохраняем TAIL_old
    
    INR  M                          ; TAIL++
    MOV  A, M
    CPI  TTY_BUF_SIZE
    JC   _isr_51_tx_no_wrap
    MVI  M, 00H                     ; Зациклили TAIL = 0

_isr_51_tx_no_wrap:
    POP  PSW                        ; A = TAIL_old
    
    ; Двухступенчатый DAD-расчет адреса чтения из буфера ОЗУ
    MOV  H, D
    MOV  L, E                       ; HL = Истинная база TTY-слота
    PUSH D
    
    LXI  D, O_TTY_TX_BUFFER
    DAD  D                          ; HL = База + O_TTY_TX_BUFFER
    
    MOV  E, A
    MVI  D, 00H                     ; DE = TAIL_old
    DAD  D                          ; HL = (База + O_TTY_TX_BUFFER) + TAIL_old
    
    POP  D                          ; Восстановили DE = База TTY-слота
    MOV  A, M                       ; A = Извлеченный из кольца ОЗУ символ

_isr_51_data_out:
    OUT  000H                       ; Физический выстрел в кремний! Патчится на (BASE+0)

    ; Декремент TX_COUNT
    MOV  H, D
    MOV  L, E
    LXI  D, O_TTY_TX_COUNT
    DAD  D
    DCR  M                          ; TX_COUNT--
    
    POP  B                          ; Восстановили статус
    POP  D                          ; Восстановили базу TTY-слота
    JMP  _isr_51_tx_done

_isr_51_tx_close:
    POP  B                          ; Восстановили статус
    POP  D                          ; Восстановили базу TTY-слота
    
    MVI  A, 026H                    ; Команда чипа: Запретить TxEN (Линия прерывания = 0)
_isr_51_cmd_out:
    OUT  000H                       ; Выстрел в командный порт. Патчится на (BASE+1)

_isr_51_tx_done:
    ; === ЭТАП 4: ЗАКРЫТИЕ ТРИГГЕРА ВН59 И ВЫХОД ===
    MVI  A, 020H
    OUT  MASTER_8259_CMD            ; Неспецифический EOI в КР580ВН59
    
    POP  H
    POP  D
    POP  B                          ; Идеальный рантайм-бэкап РОН супервизора
    EI
    RET

