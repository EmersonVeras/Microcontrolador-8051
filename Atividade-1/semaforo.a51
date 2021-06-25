org   0000h      ;Origem no endereço 00h de memória 
 
    MOV DPTR,#TABELA ;Move DPRT recebe o valor de DATA
 
 INICIO:      MOV R0,#0    
    MOV A,#0    ;Move a constante zero para o acumulador
 
 NOVO :   
    MOV A,R0    ;Move o conteúdo de R3 para o acumulador
    MOVC A,@A+DPTR  ;Move o byte relativo ao DPTR somado com o valor do acumulador para o acumulador
    JZ INICIO    ;Salto para subrotina REPETE
    MOV P1,A     ;Move o conteúdo do Acumulador para o PORT 1
    ACALL T1s    ;Chama subrotina de tempo (1 segundo)
    INC R0     ;Incrementa o valor que está no R3 (+1)
    AJMP NOVO    ;Salta para o inicio da subrotina NOVO
 
 T1s :      MOV R1,#8    ;Move a constante 8 para o registrador R2
 
 REP:       ACALL TEMPO   ;Chama a subrotina TEMPO
    DJNZ R1,REP    ;Decrementa o valor R2, se não for igual a zero salta para a subrotina REP
    RET      ;Retorno
 
 TEMPO:   MOV R3,#255   ;Move a constante 255 para o registrador zero
 
 TEMPO2:   MOV R2,#255   ;Move a constante 255 para o registrador 1
 
 LOOP:   DJNZ R2,LOOP   ;Decrementa o valor R1, se não for igual a zero salta para a subrotina AQUI 
    DJNZ R3,TEMPO2   ;Decrementa o valor R0, se não for igual a zero salta para a subrotina VOLTE
    RET       ;retorna
    
 TABELA:  DB 05EH
    DB 05DH
    DB 0B3H
    DB 0ABH
   
 
       END