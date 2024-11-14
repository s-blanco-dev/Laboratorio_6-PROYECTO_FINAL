;
; Programa Ejemplo MAnejo display LED 32x32
;
; Created: 10/9/2021 11:46:51
; Author : Curso Microprocesadores - Oct 2022
;

;Breve descripción:
;Programa ejemplo para manejar un display de 32x32. 
;Defino una memoria de pantalla en RAM de 1024bytes. 1byte = 1 pixel (32 x 32 = 1024)
;de c/u uso solo 3 bits que indican el RGB del pixel (solo on/off). 
;
;configuro el timer0 para interrumpir 1250 veces por segundo.
;luego en cada interrupción barro 1 linea cada vez.
;
;configuro el timer1 para interrumpir 1 vez por segundo, puede utilzar para hacer un reloj.
;por ahora solo modifica el color de 1 pixel para confirmar que el timer1 funciona correctamente.
;
; Pines de control del display:
;   PB5:PB0 = RGB1:RGB0
;   PC6:PC0 = LE:Clk:OE:ABCD
;
;Importante: la interrupción del timer0 utiliza el registro Y(r29:r28) y r25, no se pueden utilizar en
;otras rutinas.
;Y(r29:r28) - dirección en la RAM de oantalla de la próxima linea a barrer
;r25 - #de linea a barrer en la próxima interrupción.

;aquí defino la memoria pantalla en RAM recordar que la directiva .DSEG aclara que esto va en RAM.
.DSEG
screen:				.byte 1024		;reservo 1024 bytes para la memoria de pantalla.
screen_end:			.byte 1			;solo para marcar el final del buffer

; comienzo del programa principal ... la directive .CSEG aclara que esto va en FLASH de programa.
.CSEG
; declaro los vectores de interrupción
.ORG 0x0000
	jmp		start		;dirección de comienzo (vector de reset)
.ORG 0x0016 
	jmp		_tmr1_int	;salto atención a rutina de comparación A del timer 1
.ORG 0x001C 
	jmp		_tmr0_int	;salto atención a rutina de comparación A del timer 0

; ---------------------------------------------------------------------------------------
; acá empieza el programa
start:
;configuro los puertos:
;	PB0 PB1 PB2 - RGB0   PB3 PB4 PB5 - RGB1
    ldi		r16,	0b00111111	
	out		DDRB,	r16			;PB0 a PB5 son salidas
	ldi		r16,	0x00	
	out		PORTB,	r16			;apago PORTB

;	configuro PD0:7 no se va a usar, lo configuro como entradas. 
	ldi		r16,	0b00000000	
	out		DDRC,	r16			;PC0:7 son entradas

;	PD3 a PD0 = ABCD indica la línea del display que estoy escribiendo
;	PD4 = OE(asumo activa nivel alto), PD5 = Clk serial, PD6 = LE (STB del Latch)
	ldi		r16,	0b01111111
	out		DDRD,	r16			;configuro PD.0 a PD.6 como salidas
  	ldi		r16,	0b00000000
	out		PORTD,	r16			;inicializo todo en 0
;-------------------------------------------------------------------------------------
;Configuro el TMR0 y su interrupcion.
	ldi		r16,	0b00000010	
	out		TCCR0A,	r16			;configuro para que cuente hasta OCR0A y vuelve a cero (reset on compare), ahí dispara la interrupción
	ldi		r16,	0b00000100	
	out		TCCR0B,	r16			;prescaler = 256
	ldi		r16,	24	
	out		OCR0A,	r16			;comparo con 49			fint0 = 16000000/256/50 = 1250Hz
	ldi		r16,	0b00000010	
	sts		TIMSK0,	r16			;habilito la interrupción (falta habilitar global)
;-------------------------------------------------------------------------------------
;Configuro el TMR1 y su interrupcion.
	ldi		r16,	0b00000000
	sts		TCCR1A,	r16			;configuro para que cuente hasta OCR0A y vuelve a cero (reset on compare), ahí dispara la interrupción
	ldi		r16,	0b00001101	
	sts		TCCR1B,	r16			;prescaler = 1024
	ldi		r16,	high(15624)	
	sts		OCR1AH,	r16		
	ldi		r16,	low(15624)	
	sts		OCR1AL,	r16			;OCR1A = 15625		fint0 = 16000000/1024/15625 = 1Hz
	ldi		r16,	0b00000010	
	sts		TIMSK1,	r16			;habilito la interrupción (falta habilitar global)
;--------------------------------------------------

;-------------------------------------------------------------------------------------
;Inicializo algunos registros que voy a usar como variables.
	ldi		r25,	0x00					;inicializo r25 para el display indica qué línea estoy barriendo
	ldi		YL,	low(screen)					;apunto Y al primer byte de la pantalla
	ldi		YH,	high(screen)

	.def pos_x = r22
	.def pos_y = r21
	ldi pos_x, 12
	ldi pos_y, 22
;-------------------------------------------------------------------------------------
	sei							;habilito las interrupciones globales(set interrupt flag)
;-------------------------------------------------------------------------------------


;Programa principal

;borra el panel
	call	borra_panel						
	
;copia una imagen de fondo en el panel
	ldi		ZL,	low(Menu<<1)			;apunto Z a la imagen de fondo a copiar y luego efectivamente la copia.
	ldi		ZH,	high(Menu<<1)
	call	copia_img						;comentar esta línea para no mostrar la imagen de fondo y ver mejor los caracteres.


	
;	Imprime un '1' Verde por pantalla
	ldi		r18,	0
	mov		r17,	pos_x
	mov		r16,	pos_y
	ldi		r20,	0x04				;en R20 está el color
	call	copia_char
	


; Ahora me quedo esperando sin hacer nada o puedo hacer otras tareas;
; una vez que la memoria pantalla fué escrita se encarga la interrupcion del timer0. 
; Pruebe modificar desde la herramienta la memoria de pantalla ditrectamente.
espero:
	nop 
	nop
	sbis PINC, 1
	call izq
	call delay
	sbis PINC, 3
	call der
	call delay
	nop
	rjmp	espero

;RUTINAS
;-------------------------------------------------------------------------------------

;timer0:	
;--------
;rutina de barrido que saca 192 bits de RGB por el display, recordar que en cada paso saco por el peurto
;PORTB 6 bits, RGB0 - Pixel de la mitad de arriba y RGB1 - Pixel de la mitad de abajo.
;RGB = color, solo puedo hacer combinaciones R, G, B, (R+G), (G+B), (R+B), y (R+G+B) = blanco
;
;Cada 32 Bytes de la memoria de pantalla, saco 192 bits (96 de una linea de arriba, 96 de una linea de abajo). 
;En Y se supone está la dirección de donde comienzo a sacar los bits.
;
;Uso algunos registros exclusivos:
;	Y (YH:YL) memoriza la dirección de pantalla que estoy recorriendo
;	R25 memoriza la linea siguiente a iluminar
;-------------------------------------------------------------------------------------

;(sacaLED)
_tmr0_int:
	push	r16			; guardo contexto: registros a usar y banderas
	in		r16,	SREG
	push	r16
	push	r17
	push	r18
	push	r27			
	push	r26

	movw	X, Y						;Y apunta a la mitad de abajo
	inc		R27							;le sumo 512 a X para apuntar a la parte de abajo de la pantalla
	inc		R27

	ldi		r16, 0
	cbi		PORTD, 6					;LE = 0

LED_loop:
	cbi		PORTD, 5					;SCLK = 0

	ld		r17,	Y+					;traigo 2 bytes a sacar por la pantalla
	ld		r18,	X+					;este es de las lineas de abajo
	
LED_loop3:		
	andi	r17,	0b00000111
	swap	r18
	ror		r18
	andi	r18,	0b00111000
	or		r17, r18

	out		PORTB,	r17					;saco RGB1 RGB0 por el puerto B

	sbi		PORTD, 5					;SCLK = 1
	
	inc		r16
	cpi		r16,	32	

	brne	LED_loop					;loop si no completé la linea.

	sbi		PORTD, 4					;/OE = 1 apago display por las dudas (no es necesario)
	sbi		PORTD, 6					;LE = 1

;	Ahora dibujo una nueva linea
	out		PORTD,	r25					;NOTA: aquí ademas de pasar ABCD, estoy haciendo tambien /OE=0 y LE=0
	inc		r25
	cpi		r25,	32
	brne	LED_fin						;si no llegué a la ultima linea vuelvo de la interrupción
;	fin de pantalla, llevo r25 y Y al principio.
	ldi		r25,	0					
	ldi		YL,	low(screen)				;apunto de nuevo Y al primer byte de la pantalla
	ldi		YH,	high(screen)	

LED_fin:
	pop		r26						;restauro registros y banderas
	pop		r27
	pop		r18
	pop		r17
	pop		r16
	out		SREG,	r16
	pop		r16
	reti

;-------------------------------------------------------------------------------------
;copia_img:
;----------
;Rutina que copia un bloque de 1024 bytes de la Flash de programa a la RAM de pantalla
;en Screen.
;
;Parámetros: debo poner en Z(ZH:ZL) la dirección de comienzo de la imagen a copiar.
;-------------------------------------------------------------------------------------

copia_img:
	ldi		XL,	low(screen)			;apunto X al primer byte de la pantalla
	ldi		XH,	high(screen)

copia_loop1:
	lpm		r17,	Z+						;traigo 1 byte a copiar a la pantalla
	st		X+,		r17						;escribo la memoria de pantalla
	cpi		XL,		low(screen_end)
	brne	copia_loop1	
	cpi		XH,		high(screen_end)		;si llegué al final de la pantalla no copio más
	brne	copia_loop1	
	ret

;-------------------------------------------------------------------------------------
;borra_panel:
;----------
;Rutina que borra el display LED. 
;Escribe 1024 ceros en la RAM de pantalla
;-------------------------------------------------------------------------------------
borra_panel:
	ldi		XL,	low(screen)					;apunto de nuevo X al primer byte de la pantalla
	ldi		XH,	high(screen)
	ldi		r17, 0x00

borra_loop1:
	st		X+,		r17
	cpi		XL,		low(screen_end)
	brne	borra_loop1	
	cpi		XH,		high(screen_end)		;si llegué al final de la pantalla no copio más
	brne	borra_loop1	
	ret

;-------------------------------------------------------------------------------------
;copia_char:
;----------
;Rutina que copia un caracter en la memoria de pantalla. Por ahora pensado solo para
;los números del 0 al 9 de tamaño fijo 8x10 pixeles. Por ahora solo están el '0' y el '1'
;configurados en el mapa de caracteres pero la rutina funciona igual.
;
;los carateres son de 8x10 puntos por tanto ocupan solo 10 bytes. Esta rutina toma los 10
;bytes y bit a bit va programando la memoria de pantalla.
;
;Parámetros: 
;	r18 = numero a imprimir del 0 al 9 (por ahora solo 0 y 1 disponibles)
;	r16 y r17 = Fila y Columna del pixel superior izquierdo del caracter. 
;	r20 = color del caracter. 1-Verde 2-Rojo 4-Azul 3-Amarillo 5-cyan 6-lila 7-blanco 0-apagado 
;-------------------------------------------------------------------------------------

copia_char:
	ldi		XL,	low(screen)				;X apunta al comienzo de la memoria de pantalla
	ldi		XH,	high(screen)
	
	ldi		ZL,	low(char_0<<1)			;apunto Z al comienzo del mapa de caracteres char_0
	ldi		ZH,	high(char_0<<1)

	;Ahora ajusto Z según el caracter que quiero imprimir
	ldi		r19,	0x0A
	mul		r18,	r19				;cada 0x0A es un caracter
	clc		
	add		ZL,		r0	
	adc		ZH,		r1	

	;Ahora ajusto X segun la fila/columna donde quiero imprimir
	ldi		r18,	0x20
	mul		r16,	r18				;cada 0x20 es un salto de renglón
	clc		
	add		r0,		r17				;ahora en r1:r0 está lo que me tengo que desplazar en la pantalla
	ldi		r16,	0
	adc		r1,		r16
	clc		
	add		XL,		r0	
	adc		XH,		r1	

;ahora que esta todo listo, en este loop copio el caracter a la pantalla.
	ldi		r16,	10					;son 10 byte por caracter
copia_char1:
	lpm		r19,	Z+					;traigo 1 Byte con los bits del caracter
	ldi		r18,	8					;8 bits por byte
copia_char2:
	ld		r17,	X					;traigo 1 byte de la memoria de pantalla
	rol		r19
	brcc	copia_char3					
	mov		r17,	r20					;en r20 está el color que quiero imprimir
copia_char3:
	st		X+,		r17					;guardo el byte nuevo o el que estaba antes en la memoria de pantalla
	dec		r18
	brne	copia_char2

	adiw	XL,	0x18					;avanzo 0x18 = 24 lugares para el cambio de fila en la memoria de pantalla 
										;(no es 32 porque ya avancé 8 al dibujar la linea). 
	dec		r16
	brne	copia_char1
	ret

;imagen ejemplo con cuadrados de colores para pruebas
Imagen_1:	
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x02, 0x02, 0x07, 0x02, 0x02, 0x02, 0x07, 0x02, 0x02, 0x07, 0x02, 0x02, 0x07, 0x02, 0x02, 0x02, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07
.db 0x07, 0x02, 0x07, 0x07, 0x02, 0x07, 0x02, 0x07, 0x02, 0x07, 0x07, 0x02, 0x07, 0x07, 0x02, 0x07, 0x02, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07
.db 0x07, 0x02, 0x07, 0x07, 0x02, 0x02, 0x02, 0x07, 0x02, 0x02, 0x07, 0x02, 0x02, 0x07, 0x02, 0x02, 0x02, 0x00, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x00
.db 0x07, 0x02, 0x02, 0x07, 0x02, 0x07, 0x02, 0x07, 0x02, 0x07, 0x07, 0x02, 0x07, 0x07, 0x02, 0x07, 0x02, 0x00, 0x07, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x00, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x00, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07
.db 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07
.db 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07

Menu:
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07
.db 0x07, 0x07, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x07, 0x07, 0x07, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x07, 0x07, 0x07, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x07
.db 0x07, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x03, 0x03, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x03, 0x03, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x02, 0x07, 0x01, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x01, 0x07, 0x06, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x02, 0x07, 0x01, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x01, 0x07, 0x06, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
.db 0x00, 0x00, 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00, 0x00, 0x00
.db 0x00, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x00
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07
.db 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07, 0x07

;Mapa de caracteres, por ahora solo '0' y '1'
char_0:
.db 0b00011000, 0b00011000  ; Parte superior de la flecha (estrecha)
.db 0b00111100, 0b00111100  ; Cuerpo de la flecha (ancha)
.db 0b01111110, 0b11111111  ; Parte inferior de la flecha (ancha)
.db 0b00011000, 0b00111100  ; Punta de la flecha (cabeza)
char_1:
.db 0b00111000, 0b01111000
.db 0b00011000, 0b00011000
.db 0b00011000, 0b00011000
.db 0b00011000, 0b00011000
.db 0b00011000, 0b00111100




_tmr1_int:
	push	r16							;guardo contexto: registros y banderas
	in		r16,	SREG
	push	XH
	push	XL
		
	dec		r24
	andi	r24,	0b00000111
	
	
	ldi		XL,	low(screen)			;apunto de nuevo Y al primer byte de la pantalla
	ldi		XH,	high(screen)	

	
	st		X,		r24					;guardo el byte nuevo o el que estaba antes en la memoria de pantalla
	
	pop		XL
	pop		XH
	pop		r16
	out		SREG,	r16
	reti

der:
	push r16
	push r17
    ; Llama a una rutina que borra el contenido del display actual si es necesario
	
;copia una imagen de fondo en el panel
	ldi		ZL,	low(Menu<<1)			;apunto Z a la imagen de fondo a copiar y luego efectivamente la copia.
	ldi		ZH,	high(Menu<<1)
	call	copia_img	

	    ; Carga el carácter o imagen a mostrar en la nueva posición
    ; (Asegúrate de que copia_char pone el contenido deseado en la nueva posición)

	; ESTO NO FUNCIONA. NO VEO ERROR EN LA LOGICA PERO NO FUNCIONA
	inc pos_x
	inc pos_x 
	mov r17, pos_x
	mov r16, pos_y

	cpi pos_x, 24
	brge topper

	;ldi r17, 21
	;mov pos_x, r17
	;mov r16, pos_y
    call copia_char        ; Copia el carácter actual en la nueva posición
	rjmp fine
	
	topper:
	ldi r17, 1
	mov pos_x, r17
	mov r16, pos_y
	call copia_char	

    ; Restaura los registros guardados
	fine:
	pop r17
	pop r16
    ret                    ; Retorna de la rutina 'mover'
izq:
	push r16
	push r17
    ; Llama a una rutina que borra el contenido del display actual si es necesario
	
;copia una imagen de fondo en el panel
	ldi		ZL,	low(Menu<<1)			;apunto Z a la imagen de fondo a copiar y luego efectivamente la copia.
	ldi		ZH,	high(Menu<<1)
	call	copia_img	

	    ; Carga el carácter o imagen a mostrar en la nueva posición
    ; (Asegúrate de que copia_char pone el contenido deseado en la nueva posición)

	; ESTO NO FUNCIONA. NO VEO ERROR EN LA LOGICA PERO NO FUNCIONA
	dec pos_x
	dec pos_x 
	mov r17, pos_x
	mov r16, pos_y

	cpi pos_x, 3
	brlo topp

	;ldi r17, 21
	;mov pos_x, r17
	;mov r16, pos_y
    call copia_char        ; Copia el carácter actual en la nueva posición
	rjmp fin
	
	topp:
	ldi r17, 24
	mov pos_x, r17
	mov r16, pos_y
	call copia_char	

    ; Restaura los registros guardados
	fin:
	pop r17
	pop r16
    ret                    ; Retorna de la rutina 'mover'


delay:
	push r18
	push r19
	push r20
    ldi  r18, 10
    ldi  r19, 10
    ldi  r20, 110
L1: dec  r20
    brne L1
    dec  r19
    brne L1
    dec  r18
    brne L1
	pop r20
	pop r19
	pop r18
	ret

