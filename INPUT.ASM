; =================================================================
;                 Auto Typer для KolibriOS
;         (c) 2024, переписано для KolibriOS
; =================================================================
use32

; --- Заголовок приложения ---
    org     0
    db      'MENUET01'              ; 8-байтовая сигнатура
    dd      1                       ; версия заголовка
    dd      start                   ; адрес точки входа
    dd      i_end                   ; необходимый размер памяти
    dd      mem                     ; размер стека
    dd      stack_top               ; адрес вершины стека
    dd      0                       ; параметры (не используются)
    dd      0                       ; заголовок окна

; --- Константы ---
include 'macros.inc'

BUTTON_START    equ 10
BUTTON_CLOSE    equ 1

WIN_W           equ 400
WIN_H           equ 260

COL_WHITE       equ 0xFFFFFF
COL_BLACK       equ 0x000000
COL_L_GRAY      equ 0xE0E0E0

; --- Структура для поля ввода ---
struct EDIT_BOX
  .width       dw 0
  .height      dw 0
  .max_len     dd 0
  .text_ptr    dd 0
  .color       dd 0
  .flags       dd 0
  .caret_pos   dd 0
  .x           dd 0
  .y           dd 0
  .id          dd 0
  .reserved    rb 24
ends

; =================================================================
;                         Точка входа
; =================================================================
start:
    ; --- Основной цикл событий ---
    call draw_window

event_loop:
    mcall 10 ; Ждем событие
    mov [event_type], eax

    cmp eax, 1 ; Перерисовка окна
    je redraw

    cmp eax, 2 ; Нажатие клавиши
    je key_press

    cmp eax, 3 ; Нажатие кнопки
    je button_press

    jmp event_loop

redraw:
    call draw_window
    jmp event_loop

key_press:
    ; Системные элементы управления сами обрабатывают ввод
    jmp event_loop

button_press:

	mcall  17
    mov [event_id], eax

    cmp eax, BUTTON_CLOSE ; ID системной кнопки закрытия
    je exit_program

    cmp eax, BUTTON_START ; Наша кнопка "START"
    je handle_start

    cmp		ah, 1
    jne 	event_loop

    .exit:
    		mcall   -1

; --- Обработка нажатия кнопки START ---
handle_start:
    ; Читаем значение задержки
    mov esi, edit_delay_buffer
    call string_to_int
    mov [typing_delay], eax

    ; Читаем значение обратного отсчета
    mov esi, edit_countdown_buffer
    call string_to_int
    mov [countdown_sec], eax

    ; Запускаем процесс набора текста
    call start_typing_process
    jmp event_loop ; Возвращаемся к ожиданию событий

exit_program:
    mcall -1 ; Завершение программы


; =================================================================
;                       Отрисовка окна и элементов
; =================================================================
draw_window:
    mcall 12, 1 ; Начать отрисовку (BEGIN_DRAW)
    mcall 0, <0, WIN_W>, <0, WIN_H>, 0x34FFFFFF, 0, title ; Создать окно

    ; --- Отрисовка элементов управления ---
    call draw_labels
    call draw_edit_boxes
    call draw_buttons

    mcall 12, 2 ; Закончить отрисовку (END_DRAW)
    ret

draw_labels:
    ; Метка "Delay:"
    mcall 4, <20, 170>, 0x90000000, label_delay
    ; Метка "Countdown:"
    mcall 4, <20, 200>, 0x90000000, label_countdown
    ret

draw_edit_boxes:
    ; Основное поле для ввода текста
    mcall 65, edit_main, 20*65536 + 20, 360*65536 + 140, 1000

    ; Поле для задержки
    mcall 65, edit_delay, 150*65536 + 170, 50*65536 + 25, 1001

    ; Поле для обратного отсчета
    mcall 65, edit_countdown, 150*65536 + 200, 50*65536 + 25, 1002
    ret

draw_buttons:
    ; Кнопка "START"
    mcall 8, 20*65536+230, 100*65536+25, BUTTON_START, COL_L_GRAY
    mcall 4, 50*65536+237, COL_BLACK, button_start_text
    ret

; =================================================================
;                 Функции автоматического набора
; =================================================================

start_typing_process:
    pusha

    ; Ждем указанное время перед началом набора
    mov ecx, [countdown_sec]
delay_countdown_loop:
    test ecx, ecx
    jz countdown_done
    push ecx
    mcall 5, 100 ; Задержка 100 * 10мс = 1 секунда
    pop ecx
    dec ecx
    jmp delay_countdown_loop
countdown_done:

    ; Начинаем набор
    mov esi, edit_main_buffer
type_loop:
    lodsb
    test al, al
    jz type_done

    ; Преобразуем символ в скан-код
    call char_to_scancode
    jc type_loop ; Если символ не поддерживается, пропускаем

    ; Эмулируем нажатие клавиши
    push eax
    mcall 66, 1, eax ; 1 = нажать клавишу

    ; Небольшая задержка для надежности
    mcall 5, 2 ; 20 мс

    ; Эмулируем отпускание клавиши
    pop eax
    mcall 66, 2, eax ; 2 = отпустить клавишу

    ; Задержка между символами
    mov ecx, [typing_delay]
    mcall 5, ecx

    jmp type_loop

type_done:
    popa
    ret

; =================================================================
;                     Вспомогательные функции
; =================================================================

; --- Преобразование строки в число ---
; Вход: esi - указатель на строку
; Выход: eax - число
string_to_int:
    xor eax, eax
.loop:
    movzx ecx, byte [esi]
    inc esi
    cmp cl, '0'
    jb .done
    cmp cl, '9'
    ja .done
    sub cl, '0'
    imul eax, 10
    add eax, ecx
    jmp .loop
.done:
    ret


; --- Преобразование ASCII символа в скан-код KolibriOS ---
; Вход: al - ASCII символ
; Выход: eax - скан-код, CF=1 если символ не поддерживается
char_to_scancode:
    ; Проверяем на пустой символ
    test al, al
    jz .unsupported

    ; Преобразуем строчные буквы в заглавные
    cmp al, 'a'
    jb .check_digits
    cmp al, 'z'
    ja .check_digits
    sub al, 32

.check_digits:
    ; Проверяем буквы A-Z
    cmp al, 'A'
    jb .check_numbers
    cmp al, 'Z'
    ja .check_numbers

    push 	ebx
    movzx 	eax, al
    shl 	ebx, 2
    mov		eax, [scancode_map + ebx]
    pop		ebx
    test	eax, eax
    jz		.unsupported
    clc
    ret

.check_numbers:
    ; Проверяем цифры 0-9
    cmp al, '0'
    jb .check_special
    cmp al, '9'
    ja .check_special
    movzx eax, al
    sub eax, '0'
    add eax, [scancode_map + ('0' * 4)]
    clc
    ret

.check_special:
    ; Проверяем специальные символы
    cmp al, ' '
    je .space
    cmp al, 13 ; CR (Enter)
    je .enter
    cmp al, 10 ; LF (Enter)
    je .enter
    cmp al, '.'
    je .period
    cmp al, ','
    je .comma

.unsupported:
    stc ; Установить флаг Carry, чтобы показать ошибку
    ret

.space:
    mov eax, 0x39
    clc
    ret
.enter:
    mov eax, 0x1C
    clc
    ret
.period:
    mov eax, 0x34
    clc
    ret
.comma:
    mov eax, 0x33
    clc
    ret


; =================================================================
;                          Секция данных
; =================================================================

event_type      dd 0
event_id        dd 0, 0

title           db 'Auto Typer for KolibriOS',0
label_delay     db 'Delay (ms):', 0
label_countdown db 'Countdown (sec):', 0
button_start_text db 'START', 0

; --- Буферы и переменные для набора ---
typing_delay    dd 10 ; 100 мс по умолчанию
countdown_sec   dd 5  ; 5 секунд по умолчанию

; --- Определения полей ввода ---
edit_main:
    EDIT_BOX 360, 140, 4096, edit_main_buffer, COL_WHITE, 0x80000000
edit_delay:
    EDIT_BOX 50, 25, 5, edit_delay_buffer, COL_WHITE, 0
edit_countdown:
    EDIT_BOX 50, 25, 5, edit_countdown_buffer, COL_WHITE, 0

; --- Таблица скан-кодов (частичная) ---
scancode_map:
    dd 0x0B,0x02,0x03,0x04,0x05,0x06,0x07,0x08,0x09,0x0A ; 0-9
    times 'A'-'9'-1 dd 0
    dd 0x1E,0x30,0x2E,0x20,0x12,0x21,0x22,0x23,0x17,0x24 ; A-J
    dd 0x25,0x26,0x32,0x31,0x18,0x19,0x10,0x13,0x1F,0x14 ; K-T
    dd 0x16,0x2F,0x11,0x2D,0x15,0x2C ; U-Z


; =================================================================
;                   Секция неинициализированных данных
; =================================================================

stack_bottom:
    rb 		200*1024
    align	1024

stack_top:

edit_main_buffer:       rb 4096
edit_delay_buffer:      db '100',0
                        rb 10
edit_countdown_buffer:  db '5',0
                        rb 10
i_end:
mem: