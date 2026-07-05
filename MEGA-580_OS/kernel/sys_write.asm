; =============================================================================
; ИСПРАВЛЕННЫЙ МОНОЛИТНЫЙ СИСТЕМНЫЙ ВЫЗОВ sys_write (ТАБЛИЧНЫЙ МЕТОД VFS)
; =============================================================================
sys_write:
    PUSH B
	PUSH D
	PUSH H        ; Законсервировали контекст задачи

    ; Валидация и жесткое маскирование входного дескриптора пользователя
    MOV  A, D
    ANI  00Fh                       ; ИСПРАВЛЕНО: Очистили старшие биты регистра D!
    STA  VFS_DISPATCH_MINOR         ; Временно сохранили чистый FD (0..15)
    
    LHLD CURRENT_PCB_PTR            ; HL = Адрес PCB активного процесса
    
    LDA  VFS_DISPATCH_MINOR
    ADI  O_FILE_TABLE               ; Смещение к таблице файлов задачи
    MOV  E, A
	MVI D, 0
    DAD  D
    
    MOV  A, M                       ; A = Индекс в глобальной SYS_FILE_TABLE (0..253)
    CPI  RES_FREE_MARKER            ; Дескриптор открыт?
    JZ   write_table_err_badf

    ; Извлекаем физический адрес 16-байтовой структуры открытого файла
    MOV  D, A                       ; Передали индекс в D для нашей подпрограммы
    CALL k_vfs_get_file_struct_address ; HL = Точный адрес файла в SYS_FILE_TABLE
    MOV  A, H
	ORA L
    JZ   write_table_err_badf       ; Страховочная проверка указателя
    
    SHLD VFS_DRV_ROW_PTR            ; Запомнили адрес структуры открытого файла

    ; Извлекаем Major-тип и Minor-номер устройства из 16-байтовой структуры ядра
    MOV  A, M                       ; A = Major Number из поля F_TYPE (+0)
    STA  VFS_DISPATCH_MAJOR
    INX  H
    MOV  A, M                       ; A = Minor Number из поля F_MINOR (+1)
    STA  VFS_DISPATCH_MINOR         ; Зафиксировали внутренний Minor дескриптор

    ; Вычисляем адрес строки в таблице переключателей: VFS_SWITCH_TABLE + (Major * 10)
    LDA  VFS_DISPATCH_MAJOR
    MOV  L, A
	MVI H, 0
    DAD  H                          ; Major * 2
    PUSH H
    DAD  H
	DAD  H                 ; Major * 8
    POP  D
	DAD  D                 ; HL = Major * 10
    LXI  D, VFS_SWITCH_TABLE
	DAD D 							; HL -> Строка нужного VFS-драйвера
    
    ; Сдвигаем указатель к адресу метода write (Смещение V_OP_WRITE = +6)
    LXI  D, V_OP_WRITE
    DAD  D                          ; HL указывает точно на адрес функции write
    
    ; Извлекаем 16-битный адрес функции из таблицы переключателей
    MOV  A, M
	INX H
	MOV H, M
	MOV L, A 						; HL = Адрес функции драйвера

    ; Реставрируем РОН-параметры для драйвера периферии перед PCHL прыжком
    POP  H                          ; Восстановили оригинальный HL (Адрес буфера Ring 3)
    XCHG                            ; DE = Адрес буфера Ring 3 пользователя
    POP  B                          ; BC = Количество байт для записи
    POP  PSW                        ; Сбалансировали стек ядра Ring 0 от пары PSW
    
    LDA  VFS_DISPATCH_MINOR         ; Аккумулятор А = Чистый Minor устройства (1..254)

    ; --- МГНОВЕННЫЙ АППАРАТНЫЙ ПРЫЖОК НА ДРАЙВЕР УСТРОЙСТВА ЧЕРЕЗ PCHL ---
    PUSH H                          ; Поместили адрес функции драйвера на стек
    PCHL                            ; Драйвер отработает и сделает RET прямо в syscall_exit!

write_table_err_badf:
    POP  H
	POP  D
	POP  B         ; Восстановили оригинальный РОН-контекст задачи
    MVI  A, 0FFh                    ; Код ошибки EBADF (0xFF)
    RET
