![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)
License addendum - https://github.com/R2AKT/eMMU/blob/main/Addendum.txt

# eMMU — Hardware Memory Management Unit for KR580VM80A / Intel 8080

Choose language / Выберите язык:
* [English](#-english)
* [Русский (Russian)](#-русский)

---

# 🇺🇸 English

# eMMU — Hardware Memory Management Unit for Intel 8080 (KR580VM80A)

## 📌 Project Overview
**eMMU (extended Memory Management Unit)** is a high-performance hardware memory management subsystem implemented entirely on discrete TTL logic (74LS, 74ALS series). The project is architected around the vintage **Intel 8080 (KR580VM80A)** 8-bit microprocessor kit and radically overcomes its native architectural limitations.

### Key Features:
* **Memory Expansion:** Increases addressable physical RAM space from **64 KB to 4 MB**.
* **Privilege Isolation:** True hardware-enforced **RING 0 (Kernel Mode)** and **RING 3 (User Mode)** execution environments.
* **Hardware Exceptions:** Immediate generation of a dedicated `/PRIVILEGE_VIOLATION` interrupt upon unauthorized I/O access.
* **Instruction Filtering:** In-flight opcode interception that silently substitutes forbidden user-space interrupt commands (`DI`/`EI`) with safe `NOP` (`0x00`) instructions.
* **Isolated Data Override:** Secure cross-privilege memory window with absolute hardware Write-Protection (WP) blocking of kernel-space RAM during data transfers.
* **Reactive I/O Firewall:** Instant hardware Z-state disabling of the KR580VK38 system controller and premature `~{CS}` peripheral dropping to block rogue I/O cycles.

---

## 🗺️ System Memory Architecture (Memory Map)
The processor's 64 KB logical address space is divided into **4 fixed segments of 16 KB each**. Translation is performed by dynamically swapping logical lines `/AB14` and `/AB15` with physical high-order address lines `/MAB14`...`/MAB21` via **74LS257 (K555KP11)** multiplexers (`DD4`, `DD15`) backed by **74LS670 (K555IR26)** 4x4 register file window memory arrays (`DD7`, `DD16`).

### Logical Segment Map (64 KB) in User Mode (RING 3):
* **`0x0000 – 0x3FFF` [Segment 0]**: **Fully Free User RAM**. Dedicated entirely to user-space application code, stack, or variables. No kernel interrupt vectors or system syscall vectors are reserved here.
* **`0x4000 – 0x7FFF` [Segment 1]**: **Fully Free User RAM**. Available for application execution or heap space.
* **`0x8000 – 0xBFFF` [Segment 2]**: **Fully Free User RAM**. Architecturally designated as the controlled override window for secure Kernel-to-User data exchanges.
* **`0xC000 – 0xFFFF` [Segment 3]**: **Fully Free User RAM**. Allocated for the user-space isolated execution stack and process variables.

### Lower Virtual Space Isolation and Context Switching:
User applications maintain absolute, uninhibited control over the entire 64 KB space—including the lower virtual range (`0x0000–0x0037`)—as the processor never reads instructions from this user-space context during interrupt traps.

The moment a hardware interrupt occurs (`~{INTA} = 0`) or a software trap is triggered, the eMMU forcefully overrides the bus, **switching the memory mapping to the Kernel context (RING 0)**. The true system interrupt vector table is activated on the physical bus exclusively in Kernel mode and strictly starting from address `0x0038` onwards via the `VD1–VD3` diode selector array (`~{LOW_8K} = 0`) and the `DD17` trigger clocked by the `/M1_TRUE` signal.

## 🔌 I/O Control Port Map
MMU configuration and page-table management are handled via a privileged, hardware-isolated I/O port range: **`0x70` – `0x77`** (decoded by **`DD14` / K555ID7 / 74LS138**). Access to these ports is strictly gated by the **`DD12` (K555SP1 / 74LS85)** digital comparator and jumpers `JP1–JP4`. Any unauthorized access attempt from RING 3 instantly locks the decoder and aborts the system cycle.

| Privileged I/O Port | Signal Name | Bus Direction | Functional Description inside the MMU |
| :---: | :--- | :---: | :--- |
| **`0x70`** | `~{PORT_70_SEL}` | Write Only | Writes the physical page index for **Segment 0** into K555IR26 |
| **`0x71`** | `~{PORT_71_SEL}` | Write Only | Writes the physical page index for **Segment 1** into K555IR26 |
| **`0x72`** | `~{PORT_72_SEL}` | Write Only | Writes the physical page index for **Segment 2** into K555IR26 |
| **`0x73`** | `~{PORT_73_SEL}` | Write Only | Writes the physical page index for **Segment 3** into K555IR26 |
| **`0x74`** | `~{PORT_74_SEL}` | — | Reserved internal auxiliary control line |
| **`0x75`** | `~{PORT_75_SEL}` | Write Only | **Shadow ROM Override:** Flips trigger `DD3` to permanently disable Boot ROM after BIOS is cached to Kernel RAM |
| **`0x76`** | `~{PORT_76_SEL}` | Write Only | **KERNEL_OVERRIDE Control:** Toggles trigger `DD19` to engage/disengage user-space window mapping |
| **`0x77`** | `~{PORT_77_SEL}` | — | Reserved system port for future hardware extensions |

---

## 🛠️ Hardware-Enforced Protection Mechanisms

### 1. Boot Logic, Shadow ROM, and Diode Selection (`VD1–VD3`)
At power-on or system reset (`~{RESOUT} = 0`), the `DD3` trigger defaults to `~{ROM_EN} = 0`, forcing raw physical memory translation off. The **`VD1–VD3`** diode array strictly monitors logical address ranges, asserting **`~{LOW_8K} = 0`**. 

Gated together with `~{ROM_CS}`, this activates the `DD35` Shadow Boot ROM **strictly within the logical bounds of `0x0000–0x1FFF`**, completely preventing phantom mirroring across higher address blocks. The primary bootloader copies the core BIOS/OS image into fast physical system RAM, then fires an `OUT 0x75` command. The resulting `~{PORT_75_SEL}` strobe flips the `DD3` trigger—permanently disabling the Shadow ROM and the diode array until the next cold reset, instantly reclaiming Segment 0 for user space.

### 2. Privileged I/O Gating and the Reactive I/O Firewall
The board incorporates a reactive hardware monitoring matrix over the I/O subsystem. In RING 3, discrete gates `DD11` and `DD44` actively watch the execution of system input/output command strobes **`~{IOR}`** and **`~{IOW}`**.
* **Violation Detection:** Any rogue `IN`/`OUT` execution from user space targeted at protected peripheral spaces triggers an immediate **`~{IO_VIOLATION} = 0`** fault signal. Trigger **`DD55`** latches this hardware exception and relays a persistent **`/PRIVILEGE_VIOLATION`** interrupt request to the system controller via the `JP5–JP12` matrix. The kernel clears the exception state by pulsing port `0x76`.
* **Hardware Interception Matrix:** Simultaneously with the interrupt, the asserted `~{IO_VIOLATION} = 0` line instantly forces the main **KR580VK38** system controller data bus transceivers into a high-impedance Z-state, effectively disconnecting the CPU's local lines. Mitigation is achieved by **prematurely forcing Chip Select (`~{CS}`) lines to high (`1`)** on the external peripheral decoders. This hardware drop completely isolates external LSI chips (such as KR580VV55 or KR580VI53) *before* the active logical `~{IOW}` or `~{IOR}` bus signals finish their machine cycle, making the theft or corruption of internal peripheral control data physically impossible.

### 3. Opcode Invalidation (`DI` / `EI` Gating)
During RING 3 execution, the `DD26` decoder tracks the exact appearance of `0xF3` (`DI`) and `0xFB` (`EI`) opcodes strictly inside `M1` fetch cycles. Upon matches, the `~{DI-EI_CODE}` line falls low, opening the `DD13` bus-override buffer which grounds the processor's data lines on-the-fly. The processor registers a safe **`NOP` (`0x00`)** instruction instead, leaving user-space interrupts enabled and maintaining total OS multitasking stability.

### 4. Delayed Privilege Escalation and Symmetric Returns
When an interrupt hits (`~{INTA} = 0`), the CPU executes the initial branch cycle completely in RING 3. The return address (`PC`) is written to the user stack using user-space translation tables. Because privilege escalation to RING 0 (`/KERNEL_MODE = 1`) is strictly delayed until the first opcode fetch (`M1`) from vector `0x0038` (handled by the `/M1_TRUE` trigger), the kernel's physical pages are fundamentally insulated from being overwritten by a corrupt user-space `SP`.

Symmetric returns are cleanly automated via the `~{RET_STROBE}` line, which intercepts the `RET` (`0xC9`) instruction in its `M1` cycle. The processor reads its return coordinates from the stack *after* the hardware has already swapped the context back to RING 3, ensuring the kernel's execution context is kept clean.

### 5. Secure Context Override (`KERNEL_OVERRIDE`)
To transfer blocks between Kernel Mode and User Mode safely, the kernel writes to port `0x76`, setting `~{KERNEL_OVERRIDE} = 0`. Inside Segment 2 (`0x8000–0xBFFF`), a **K555LI1 (74LS08)** logical `AND` gate forces the IR26 registers and KP11 multiplexers into translation mode. While Segments 0, 1, and 3 continue to map true kernel pages (mirrored by the OS inside register positions 0, 1, and 3 of the IR26 files), Segment 2 securely routes data directly to the physical user process page.

Crucially, the active-low `~{KERNEL_OVERRIDE_EN} = 0` line is fed directly into the active-low enable input `E1` (pin 4) of the **`DD39`** kernel memory decoder. The moment an override cycle runs, **`DD39` is forcefully disabled by the hardware**, driving `~{CS_32}` and `~{CS_64}` high. Physical kernel RAM chips (`DD50`, `DD51`) are completely decoupled from the data bus, making malicious memory corruption through illegal user pointers mathematically impossible.

---

# 🇷🇺 Русский

## 📌 Описание проекта
**eMMU (extended Memory Management Unit)** — это высокоуровневый аппаратный диспетчер памяти, реализованный на жесткой ТТЛ-логике (серии К555/К1533). Проект спроектирован вокруг классического микропроцессорного комплекта **КР580ВМ80А (Intel 8080)** и полностью решает его базовые архитектурные ограничения.

### Ключевые возможности:
* **Расширение памяти:** Адресация физического ОЗУ увеличивается с **64 КБ до 4 МБ**.
* **Разделение привилегий:** Полноценная аппаратная реализация режимов **RING 0 (Ядро)** и **RING 3 (Пользователь)**.
* **Аппаратные исключения:** Генерация прерывания `/PRIVILEGE_VIOLATION` при несанкционированном доступе к портам ввода-вывода.
* **Фильтрация команд:** Перехват и «тихая» подмена запрещенных инструкций `DI`/`EI` в пространстве пользователя на безопасные `NOP` (`0x00`).
* **Защищенный оверрайд:** Межпривилегированный сегмент обмена данными с жесткой WP-блокировкой системного ОЗУ.
* **Аппаратный I/O Firewall:** Принудительное Z-глушение ВК38 и опережающее отключение сигналов `~{CS}` периферии при нелегальном доступе к портам в RING 3.

---

## 🗺️ Архитектурная карта памяти (Memory Map)
Логическое адресное пространство процессора (64 КБ) разделено на **4 фиксированных сегмента объемом по 16 КБ каждое**. Трансляция осуществляется заменой логических линий `/AB14` и `/AB15` на физические `/MAB14`...`/MAB21` через мультиплексоторы **К555КП11 (`DD4`, `DD15`)** и регистровую память окон **К555ИР26 (`DD7`, `DD16`)**.

### Сетка логических сегментов процессора (64 КБ) в режиме Пользователя (RING 3):
* **`0x0000 – 0x3FFF` [Сегмент 0]**: **Полностью свободен**. Назначение определяется пользователем (код / стек / данные).
* **`0x4000 – 0x7FFF` [Сегмент 1]**: **Полностью свободен**. Назначение определяется пользователем (код / стек / данные).
* **`0x8000 – 0xBFFF` [Сегмент 2]**: **Полностью свободен**. Назначение определяется пользователем. Аппаратно выделен как область контролируемого оверрайда для доступа Ядра к пользовательской памяти.
* **`0xC000 – 0xFFFF` [Сегмент 3]**: **Полностью свободен**. Назначение определяется пользователем (код / стек / данные).

### Механизм изоляции и принудительного переключения:
Все четыре сегмента в пользовательском режиме полностью очищены от обязательного присутствия системных структур ядра. Пользовательское ПО может монопольно распоряжаться всем пространством 64 КБ.

В момент программного вызова (команды `RST`, `CALL`) или аппаратного прерывания (`~{INTA} = 0`), eMMU аппаратно перехватывает шину и **принудительно переключает адресное пространство в контекст Ядра (RING 0)**. Истинная системная база ОС активируется на физической шине строго в режиме ядра, защищая пользовательские данные.

---

## 🔌 Карта портов ввода-вывода (I/O Control Map)
Управление диспетчером памяти выполняется через диапазон портов **`0x70` – `0x77`** (дешифратор **`DD14` / К555ИД7**). Доступ аппаратно защищен компаратором **`DD12` (К555СП1)** и блоком джамперов `JP1–JP4`. Обращение из RING 3 мгновенно блокирует дешифратор и вызывает сбой системы.

| Порт I/O | Название сигнала | Направление | Функциональное назначение в MMU |
| :---: | :--- | :---: | :--- |
| **`0x70`** | `~{PORT_70_SEL}` | Запись | Физический адрес страницы для **Сегмента 0** в К555ИР26 |
| **`0x71`** | `~{PORT_71_SEL}` | Запись | Физический адрес страницы для **Сегмента 1** в К555ИР26 |
| **`0x72`** | `~{PORT_72_SEL}` | Запись | Физический адрес страницы для **Сегмента 2** в К555ИР26 |
| **`0x73`** | `~{PORT_73_SEL}` | Запись | Физический адрес страницы для **Сегмента 3** в К555ИР26 |
| **`0x74`** | `~{PORT_74_SEL}` | — | Резервный управляющий канал периферии |
| **`0x75`** | `~{PORT_75_SEL}` | Запись | **Отключение теневого ПЗУ**: защелка триггера `DD3` после копирования BIOS в ОЗУ ядра |
| **`0x76`** | `~{PORT_76_SEL}` | Запись | **Включение / выключение режима KERNEL_OVERRIDE** (управление триггером `DD19`) |
| **`0x77`** | `~{PORT_77_SEL}` | — | Резервный системный порт диспетчера |

---

## 🛠️ Механизмы аппаратной защиты

### 1. Логика старта, теневое ПЗУ и диодный селектор `VD1–VD3`
При подаче питания или системном сбросе (`~{RESOUT} = 0`) триггер `DD3` автоматически выставляет `~{ROM_EN} = 0`. Трансляция отключена. Диодная сборка **`VD1–VD3`** непрерывно идентифицирует обращения процессора к нижним адресам памяти и формирует сигнал **`~{LOW_8K} = 0`**. 

В связке с цепью `~{ROM_CS}` это аппаратно активирует теневое ПЗУ `DD35` **строго в границах диапазона `0x0000–0x1FFF`**, исключая его ложное зеркалирование на остальную память. Первичный бутлоадер переносит код BIOS/ОС в физическое системное ОЗУ, после чего выполняет команду `OUT 0x75`. Сигнал `~{PORT_75_SEL}` сбрасывает триггер `DD3` — теневое ПЗУ и диодная сборка навсегда отключаются до следующего аппаратного RESET, освобождая Сегмент 0 для полноценного использования пользователем.

### 2. Защита ввода-вывода и Экспериментальный I/O Firewall
Плата реализует жесткий аппаратный контроль пространства ввода-вывода. В режиме RING 3 элементы логики `DD11` и `DD44` непрерывно мониторят появление системных стробов чтения/записи портов **`~{IOR}`** и **`~{IOW}`**.
* **Детектирование нарушений:** Любая попытка вызова команд `IN`/`OUT` в пользовательском пространстве к служебным/управляющим портам eMMU формирует сигнал **`~{IO_VIOLATION} = 0`**. Триггер **`DD55`** мгновенно фиксирует (защелкивает) это событие и через систему джамперов `JP5–JP12` отправляет сигнал прерывания **`/PRIVILEGE_VIOLATION`** контроллеру прерываний для обработки операционной системой. Сброс триггера нарушения производится ядром через порт `0x76`.
* **ЭКСПЕРИМЕНТАЛЬНАЯ защита (Блокировка периферии):** Сигнал нарушения `~{IO_VIOLATION} = 0` мгновенно переводит системный контроллер **КР580ВК38** в высокоимпедансное Z-состояние, изолируя локальные линии данных процессора. Предотвращение несанкционированного выполнения операции (чтения служебных/управляющих данных или записи деструктивного мусора в регистры) достигается за счет **опережающего аппаратного снятия сигналов выбора кристалла `~{CS}`** с дешифраторов внешних периферийных модулей (они принудительно уводятся в `1`). Блокировка срабатывания логики внешних БИС происходит до того, как текущие системные стробы `~{IOW}` или `~{IOR}` успеют завершить машинный цикл и подняться обратно в пассивное состояние, гарантируя полную изоляцию служебных портов.

### 3. Блокировка `DI` / `EI`
В пользовательском режиме компаратор `DD26` отслеживает опкоды `0xF3` (`DI`) и `0xFB` (`EI`) в цикле `M1`. При совпадении активируется линия `~{DI-EI_CODE}`, открывая буфер глушения шины `DD13`, который прижимает данные процессора к нулю. Процессор выполняет операцию **`NOP` (`0x00`)**.

### 4. Межпривилегированные переходы и Стек
При прерывании или системном вызове (`~{INTA} = 0`) процессор выполняет переход полностью в контексте RING 3. Адрес возврата (`PC`) сохраняется в текущем пользовательском стеке по правилам трансляции страниц пользователя. Поскольку переключение в RING 0 (`/KERNEL_MODE = 1`) происходит отложено — строго по сигналу `/M1_TRUE` при выборке первой инструкции обработчика ядра из предела `0x0038`, физические адреса ядра гарантированно защищены от записи со стороны пользовательского указателя стека `SP`.

Автоматический выход в RING 3 осуществляется по сигналу `~{RET_STROBE}` при детекции опкода `RET` (`0xC9`) в цикле `M1`. Чтение стека процессором происходит уже в контексте пользовательских таблиц страниц.

### 5. Синхронизация KERNEL_OVERRIDE
Включение режима контролируемого доступа к памяти пользователя производится командой `OUT 0x76`, взводящей линию `~{KERNEL_OVERRIDE} = 0`. В режиме оверрайда, привязанном строго к Сегменту 2 (`0x8000–0xBFFF`), логическое «И» на микросхеме **К555ЛИ1** принудительно включает ИР26 и КП11. Для Сегментов 0, 1 и 3 на шину транслируются системные адреса ядра (продублированные ОС в ячейках 0, 1 и 3 ИР26), а для Сегмента 2 — страница пользователя.

Строб `~{KERNEL_OVERRIDE_EN} = 0` заведен на инверсный вход разрешения `E1` дешифратора памяти ядра **`DD39`**. В момент работы оверрайда дешифратор `DD39` **аппаратно блокируется**, уводя сигналы `~{CS_32}` и `~{CS_64}` в пассивную единицу, что полностью исключает риск затирания памяти ядра пользовательскими данными. По окончании работы ядро сбрасывает режим оверрайда повторной записью в порт `0x76`.

---
*Engineered as part of the eMMU Protected System Architecture.*

---
