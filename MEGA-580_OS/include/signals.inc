; =============================================================================
; НАЗВАНИЕ: signals.inc (Спецификация 16-битных POSIX-сигналов ядра)
; СРЕДА:    Ring 0 супервизора | Архитектура КР580ВМ80А | eMMU РЕВ_2.0
; =============================================================================

; === БЛОК 1: МЛАДШИЙ БАЙТ МАСКИ СИГНАЛОВ — O_SIG_PENDING (+26) ===
; Отвечает за системные сигналы с номерами от 1 до 8.

SIG_HUP             EQU 1           ; Сигнал 1: Обрыв линии терминала / сессии (SIGHUP)
SIGHUP_MASK_L       EQU 001H        ; Бит 0 (00000001b)

SIG_INT             EQU 2           ; Сигнал 2: Прерывание пользователя Ctrl+C (SIGINT)
SIGINT_MASK_L       EQU 002H        ; Бит 1 (00000010b)

SIG_QUIT            EQU 3           ; Сигнал 3: Останов процесса с дампом Ctrl+\ (SIGQUIT)
SIGQUIT_MASK_L      EQU 004H        ; Бит 2 (00000100b)

SIG_ILL             EQU 4           ; Сигнал 4: Недопустимый код операции CPU (SIGILL)
SIGILL_MASK_L       EQU 008H        ; Бит 3 (00001000b)

SIG_TRAP            EQU 5           ; Сигнал 5: Трассировочная ловушка отладчика (SIGTRAP)
SIGTRAP_MASK_L      EQU 010H        ; Бит 4 (00010000b)

SIG_ABRT            EQU 6           ; Сигнал 6: Аварийное завершение через abort() (SIGABRT)
SIGABRT_MASK_L      EQU 020H        ; Бит 5 (00100000b)

SIG_BUS             EQU 7           ; Сигнал 7: Ошибка системной шины / оверран eMMU (SIGBUS)
SIGBUS_MASK_L       EQU 040H        ; Бит 6 (01000000b)

SIG_FPE             EQU 8           ; Сигнал 8: Арифметическая ошибка / деление на ноль (SIGFPE)
SIGFPE_MASK_L       EQU 080H        ; Бит 7 (10000000b)


; === БЛОК 2: СТАРШИЙ БАЙТ МАСКИ СИГНАЛОВ — O_SIG_PENDING + 1 (+27) ===
; Отвечает за системные сигналы с номерами от 9 до 16.

SIG_KILL            EQU 9           ; Сигнал 9: Безусловное неперехватываемое убийство (SIGKILL)
SIGKILL_MASK_H      EQU 001H        ; Бит 0 (00000001b)

SIG_USR1            EQU 10          ; Сигнал 10: Пользовательский сигнал №1 (SIGUSR1)
SIGUSR1_MASK_H      EQU 002H        ; Бит 1 (00000010b)

SIG_SEGV            EQU 11          ; Сигнал 11: Нарушение защиты/границ памяти (SIG_SEGV)
SIGSEGV_MASK_H      EQU 004H        ; Бит 2 (00000100b)

SIG_USR2            EQU 12          ; Сигнал 12: Пользовательский сигнал №2 (SIGUSR2)
SIGUSR2_MASK_H      EQU 008H        ; Бит 3 (00001000b)

SIG_PIPE            EQU 13          ; Сигнал 13: Запись в пайп / сокет без читателя (SIGPIPE)
SIGPIPE_MASK_H      EQU 010H        ; Бит 4 (00010000b)

SIG_ALRM            EQU 14          ; Сигнал 14: Истечение таймера будильника ВИ53 (SIGALRM)
SIGALRM_MASK_H      EQU 020H        ; Бит 5 (00100000b)

SIG_TERM            EQU 15          ; Сигнал 15: Мягкое программное завершение процесса (SIGTERM)
SIGTERM_MASK_H      EQU 040H        ; Бит 6 (01000000b)

SIG_CHLD            EQU 16          ; Сигнал 16: Сигнал родителю от умершего потомка (SIGCHLD)
SIGCHLD_MASK_H      EQU 080H        ; Бит 7 (10000000b)


; === БЛОК 3: КОМБИНИРОВАННЫЕ МАСКИ СМЕРТЕЛЬНЫХ СИГНАЛОВ ДЛЯ ISR ===
; Позволяют ядру одной быстрой командой отфильтровать критические ситуации.

; Маска смертельных сигналов младшего байта (HUP, INT, QUIT, ILL, ABRT, BUS, FPE)
SIG_FATAL_MASK_L    EQU SIGHUP_MASK_L OR SIGINT_MASK_L OR SIGQUIT_MASK_L OR SIGILL_MASK_L OR SIGABRT_MASK_L OR SIGBUS_MASK_L OR SIGFPE_MASK_L

; Маска смертельных сигналов старшего байта (KILL, SEGV, TERM)
SIG_FATAL_MASK_H    EQU SIGKILL_MASK_H OR SIGSEGV_MASK_H OR SIGTERM_MASK_H
