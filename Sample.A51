;************************************************************************
; definitions for internal data memory allocations

rr0     ds      1       ;bank 0 registers
rr1     ds      1
rr2     ds      1
rr3     ds      1
rr4     ds      1
rr5     ds      1
rr6     ds      1
rr7     ds      1

;;;; serial control variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
rx_buf  ds      1               ; serial receive buffer

;;;; subroutine parameter passing variables ;;;;;;;;;;;;;;;;;
par1    ds      1       ; parameter 1
par2    ds      1       ; parameter 2
par3    ds      1       ; parameter 3
par4    ds      1       ; parameter 4
par5    ds      1       ; parameter 5
par6    ds      1       ; parameter 6
par7    ds      1       ; parameter 7
par8    ds      1       ; parameter 8

;;;; temporary variables used within subroutines ;;;;;;;;;;;;;;;;;
t1      ds      1
t2      ds      1
t3      ds      1
t4      ds      1
t5      ds      1
t6      ds      1
t7      ds      1
t8      ds      1

;;;; bit addressable memory locations (start at ram address 20h)
        dataorg 20h
sstat   ds      1
txempty equ     20h.0   ; bit 0 = 0 -> transmit buffer empty (char sent)
                        ;       = 1 -> transmit buffer full
rxempty equ     20h.1   ; bit 1 = 0 -> receive buffer empty
                        ;       = 1 -> receive buffer full (char received)

;;;; the stack is last ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
the_stack   ds      1
cpu_stack   equ     the_stack-1 ;top of stack ( equal to the
                                ; last entry in this table)

;************************************************************************
; definitions for symbols

cr      equ     13
lf      equ     10
eom     equ     0
eos     equ     0


;************************************************************************
; program start and interrupt vector code (first actual code)

        org     0
rst:    ljmp    start           ; power on reset and reset vector

        org     rst+03h
ext_int_0:                      ;external interrupt 0
        reti

        org     rst+0bh
timer_0:
        ljmp    tsr0            ;timer 0 interrupt service routine
        reti

        org     rst+013h
                                ;external interrupt 1
        reti

        org     rst+01bh
                                ;timer 1 interrupt
        reti

        org     rst+023h
                                ;transmit and receive interrupt
        ljmp    rs232

;************************************************************************
; start of program code
start:  mov     sp,#cpu_stack       ; initialize stack pointer

        call    init

        mov     par1,#255
        mov     par2,#255
        mov     par3,#255
        mov     par4,#255

st1:    call    mul16x16
        jmp     st1


;************************************************************************
result: db      cr, 'C: ', eom
sput_result:
        push    rr3

        mov     dptr,#result
        call    send_code_string

        mov     a,par1

        mov     r3,#3   ; 3 digits
sp1:    mov     b,#10
        div     ab
        push    b
        djnz    r3,sp1

        mov     r3,#3
sp2:    pop     acc
        add     a,#'0'
        mov     par1,a
        call    sputch
        djnz    r3,sp2

        pop     rr3
        ret

;************************************************************************
; starts an A/d conversion, waits for completeion, then returns
; the result in par1
read_adc:
        push    acc
        push    dpl
        push    dph

;        mov     dptr,#0fff0h
        clr     p1.7            ; set cs on AD0804 active (low)
        movx    @dptr,a         ; token write to strobe wr line on converter
radc1:  jb      p3.2,radc1      ; wait for end of conversion
        movx    a,@dptr         ; read converted value
        mov     par1,a          ; copy to return parameter
        setb    p1.7            ; set cs on AD0804 inactive (high)

        pop     dph
        pop     dpl
        pop     acc
        ret

;*************************************************************************
; serial port control subroutines
;*************************************************************************
; initialize and enable the serial port for 19.2k bps
;    - start bit (0), 8 data (lsb first), stop (1)
;
; bps rate is derived from the external crystal, th1 and smod (msb of pcon)
; th1 (timer reload value) is determined as follows:
;
;                  |     xtal    |
; th1 = 256 - round|-------------|   ; for smod=0 and scon=50h
;                  |(bps)(32)(12)|
;
; where: xtal is the crystal frequency.
;        bps is the desired bits per second rate.
;        th1 is the timer preload value.
;
; the bps rate is doubled if the smod bit in pcon is set (smod = 1).
; in which case the equation is
;
;                  |     xtal    |
; th1 = 256 - round|-------------|   ; for smod=1 and scon=50h
;                  |(bps)(16)(12)|
;
serial_init:
        mov     th1,#234        ; 2400bps @10.0MHz, smode=1

        mov     a,pcon          ; set smod = 1 to double bps rate
        orl     a,#80h
        mov     pcon,a

;        mov     scon,#01010000b ; default mode 1, 8 bit variable clock rate
        mov     scon,#11011000b ; default mode 3, 9 bit variable clock rate
                                ; TB8 = 1 (adds an extra TxD stop bit)

        mov     a,tcon
        orl     a,#01000000b    ; set tr1 bit - start baud timer
        mov     tcon,a

        mov     tmod,#021h      ; timer control
                                ; timer 0 16 bit timer
                                ; timer 1 8 bit autoload timer (baud clk)

        mov     ie,#10010000b   ; init interrupt enable register
;                          ^      disable int0
;                         ^       enable timer0 interrupt
;                        ^        disable int1
;                       ^         disable timer1 interrupt
;                      ^          enable serial port interrupt
;                    ^^           not used. must be 0.
;                   ^             enable interrupts (ea=1)

        clr     txempty         ; clear serial status bits
        clr     rxempty

        ret

;************************************************************************
; serial port interrupt handler.
rs232:  push    acc             ; save all registers to be used
        push    psw
        push    dpl
        push    dph

ck_port:
        jb      ri,rx_data              ; RxD interrupt occured
        jb      ti,tx_data              ; TxD interrupt occured

; if RxD and TxD interrupts not pending restore registers and return to
;  interrupted routine.
exit_rs232:
        pop     dph
        pop     dpl
        pop     psw
        pop     acc
        reti

;--------------------------------------------------------

tx_data:
        clr     ti              ; clear TxD interrupt bit
        clr     txempty
        jmp     ck_port

;--------------------------------------------------------

rx_data:
        clr     ri              ; clear RxD interrupt flag
        mov     rx_buf,sbuf     ; save received byte
        setb    rxempty         ; indicate byte received
        jmp     ck_port         ; exit and wait for next byte


;************************************************************************
; wait for tx buffer to be empty (txempty == 0)
; then place byte in par1 into sbuf.
sputch:
        push    acc

sputlp: jb      txempty,sputlp  ; wait for previous byte to be sent

        mov     sbuf,par1       ; place byte in buffer
        setb    txempty         ; set flag to indicate byte in buffer
                                ;  and not yet sent.
        pop     acc
        ret

;************************************************************************
send_code_string:
        push    acc
        push    par1

send_loop:
        mov     a,#0
        movc    a,@a+dptr       ; get first char of string
        jz      scs_end         ; test for null terminator
        mov     par1,a
        call    sputch
        inc     dptr
        jmp     send_loop

scs_end:
        pop     par1
        pop     acc
        ret

;************************************************************************
ss_menu: db     13,10
         db     '?    - Displays this help message.',13,10
         db     eom
display_menu:
        push    dpl
        push    dph

        mov     dptr,#ss_menu   ; point to message in code memory
        call    send_code_string

        pop     dph
        pop     dpl
        ret

;************************************************************************
prompt: db      13,10
        db      'Command>'
        db      eom
display_prompt:
        push    dpl
        push    dph

        mov     dptr,#prompt            ; point to message in code memory
        call    send_code_string

        pop     dph
        pop     dpl
        ret

;************************************************************************
; multiply two 16-bit values
;   par1:par2 * par3:par4 => par5:par6:par7:par8
;
; let
;   m = par1
;   n = par2
;   o = par3
;   p = par4
;
;       np        - np = par2 * par4
;      mp.        - mp = par1 * par4
;      no.        - no = par2 * par3
;   + mo..        - mo = par1 * par3
;    -----
;     5678        - par5:par6:par7:par8
;
mul16x16:
; np
        mov     a,par2          ; a = par2
        mov     b,par4          ; b = par4
        mul     ab              ; ab = a * b
        mov     par8,a          ; par8 = a
        mov     par7,b          ; par7 = b

; mp
        mov     a,par1          ; a = par1
        mov     b,par4          ; b = par4
        mul     ab              ; ab = a * b
        add     a,par7          ; par7 = par7 + a
        mov     par7,a
        mov     a,b             ; par6 = b + cy
        addc    a,#0
        mov     par6,a

; no
        mov     a,par2          ; a = par2
        mov     b,par3          ; b = par3
        mul     ab              ; ab = a * b
        add     a,par7          ; par7 = par7 + a
        mov     par7,a
        mov     a,b             ; par6 = par6 + b + cy
        addc    a,par6
        mov     par6,a
        clr     a               ; par5 = cy
        rlc     a
        mov     par5,a

; mo
        mov     a,par1          ; a = par1
        mov     b,par3          ; b = par3
        mul     ab              ; ab = a * b
        add     a,par6          ; par6 = par6 + a
        mov     par6,a
        mov     a,b             ; par5 = par5 + b + cy
        addc    a,par5
        mov     par5,a

        ret

;************************************************************************
init:
        call    serial_init
        call    init_t0

        ret

;************************************************************************
; initialize timer 0 for 16-bit count and enable timer interrupt
; to drive the sampling subroutines
init_t0:
        mov     th0,#0          ; clear count to insure it doesn't
        mov     tl0,#0          ;  intterupt before we are ready

        mov     a,tmod          ; copy to acc for modification
        anl     a,#0f0h         ; clear lower nibble
        orl     a,#001          ; select mode 1 (16-bit) counter
        mov     tmod,a          ; save modified value back

        setb    tcon.4          ; set TR0 to enable timer 0 counting
        setb    ie.1            ; set ET0 to Enable Timer 0 interrupt
        
        ret


;************************************************************************
tsr0:

        reti


end

;************************************************************************
; initialize timer 0 for 16-bit count and enable timer interrupt
; to drive the sampling subroutines
init_t0:
        mov     th0,#0          ; clear count to insure it doesn't
        mov     tl0,#0          ;  intterupt before we are ready

        mov     a,tmod          ; copy to acc for modification
        anl     a,#0f0h         ; clear lower nibble
        orl     a,#001          ; select mode 1 (16-bit) counter
        mov     tmod,a          ; save modified value back

        setb    tcon.4          ; set TR0 to enable timer 0 counting
        setb    ie.1            ; set ET0 to Enable Timer 0 interrupt
        
        ret


;************************************************************************
tsr0:

        reti


end

;************************************************************************
; initialize timer 0 for 16-bit count and enable timer interrupt
; to drive the sampling subroutines
init_t0:
        mov     th0,#0          ; clear count to insure it doesn't
        mov     tl0,#0          ;  intterupt before we are ready

        mov     a,tmod          ; copy to acc for modification
        anl     a,#0f0h         ; clear lower nibble
        orl     a,#001          ; select mode 1 (16-bit) counter
        mov     tmod,a          ; save modified value back

        setb    tcon.4          ; set TR0 to enable timer 0 counting
        setb    ie.1            ; set ET0 to Enable Timer 0 interrupt
        
        ret


;************************************************************************
tsr0:

        reti


end

;************************************************************************
; initialize timer 0 for 16-bit count and enable timer interrupt
; to drive the sampling subroutines
init_t0:
        mov     th0,#0          ; clear count to insure it doesn't
        mov     tl0,#0          ;  intterupt before we are ready

        mov     a,tmod          ; copy to acc for modification
        anl     a,#0f0h         ; clear lower nibble
        orl     a,#001          ; select mode 1 (16-bit) counter
        mov     tmod,a          ; save modified value back

        setb    tcon.4          ; set TR0 to enable timer 0 counting
        setb    ie.1            ; set ET0 to Enable Timer 0 interrupt
        
        ret


;************************************************************************
tsr0:

        reti


end

;************************************************************************
; initialize timer 0 for 16-bit count and enable timer interrupt
; to drive the sampling subroutines
init_t0:
        mov     th0,#0          ; clear count to insure it doesn't
        mov     tl0,#0          ;  intterupt before we are ready

        mov     a,tmod          ; copy to acc for modification
        anl     a,#0f0h         ; clear lower nibble
        orl     a,#001          ; select mode 1 (16-bit) counter
        mov     tmod,a          ; save modified value back

        setb    tcon.4          ; set TR0 to enable timer 0 counting
        setb    ie.1            ; set ET0 to Enable Timer 0 interrupt
        
        ret


;************************************************************************
tsr0:

        reti


end

;************************************************************************
; initialize timer 0 for 16-bit count and enable timer interrupt
; to drive the sampling subroutines
init_t0:
        mov     th0,#0          ; clear count to insure it doesn't
        mov     tl0,#0          ;  intterupt before we are ready

        mov     a,tmod          ; copy to acc for modification
        anl     a,#0f0h         ; clear lower nibble
        orl     a,#001          ; select mode 1 (16-bit) counter
        mov     tmod,a          ; save modified value back

        setb    tcon.4          ; set TR0 to enable timer 0 counting
        setb    ie.1            ; set ET0 to Enable Timer 0 interrupt
        
        ret


;************************************************************************
tsr0:

        reti


end

 

thatdh adsh aydatjyastd ujasdasd
dasdasdasdasda
dasdasdasdasd
adasdasdasdasd
asdasdasdasdas
asdsadsadsadasd
adsasdsadsadasdas
adsadsadsadasdsad
asdsadsadasdasdsaad
asdasdsadasdsad
asdsadasdsadsdsadsdasd
asdasdsadsadasdas
sadsadasdsadasdasdsaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaa