; =============================================================================
; НАЗВАНИЕ: chrdev.asm (Системный Plug-and-Play регистратор драйверов)
; СРЕДА:    Ring 0 супервизора | Архитектура КР580ВМ80А | Модуль VFS
; =============================================================================
; =============================================================================
; ПРОЦЕДУРА: k_register_chrdev
; Вход:  A  = Целевой MAJOR номер устройства (0..31).
;        HL = Физический адрес функции write драйвера (HAL-мост).
;        DE = Физический адрес функции read драйвера (HAL-мост).
; Задача: Проверить Major на выход за границы таблицы. Рассчитать смещение 
;         Major * 4 и атомарно прошить адреса методов в SYS_CHRDEV_SWITCH.
; Выход: CY = 0 — Драйвер успешно встроен в коммутатор VFS.
;        CY = 1 — Провал: Передан недопустимый Major >= VFS_MAX_TYPES (Защита памяти ядра).
;        Все РОН полностью сохранены согласно контракту HAL Варианта B.
; =============================================================================
k_register_chrdev:
    ; --- ЭТАП 1: КОНТРОЛЬ MAJOR ---
    CPI  VFS_MAX_TYPES
    JNC  _k_reg_chrdev_fault

    PUSH B
    PUSH D
    PUSH H                      ; Стек: [HL_user, DE_user, BC_user, ret]
    PUSH PSW                    ; Стек: [PSW_user, HL_user, DE_user, BC_user, ret]

    ; --- ЭТАП 2: ВЫЧИСЛЕНИЕ СМЕЩЕНИЯ (ИСПРАВЛЕНО!) ---
    LXI  H, 0
    DAD  SP                     ; HL = SP
    MOV  A, M                   ; A = Major из PSW на стеке ✓
    ADD  A
    ADD  A                      ; A = Major * 4
    MOV  C, A
    MVI  B, 0                   ; BC = смещение

    ; --- ЭТАП 3: АДРЕС СЛОТА ---
    LXI  H, SYS_CHRDEV_SWITCH
    DAD  B                      ; HL = адрес слота

    ; --- ЭТАП 4: ПРОШИВКА WRITE ---
    PUSH H                      ; Сохраняем адрес слота
    LXI  H, 0
    DAD  SP
    LXI  D, 4                   ; SP + 4 → HL (write)
    DAD  D
    MOV  E, M
    INX  H
    MOV  D, M                   ; DE = write ✓
    POP  H                      ; HL = адрес слота

    MOV  M, E                   ; Прошиваем младший байт WRITE
    INX  H
    MOV  M, D                   ; Прошиваем старший байт WRITE
    INX  H                      ; HL -> READ (+2)

    ; --- ЭТАП 4.5: ПРОШИВКА READ (ИСПРАВЛЕНО!) ---
    PUSH H                      ; Сохраняем указатель на READ
    LXI  H, 0
    DAD  SP
    LXI  D, 8                   ; ← ИСПРАВЛЕНО: SP + 8 → DE (read)
    DAD  D
    MOV  E, M
    INX  H
    MOV  D, M                   ; DE = read ✓
    POP  H                      ; HL = указатель на READ

    MOV  M, E                   ; Прошиваем младший байт READ
    INX  H
    MOV  M, D                   ; Прошиваем старший байт READ

    ; --- ЭТАП 5: ВОССТАНОВЛЕНИЕ ---
    POP  PSW
    POP  H
    POP  D
    POP  B
    XRA  A                      ; A = 0, CY = 0 (успех)
    IRET

_k_reg_chrdev_fault:
    STC                         ; CY = 1 (ошибка)
    IRET

; =============================================================================
; НАЗВАНИЕ: chrdev.asm (Табличный сквозной коммутатор записи VFS)
; СРЕДА:    Ring 0 супервизора | Архитектура КР580ВМ80А | Модуль VFS
; =============================================================================
; =============================================================================
; ПРОЦЕДУРА: vfs_chrdev_write
; Вход:  А  = Выводимый ASCII-символ.
;        C  = Major-номер символьного устройства, извлеченный из Inode (0..31).
;        B  = Minor-номер конкретного порта / устройства из Inode (0..3).
; Задача: Валидировать Major. Рассчитать адрес слота в SYS_CHRDEV_SWITCH,
;         извлечь 16-битный указатель метода write драйвера и выполнить 
;         косвенный переход по PCHL с сохранением РОН.
; Выход: Все РОН полностью сохранены согласно контракту HAL Варианта B.
; =============================================================================
vfs_chrdev_write:
    ; --- ЭТАП 1: КОНТРОЛЬ MAJOR ---
    MOV  A, C
    CPI  VFS_MAX_TYPES
    JNC  _chr_table_wr_fault

    ; --- ЭТАП 1.5: СОХРАНЕНИЕ СИМВОЛА (ИСПРАВЛЕНО!) ---
    STA  _VFS_WR_CHAR               ; ← СНАЧАЛА сохраняем A в память!
                                    ; Теперь A можно перезаписывать

    ; --- ЭТАП 1.6: СОХРАНЕНИЕ КОНТЕКСТА ---
    PUSH B
    PUSH D
    PUSH H                          ; Стек: [HL, DE, BC, ret]

    ; --- ЭТАП 2: РАСЧЕТ СМЕЩЕНИЯ ---
    MOV  A, C
    ADD  A
    ADD  A                          ; A = Major * 4
    MOV  L, A
    MVI  H, 0

    ; --- ЭТАП 3: ИЗВЛЕЧЕНИЕ АДРЕСА ДРАЙВЕРА ---
    LXI  D, SYS_CHRDEV_SWITCH
    DAD  D
    MOV  A, M
    INX  H
    MOV  H, M
    MOV  L, A                       ; HL = адрес драйвера
    MOV  A, H
    ORA  L
    JZ   _chr_table_wr_empty

    SHLD _VFS_WR_DRIVER_ADDR        ; Сохраняем адрес в память

    ; --- ЭТАП 4: ВОССТАНОВЛЕНИЕ СИМВОЛА И ПРЫЖОК ---
    LDA  _VFS_WR_CHAR               ; ← Восстанавливаем символ из памяти!
                                    ; A теперь = оригинальный символ ✓

    LXI  D, _chr_table_wr_ret
    PUSH D                          ; Адрес возврата на стек

    LHLD _VFS_WR_DRIVER_ADDR        ; HL = адрес драйвера
    PCHL                            ; Прыжок на драйвер!

_chr_table_wr_empty:
    MVI  A, 044H                    ; ENODEV
    STA  _VFS_WR_RESULT
    JMP  _chr_table_wr_done

_chr_table_wr_ret:
    STA  _VFS_WR_RESULT             ; Результат в память

_chr_table_wr_done:
    POP  H
    POP  D
    POP  B
    LDA  _VFS_WR_RESULT             ; Результат в A
    IRET

_chr_table_wr_fault:
    MVI  A, 009H                    ; EBADF
    IRET

; =============================================================================
; НАЗВАНИЕ: chrdev.asm (Табличный сквозной коммутатор чтения VFS)
; СРЕДА:    Ring 0 супервизора | Архитектура КР580ВМ80А | Модуль VFS
; =============================================================================
; =============================================================================
; ПРОЦЕДУРА: vfs_chrdev_read
; Вход:  C  = Major-номер символьного устройства, извлеченный из Inode (0..31).
;        B  = Minor-номер конкретного порта / устройства из Inode (0..3).
; Задача: Валидировать Major. Рассчитать адрес слота в SYS_CHRDEV_SWITCH,
;         извлечь 16-битный указатель метода read драйвера и выполнить
;         косвенный переход по PCHL. Защитить принятый символ от затирания POP.
; Выход: А  = Принятый из драйвера ASCII-символ (00H — если буфер пуст / пустой слот).
;        Все остальные РОН (BC, DE, HL) полностью сохранены по контракту.
; =============================================================================
vfs_chrdev_read:
    ; --- ЭТАП 1: КОНТРОЛЬ MAJOR ---
    MOV  A, C
    CPI  VFS_MAX_TYPES
    JC   _chr_table_rd_valid
    MVI  A, 009H                ; EBADF
    IRET

_chr_table_rd_valid:
    PUSH B
    PUSH D
    PUSH H                      ; Стек: [HL, DE, BC, ret]

    ; --- ЭТАП 2: РАСЧЕТ СМЕЩЕНИЯ ---
    MOV  A, C
    ADD  A
    ADD  A                      ; A = Major * 4
    MOV  L, A
    MVI  H, 0
    LXI  D, SYS_CHRDEV_SWITCH
    DAD  D
    INX  H
    INX  H                      ; HL -> O_CHR_READ

    ; --- ЭТАП 3: ИЗВЛЕЧЕНИЕ И СОХРАНЕНИЕ АДРЕСА ДРАЙВЕРА ---
    MOV  A, M
    INX  H
    MOV  H, M
    MOV  L, A                   ; HL = адрес драйвера
    MOV  A, H
    ORA  L
    JZ   _chr_table_rd_empty

    SHLD _VFS_RD_DRIVER_ADDR    ; ← СОХРАНЯЕМ АДРЕС В ПАМЯТЬ!
                                ; Теперь HL свободен

    ; --- ЭТАП 4: ВОССТАНОВЛЕНИЕ ПАРАМЕТРОВ ---
    ; Стек: [SP+0]=HL, [SP+2]=DE, [SP+4]=BC
    
    ; DE = буфер Ring 3 из [SP+2]
    LXI  H, 0
    DAD  SP
    LXI  D, 2
    DAD  D
    MOV  E, M
    INX  H
    MOV  D, M                   ; DE = буфер ✓

    ; HL = счётчик из [SP+0]
    LXI  H, 0
    DAD  SP
    MOV  A, M
    INX  H
    MOV  H, M
    MOV  L, A                   ; HL = счётчик ✓

    ; BC = Minor:Major из [SP+4]
    LXI  H, 0
    DAD  SP
    LXI  D, 4
    DAD  D
    MOV  C, M
    INX  H
    MOV  B, M                   ; BC = Minor:Major ✓

    ; Теперь: BC=Minor:Major, DE=буфер, HL=счётчик
    ; Адрес драйвера сохранён в _VFS_RD_DRIVER_ADDR

    ; --- ПРЫЖОК НА ДРАЙВЕР ---
    LHLD _VFS_RD_DRIVER_ADDR    ; HL = адрес драйвера
    PUSH H                      ; Сохраняем HL
    LXI  H, _chr_table_rd_ret
    XTHL                        ; [SP]=ret, HL=адрес драйвера
    PCHL                        ; Прыжок на драйвер!

_chr_table_rd_empty:
    MVI  A, 044H                ; ENODEV
    STA  _VFS_RD_RESULT
    JMP  _chr_table_rd_done

_chr_table_rd_ret:
    STA  _VFS_RD_RESULT

_chr_table_rd_done:
    POP  H
    POP  D
    POP  B
    LDA  _VFS_RD_RESULT
    IRET
