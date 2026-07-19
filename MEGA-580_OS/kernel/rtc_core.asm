; =============================================================================
; MEGA-580_OS // FILE: rtc_core.asm // SUBSYSTEM RTC/NVRAM STEP_5.1 (FINAL)
; =============================================================================

; -----------------------------------------------------------------------------
; K_RTC_READ_BRIDGE
; Канонический VFS-мост чтения данных из устройства /dev/rtc (Major 8)
; Вход:  HL = Физический адрес структуры открытого файла (SYS_FILE_TABLE)
;        DE = Адрес буфера Ring 3 внутри Сегмента 2 (0x8000-0xBFFF)
;        C  = Количество байт для чтения
; Выход: В случае успеха:
;           Флаг переноса CY = 0
;           Регистр A = Количество успешно прочитанных байт
;        В случае ошибки:
;           Флаг переноса CY = 1
;           Регистр A = POSIX-код ошибки (EBUSY / EINVAL)
; -----------------------------------------------------------------------------

; -----------------------------------------------------------------------------
; K_RTC_READ_BRIDGE
; Канонический VFS-мост чтения данных из устройства /dev/rtc (Major 8)
; Вход:  HL = Физический адрес структуры открытого файла (SYS_FILE_TABLE)
;        DE = Адрес буфера Ring 3 внутри Сегмента 2 (0x8000-0xBFFF)
;        C  = Количество байт для чтения
; Выход: В случае успеха:
;           Флаг переноса CY = 0
;           Регистр A = Количество успешно прочитанных байт
;        В случае ошибки:
;           Флаг переноса CY = 1
;           Регистр A = POSIX-код ошибки (EBUSY / EINVAL)
; -----------------------------------------------------------------------------
rtc_read_bridge:
    DI                             ; Изоляция транзакции ядра, отсекаем ВИ53
    PUSH B
    PUSH D
    PUSH H                         ; Сохранили полный РОН-контекст супервизора

    ; === КРИТИЧЕСКИ ВАЖНО: Разрешаем Ring 0 доступ к памяти Ring 3 (Сегмент 2) ===
    MVI  A, KERNEL_OVERRIDE_ON
    OUT  EMMU_OVERRIDE             ; Порт 0x76: открываем окно в User RAM

    ; Извлекаем Minor-номер устройства из структуры файла (смещение +1 от базы HL)
    INX  H                         ; HL -> Поле F_MINOR (+1)
    MOV  A, M                      ; A = Minor-номер (0 или 1)
    
    CPI  MINOR_RTC_TIME            ; Проверяем режим структуры времени (1)?
    JZ   rtc_read_struct_mode      ; Да — уходим на копирование календаря
    
    CPI  MINOR_RTC_RAW             ; Проверяем прямой низкоуровневый доступ (0)?
    JZ   rtc_read_raw_mode
    
    ; Неизвестный минор — возвращаем ошибку нелегального аргумента
    MVI  A, EINVAL
    JMP  rtc_read_err_common

rtc_read_struct_mode:
    ; Валидация размера буфера Ring 3 против оверфлоу
    MOV  A, C
    CPI  RTC_TIME_STRUCT_SIZE      ; Сравниваем с константой 6 (из rtc.inc)
    JC   rtc_read_err_inval        ; Если передан буфер < 6 байт -> EINVAL

    ; Вызываем запечатанный низкоуровневый HAL побайтового чтения
    CALL k_rtc_read_time_to_globals
    JC   rtc_read_err_busy         ; Если чип выдал таймаут бита UIP -> EBUSY

    ; --- Потоковое копирование globals в User RAM (Окно Сегмента 2) ---
    MOV  B, D
    MOV  C, E                      ; BC = Целевой буфер Ring 3 в Сегменте 2
    
    LXI  H, k_rtc_raw_sec          ; HL = Источник (сырые байты в ОЗУ ядра)
    MVI  D, RTC_TIME_STRUCT_SIZE   ; D = Счетчик итераций копирования (6 байт)

rtc_struct_copy_loop:
    MOV  A, M                      ; A = Чистый двоичный байт из ОЗУ ядра
    STAX B                         ; Запись в память Ring 3 (требует KERNEL_OVERRIDE)
    INX  H
    INX  B                         ; Сдвиг указателей источника и приемника
    DCR  D
    JNZ  rtc_struct_copy_loop

    MVI  A, RTC_TIME_STRUCT_SIZE   ; ABI-возврат: возвращаем точную длину (6)
    JMP  rtc_read_success

rtc_read_raw_mode:
    ; Прямой побайтовый доступ к служебному регистру D чипа
    MVI  A, RTC_REG_STAT_D
    OUT  RTC_PORT_ADDR
    IN   RTC_PORT_DATA             ; A = Считывали аппаратное состояние линии VRT
    
    ; Переносим один считанный байт в начало буфера пользователя Ring 3
    STAX D
    
    MVI  A, 1                      ; Прочитан ровно 1 байт аппаратного статуса
    JMP  rtc_read_success

rtc_read_err_inval:
    MVI  A, EINVAL                 ; A = Канонический код ошибки 22 (0x16)
    JMP  rtc_read_err_common

rtc_read_err_busy:
    MVI  A, EBUSY                  ; A = Канонический код ошибки 16 (0x10)
    JMP  rtc_read_err_common

rtc_read_err_common:
    ; === ОТКЛЮЧЕНИЕ ДОСТУПА К RING 3 ПЕРЕД ВЫХОДОМ С ОШИБКОЙ ===
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE             ; Порт 0x76: закрываем окно
    
    POP  H
    POP  D
    POP  B
    STC                            ; АППАРАТНЫЙ СБОЙ: CY = 1
    RET

rtc_read_success:
    ; === ОТКЛЮЧЕНИЕ ДОСТУПА К RING 3 ПЕРЕД УСПЕШНЫМ ВЫХОДОМ ===
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE             ; Порт 0x76: закрываем окно
    
    POP  H
    POP  D
    POP  B
    ANA  A                         ; CY = 0 (Успешное завершение вызова)
    RET

; -----------------------------------------------------------------------------
; RTC_WRITE_BRIDGE
; Унифицированный VFS-мост записи данных (установки времени) в /dev/rtc (Major 8)
; Вход:  HL = Физический адрес структуры открытого файла (SYS_FILE_TABLE)
;        DE = Адрес буфера-источника Ring 3 внутри Сегмента 2 (0x8000-0xBFFF)
;        C  = Количество байт для записи
; Выход: В случае успеха:
;           Флаг переноса CY = 0
;           Регистр A = Количество успешно записанных байт (6)
;        В случае ошибки:
;           Флаг переноса CY = 1
;           Регистр A = POSIX-код ошибки (EINVAL)
; -----------------------------------------------------------------------------
rtc_write_bridge:
    DI                             ; Атомарная транзакция, блокировка таймера
    PUSH B
    PUSH D
    PUSH H                         ; Сохранили РОН-контекст супервизора

    ; === КРИТИЧЕСКИ ВАЖНО: Разрешаем Ring 0 доступ к памяти Ring 3 (Сегмент 2) ===
    MVI  A, KERNEL_OVERRIDE_ON
    OUT  EMMU_OVERRIDE             ; Порт 0x76: открываем окно в User RAM

    ; Извлекаем Minor-номер устройства из структуры файла (F_MINOR лежит на HL + 1)
    INX  H                         ; HL -> Поле F_MINOR
    MOV  A, M                      ; A = Minor
    CPI  MINOR_RTC_TIME            ; Проверяем, затребована ли установка времени (1)?
    JZ   rtc_write_struct_mode     ; Да — уходим на парсинг и прошивку
    
    ; Прямая побайтовая запись в порты часов (Minor 0) заблокирована ради безопасности
    JMP  rtc_write_err_common

rtc_write_struct_mode:
    ; Валидация входной длины: процесс обязан передать строго 6 байт структуры
    MOV  A, C
    CPI  RTC_TIME_STRUCT_SIZE      ; Сравниваем с константой 6 (из rtc.inc)
    JNZ  rtc_write_err_common      ; Если длина не равна 6 -> EINVAL

    ; --- Валидация диапазонов времени (Защита кремния КР512ВИ1) ---
    ; Пару DE (указатель на User RAM) временно переносим в HL для проверки
    MOV  H, D
    MOV  L, E                      ; HL = Адрес структуры пользователя в Окне 2

    ; 1. Проверка секунд (0..59)
    MOV  A, M \ CPI 60 \ JNC rtc_write_err_common
    MOV  B, A                      ; B = Валидные секунды
    
    ; 2. Проверка минут (0..59)
    INX  H \ MOV  A, M \ CPI 60 \ JNC rtc_write_err_common
    MOV  C, A                      ; C = Валидные минуты
    
    ; 3. Проверка часов (0..23)
    INX  H \ MOV  A, M \ CPI 24 \ JNC rtc_write_err_common
    MOV  D, A                      ; D = Валидные часы
    
    ; 4. Проверка дня месяца (1..31)
    INX  H \ MOV  A, M \ CPI 1 \ JC rtc_write_err_common
    CPI  32 \ JNC rtc_write_err_common
    MOV  E, A                      ; E = Валидный день
    
    ; 5. Проверка месяца (1..12)
    INX  H \ MOV  A, M \ CPI 1 \ JC rtc_write_err_common
    CPI  13 \ JNC rtc_write_err_common
    PUSH H                         ; Спрятали текущий указатель ОЗУ на стек ядра
    MOV  H, A                      ; H = Валидный месяц (временно используем регистр H)
    
    ; 6. Проверка года (0..99)
    POP  B                         ; Извлекли указатель ОЗУ обратно в BC
    INX  B                         ; BC теперь указывает на байт года
    LDAX B \ CPI 100 \ JNC rtc_write_err_common
    MOV  L, A                      ; L = Валидный год
    
    ; Контекст проверен и распределен по регистрам: 
    ; B=Sec, C=Min, D=Hour, E=Day, H=Month, L=Year

    ; --- ФИЗИЧЕСКАЯ ПРОШИВКА КРИСТАЛЛА КР512ВИ1 ---
    MVI  A, RTC_REG_STAT_B
    OUT  RTC_PORT_ADDR
    MVI  A, 0x86                   ; Взводим бит SET=1 (Остановка обновления времени)
    OUT  RTC_PORT_DATA

    ; Последовательно прошиваем проверенные регистры
    MVI  A, RTC_REG_SEC   \ OUT RTC_PORT_ADDR \ MOV A, B \ OUT RTC_PORT_DATA
    MVI  A, RTC_REG_MIN   \ OUT RTC_PORT_ADDR \ MOV A, C \ OUT RTC_PORT_DATA
    MVI  A, RTC_REG_HOUR  \ OUT RTC_PORT_ADDR \ MOV A, D \ OUT RTC_PORT_DATA
    MVI  A, RTC_REG_DAY   \ OUT RTC_PORT_ADDR \ MOV A, E \ OUT RTC_PORT_DATA
    MVI  A, RTC_REG_MONTH \ OUT RTC_PORT_ADDR \ MOV A, H \ OUT RTC_PORT_DATA
    MVI  A, RTC_REG_YEAR  \ OUT RTC_PORT_ADDR \ MOV A, L \ OUT RTC_PORT_DATA

    ; Восстанавливаем штатный режим работы чипа и запускаем счетчик времени
    MVI  A, RTC_REG_STAT_B
    OUT  RTC_PORT_ADDR
    MVI  A, RTC_VAL_STAT_B         ; 0x06 (SET=0, DM=1, 24h=1)
    OUT  RTC_PORT_DATA

    ; Операция записи календаря успешно завершена
    MVI  A, RTC_TIME_STRUCT_SIZE   ; Возвращаем 6 успешно записанных байт
    JMP  rtc_write_success

rtc_write_err_common:
    ; === ОТКЛЮЧЕНИЕ ДОСТУПА К RING 3 ПЕРЕД ВЫХОДОМ С ОШИБКОЙ ===
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE             ; Порт 0x76: закрываем окно
    
    POP  H
    POP  D
    POP  B
    MVI  A, EINVAL                 ; A = Канонический код ошибки 22
    STC                            ; CY = 1 (Провал сисколла)
    RET

rtc_write_success:
    ; === ОТКЛЮЧЕНИЕ ДОСТУПА К RING 3 ПЕРЕД УСПЕШНЫМ ВЫХОДОМ ===
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE             ; Порт 0x76: закрываем окно
    
    POP  H
    POP  D
    POP  B
    ANA  A                         ; CY = 0 (Полный успех)
    RET

; -----------------------------------------------------------------------------
; NVRAM_READ_BRIDGE
; Канонический VFS-мост для чтения блока данных из /dev/nvram (Major 9)
; -----------------------------------------------------------------------------
nvram_read_bridge:
    DI                             ; Изоляция транзакции ядра
    PUSH B
    PUSH D
    PUSH H                         ; Сохранили полный РОН-контекст супервيزора

    ; Извлекаем текущую позицию в файле (F_OFFSET), которая лежит по смещению +5
    MOV  A, L
    ADI  5
    MOV  L, A
    MOV  A, H
    ACI  0                         ; ИСПРАВЛЕНО: ACI 0 вместо несуществующего SCI 0
    MOV  H, A                      ; HL указывает строго на младший байт F_OFFSET в структуре файла
    
    MOV  A, M                      ; A = Текущее смещение (0..49 для NVRAM)
    
    ; Защитная маска: прибавляем базовый адрес NVRAM, если передан относительный индекс
    CPI  RTC_NVRAM_SIZE            ; Проверяем, передан относительный индекс (0..49)?
    JNC  nvram_rd_br_abs
    ADI  RTC_NVRAM_BASE            ; Трансляция: А = F_OFFSET + 0x0E

nvram_rd_br_abs:
    MOV  B, A                      ; B = Внутренний адрес чипа (сохраняем)
    
    ; Восстанавливаем DE_user из сохраненного стека ядра (смещение +4)
    PUSH H                         ; Спрятали текущий указатель структуры
    LXI  H, 4                      ; Смещение +4 (учитывая PUSH B, D, H и новый PUSH H)
    DAD  SP
    MOV  E, M \ INX H \ MOV D, M   ; DE = Восстановленный чистый DE_user
    POP  H                         ; Восстановили HL структуры

    ; === ВКЛЮЧЕНИЕ ДОСТУПА К USER RAM ===
    MVI  A, KERNEL_OVERRIDE_ON
    OUT  EMMU_OVERRIDE             ; Порт 0x76 открыт. Сегмент 2 переключен на Ring 3.

    MOV  A, B                      ; А = Восстановили адрес чипа
    XCHG                           ; Теперь HL = Буфер Ring 3, DE = Мусор структуры
    
    CALL k_nvram_read_block        ; Вызов запечатанного блочного итератора
    JC   nvram_rd_br_err           ; Если вылетели за границы чипа (CY=1) -> Ошибка

    ; Обновляем указатель F_OFFSET в структуре файла на количество прочитанных байт
    XCHG                           ; HL = Восстановили адрес структуры, DE = Буфер
    MOV  A, L
    SUI  5
    MOV  L, A
    MOV  A, H
    SBI  0
    MOV  H, A                      ; Вернули HL на поле F_OFFSET (+5) структуры файла
    
    MOV  A, M
    ADD  C                         ; C не был изменен k_nvram_read_block, содержит запрошенную длину
    MOV  M, A                      ; F_OFFSET = F_OFFSET + Прочитано байт

    ; Выход из оверрайда и успешный возврат
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE
    POP  H \ POP  D \ POP  B
    MOV  A, C                      ; Возвращаем количество прочитанных байт
    ANA  A                         ; CY = 0
    RET

nvram_rd_br_err:
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE
    POP  H \ POP  D \ POP  B
    MVI  A, EINVAL                 ; Код ошибки 22
    STC                            ; CY = 1
    RET

; -----------------------------------------------------------------------------
; NVRAM_WRITE_BRIDGE
; Канонический VFS-мост для записи блока данных из User RAM в /dev/nvram (Major 9)
; -----------------------------------------------------------------------------
nvram_write_bridge:
    DI
    PUSH B
    PUSH D
    PUSH H

    ; Извлекаем позицию в файле (F_OFFSET) для адресации NVRAM
    MOV  A, L
    ADI  5                         ; ИСПРАВЛЕНО: Смещение +5 вместо +3
    MOV  L, A
    MOV  A, H
    ACI  0                         ; ИСПРАВЛЕНО: ACI 0 вместо SCI 0
    MOV  H, A
    MOV  A, M                      ; A = F_OFFSET
    
    CPI  RTC_NVRAM_SIZE
    JNC  nvram_wr_br_abs
    ADI  RTC_NVRAM_BASE

nvram_wr_br_abs:
    MOV  B, A                      ; B = Внутренний адрес чипа
    
    ; Извлекаем буфер пользователя из стека Ring 0
    PUSH H
    LXI  H, 4
    DAD  SP
    MOV  E, M \ INX H \ MOV D, M
    POP  H

    ; === ВКЛЮЧЕНИЕ ДОСТУПА К USER RAM ===
    MVI  A, KERNEL_OVERRIDE_ON
    OUT  EMMU_OVERRIDE

    MOV  A, B                      ; А = Адрес чипа
    XCHG                           ; HL = Источник данных из Ring 3, DE = Структура файла
    
    CALL k_nvram_write_block       ; Вызов запечатанного блочного итератора записи
    JC   nvram_wr_br_err

    ; Обновляем указатель файла F_OFFSET
    XCHG
    MOV  A, L
    SUI  5
    MOV  L, A
    MOV  A, H
    SBI  0
    MOV  H, A                      ; Вернули HL на поле F_OFFSET (+5)
    
    MOV  A, M
    ADD  C                         ; C не был изменен k_nvram_write_block
    MOV  M, A                      ; F_OFFSET = F_OFFSET + Записано байт

    ; Выход из оверрайда и успешный возврат
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE
    POP  H \ POP  D \ POP  B
    MOV  A, C                      ; Возвращаем количество записанных байт
    ANA  A                         ; CY = 0
    RET

nvram_wr_br_err:
    MVI  A, KERNEL_OVERRIDE_OFF
    OUT  EMMU_OVERRIDE
    POP  H \ POP  D \ POP  B
    MVI  A, EINVAL
    STC                            ; CY = 1
    RET

;+++++++
; =============================================================================
; MEGA-580_OS // FILE: rtc_core.asm // SUBSYSTEM RTC/NVRAM STEP_5.4 (UNIFIED)
; =============================================================================

; --- СТРУКТУРА ВЕКТOРОВ ОПЕРАЦИЙ ДЛЯ ДРАЙВЕРА ЧАСОВ /dev/rtc (MAJOR 8) ---
rtc_driver_vectors:
    DW k_vfs_enotsupp             ; V_OP_OPEN  -> Возврат ENODEV заглушки
    DW k_vfs_enotsupp             ; V_OP_CLOSE
    DW rtc_read_bridge            ; V_OP_READ  -> Наш запечатанный мост чтения (v1.5.156)
    DW rtc_write_bridge           ; V_OP_WRITE -> Наш запечатанный мост записи (v1.5.157)
    DW k_vfs_enotsupp             ; V_OP_IOCTL

; --- СТРУКТУРА ВЕКТOРОВ ОПЕРАЦИЙ ДЛЯ ДРАЙВЕРА ОЗУ /dev/nvram (MAJOR 9) ---
nvram_driver_vectors:
    DW k_vfs_enotsupp             ; V_OP_OPEN
    DW k_vfs_enotsupp             ; V_OP_CLOSE
    DW nvram_read_bridge          ; V_OP_READ  -> Наш запечатанный мост чтения NVRAM (v1.5.158)
    DW nvram_write_bridge         ; V_OP_WRITE -> Наш запечатанный мост записи NVRAM (v1.5.158)
    DW k_vfs_enotsupp             ; V_OP_IOCTL

; -----------------------------------------------------------------------------
; K_RTC_REGISTER_VFS
; Каноническая процедура сквозного монтирования векторов RTC и NVRAM в ядро
; Вызывается один раз на этапе холодной инициализации рантайма VFS.
; -----------------------------------------------------------------------------
; k_rtc_register_vfs:
    ; DI                             ; Атомарный перехват, блокировка тиков ВИ53
    ; PUSH B
    ; PUSH D
    ; PUSH H                         ; Спасли РОН-контекст супервизора

    ; ; --- 1. Прошивка дескриптора часов /dev/rtc в Слот 8 таблицы ---
    ; MVI  A, VFS_TYPE_RTC           ; A = 8 (Из нашего запечатанного vfs.inc)
    ; LXI  H, rtc_driver_vectors     ; HL = Физический адрес структуры векторов RTC
    ; CALL k_vfs_register_driver     ; Вызов проверенного вручную регистратора (Функция №2)

    ; ; --- 2. Прошивка дескриптора памяти /dev/nvram в Слот 9 таблицы ---
    ; MVI  A, VFS_TYPE_NVRAM         ; A = 9
    ; LXI  H, nvram_driver_vectors    ; HL = Физический адрес структуры векторов NVRAM
    ; CALL k_vfs_register_driver     ; Вызов проверенного вручную регистратора

    ; POP  H
    ; POP  D
    ; POP  B
    ; EI                             ; Безопасное восстановление маски прерываний
    ; RET
; =============================================================================
; MEGA-580_OS // FILE: rtc_core.asm // SUBSYSTEM RTC/NVRAM STEP_5.4 (CORRECTED)
; =============================================================================

; -----------------------------------------------------------------------------
; K_RTC_REGISTER_VFS
; Каноническая процедура сквозного монтирования векторов и текстовых узлов /dev
; -----------------------------------------------------------------------------
k_rtc_register_vfs:
    DI                             ; Атомарный перехват, блокировка тиков ВИ53
    PUSH B
    PUSH D
    PUSH H                         ; Спасли РОН-контекст супервизора

    ; === ЧАСТЬ 1: ПРОШИВКА ТАБЛИЦЫ КОММУТАТОРА ВЕКТОРOВ ===
    MVI  A, VFS_TYPE_RTC           ; A = 8
    LXI  H, rtc_driver_vectors     
    CALL k_vfs_register_driver     ; Запечатали векторы часов в Слот 8

    MVI  A, VFS_TYPE_NVRAM         ; A = 9
    LXI  H, nvram_driver_vectors    
    CALL k_vfs_register_driver     ; Запечатали векторы NVRAM в Слот 9

    ; === ЧАСТЬ 2: АВТОМОНТИРОВАНИЕ ТЕКСТОВЫХ УЗЛОВ В DEV_MOUNT_TABLE ===
    LXI  H, DEV_MOUNT_TABLE
    MVI  B, MAX_MOUNT_DEVS         ; Счетчик цикла = 16 слотов (из v1.5.150)

rtc_mount_node_scan:
    MOV  A, M
    INX  H
    ORA  M                         ; Проверяем, свободен ли текущий слот (указатель == 0x0000)?
    DCX  H                         ; Вернули HL на начало слота
    JZ   rtc_mount_slot_found      ; Нашли пустой слот — уходим на прошивку!
    
    ; Слот занят — шагаем вперед на размер записи (+6 байт)
    LXI  D, 6                      ; MNT_ENTRY_SZ = 6
    DAD  D
    DCR  B
    JNZ  rtc_mount_node_scan
    JMP  rtc_mount_exit            ; Аварийный выход: в таблице нет мест

rtc_mount_slot_found:
    ; --- 1. Монтирование символьного узла /dev/rtc ---
    LXI  D, _vfs_rtc_str           ; DE = Физический адрес запечатанной строки "rtc"
    MOV  M, E \ INX H
    MOV  M, D \ INX H              ; Прошили указатель на имя (+0)
    MVI  M, VFS_TYPE_RTC \ INX H   ; Прошили MAJOR = 8 (+2)
    MVI  M, MINOR_RTC_TIME \ INX H ; Прошили MINOR = 1 (+3)
    MVI  M, 0x01 \ INX H           ; Прошили флаги статуса (0x0001 = Активен)
    MVI  M, 0x00 \ INX H

    ; Проверяем, остался ли лимит под второй узел (nvram)
    DCR  B
    JZ   rtc_mount_exit            ; Таблица переполнилась

    ; --- 2. Монтирование символьного узла /dev/nvram ---
    ; Пара HL сейчас автоматически указывает на начало следующего 6-байтового слота
    LXI  D, _vfs_nvram_str         ; DE = Физический адрес запечатанной строки "nvram"
    MOV  M, E \ INX H
    MOV  M, D \ INX H              ; Прошили указатель на имя (+0)
    MVI  M, VFS_TYPE_NVRAM \ INX H ; Прошили MAJOR = 9 (+2)
    MVI  M, MINOR_RTC_RAW \ INX H  ; ИСПРАВЛЕНО И СИНХРОНИЗИРОВАНО: Прошили MINOR = 0 (+3)
    MVI  M, 0x01 \ INX H           ; Прошили флаги статуса (0x0001 = Активен)
    MVI  M, 0x00                   ; HL остановился на последнем байте слота

rtc_mount_exit:
    POP  H
    POP  D
    POP  B
    EI                             ; Безопасное восстановление маски прерываний
    RET

; Каноничные ASCIIZ-имена для строкового компаратора k_vfs_resolve_dev
_vfs_rtc_str:        DB "/dev/rtc", 0
_vfs_nvram_str:      DB "/dev/nvram", 0
