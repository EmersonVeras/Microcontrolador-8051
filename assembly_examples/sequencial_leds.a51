org 00h

inicio: 
        MOV DPTR, #tabela
        MOV R7, #09h

main:
        MOV A, #00h ;declarando que o acumulador é inicialmente igual a zero
        MOVC A, @A+DPTR ; Acumulador recebe o primeiro valor contido na tabela 80h
        MOV P2, A ;Declarando que o P2 recebe o valor do acumulador        
    
        DJNZ R7, delay500ms
        JMP inicio
        
        
        

incrementa_tabela:
        INC DPTR ;Incrementa a posição da tabela 
        ajmp main ;Salta para subrotina inicial
        
        
        
delay500ms:

        mov r1, #0fah ;move 250 decimal para o registrador 1

aux1:

        mov R2,#0f9h
        nop
        nop
        nop
        nop
        nop
        nop

aux2:
        nop
        nop
        nop
        nop
        nop
        nop
        
        djnz r2, aux2
        djnz r1, aux1
        
        ajmp incrementa_tabela

tabela:
db 80h, 40h, 20h, 10h, 8h, 4h, 2h, 1h, 00h

end