; =============================================================================
; /include/vfs.inc - MEGA-580 OS - КОНСТАНТЫ И ОШИБКИ POSIX API (ВЕРСИЯ 1.5.2)
; =============================================================================

; --- ЛИМИТЫ И ГАБАРИТЫ ПОДСИСТЕМЫ VFS ---
VFS_MAX_TYPES      EQU 32           ; До 32 типов VFS драйверов!
VFS_DRV_OPS_COUNT  EQU 5            ; 5 методов: open, close, read, write, ioctl
VFS_ROW_SIZE       EQU 10           ; 5 методов * 2 байта = 10 байт на строку драйвера
MAX_SYS_FILES      EQU 128          ; 128 дескрипторов на систему
SYS_FILE_SLOT_SIZE EQU 10           ; Каноничный размер строки таблицы файлов = 10 байт
MAX_MOUNT_DEVS     EQU 16           ; Количество записей в таблице устройств /dev
MNT_ENTRY_SZ       EQU 6            ; Сжатый каноничный размер записи монтирования = 6 байт

; --- СМЕЩЕНИЯ МЕТОДОВ ВНУТРИ СТРОКИ VFS_SWITCH_TABLE (10 БАЙТ) ---
V_OP_OPEN          EQU 0            ; +0 [2 B]: Адрес функции open
V_OP_CLOSE         EQU 2            ; +2 [2 B]: Адрес функции close
V_OP_READ          EQU 4            ; +4 [2 B]: Адрес функции read
V_OP_WRITE         EQU 6            ; +6 [2 B]: Адрес функции write
V_OP_IOCTL         EQU 8            ; +8 [2 B]: Адрес функции ioctl

; --- ОФИЦИАЛЬНЫЕ MAJOR-НОМЕРА СИСТЕМНЫХ ДРАЙВЕРОВ ---
VFS_TYPE_FREE      EQU 000h         ; Слот свободен
VFS_TYPE_DISK      EQU 001h         ; Experimental FS (CompactFlash)
VFS_TYPE_PIPE      EQU 002h         ; IPC Конвейеры ОЗУ
VFS_TYPE_TTY       EQU 003h         ; Физический terminal КР580ВВ51А
VFS_TYPE_UNIX      EQU 004h         ; Программный сокет AF_UNIX
VFS_TYPE_INET      EQU 005h         ; Аппаратный Ethernet-сокет (KSZ8851)
VFS_TYPE_PTY       EQU 006h         ; Виртуальный псевдотерминал PTY
VFS_TYPE_LPT       EQU 007h         ; Аппаратный параллельный порт LPT

; --- СТРУКТУРА ГЛОБАЛЬНОЙ SYS_FILE_TABLE (СТРОГО 10 БАЙТ) ---
F_TYPE             EQU 0            ; Major Number [1 байт] (00h = Свободный слот)
F_MINOR            EQU 1            ; Minor Number [1 байт]
F_REF              EQU 2            ; Счетчик ссылок дескриптора [1 байт]
F_INODE            EQU 3            ; Номер дискового Inode [2 байта]
F_OFFSET           EQU 5            ; 32-битная позиция чтения/записи файла [4 байта]
F_DIRTY            EQU 9            ; Флаг грязного буфера отложенной записи [1 байт]
RES_FREE_MARKER    EQU 0FFh

; --- СТРУКТУРА ТАБЛИЦЫ МОНТИРОВАНИЯ DEV_MOUNT_TABLE (СТРОГО 6 БАЙТ) ---
; Устранено наложение смещений: структура выровнена линейно без дыр
MNT_START          EQU 0
O_MNT_PATH_PTR     EQU MNT_START    ; +0 [2 B] Указатель на ASCII-строку имени модуля
O_MNT_MAJOR        EQU 2            ; +2 [1 B] Номер связанного мажорного драйвера
O_MNT_MINOR        EQU 3            ; +3 [1 B] Номер минорного порта устройства
O_MNT_RESERVED     EQU 4            ; +4 [2 B] Резерв для выравнивания / Флаги доступа

; === КАНОНИЧЕСКИЕ POSIX-КОДЫ ОШИБОК ABI ЯДРА ===
EPERM              EQU 1            ; Operation not permitted
ENOENT             EQU 2            ; No such file or directory
ESRCH              EQU 3            ; No such process
EINTR              EQU 4            ; Interrupted system call
EIO                EQU 5            ; I/O error
EBADF              EQU 9            ; Bad file number
ECHILD             EQU 10           ; No child processes
EAGAIN             EQU 11           ; Try again
ENOMEM             EQU 12           ; Out of memory
EACCES             EQU 13           ; Permission denied
EFAULT             EQU 14           ; Bad address
EBUSY              EQU 16           ; Device or resource busy
EEXIST             EQU 17           ; File exists
ENODEV             EQU 19           ; No such device
EINVAL             EQU 22           ; Invalid argument
ENFILE             EQU 23           ; File table overflow
EMFILE             EQU 24           ; Too many open files
ENOTTY             EQU 25           ; Not a typewriter
ESPIPE             EQU 29           ; Invalid seek
EROFS              EQU 30           ; Read-only file system
EMLINK             EQU 31           ; Too many links
EPIPE              EQU 32           ; Broken pipe
EDOM               EQU 33           ; Math argument out of domain
ERANGE             EQU 34           ; Math result not representable
EDEADLK            EQU 35           ; Resource deadlock avoided
ENAMETOOLONG       EQU 36           ; File name too long
ENOLCK             EQU 37           ; No locks available
ENOSYS             EQU 38           ; Function not implemented
ENOTEMPTY          EQU 39           ; Directory not empty
ELOOP              EQU 40           ; Too many levels of symbolic links
EWOULDBLOCK        EQU EAGAIN       ; Operation would block
ENOMSG             EQU 42           ; No message of desired type
EIDRM              EQU 43           ; Identifier removed
EAFNOSUPPORT       EQU 97           ; Address family not supported
ENOTCONN           EQU 107          ; Transport endpoint is not connected

VFS_MAX_INODES      EQU 64          ; Максимальное число файлов на RAM-диске
INODE_STRUCT_SIZE   EQU 16          ; Размер одной структуры Inode (16 байт)

; Канонические типы файлов POSIX VFS ядра
I_TYPE_FREE         EQU 00H         ; Слот Inode свободен
I_TYPE_REGULAR      EQU 01H         ; Обычный регулярный файл
I_TYPE_CHRDEV       EQU 02H         ; Символьное устройство (TTY, LP, NULL)
I_TYPE_BLKDEV       EQU 03H         ; Блочное устройство (RAM-диск, FDD)
