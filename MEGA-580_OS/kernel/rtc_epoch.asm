; =============================================================================
; MEGA-580_OS // FILE: kernel/rtc_epoch.asm // SUBSYSTEM RTC/NVRAM STEP_3
; =============================================================================

; -----------------------------------------------------------------------------
; K_RTC_CONVERT_RAW_TO_UNIX
; Пересчет считанных параметров k_rtc_raw_... в 32-битный Little-Endian UNIX Time
; Вход: Данные в буфере k_rtc_raw_sec .. k_rtc_raw_year
; Выход: k_rtc_sec_acc_b0..b3 содержит итоговое 32-битное число
; -----------------------------------------------------------------------------
k_rtc_convert_raw_to_unix:
    DI                             ; Критическая секция вычислений
    PUSH B
    PUSH D
    PUSH H

    ; --- Этап 1: Инициализация аккумулятора базой 2026 года ---
    MVI  A, UNIX_BASE_2026_B0
    STA  k_rtc_sec_acc_b0
    MVI  A, UNIX_BASE_2026_B1
    STA  k_rtc_sec_acc_b1
    MVI  A, UNIX_BASE_2026_B2
    STA  k_rtc_sec_acc_b2
    MVI  A, UNIX_BASE_2026_B3
    STA  k_rtc_sec_acc_b3

    ; --- Этап 2: Добавление секунд, минут и часов ---
    
    ; 2.1 Секунды (прямое добавление)
    LDA  k_rtc_raw_sec
    MOV  E, A
    MVI  D, 0x00                   ; DE = Секунды
    CALL k_rtc_add_to_acc_32

    ; 2.2 Минуты * 60 (Безопасный 16-битный расчет: Мин * 64 - Мин * 4)
    LDA  k_rtc_raw_min
    MOV  L, A
    MVI  H, 0x00                   ; HL = Минуты
    DAD  H                         ; HL = Мин * 2
    DAD  H                         ; HL = Мин * 4
    MOV  E, L
    MOV  D, H                      ; DE = Мин * 4 (сохраняем вычитаемое)
    DAD  H                         ; HL = Мин * 8
    DAD  H                         ; HL = Мин * 16
    DAD  H                         ; HL = Мин * 32
    DAD  H                         ; HL = Мин * 64
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A   ; HL = (Мин * 64) - (Мин * 4) = Мин * 60
    XCHG                           ; DE = Минуты в секундах
    CALL k_rtc_add_to_acc_32

    ; 2.3 Часы * 3600 (16-битный итератор: Часы * 1800 * 2)
    LDA  k_rtc_raw_hour
    MOV  C, A                      ; С = Счетчик итераций часов (макс. 23)
    LXI  D, 1800                   ; Шаг сложения
    LXI  H, 0x0000                 ; Очистка сумматора
rtc_hour_loop:
    MOV  A, C
    ORA  A
    JZ   rtc_hour_done
    DAD  D                         ; HL = HL + 1800
    DCR  C
    JMP  rtc_hour_loop
rtc_hour_done:
    XCHG                           ; DE = Часы * 1800
    CALL k_rtc_add_to_acc_32       ; Добавляем первые 1800 * Часы
    CALL k_rtc_add_to_acc_32       ; Добавляем вторые 1800 * Часы (Итого Часы * 3600)

    ; --- Этап 3: Расчет полного количества дней с 01.01.2026 ---
    
    ; 3.1 Дни от прошедших лет (diff_years * 365)
    LDA  k_rtc_raw_year
    SUI  26                        ; А = разница лет (0 для 2026 года)
    MOV  C, A                      ; С = Итератор лет
    LXI  D, 365
    LXI  H, 0x0000
rtc_year_loop:
    MOV  A, C
    ORA  A
    JZ   rtc_year_done
    DAD  D                         ; HL = HL + 365
    DCR  C
    JMP  rtc_year_loop
rtc_year_done:
    SHLD k_rtc_tmp_days

    ; 3.2 Добавляем прошедшие високосные годы (Каждый 4-й год, строго завершенные)
    LDA  k_rtc_raw_year
    SUI  25                        ; Смещение для корректного целочисленного деления
    MOV  C, A
    MVI  B, 0x00                   ; Число високосных дней в B
rtc_leap_calc_loop:
    MOV  A, C
    CPI  4
    JC   rtc_leap_calc_done
    INR  B                         ; Найдено кратное 4
    MOV  A, C
    SUI  4
    MOV  C, A
    JMP  rtc_leap_calc_loop
rtc_leap_calc_done:
    MOV  E, B
    MVI  D, 0x00
    LHLD k_rtc_tmp_days
    DAD  D
    SHLD k_rtc_tmp_days

    ; 3.3 Добавляем дни из таблицы месяцев
    ; ВАЖНО: Таблица k_rtc_days_before_month состоит из 12 элементов (.dw),
    ;        где индекс 0 = Январь (0 дней), индекс 1 = Февраль (31 день) и т.д.
    ;        Поэтому смещение = (месяц - 1) * 2 байта
    LDA  k_rtc_raw_month        ; A = номер месяца (1..12)
    DCR  A                      ; A = месяц - 1 (0..11)
    MOV  L, A
    MVI  H, 0x00                ; HL = (месяц - 1)
    DAD  H                      ; HL = (месяц - 1) * 2 (индекс в массиве 16-битных слов)
    XCHG                        ; DE = (месяц - 1) * 2
    LXI  H, k_rtc_days_before_month  ; База таблицы
    DAD  D                      ; HL = адрес нужного элемента таблицы
    MOV  E, M                   ; E = младший байт накопленных дней
    INX  H
    MOV  D, M                   ; D = старший байт накопленных дней
    ; Теперь DE = точное количество дней, прошедших с начала года до текущего месяца
    
    LHLD k_rtc_tmp_days         ; HL = текущий накопитель дней
    DAD  D                      ; HL = HL + DE (прибавляем дни до месяца)
    SHLD k_rtc_tmp_days         ; Сохраняем обновлённый счётчик

    ; 3.4 Коррекция на текущий високосный год (год % 4 == 0 И месяц > 2)
    LDA  k_rtc_raw_year
    ANI  03H                    ; LEAP_YEAR_MASK
    JNZ  rtc_skip_leap
    LDA  k_rtc_raw_month
    CPI  3
    JC   rtc_skip_leap          ; Если январь (1) или февраль (2) — високосный день еще не наступил
    LHLD k_rtc_tmp_days
    INX  H                      ; +1 день (29 февраля)
    SHLD k_rtc_tmp_days
rtc_skip_leap:

    ; 3.5 Добавляем текущие дни месяца (Day - 1)
    LDA  k_rtc_raw_day
    DCR  A                      ; Текущий день еще не завершен
    MOV  E, A
    MVI  D, 0x00
    LHLD k_rtc_tmp_days
    DAD  D
    SHLD k_rtc_tmp_days

    ; --- Этап 4: Перевод накопленных дней в секунды (Days * 86400) ---
    ; 86400 = 65536 (0x00010000) + 20864 (0x00005180)
    LHLD k_rtc_tmp_days
    MOV  B, H
    MOV  C, L                   ; BC = Суммарный счетчик дней
rtc_days_loop:
    MOV  A, B
    ORA  C
    JZ   rtc_days_done          ; Если дней больше нет — расчет завершен
    
    ; 1. Безусловно добавляем 1 к старшему слову (это +65536)
    LHLD k_rtc_sec_acc_b2
    INX  H
    SHLD k_rtc_sec_acc_b2
    
    ; 2. Добавляем 20864 к младшему слову
    LHLD k_rtc_sec_acc_b0
    LXI  D, 20864
    DAD  D
    SHLD k_rtc_sec_acc_b0
    JNC  rtc_days_no_carry      ; Если нет переноса, переходим к следующей итерации
    
    ; 3. Если было переполнение младшего слова, добавляем еще 1 к старшему
    LHLD k_rtc_sec_acc_b2
    INX  H
    SHLD k_rtc_sec_acc_b2
rtc_days_no_carry:
    DCX  B                      ; Минус один день
    JMP  rtc_days_loop
rtc_days_done:

    POP  H
    POP  D
    POP  B
    EI
    RET

; -----------------------------------------------------------------------------
; K_RTC_ADD_TO_ACC_32
; Сложение 32-битного аккумулятора ядра с 16-битным значением в DE
; -----------------------------------------------------------------------------
k_rtc_add_to_acc_32:
    PUSH H
    LHLD k_rtc_sec_acc_b0       ; Загружаем младшие 16 бит (B1:B0)
    DAD  D                      ; HL = HL + DE
    SHLD k_rtc_sec_acc_b0       ; Сохраняем обратно
    JNC  rtc_add_32_done        ; Если нет переноса — выход
    
    LHLD k_rtc_sec_acc_b2       ; Загружаем старшие 16 бит (B3:B2)
    INX  H                      ; Прокатываем перенос +1
    SHLD k_rtc_sec_acc_b2
rtc_add_32_done:
    POP  H
    RET

; -----------------------------------------------------------------------------
; K_RTC_CONVERT_UNIX_TO_RAW
; Симметричное обратное преобразование 32-битного UNIX Time в компоненты RTC
; Вход: k_rtc_sec_acc_b0..b3 содержит исходное 32-битное Little-Endian число
; Выход: Данные разложены в буфер k_rtc_raw_sec .. k_rtc_raw_year в Binary Mode
; -----------------------------------------------------------------------------
k_rtc_convert_unix_to_raw:
    DI                             ; Изоляция критической секции вычислений
    PUSH B
    PUSH D
    PUSH H

    ; --- Этап 1: Вычитание базового таймстемпа 01.01.2026 (0x6955B900) ---
    LHLD k_rtc_sec_acc_b0          ; HL = B1:B0
    LXI  D, 0xB900                 ; Младшие 16 бит базы 2026 года
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_sec_acc_b0          ; Сохраняем очищенные младшие байты
    
    LHLD k_rtc_sec_acc_b2          ; HL = B3:B2
    LXI  D, 0x6955                 ; Старшие 16 бит базы 2026 года
    MOV  A, L \ SBB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_sec_acc_b2          ; Аккумулятор теперь содержит секунды от начала эпохи

    ; --- Этап 2: Выделение полных суток (Секунды / 86400) ---
    LXI  H, 0x0000
    SHLD k_rtc_tmp_days            ; Очищаем накопитель суток
    
rtc_sub_days_loop:
    ; Проверяем, остался ли баланс секунд >= 86400 (0x00015180)
    LHLD k_rtc_sec_acc_b2          ; Проверяем старшее слово B3:B2
    MOV  A, H
    ORA  A
    JNZ  rtc_sub_day_execute       ; Если B3 > 0, гарантированно >= 86400
    
    MOV  A, L
    CPI  0x01
    JNC  rtc_sub_day_check_low     ; Если B2 >= 1, нужна проверка младшего слова
    JMP  rtc_extract_hours         ; Баланс секунд < 86400, переходим к часам

rtc_sub_day_check_low:
    JNZ  rtc_sub_day_execute       ; Если B2 > 1, то баланс точно больше 86400
    LHLD k_rtc_sec_acc_b0          ; Если B2 == 1, проверяем младшее слово против 0x5180
    MOV  A, H
    CPI  0x51
    JC   rtc_extract_hours         ; H < 0x51 -> точно меньше 86400
    JNZ  rtc_sub_day_execute       ; H > 0x51 -> точно больше 86400
    ; Если H == 0x51, проверяем младший байт
    MOV  A, L
    CPI  0x80
    JC   rtc_extract_hours         ; H == 0x51 и L < 0x80 -> меньше 86400

rtc_sub_day_execute:
    ; Вычитаем 86400 (0x00015180) из 32-битного аккумулятора секунд
    LHLD k_rtc_sec_acc_b0
    LXI  D, 0x5180
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_sec_acc_b0
    
    LHLD k_rtc_sec_acc_b2
    LXI  D, 0x0001                 ; Старшее вычитаемое слово
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_sec_acc_b2          ; Вычитание завершено успешно
    
    ; Инкремент накопленных полных суток
    LHLD k_rtc_tmp_days
    INX  H
    SHLD k_rtc_tmp_days
    JMP  rtc_sub_days_loop

    ; --- Этап 3: Выделение Часов, Минут и Секунд из остатка ---
rtc_extract_hours:
    MVI  B, 0                      ; Накопитель часов
rtc_sub_hours_loop:
    LHLD k_rtc_sec_acc_b0          ; Старшее слово B3:B2 гарантированно равно 0
    LXI  D, 3600                   ; Секунд в одном часе
    
    ; БЕЗОПАСНАЯ ПРОВЕРКА: HL >= DE ?
    MOV  A, H
    CMP  D
    JC   rtc_hours_done            ; H < D -> точно меньше 3600
    JNZ  rtc_hours_sub_exec        ; H > D -> точно больше или равно
    MOV  A, L
    CMP  E
    JC   rtc_hours_done            ; H == D и L < E -> меньше 3600

rtc_hours_sub_exec:
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_sec_acc_b0
    INR  B
    JMP  rtc_sub_hours_loop

rtc_hours_done:
    MOV  A, B \ STA k_rtc_raw_hour ; Часы зафиксированы (0..23)

    MVI  B, 0                      ; Накопитель минут
rtc_sub_minutes_loop:
    LHLD k_rtc_sec_acc_b0
    LXI  D, 60                     ; Секунд в минуте
    
    ; БЕЗОПАСНАЯ ПРОВЕРКА: HL >= DE ?
    MOV  A, H
    CMP  D
    JC   rtc_minutes_done          ; H < D -> точно меньше 60
    JNZ  rtc_minutes_sub_exec      ; H > D -> точно больше или равно
    MOV  A, L
    CMP  E
    JC   rtc_minutes_done          ; H == D и L < E -> меньше 60

rtc_minutes_sub_exec:
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_sec_acc_b0
    INR  B
    JMP  rtc_sub_minutes_loop

rtc_minutes_done:
    MOV  A, B \ STA k_rtc_raw_min  ; Минуты зафиксированы (0..59)
    
    LDA  k_rtc_sec_acc_b0          ; Финальный остаток (строго < 60)
    STA  k_rtc_raw_sec             ; Секунды зафиксированы (0..59)

    ; --- Этап 4: Разворот k_rtc_tmp_days в Год, Месяц и Число месяца ---
    MVI  A, 26
    STA  k_rtc_raw_year            ; Начинаем разворот с базового 2026 года
    
rtc_year_extract_loop:
    LHLD k_rtc_tmp_days
    
    ; Проверяем, високосный ли текущий разбираемый год (год % 4 == 0)
    LDA  k_rtc_raw_year
    ANI  03H                       ; LEAP_YEAR_MASK
    LXI  D, 365                    ; По умолчанию в невисокосном году 365 дней
    JNZ  rtc_year_not_leap
    LXI  D, 366                    ; Для високосного года — 366 дней
rtc_year_not_leap:
    
    ; БЕЗОПАСНАЯ ПРОВЕРКА: HL >= DE ?
    MOV  A, H
    CMP  D
    JC   rtc_year_extraction_done  ; H < D -> дней в году больше, чем осталось
    JNZ  rtc_year_sub_exec         ; H > D -> дней в году меньше, вычитаем
    MOV  A, L
    CMP  E
    JC   rtc_year_extraction_done  ; H == D и L < E -> дней в году больше

rtc_year_sub_exec:
    MOV  A, L \ SUB E \ MOV L, A
    MOV  A, H \ SBB D \ MOV H, A
    SHLD k_rtc_tmp_days            ; Уменьшаем накопитель дней на длину года
    
    LDA  k_rtc_raw_year
    INR  A
    STA  k_rtc_raw_year            ; Переходим к следующему календарному году
    JMP  rtc_year_extract_loop

rtc_year_extraction_done:
    ; Календарный год выделен. Переходим к декомпозиции месяцев.
    MVI  B, 12                     ; Начинаем поиск с декабря (Индекс 11)
rtc_month_extract_loop:
    MOV  A, B
    DCR  A                         ; Перевод 1..12 в индекс 0..11
    ADD  A                         ; Шаг по 2 байта для .dw
    MOV  E, A
    MVI  D, 0x00
    LXI  H, k_rtc_days_before_month
    DAD  D                         ; HL указывает строго на элемент таблицы
    MOV  E, M
    INX  H
    MOV  D, M                      ; DE = Накопленные дни до начала месяца Б
    
    ; Коррекция таблицы для текущего високосного года (если год високосный и месяц > 2)
    MOV  A, B
    CPI  3
    JC   rtc_month_no_leap_adj     ; Январь и февраль изменений не требуют
    LDA  k_rtc_raw_year
    ANI  03H
    JNZ  rtc_month_no_leap_adj     ; Год невисокосный
    INX  D                         ; Сдвигаем базовую планку вперед на +1 день (29 февраля)

rtc_month_no_leap_adj:
    LHLD k_rtc_tmp_days            ; Сколько дней осталось
    
    ; БЕЗОПАСНАЯ ПРОВЕРКА: HL >= DE ?
    MOV  A, H
    CMP  D
    JC   rtc_prev_month            ; H < D -> остаток меньше планки
    JNZ  rtc_month_sub_exec        ; H > D -> остаток больше планки
    MOV  A, L
    CMP  E
    JC   rtc_prev_month            ; H == D и L < E -> остаток меньше планки
    
rtc_month_sub_exec:
    ; Мы нашли текущий месяц! Индекс сохранен в регистре B
    MOV  A, B
    STA  k_rtc_raw_month           ; Месяц зафиксирован (1..12)
    
    ; Вычисляем число месяца: Число = (Остаток дней - Планка месяца) + 1
    MOV  A, L
    SUB  E
    MOV  L, A
    MOV  A, H
    SBB  D
    MOV  H, A
    INR  L                         ; Восстанавливаем человеческий день (1..31)
    MOV  A, L
    STA  k_rtc_raw_day             ; День месяца зафиксирован
    JMP  rtc_convert_complete

rtc_prev_month:
    DCR  B                         ; Шагаем назад к предыдущему месяцу года
    JMP  rtc_month_extract_loop

rtc_convert_complete:
    POP  H
    POP  D
    POP  B
    EI
    RET
