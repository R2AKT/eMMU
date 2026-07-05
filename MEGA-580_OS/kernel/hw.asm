hw_int_init:
 ; Инициализация Контроллера Прерываний КР580ВН59 (База векторов 0x0040)
    MVI  A, 013H
	OUT MASTER_8259_CMD  ; ICW1: По фронту прерываний, одиночный, нужен ICW4
    MVI  A, 040H
	OUT MASTER_8259_DATA ; ICW2: Базовое смещение аппаратной таблицы векторов = 0x0040
    MVI  A, 001H
	OUT MASTER_8259_DATA ; ICW4: Режим микропроцессора 8085/8086, обычный EOI
    MVI  A, 07CH
	OUT MASTER_8259_DATA ; OCW1 (Маска): Включаем IRQ0 (Таймер), IRQ1 (UART), IRQ7 (eMMU). Маска 0x7C 

	RET
