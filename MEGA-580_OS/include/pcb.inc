; =============================================================================
; /include/pcb.inc - КАНОНИЧЕСКАЯ UNIX-СТРУКТУРА PCB (ВЕРСИЯ 1.5.75_STABLE)
; ТОКЕН:    TOKEN::MEGA-580_OS_v1.5.75_PCB_INC_REBUILT_MATCHED_20260708
; =============================================================================
PCB_START           EQU 0

; --- БЛОК 1: РАНТАЙМ-СТАТУС И ИДЕНТИФИКАЦИЯ (0..7) ---
O_PID               EQU PCB_START    ; +0 [1 B] PID процесса (0=FREE, 1=init...)
O_STATUS            EQU O_PID + 1    ; +1 [1 B] Статус (READY, RUNNING, WAITING, ZOMBIE)
O_WAIT_CODE         EQU O_STATUS + 1 ; +2 [1 B] wait-channel (Причина сна)
O_SAVED_SP          EQU O_WAIT_CODE + 1 ; +3 [2 B] Сохраненный указатель стека Ring 3
O_SYSCALL_RES       EQU O_SAVED_SP + 2 ; +5 [1 B] Результат сисколла / exit code
O_PPID              EQU O_SYSCALL_RES + 1 ; +6 [1 B] PID родительского процесса
O_PAGE_DIRTY_MASK   EQU O_PPID + 1   ; +7 [1 B] Битовая маска измененных страниц eMMU

; --- БЛОК 2: АППАРАТНАЯ MMU-КАРТА И ОВЕРЛЕИ (8..15) ---
O_PAGES_MAP         EQU O_PAGE_DIRTY_MASK + 1 ; +8 [4 B] Физические страницы ОЗУ (Сегменты 0-3)
O_EXT_PAGES_MAP     EQU O_PAGES_MAP + 4 ; +12 [4 B] ОВЕРЛЕИ: Страницы динамических библиотек Ring 3

; --- БЛОК 3: ПРИОРИТЕТЫ ПЛАНИРОВАНИЯ POSIX (16..19) ---
O_PRIO_STATIC       EQU O_EXT_PAGES_MAP + 4 ; +16 [1 B] Базовый статический приоритет
O_PRIO_NICE         EQU O_PRIO_STATIC + 1 ; +17 [1 B] POSIX nice-поправка (0-40)
O_PRIO_DYNAMIC      EQU O_PRIO_NICE + 1 ; +18 [1 B] Текущий динамический приоритет
O_CPU_TICKS         EQU O_PRIO_DYNAMIC + 1 ; +19 [1 B] Штрафной счетчик времени CPU

; --- БЛОК 4: БЕЗОПАСНОСТЬ, СЕССИИ И ДЕМОНЫ (20..24) ---
O_UID               EQU O_CPU_TICKS + 1 ; +20 [1 B] User ID (0 = ROOT)
O_GID               EQU O_UID + 1    ; +21 [1 B] Group ID
O_PGID              EQU O_GID + 1    ; +22 [1 B] Process Group ID
O_SID               EQU O_PGID + 1   ; +23 [1 B] Session ID (Уникальный маркер демона)
O_TTY_INDEX         EQU O_SID + 1    ; +24 [1 B] Index управляющего TTY (0xFF = отвязан)

; --- БЛОК 5: АСИНХРОННЫЕ СИГНАЛЫ И ТАЙМЕРЫ (25..30) ---
O_SIG_PENDING       EQU O_TTY_INDEX + 1 ; +25 [2 B] 16-битная маска ожидающих сигналов
O_SIG_BLOCKED       EQU O_SIG_PENDING + 2 ; +27 [2 B] 16-битная маска заблокированных сигналов
O_SIG_TABLE_PTR     EQU O_SIG_BLOCKED + 2 ; +29 [2 B] Системный указатель на векторы sigaction

; --- БЛОК 6: ВВОД-ВЫВОД VFS С ЛИМИТОМ 16 ФАЙЛОВ НА ПРОЦЕСС (31..49) ---
O_CWD_INODE         EQU O_SIG_TABLE_PTR + 2 ; +31 [2 B] Номер Inode текущей директории файла
O_UMASK             EQU O_CWD_INODE + 2 ; +33 [1 B] Маска создания файлов (POSIX umask)
O_FILE_TABLE        EQU O_UMASK + 1  ; +34 [16 B] Локальная таблица 16 дескрипторов (FD 0..15)

; === ДОБАВЛЕНО В РАМКАХ ИНКРЕМЕНТА: СУПЕРВИЗОРСКИЙ РЕЗЕРВ (50..63) ===
O_ALARM_TICKS       EQU O_FILE_TABLE + 16 ; +50 [2 B] 16-битный счетчик мягкого POSIX-будильника

; === АВТОМАТИЧЕСКИЙ СИСТЕМНЫЙ КОНТРОЛЬ ГАБАРИТОВ ===
PCB_USED_SPACE      EQU O_ALARM_TICKS + 2 ; Всего занято по калькуляции = 52 байта
PCB_SIZE            EQU 64           ; КАНOНИЧНЫЙ ИНВАРИАНТ СОХРАНЕН БЕЗ СДВИГОВ!
O_RESERVED_PAD      EQU PCB_SIZE - PCB_USED_SPACE ; 12 байт глубокого резерва супервизора

; МАСШТАБЫ СИСТЕМЫ ДЛЯ ЧИСТОЙ RAM-МОДЕЛИ (4 МБ)
MAX_PROCS           EQU 32           ; 32 процесса (Таблица PCB_TABLE весит ровно 2 КБ)
RES_FREE_MARKER     EQU 0FFH         ; Маркер свободного ресурса

; Константы состояний процессов
ST_FREE             EQU 000h         ; Слот PCB свободен
ST_CREATED          EQU 001h         ; Процесс создается (sys_fork)
ST_READY            EQU 002h         ; Процесс готов к исполнению
ST_RUNNING          EQU 003h         ; Процесс выполняется на CPU
ST_WAITING          EQU 004h         ; Процесс заблокирован/спит асинхронно
ST_ZOMBIE           EQU 005h         ; Процесс мертв, ожидает waitpid()

; --- КОНСТАНТЫ РАСЧЕТА CPU_USAGE (0..4) ---
CPU_LOAD_0          EQU 0            ; 0%   - Процессор полностью простаивает
CPU_LOAD_25         EQU 1            ; 25%  - Низкая загрузка
CPU_LOAD_50         EQU 2            ; 50%  - Средняя загрузка
CPU_LOAD_75         EQU 3            ; 75%  - Высокая загрузка
CPU_LOAD_100        EQU 4            ; 100% - Полная загруженность
