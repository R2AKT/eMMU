; =============================================================================
; MEGA-580_OS // FILE: rtc.asm // SUBSYSTEM RTC/NVRAM STEP_1
; =============================================================================
; =============================================================================
; K_RTC_HARDWARE_INIT
; Комплексный кремниевый тест наличия чипа, валидация линии VRT и базовая настройка
; Выход: A = 0x00 (Успех), A = 0x01 (Критический сбой / Чип отсутствует)
; =============================================================================
k_rtc_hardware_init:
    DI                             ; Изоляция внутренней шины RTC

    ; --- Проверка 1: Тест шины и наличия чипа через Регистр B ---
    ; Регистр B не имеет динамических битов (в отличие от Регистра А с битом UIP),
    ; поэтому он идеален для надежного теста записи/чтения.
    MVI  A, RTC_REG_STAT_B
    OUT  RTC_PORT_ADDR
    MVI  A, 0x5A                   ; Тестовый паттерн (PIE=1, AIE=1, UIE=1, SQWE=1, DM=1, 24h=1)
    OUT  RTC_PORT_DATA
    IN   RTC_PORT_DATA             ; Читаем обратно
    CPI  0x5A                      ; Совпало?
    JNZ  rtc_chip_missing         ; Нет — шина висит (0xFF) или замкнута (0x00), чипа нет
    
    ; Восстанавливаем штатное значение Регистра B перед дальнейшей работой
    MVI  A, RTC_VAL_STAT_B
    OUT  RTC_PORT_DATA
    JMP  rtc_check_vrt

rtc_chip_missing:
    ; Чип не прошел тест или отсутствует на шине eMMU
    MVI  A, 0xFF
    STA  k_rtc_status
    MVI  A, 0x01                   ; Возврат кода ошибки "Чип не найден"
    RET

rtc_check_vrt:
    XRA  A
    STA  k_rtc_status              ; Фиксируем: статус чипа "ОК"

    ; --- Проверка 2: Контроль линии Valid RAM and Time (Регистр D) ---
    MVI  A, RTC_REG_STAT_D
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA             ; Бит 7 (VRT) показывает состояние резервной батареи
    ANI  0x80                      ; Изолируем Бит 7
    JNZ  rtc_battery_ok           ; Если VRT = 1, внутреннее ОЗУ и часы валидны

    ; Зафиксирован полный сбой питания резервной батареи КР512ВИ1
    MVI  A, 0xFF
    STA  k_rtc_power_fault
    
    ; Переходим к начальной аварийной установке дефолтной даты
    CALL k_rtc_set_default_date
    JMP  rtc_config_done

rtc_battery_ok:
    XRA  A
    STA  k_rtc_power_fault         ; Батарея в норме, данные валидны (0x00)

rtc_config_done:
    ; --- Проверка 3: Жесткая инициализация режима данных (Регистр B) ---
    ; Гарантируем, что чип работает в двоичном (Binary) и 24-часовом формате
    MVI  A, RTC_REG_STAT_B
    OUT  RTC_PORT_ADDR
    MVI  A, RTC_VAL_STAT_B         ; Принудительно: DM=1 (Binary), 24h=1, SET=0
    OUT  RTC_PORT_DATA

    XRA  A                         ; Возврат 0x00 — Шаг 1 успешно завершен
    RET

; =============================================================================
; K_RTC_SET_DEFAULT_DATE (Внутренняя процедура аварийного сброса)
; Запись дефолтного времени: 00:00:00, 01 января 2026 года в двоичном формате
; =============================================================================
k_rtc_set_default_date:
    ; 1. Останавливаем обновление времени (SET = 1)
    MVI  A, RTC_REG_STAT_B
    OUT  RTC_PORT_ADDR
    MVI  A, 0x86                   ; SET=1, DM=1 (Binary), 24h=1
    OUT  RTC_PORT_DATA

    ; 2. Записываем дефолтную дату (разбито на строки для 100% совместимости с любым ассемблером)
    MVI  A, RTC_REG_SEC
    OUT  RTC_PORT_ADDR
    MVI  A, 0x00
    OUT  RTC_PORT_DATA

    MVI  A, RTC_REG_MIN
    OUT  RTC_PORT_ADDR
    MVI  A, 0x00
    OUT  RTC_PORT_DATA

    MVI  A, RTC_REG_HOUR
    OUT  RTC_PORT_ADDR
    MVI  A, 0x00
    OUT  RTC_PORT_DATA
    
    MVI  A, RTC_REG_DAY
    OUT  RTC_PORT_ADDR
    MVI  A, 0x01
    OUT  RTC_PORT_DATA

    MVI  A, RTC_REG_MONTH
    OUT  RTC_PORT_ADDR
    MVI  A, 0x01
    OUT  RTC_PORT_DATA

    MVI  A, RTC_REG_YEAR
    OUT  RTC_PORT_ADDR
    MVI  A, 26                     ; 26 (десятичное) = 0x1A (шестнадцатеричное) -> 2026 год
    OUT  RTC_PORT_DATA

    ; 3. Сбрасываем SET=0, запуская генератор и счетчик времени КР512ВИ1
    MVI  A, RTC_REG_STAT_B
    OUT  RTC_PORT_ADDR
    MVI  A, RTC_VAL_STAT_B         ; 0x06 (SET=0, DM=1, 24h=1)
    OUT  RTC_PORT_DATA
    RET

; =============================================================================
; K_RTC_WAIT_UPDATE_DONE (Необходимое дополнение)
; Задача: Дождаться окончания цикла обновления данных в RTC (бит UIP = 0).
;         После этого у нас есть ~244 мкс на безопасное атомарное чтение всех регистров.
; Выход: CY = 0 (Успех), CY = 1 (Таймаут/Ошибка)
; =============================================================================
k_rtc_wait_update_done:
    PUSH B
    MVI  B, 0FFH                   ; Счетчик попыток (защита от зависания шины)
wait_uip_loop:
    MVI  A, RTC_REG_STAT_A
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    ANI  80H                       ; Проверяем бит 7 (UIP - Update In Progress)
    JZ   wait_uip_done            ; Если 0, обновление завершено, окно чтения открыто
    DCR  B
    JNZ  wait_uip_loop
    POP  B
    STC                            ; CY = 1 (Ошибка таймаута)
    RET
wait_uip_done:
    POP  B
    ANA  A                         ; CY = 0 (Успех)
    RET

; =============================================================================
; K_RTC_READ_TIME_TO_GLOBALS (Необходимое дополнение)
; Задача: Атомарное чтение текущего времени из RTC в глобальные переменные ядра (rtc.mem).
; Выход: CY = 0 (Успех, буфер заполнен), CY = 1 (Ошибка обновления)
; =============================================================================
k_rtc_read_time_to_globals:
    PUSH B
    PUSH D
    PUSH H
    
    CALL k_rtc_wait_update_done
    JC   rtc_read_err

    ; Читаем регистры последовательно. Для КР580ВМ80А на 2-4 МГц это займет ~30-50 мкс,
    ; что с огромным запасом укладывается в безопасное окно 244 мкс.
    MVI  A, RTC_REG_SEC
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    STA  k_rtc_raw_sec

    MVI  A, RTC_REG_MIN
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    STA  k_rtc_raw_min

    MVI  A, RTC_REG_HOUR
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    STA  k_rtc_raw_hour

    MVI  A, RTC_REG_DAY
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    STA  k_rtc_raw_day

    MVI  A, RTC_REG_MONTH
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    STA  k_rtc_raw_month

    MVI  A, RTC_REG_YEAR
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA
    STA  k_rtc_raw_year

    POP  H
    POP  D
    POP  B
    ANA  A                         ; CY = 0 (Успех)
    RET

rtc_read_err:
    POP  H
    POP  D
    POP  B
    STC                            ; CY = 1 (Ошибка)
    RET

; -----------------------------------------------------------------------------
; K_RTC_BOOT_SYNC_UNIX_TIME
; Инициализация времени ядра по аппаратным часам КР512ВИ1 при холодном старте
; Выход: SYS_UNIX_TIME и SYS_TICK_COUNTER инициализированы. 
;        А = 0x00 (Успех), А = 0xFF (Сбой RTC, запущен аварийный дефолт)
; -----------------------------------------------------------------------------
k_rtc_boot_sync_unix_time:
    DI                             ; Полная изоляция шины на этапе бута
    PUSH B
    PUSH D
    PUSH H

    ; --- 1. Аппаратный тест чипа и проверка батареи ---
    CALL k_rtc_hardware_init
    ORA  A
    JNZ  rtc_boot_fault            ; Если А != 0, чип отсутствует -> уходим на дефолт

    ; --- 2. Побайтовое чтение календаря в глобальные ячейки ---
    CALL k_rtc_read_time_to_globals
    JC   rtc_boot_fault            ; Если CY = 1 (таймаут UIP) -> аварийный выход

    ; --- 3. Математическая Epoch-конвертация в 32 бита ---
    CALL k_rtc_convert_raw_to_unix
    
    ; === КРИТИЧЕСКИЙ ФИКС: k_rtc_convert_raw_to_unix заканчивается инструкцией EI ===
    ; Чтобы гарантировать атомарность копирования в SYS_UNIX_TIME, 
    ; мы обязаны повторно запретить прерывания перед критической секцией записи.
    DI                             

    ; --- 4. Атомарный перенос вычисленного времени в структуры планировщика ---
    LHLD k_rtc_sec_acc_b0          ; HL = Младшие 16 бит (B1:B0)
    SHLD SYS_UNIX_TIME             ; Запись в байты 0 и 1 глобального времени
    
    LHLD k_rtc_sec_acc_b2          ; HL = Старшие 16 бит (B3:B2)
    SHLD SYS_UNIX_TIME + 2         ; Запись в байты 2 и 3 глобального времени

    ; Сброс тиков системного кванта 20 мс
    XRA  A
    STA  SYS_TICK_COUNTER          ; Инициализируем тик-каунтер (0..49) нулем
    
    POP  H
    POP  D
    POP  B
    XRA  A                         ; А = 0x00 (Успешная рантайм-синхронизация)
    RET

; -----------------------------------------------------------------------------
; RTC_BOOT_FAULT (Аварийный обработчик)
; -----------------------------------------------------------------------------
rtc_boot_fault:
    ; Сюда мы попадаем, если чип физически мертв, отсутствует или выдал таймаут.
    ; Система не падает, а закладывает аварийную константу 01.01.2026 00:00:00
    MVI  A, UNIX_BASE_2026_B0 \ STA SYS_UNIX_TIME
    MVI  A, UNIX_BASE_2026_B1 \ STA SYS_UNIX_TIME + 1
    MVI  A, UNIX_BASE_2026_B2 \ STA SYS_UNIX_TIME + 2
    MVI  A, UNIX_BASE_2026_B3 \ STA SYS_UNIX_TIME + 3

    XRA  A
    STA  SYS_TICK_COUNTER          ; Обнуляем тики планировщика
    
    POP  H
    POP  D
    POP  B
    MVI  A, 0xFF                   ; А = 0xFF (Сигнал системе о сбое RTC)
    RET
