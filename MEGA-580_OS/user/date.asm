; =============================================================================
; MEGA-580_OS // FILE: date.asm // USER-SPACE RING 3 UTILITY (STRESS TEST)
; =============================================================================

; --- Системные константы векторов сисколлов (Спецификация ABI супервизора) ---
SYS_CALL_GATE       EQU 6          ; Вектор RST 6 — единый шлюз в ядро MEGA-580_OS
SYS_OPEN            EQU 5          ; Номер сисколла sys_open
SYS_CLOSE           EQU 6          ; Номер сисколла sys_close
SYS_READ            EQU 7          ; Номер сисколла sys_read
SYS_WRITE           EQU 8          ; Номер сисколла sys_write

O_RDONLY            EQU 1          ; Флаг открытия: только чтение

user_app_start:
    ; === ШАГ 1: ОТКРЫТИЕ СИМВOЛЬНОГО УЗЛА /dev/rtc ===
    MVI  A, SYS_OPEN               ; Регистр A = Номер системной функции
    LXI  D, rtc_device_path        ; DE = Физический адрес строки пути в Ring 3
    MVI  C, O_RDONLY               ; C = Флаги доступа
    RST  SYS_CALL_GATE             ; ПРЯМОЙ ШЛЮЗ В Ring 0! 
    
    ; Обработка ошибок шлюза VFS
    JC   app_exit_with_error       ; Если CY = 1 — сисколл провален, в A код ошибки
    STA  user_rtc_fd               ; Если CY = 0 — в A чистый локальный дескриптор FD (0..15)

    ; === ШАГ 2: СИНХРOННОЕ ЧТЕНИЕ 6-БАЙТOВОЙ СТРУКТУРЫ ВРЕМЕНИ ===
    MVI  A, SYS_READ               ; Вызов функции чтения
    LDA  user_rtc_fd
    MOV  B, A                      ; B = Локальный дескриптор файла процесса
    MVI  C, 6                      ; C = Количество запрашиваемых байт (Лимит структуры)
    LXI  D, user_time_buf          ; DE = Адрес приемного буфера в памяти задачи Ring 3
    RST  SYS_CALL_GATE             ; Толкаем транзакцию через шлюз прерывания
    JC   app_close_and_fail        ; Чип часов вылетел за границы или занят (EBUSY) — авария!

    ; === ШАГ 3: ФOРМАТИРOВАНИЕ ДАННЫХ И ВЫВOД НА КОНСOЛЬ TTY0 ===
    ; Наш буфер user_time_buf теперь содержит: +0:Sec, +1:Min, +2:Hour, +3:Day, +4:Month, +5:Year
    
    ; 3.1 Выводим ЧАСЫ
    LDA  user_time_buf + 2
    CALL app_print_bcd_byte
    MVI  A, ':' \ CALL app_print_char
    
    ; 3.2 Выводим МИНУТЫ
    LDA  user_time_buf + 1
    CALL app_print_bcd_byte
    MVI  A, ':' \ CALL app_print_char
    
    ; 3.3 Выводим СЕКУНДЫ
    LDA  user_time_buf + 0
    CALL app_print_bcd_byte
    MVI  A, ' ' \ CALL app_print_char
    
    ; 3.4 Выводим ДЕНЬ МЕСЯЦА
    LDA  user_time_buf + 3
    CALL app_print_bcd_byte
    MVI  A, '.' \ CALL app_print_char
    
    ; 3.5 Выводим МЕСЯЦ
    LDA  user_time_buf + 4
    CALL app_print_bcd_byte
    MVI  A, '.' \ CALL app_print_char
    
    ; 3.6 Выводим ГОД (Префикс "20" + значение "26")
    MVI  A, '2' \ CALL app_print_char
    MVI  A, '0' \ CALL app_print_char
    LDA  user_time_buf + 5
    CALL app_print_bcd_byte
    
    ; Замыкающий перевод строки на консоли
    MVI  A, 0x0D \ CALL app_print_char
    MVI  A, 0x0A \ CALL app_print_char

    ; === ШАГ 4: КАНОНИЧЕСКОЕ ЗАКРЫТИЕ ДЕСКРИПТOРА (ДЕАЛЛOКАЦИЯ МЕМОРИ) ===
app_close_and_fail:
    MVI  A, SYS_CLOSE
    LDA  user_rtc_fd
    MOV  B, A                      ; B = Наш файловый дескриптор
    RST  SYS_CALL_GATE             ; Сисколл закрытия освобождает слоты ОЗУ ядра
    
app_exit_with_error:
    ; Завершение работы пользовательского процесса, возврат в CLI/Shell
    ; (Вызов sys_exit планировщика задач)
    MVI  A, 1                      ; Номер сисколла sys_exit
    RST  SYS_CALL_GATE

; -----------------------------------------------------------------------------
; APP_PRINT_BCD_BYTE (Вспомогательный конвертер двоичного байта в два ASCII-символа)
; Вход: A = Чистый двоичный байт времени (0..59)
; -----------------------------------------------------------------------------
app_print_bcd_byte:
    PUSH PSW                       ; Сохранили исходный байт
    
    ; Поскольку на Шаге 1 мы принудительно заставили КР512ВИ1 считать время в чистом 
    ; двоичном виде (DM=1), нам нужно рантайм-разложить число на десятки и единицы
    MVI  B, 0                      ; Счетчик десятков
app_div_ten_loop:
    CPI  10
    JC   app_div_ten_done
    SUI  10
    INR  B
    JMP  app_div_ten_loop
app_div_ten_done:
    MOV  C, A                      ; C = Остаток (Единицы)
    
    MOV  A, B
    ADI  48                        ; Превратили десятки в ASCII-код цифры '0'..'9'
    CALL app_print_char            ; Вытолкнули старшую цифру в VFS-мост tty
    
    MOV  A, C
    ADI  48                        ; Превратили единицы в ASCII-код
    CALL app_print_char            ; Вытолкнули младшую цифру в VFS-мост tty
    
    POP  PSW
    RET

; -----------------------------------------------------------------------------
; APP_PRINT_CHAR (Низкоуровневый оберточный сисколл посимвольного вывода задачи)
; Вход: A = ASCII-символ
; -----------------------------------------------------------------------------
app_print_char:
    PUSH B
    PUSH D
    PUSH H                         ; Сохранили контекст пользовательской утилиты
    
    MOV  C, A                      ; C = Символ для вывода
    MVI  A, SYS_WRITE              ; Функция записи
    MVI  B, 1                      ; FD = 1 (Стандартный вывод stdout процесса /dev/tty0)
    LXI  D, app_char_buf           ; DE = Временный микробуфер Ring 3
    MOV  A, C
    STA  app_char_buf              ; Прошили символ в буфер
    MVI  C, 1                      ; Длина записи = 1 байт
    MVI  A, SYS_WRITE              ; Идентификатор сисколла записи
    RST  SYS_CALL_GATE             ; Прыжок через шлюз прерывания супервизора!
    
    POP  H
    POP  D
    POP  B
    RET

; =============================================================================
; СЕКЦИЯ КОНСТАНТНЫХ ДАННЫХ И НЕИНИЦИАЛИЗИРОВАННОЙ ПАМЯТИ ПРОЦЕССА (Ring 3)
; =============================================================================

; Каноничный полный путь к файлу устройства времени
rtc_device_path:     DB "/dev/rtc", 0

; Локальные ОЗУ-ячейки внутри перемещаемого пространства задачи
user_rtc_fd:         DS 1          ; Хранилище локального файлового дескриптора
app_char_buf:        DS 1          ; Временный 1-байтовый буфер для stdout

; 6-байтовая структура для приема аппаратного календаря от моста rtc_read_bridge
user_time_buf:       DS 6
