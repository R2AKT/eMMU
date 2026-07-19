; =============================================================================
; MEGA-580_OS // FILE: rtc.inc // SUBSYSTEM RTC/NVRAM STEP_1 (FULL)
; =============================================================================

; --- Системные физические порты защелки адреса и шины данных eMMU ---
RTC_PORT_ADDR       EQU 078H      ; Запись индекса регистра (сигнал AS)
RTC_PORT_DATA       EQU 079H      ; Чтение/Запись данных (сигнал DS)

; --- Регистровая карта КР512ВИ1 / DS12885 (Оптимизированная: без будильников) ---
RTC_REG_SEC         EQU 00H       ; Секунды
RTC_REG_MIN         EQU 02H       ; Минуты
RTC_REG_HOUR        EQU 04H       ; Часы
RTC_REG_DAY         EQU 07H       ; День месяца
RTC_REG_MONTH       EQU 08H       ; Месяц
RTC_REG_YEAR        EQU 09H       ; Год
RTC_REG_STAT_A      EQU 0AH       ; Регистр статуса A (UIP, DV)
RTC_REG_STAT_B      EQU 0BH       ; Регистр статуса B (SET, DM, 24/12)
RTC_REG_STAT_C      EQU 0CH       ; Регистр статуса C (Флаги прерываний)
RTC_REG_STAT_D      EQU 0DH       ; Регистр статуса D (Бит 7 = VRT, наличие питания)

; --- Константы конфигурации ---
RTC_VAL_STAT_A      EQU 020H      ; DV2-DV0 = 010 (Включение внутреннего делителя 32768 Гц)
RTC_VAL_STAT_B      EQU 006H      ; SET=0, DM=1 (Двоичный режим), 24h=1, DSE=0

; --- Структура буфера времени в ОЗУ (6 байт) ---
; Используется для передачи данных между Ring 3 и Ring 0
RTC_TIME_STRUCT_SIZE EQU 6
O_RTC_SEC           EQU 0
O_RTC_MIN           EQU 1
O_RTC_HOUR          EQU 2
O_RTC_DAY           EQU 3
O_RTC_MONTH         EQU 4
O_RTC_YEAR          EQU 5

; --- POSIX-коды ошибок для RTC ---
RTC_ERR_NO_CHIP     EQU ENODEV    ; Чип не отвечает или села батарейка
RTC_ERR_UPDATE      EQU EBUSY     ; Не удалось дождаться окончания обновления
