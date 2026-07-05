; =============================================================================
; /kernel/pcb.asm - ДИНАМИЧЕСКИЙ ПРИОРИТЕТНЫЙ ПЛАНИРОВЩИК И КОНТЕКСТНЫЙ ДИСПЕТЧЕР
; =============================================================================
; R2AKT, 03/07/2026.
; -----------------------------------------------------------------------------
; ЦЕНТРАЛЬНАЯ ПОДПРОГРАММА: СКАНИРОВАНИЕ И НАЧИСЛЕНИЕ ДИНАМИЧЕСКИХ ПРИОРИТЕТОВ
; -----------------------------------------------------------------------------
; Вызывается из прерываний Ring 0 при DI.
; Выход: А = PID процесса, назначенного на исполнение (NEXT_PID).
; =============================================================================
scheduler:
    PUSH B
    PUSH D
    PUSH H                          ; Сохранили РОН супервизора в KERNEL_STACK

    ; --- ЭТАП 1: ШТРАФОВАНИЕ ВЫПОЛНЯВШЕГОСЯ ПРОЦЕССА ---
    LHLD CURRENT_PCB_PTR            ; HL = Адрес активного PCB из кэша ядра
    MOV  A, H
    ORA  L
    JZ   sched_find_candidate       ; Если холодный старт (указатель 0) — пропускаем

    ; Проверяем статус задачи
    PUSH H                          ; Локальный снапшот базы для Фазы 1
    LXI  D, O_STATUS
    DAD  D                          ; HL -> O_STATUS (+1)
    MOV  A, M
    CPI  ST_RUNNING
    JNZ  sched_skip_penalty         ; Если процесс сам ушел в сон (ST_WAITING) — не штрафуем
    
    MVI  M, ST_READY                ; Вернули вытесненный процесс в queue готовности

    ; Увеличиваем штрафной счетчик использованного процессорного времени
    POP  H
    PUSH H                          ; Восстановили базу текущего PCB
    LXI  D, O_CPU_TICKS
    DAD  D                          ; HL -> O_CPU_TICKS (+19)
    MOV  A, M
    CPI  0FFh                       ; Защита от переполнения байта
    JZ   skip_tick_inc              
    INR  M                          ; O_CPU_TICKS++
skip_tick_inc:

    ; === БЕЗОПАСНЫЙ ПЕРЕСЧЕТ ДИНАМИЧЕСКОГО ПРИОРИТЕТА С НАСЫЩЕНИЕМ ===
    POP  H
    PUSH H
    LXI  D, O_PRIO_STATIC
    DAD  D                          ; HL -> O_PRIO_STATIC (+16)
    MOV  A, M                       ; A = Базовый статический приоритет
    
    INX  H                          ; HL -> O_PRIO_NICE (+17)
    ADD  M                          ; A = STATIC + NICE
    JNC  _sched_add_ticks           ; Если нет переноса — переходим к тикам
    MVI  A, 0FFh                    ; Переполнение! Принудительно выставляем потолок 255
    JMP  _sched_write_prio          ; Сразу пишем максимум, тики уже не изменят лимит

_sched_add_ticks:
    INX  H                          ; HL -> O_PRIO_DYNAMIC (+18)
    INX  H                          ; HL -> O_CPU_TICKS (+19)
    ADD  M                          ; A = (STATIC + NICE) + CPU_TICKS
    JNC  _sched_save_calc           ; Если нет переноса — пишем честный результат
    MVI  A, 0FFh                    ; Переполнение! Насыщаем до 255
    JMP  _sched_write_prio

_sched_save_calc:
    DCX  H                          ; Фикс указателя: HL -> O_PRIO_DYNAMIC (+18)
    MOV  M, A                       ; Зафиксировали вычисленный приоритет
    JMP  sched_skip_penalty

_sched_write_prio:
    ; Специфический маркер для записи насыщения, если HL ушел на +19
    POP  H
    PUSH H                          ; Восстановили чистую базу PCB
    LXI  D, O_PRIO_DYNAMIC
    DAD  D                          ; HL -> O_PRIO_DYNAMIC (+18)
    MVI  M, 0FFh                    ; Записали жесткий лимит 0xFF (255)

sched_skip_penalty:
    POP  H                          ; Очистили локальный снапшот адреса базы PCB

sched_find_candidate:
    ; --- ЭТАП 2: ПОИСК READY-ЗАДАЧИ С НАИЛУЧШИМ ПРИOРИТЕТОМ ---
    MVI  A, 0FFh
    STA  SCHED_BEST_PRIO            ; Инициализируем минимум наихудшим весом (255)
    
    XRA  A                          ; A = 00h
    STA  SCHED_BEST_PID             ; Дефолтный кандидат принудительно = PID 0 (Idle task)

    LXI  H, PCB_TABLE               ; HL -> Стартовый адрес таблицы задач
    MVI  B, MAX_PROCS               ; Счетчик цикла = 32 слота

sched_scan_loop:
    PUSH H                          ; Спасли физический адрес текущего PCB на итерации
    
    ; Проверяем статус существования процесса (O_STATUS == ST_FREE)?
    LXI  D, O_STATUS
    DAD  D                          ; HL -> O_STATUS (+1)
    MOV  A, M
    CPI  ST_FREE                    
    JZ   sched_pop_next_slot        ; Если слот пуст — шагаем на следующий процесс
    
    CPI  ST_READY                   ; Процесс готов к выполнению (02h)?
    JNZ  sched_check_zombie         ; Если не READY (сон, зомби) — проверяем перед Aging

    ; Процесс готов! Извлекаем его динамический приоритет O_PRIO_DYNAMIC (+18)
    POP  H
    PUSH H                          ; Удержали адрес базы на стеке
    LXI  D, O_PRIO_DYNAMIC
    DAD  D                          ; HL -> O_PRIO_DYNAMIC (+18)
    MOV  A, M                       ; A = Текущий динамический приоритет задачи
    
    LXI  H, SCHED_BEST_PRIO
    CMP  M                          ; Сравниваем текущий приоритет с рекордом (A - M)
    JNC  sched_check_zombie_direct  ; Если приоритет хуже или равен рекорду — на Aging

    ; Нашли процесс с лучшим приоритетом!
    STA  SCHED_BEST_PRIO            ; Обновили рекорд минимума
    POP  H
    PUSH H                          ; Восстановили адрес проверяемого PCB
    MOV  A, M                       ; A = O_PID текущего процесса (+0)
    STA  SCHED_BEST_PID             ; Зафиксировали PID лучшего кандидата
    
    JMP  sched_pop_next_slot        

sched_check_zombie_direct:
    JMP  sched_aging_execute

sched_check_zombie:
    CPI  ST_ZOMBIE                  ; Проверяем считанный O_STATUS
    JZ   sched_pop_next_slot        ; Если Zombie — полностью изолируем от Aging

sched_aging_process:
sched_aging_execute:
    POP  H
    PUSH H                          ; Сбалансированный доступ к базе PCB
    LXI  D, O_CPU_TICKS
    DAD  D                          ; HL -> O_CPU_TICKS (+19)
    MOV  A, M
    ORA  A                          ; Проверка на 0
    JZ   sched_pop_next_slot        ; Штраф уже равен 0 — уменьшать некуда
    DCR  M                          ; O_CPU_TICKS-- (Приоритет растет вверх!)

sched_pop_next_slot:
    POP  H                          ; Балансировка стека ядра завершена

sched_next_slot:
    LXI  D, PCB_SIZE                ; Шаг равен каноничным 64 байтам
    DAD  D                          ; HL переместился на следующий PCB
    DCR  B
    JNZ  sched_scan_loop            ; Повторяем для всех 32 слотов таблицы процессов

    ; --- ЭТАП 3: ФИКСАЦИЯ РЕЗУЛЬТАТА И СБРОС ТИКОВ ИЗБРАННИКА ---
    LDA  SCHED_BEST_PID
    STA  NEXT_PID                   ; Назначили PID следующей исполняемой задачи

    ; Вычисляем адрес PCB выбранного процесса: База = PCB_TABLE + (NEXT_PID * 64)
    MOV  L, A
    MVI  H, 0
    DAD  H                          ; *2
    DAD  H                          ; *4
    DAD  H                          ; *8
    DAD  H                          ; *16
    DAD  H                          ; *32
    DAD  H                          ; HL = NEXT_PID * 64
    LXI  D, PCB_TABLE
    DAD  D                          ; HL = физический адрес PCB выбранного процесса
    
    ; Обнуляем счётчик тиков O_CPU_TICKS избранной задачи
    LXI  D, O_CPU_TICKS
    DAD  D                          ; HL -> O_CPU_TICKS (+19)
    MVI  M, 00H                     ; Сброс штрафных тиков для запускаемого процесса

    POP  H
    POP  D
    POP  B                          ; Восстановили РОН супервизора
    LDA  NEXT_PID                   ; Возврат результирующего PID в аккумуляторе А
    RET

; -----------------------------------------------------------------------------
; АППАРАТНЫЙ ДИСПЕТЧЕР КОНТЕКСТОВ: switch_mmu_context
; -----------------------------------------------------------------------------
; Атомарно прошивает flat-карту памяти Ring 3 и обновляет кэш CURRENT_PCB_PTR.
; Вызывается строго внутри критических секций ядра при заблокированных прерываниях (DI).
; =============================================================================
switch_mmu_context:
    ; Вход: Прерывания запрещены (DI). SP указывает на KERNEL_STACK.
    ;       SP процесса УЖЕ сохранён в O_SAVED_SP вызывающим кодом.

    ; === ЭТАП 1: АКТИВАЦИЯ ИДЕНТИФИКАТОРОВ НОВОЙ ЗАДАЧИ ===
    LDA  NEXT_PID
    STA  CURRENT_PID

    ; Вычисляем адрес нового PCB: HL = PCB_TABLE + (NEXT_PID * 64)
    MOV  L, A
    MVI  H, 0
    DAD  H                          ; *2
    DAD  H                          ; *4
    DAD  H                          ; *8
    DAD  H                          ; *16
    DAD  H                          ; *32
    DAD  H                          ; *64
    LXI  D, PCB_TABLE
    DAD  D
    SHLD CURRENT_PCB_PTR

    ; Выставляем статус ST_RUNNING (+1)
    LXI  D, O_STATUS
    DAD  D
    MVI  M, ST_RUNNING

    ; === ЭТАП 2: РЕКОНФИГУРАЦИЯ eMMU ===
    ; Переход от O_STATUS (+1) к O_PAGES_MAP (+8). Разница = 7 байт.
    LXI  D, 0007H
    DAD  D

    ; Прошиваем окна К555ИР26
    MOV  A, M
    OUT  EMMU_PAGE_REG0
    INX  H
    MOV  A, M
    OUT  EMMU_PAGE_REG1
    INX  H
    MOV  A, M
    OUT  EMMU_PAGE_REG2
    INX  H
    MOV  A, M
    OUT  EMMU_PAGE_REG3

    ; === ЭТАП 3: ВОССТАНОВЛЕНИЕ СТЭКА НОВОЙ ЗАДАЧИ ===
    LHLD CURRENT_PCB_PTR
    LXI  D, O_SAVED_SP
    DAD  D
    MOV  E, M
    INX  H
    MOV  D, M                       ; DE = SP новой задачи

    XCHG
    SPHL                            ; Переключаемся на стек новой задачи

    ; Восстанавливаем РОН
    POP  H
    POP  D
    POP  B
    POP  PSW

    RET                             ; Возврат в Ring 3

; =============================================================================
; k_pcb_subsys_init - ИНИЦИАЛИЗАЦИЯ ПОДСИСТЕМЫ ПЛАНИРОВАНИЯ И ТАБЛИЦЫ PCB
; =============================================================================
; Вход:  Cold Boot, Ring 0, прерывания запрещены.
; Задача: Полностью подготовить PCB_TABLE (32 слота × 64 байта = 2 КБ)
;         и управляющие ячейки планировщика к работе.
; Выход: CURRENT_PCB_PTR указывает на PCB PID 0 (idle-задача ядра).
; =============================================================================
k_pcb_subsys_init:
    ; === ШАГ 1: ПОЛНЫЙ СБРОС УПРАВЛЯЮЩИХ ЯЧЕЕК ПЛАНИРОВЩИКА ===
    XRA  A
    STA  CURRENT_PID             ; Активный процесс = PID 0 (idle)
    STA  NEXT_PID                ; Следующий на активацию = PID 0
    STA  SCHED_BEST_PRIO         ; Сброс рекорда приоритета
    STA  SCHED_BEST_PID          ; Сброс PID кандидата
    STA  CPU_USAGE               ; Сброс метрики загрузки CPU

    ; === ШАГ 2: РАЗМЕТКА ТАБЛИЦЫ PCB (32 СЛОТА ПО 64 БАЙТА) ===
    LXI  H, PCB_TABLE            ; HL = начало таблицы процессов
    MVI  C, 0                    ; C = текущий PID (0..31)

_init_pcb_loop:
    ; --- 2.1: Полное зануление 64-байтного слота ---
    ; Это гарантирует безопасные дефолтные значения для всех полей:
    ; O_SIG_PENDING = 0, O_SIG_BLOCKED = 0, O_SIG_TABLE_PTR = 0,
    ; O_CWD_INODE = 0, O_UMASK = 0, O_RESERVED_PAD = 0 и т.д.
    PUSH H                       ; Сохраняем базу текущего слота
    MVI  B, PCB_SIZE             ; B = 64
_clear_pcb_slot:
    MVI  M, 00H
    INX  H
    DCR  B
    JNZ  _clear_pcb_slot
    POP  H                       ; Восстанавливаем базу слота

    ; --- 2.2: Установка специфических маркеров структуры ---
    ; O_PID (+0) = текущий PID (C)
    MOV  M, C

    ; O_STATUS (+1) = ST_FREE (слот свободен)
    INX  H
    MVI  M, ST_FREE

    ; O_PPID (+6) = RES_FREE_MARKER (родитель отсутствует)
    POP  H
    PUSH H
    LXI  D, O_PPID
    DAD  D
    MVI  M, RES_FREE_MARKER

    ; O_TTY_INDEX (+24) = RES_FREE_MARKER (отвязан от TTY)
    POP  H
    PUSH H
    LXI  D, O_TTY_INDEX
    DAD  D
    MVI  M, RES_FREE_MARKER

    ; O_FILE_TABLE (+34..+49) = 16 дескрипторов по RES_FREE_MARKER
    ; В новой структуре PCB 16 FD (FD 0..15), а не 8!
    POP  H
    PUSH H
    LXI  D, O_FILE_TABLE
    DAD  D                       ; HL -> O_FILE_TABLE
    MVI  B, 16                   ; 16 файловых дескрипторов
_init_file_table_loop:
    MVI  M, RES_FREE_MARKER      ; FD свободен (0xFF)
    INX  H
    DCR  B
    JNZ  _init_file_table_loop

    ; --- 2.3: Переход к следующему слоту таблицы ---
    POP  H                       ; HL = база текущего PCB
    LXI  D, PCB_SIZE             ; PCB_SIZE = 64
    DAD  D                       ; HL = начало следующего слота

    INR  C                       ; PID++
    MOV  A, C
    CPI  MAX_PROCS               ; MAX_PROCS = 32
    JNZ  _init_pcb_loop          ; Повторяем для всех 32 слотов

    ; === ШАГ 3: АВТОРИЗОВАННАЯ КОНФИГУРАЦИЯ PID 0 (IDLE-ЗАДАЧА ЯДРА) ===
    ; PID 0 — это особая задача: она всегда ST_RUNNING, имеет ROOT-права,
    ; владеет физическими страницами 0..3 и имеет высший приоритет.
    LXI  H, PCB_TABLE            ; HL = база PID 0

    ; O_STATUS (+1) = ST_RUNNING (ядро выполняется на CPU)
    LXI  D, O_STATUS
    DAD  D
    MVI  M, ST_RUNNING

    ; O_UID (+20) = 0 (ROOT), O_GID (+21) = 0
    LXI  H, PCB_TABLE
    LXI  D, O_UID
    DAD  D
    MVI  M, 00H                  ; UID = 0 (Superuser)
    INX  H
    MVI  M, 00H                  ; GID = 0

    ; O_PAGES_MAP (+8..+11) = [0, 1, 2, 3] — физические страницы ядра
    LXI  H, PCB_TABLE
    LXI  D, O_PAGES_MAP
    DAD  D
    MVI  M, 00H                  ; Сегмент 0 = физ. страница 0
    INX  H
    MVI  M, 01H                  ; Сегмент 1 = физ. страница 1
    INX  H
    MVI  M, 02H                  ; Сегмент 2 = физ. страница 2
    INX  H
    MVI  M, 03H                  ; Сегмент 3 = физ. страница 3

    ; O_PRIO_STATIC (+16) = 0 (высший базовый приоритет)
    ; O_PRIO_NICE (+17) = 20 (нейтральный nice-фактор)
    ; O_PRIO_DYNAMIC (+18) = 20 (стартовый динамический вес)
    LXI  H, PCB_TABLE
    LXI  D, O_PRIO_STATIC
    DAD  D
    MVI  M, 00H                  ; STATIC = 0
    INX  H
    MVI  M, 20                   ; NICE = 20
    INX  H
    MVI  M, 20                   ; DYNAMIC = 20

    ; O_PPID (+6) = RES_FREE_MARKER (у ядра нет родителя)
    LXI  H, PCB_TABLE
    LXI  D, O_PPID
    DAD  D
    MVI  M, RES_FREE_MARKER

    ; O_TTY_INDEX (+24) = RES_FREE_MARKER (ядро не привязано к TTY)
    LXI  H, PCB_TABLE
    LXI  D, O_TTY_INDEX
    DAD  D
    MVI  M, RES_FREE_MARKER

    ; O_FILE_TABLE (+34..+49) = 16 × 0xFF (у ядра нет открытых файлов)
    LXI  H, PCB_TABLE
    LXI  D, O_FILE_TABLE
    DAD  D
    MVI  B, 16
_init_pid0_fd_loop:
    MVI  M, RES_FREE_MARKER
    INX  H
    DCR  B
    JNZ  _init_pid0_fd_loop

    ; === ШАГ 4: ФИКСАЦИЯ КЭШ-УКАЗАТЕЛЯ ЯДРА ===
    LXI  H, PCB_TABLE
    SHLD CURRENT_PCB_PTR         ; Кэш указывает на настроенный PID 0

    RET                          ; Возврат в k_power_on_init

; =============================================================================
k_calc_cpu_usage:
    ; Вход: Вызывается планировщиком или системным таймером (вектор 0x0038).
    ; Задача: Подсчитать количество пользовательских задач в состоянии ST_READY
    ;         и спроецировать результат в метрику CPU_USAGE (0..4).
    PUSH B
    PUSH D
    PUSH H                          ; Сохраняем контекст супервизора

    XRA  A                          ; A = 0 (Счетчик готовых задач)
    MOV  C, A                       ; C = 0 (Текущее число ST_READY процессов)
    
    LXI  H, PCB_TABLE               ; HL -> Начало таблицы процессов
    MVI  B, MAX_PROCS               ; Счетчик цикла = 32 слота

_cpu_scan_loop:
    PUSH H                          ; Сохраняем базовый адрес текущего PCB
    
    ; Проверяем O_PID. Слот IDLE-процесса (PID = 0) исключаем из расчёта нагрузки.
    MOV  A, M
    ORA  A                          ; Проверка на PID == 0
    JZ   _cpu_skip_slot             ; Пропускаем swapper
    
    ; Переходим к проверке статуса
    LXI  D, O_STATUS
    DAD  D                          ; HL -> O_STATUS (+1)
    MOV  A, M
    CPI  ST_READY                   ; Задача ожидает выполнения?
    JNZ  _cpu_skip_slot             ; Если спит, свободна или зомби — не считаем
    
    INR  C                          ; Увеличиваем счётчик готовых процессов

_cpu_skip_slot:
    POP  H                          ; Восстанавливаем базу текущего PCB
    LXI  D, PCB_SIZE                ; Шаг в 64 байта
    DAD  D                          ; Сдвиг на следующий PCB
    
    DCR  B                          ; Уменьшаем счётчик слотов
    JNZ  _cpu_scan_loop             ; Повторяем для всех 32 процессов

    ; --- ЭТАП 2: ТАБЛИЧНОЕ МАСШТАБИРОВАНИЕ В ДИАПАЗОН 0..4 ---
    MOV  A, C                       ; A = Общее число найденных READY процессов
    
    CPI  1
    JC   _load_0                    ; Если 0 процессов -> Загрузка 0%
    
    CPI  2
    JC   _load_25                   ; Если 1 процесс   -> Загрузка 25%
    
    CPI  3
    JC   _load_50                   ; Если 2 процесса  -> Загрузка 50%
    
    CPI  4
    JC   _load_75                   ; Если 3 процесса  -> Загрузка 75%
    
    ; Если процессов >= 4, то наступает 100% насыщение очереди
    MVI  A, CPU_LOAD_100
    JMP  _write_metric

_load_0:
    MVI  A, CPU_LOAD_0
    JMP  _write_metric

_load_25:
    MVI  A, CPU_LOAD_25
    JMP  _write_metric

_load_50:
    MVI  A, CPU_LOAD_50
    JMP  _write_metric

_load_75:
    MVI  A, CPU_LOAD_75

_write_metric:
    STA  CPU_USAGE                  ; Записываем результат (0..4) в память ядра

    POP  H
    POP  D
    POP  B                          ; Восстанавливаем контекст супервизора
    RET
