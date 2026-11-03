; =====================================================================
; LOADER_RAIN.SYS - carica ntpplayer + rain.ntp e li fa suonare
; Target: Merlin32, Apple IIgs
;
; "Ramo laterale" del progetto tunnel: prova solo la parte audio,
; separata dalla grafica, come richiesto.
;
; COSA FA:
;   1) Carica il file NTPPLAYER (binario, 34672 byte) in banco $0F,
;      offset $0000 - esattamente dove il player si aspetta di stare
;      (il suo sorgente dichiara "org $0f0000").
;   2) Carica il file RAIN.NTP (88679 byte, > 64K) a partire da banco
;      $0D, offset $0000 - i primi 65536 byte riempiono ESATTAMENTE
;      il banco $0D, i restanti 23143 byte proseguono in banco $0E.
;   3) Chiama NTPprepare (JSL, banco $0F) passandogli X=offset,
;      Y=banco del file appena caricato, poi NTPplay per avviarlo.
;      Da li' in poi il player suona da solo via interrupt: il nostro
;      loop principale si limita ad aspettare ESC per fermarsi.
;
; PERCHE' SERVE UN BUFFER DI APPOGGIO: ProDOS 8 (MLI) legge sempre in
; un indirizzo raggiungibile a 16 bit (banco $00) - non puo' scrivere
; direttamente in banchi come $0D/$0F. Quindi si legge a blocchi di
; 4096 byte in un buffer di appoggio in banco 0, poi si copiano nel
; banco giusto con l'istruzione nativa MVN (block-move). 4096 divide
; 65536 esattamente: il passaggio $0D->$0E cade sempre su un confine
; di blocco pulito, niente bisogno di aritmetica a 32 bit sul conteggio
; byte.
;
; ATTENZIONE NOMI FILE: assumo che sul disco i file si chiamino
; esattamente NTPPLAYER e RAIN.NTP (prefisso ProDOS corrente). Se sul
; tuo disco hanno un altro nome, modifica PATH_PLAYER/PATH_RAIN qui
; sotto (byte di lunghezza + testo, come vuole ProDOS).
;
; ATTENZIONE DIMENSIONI: le dimensioni dei due file sono hardcoded qui
; sotto (NTPPLAYER_SIZE, RAIN_SIZE) invece di essere lette con una
; GET_EOF - scelta deliberata per tenere questa prima versione il piu'
; semplice possibile. Se sostituisci i file con altri di dimensione
; diversa, questi due valori vanno aggiornati a mano.
; =====================================================================

            DSK   LOADER_RAIN.SYS
            TYP   $FF
            ORG   $2000

; ---------------------------------------------------------------------
; Chiamate al player NinjaTracker+ (copiate dalla documentazione nel
; sorgente ninjatrackerplus.s - vanno chiamate con JSL, registri a 16
; bit)
; ---------------------------------------------------------------------
NinjaTrackerPlus        EQU   $0F0000
NTPprepare              EQU   NinjaTrackerPlus
NTPplay                 EQU   NinjaTrackerPlus+3
NTPstop                 EQU   NinjaTrackerPlus+6

; ---------------------------------------------------------------------
; Direct Page (programma a se stante, nessun conflitto con tl4x.s)
; ---------------------------------------------------------------------
REF_NUM        EQU   $80        ; reference number del file aperto
BYTES_LEFT     EQU   $82        ; byte ancora da leggere in QUESTA fase
CHUNK_NOW      EQU   $84        ; byte richiesti in questa lettura
DEST_BANK_VAR  EQU   $86        ; banco di destinazione corrente
DEST_OFF       EQU   $88        ; offset corrente nel banco destinazione

CHUNK_SIZE     EQU   4096       ; divide 65536 esattamente (16 blocchi)
NTPPLAYER_SIZE EQU   34672
RAIN_FULL_BANK EQU   65536      ; = 16 blocchi da 4096, riempie $0D esatto
RAIN_REMAINDER EQU   23143      ; = 88679 - 65536, va in banco $0E

IO_BUFFER      EQU   $6000      ; buffer da 1024 byte per l'I/O ProDOS
STAGE_BUF      EQU   $6400      ; buffer di appoggio, 4096 byte

; ---------------------------------------------------------------------
; MAIN
; ---------------------------------------------------------------------
START       SEI
            CLC
            XCE                    ; modalita' nativa
            REP   #$30
            MX    %00
            LDA   #$0000
            TCD                    ; Direct Page = $0000

            PHK
            PLB
            PEA   $0000
            PLB
            PLB                    ; DBR = $00 (stesso trucco di tl4x.s)

            JSR   LOAD_NTPPLAYER
            BCC   :start_ok1        ; branch corto sicuro
            JMP   LOAD_FAIL
:start_ok1
            JSR   LOAD_RAIN
            BCC   :start_ok2
            JMP   LOAD_FAIL
:start_ok2
            ; --- avvia il player ---
            REP   #$30
            MX    %00
            LDX   #$0000           ; offset del file rain.ntp: inizio banco $0D
            LDY   #$000D           ; banco $0D
            LDA   #$0000           ; 0 = normale (2 oscillatori/traccia)
            JSL   NTPprepare
            BCS   LOAD_FAIL        ; A contiene il codice di errore NTP (1/2/3)

            LDA   #$0000           ; 0 = ripeti il brano in loop
            JSL   NTPplay

; ---------------------------------------------------------------------
; MAIN LOOP: il player suona da solo via interrupt. Aspettiamo ESC.
; ---------------------------------------------------------------------
MAIN_LOOP   LDA   $C000
            AND   #$0080
            BEQ   MAIN_LOOP
            STA   $C010
            LDA   $C000
            AND   #$007F
            CMP   #$001B
            BNE   MAIN_LOOP

            JSL   NTPstop
            BRA   QUIT

LOAD_FAIL   ; per ora nessuna gestione elaborata: resta qui in loop.
            ; Se arrivi in monitor con PC bloccato su questa riga,
            ; l'errore e' nel caricamento file o nell'header NTP
            ; (controlla A per il codice errore appena PRIMA di qui).
            BRA   LOAD_FAIL

; ---------------------------------------------------------------------
; QUIT: torna a ProDOS 8 BASIC (stesso schema di EXIT_DEMO in tl4x.s)
; ---------------------------------------------------------------------
QUIT        REP   #$30
            MX    %00
            LDA   #$0000
            TCD
            SEP   #$20
            MX    %10
            LDA   #$00
            PHA
            PLB
            SEC
            XCE
            JSR   $BF00
            DFB   $65
            DA    QUIT_PARMS

QUIT_PARMS  DFB   $04
            DFB   $00
            DA    $0000
            DFB   $00
            DA    $0000

; ---------------------------------------------------------------------
; LOAD_NTPPLAYER: apre NTPPLAYER, lo carica tutto in banco $0F
; (34672 byte, sta in un banco solo), chiude il file.
; Esce con carry=0 se ok, carry=1 in caso di errore MLI.
; ---------------------------------------------------------------------
LOAD_NTPPLAYER
            REP   #$30
            MX    %00
            LDA   #PATH_PLAYER
            STA   OPEN_PATHPTR
            JSR   MLI_OPEN
            BCS   :np_err

            LDA   #NTPPLAYER_SIZE
            STA   BYTES_LEFT
            LDA   #$0F
            STA   DEST_BANK_VAR
            STZ   DEST_OFF
            JSR   READ_INTO_BANK
            BCS   :np_err

            JSR   MLI_CLOSE
            CLC
            RTS
:np_err     SEC
            RTS

; ---------------------------------------------------------------------
; LOAD_RAIN: apre RAIN.NTP, carica i primi 65536 byte in banco $0D
; (esattamente pieno), poi i restanti 23143 byte in banco $0E, chiude
; il file. Esce con carry=0 se ok, carry=1 in caso di errore MLI.
; ---------------------------------------------------------------------
LOAD_RAIN   REP   #$30
            MX    %00
            LDA   #PATH_RAIN
            STA   OPEN_PATHPTR
            JSR   MLI_OPEN
            BCC   :lr_ok1           ; branch corto sicuro
            JMP   :lr_err
:lr_ok1
            ; --- fase 1: banco $0D, esattamente pieno (16 blocchi) ---
            LDA   #$0D
            STA   DEST_BANK_VAR
            STZ   DEST_OFF
            LDX   #16              ; 16 blocchi da 4096 = 65536 esatti
:lr_bank_d  LDA   #CHUNK_SIZE
            STA   CHUNK_NOW
            PHX
            JSR   READ_CHUNK_AND_COPY
            PLX
            BCC   :lr_ok2
            JMP   :lr_err
:lr_ok2
            DEX
            BNE   :lr_bank_d

            ; --- fase 2: banco $0E, resto (23143 byte) ---
            LDA   #$0E
            STA   DEST_BANK_VAR
            STZ   DEST_OFF
            LDA   #RAIN_REMAINDER
            STA   BYTES_LEFT
            JSR   READ_INTO_BANK
            BCC   :lr_ok3
            JMP   :lr_err
:lr_ok3
            JSR   MLI_CLOSE
            CLC
            RTS
:lr_err     SEC
            RTS

; ---------------------------------------------------------------------
; READ_INTO_BANK: legge BYTES_LEFT byte (< 65536) in blocchi da
; CHUNK_SIZE dentro DEST_BANK_VAR, a partire da DEST_OFF. Aggiorna
; DEST_OFF man mano. Assume che il file sia gia' aperto (REF_NUM
; valido). Esce con carry=0 se ok, carry=1 in caso di errore MLI.
; ---------------------------------------------------------------------
READ_INTO_BANK
            REP   #$30
            MX    %00
:rib_loop   LDA   BYTES_LEFT
            BEQ   :rib_done
            CMP   #CHUNK_SIZE
            BCC   :rib_last
            LDA   #CHUNK_SIZE
:rib_last   STA   CHUNK_NOW
            JSR   READ_CHUNK_AND_COPY
            BCS   :rib_err
            LDA   BYTES_LEFT
            SEC
            SBC   CHUNK_NOW
            STA   BYTES_LEFT
            BRA   :rib_loop
:rib_done   CLC
            RTS
:rib_err    SEC
            RTS

; ---------------------------------------------------------------------
; READ_CHUNK_AND_COPY: legge CHUNK_NOW byte (<=CHUNK_SIZE) dal file
; aperto dentro STAGE_BUF (banco $00), poi li copia con MVN in
; DEST_BANK_VAR:DEST_OFF; avanza DEST_OFF di CHUNK_NOW.
; Esce con carry=0 se ok, carry=1 in caso di errore MLI.
; ---------------------------------------------------------------------
READ_CHUNK_AND_COPY
            REP   #$30
            MX    %00
            LDA   CHUNK_NOW
            STA   READ_COUNT
            JSR   MLI_READ
            BCC   :rc_ok            ; branch corto sicuro
            JMP   :rc_err
:rc_ok
            ; --- copia STAGE_BUF -> DEST_BANK_VAR:DEST_OFF (MVN) ---
            SEP   #$20
            MX    %10
            LDA   DEST_BANK_VAR
            STA   MVN_DEST_PATCH   ; patch del banco destinazione in MVN
            REP   #$20
            MX    %00

            LDX   #STAGE_BUF
            LDY   DEST_OFF
            LDA   CHUNK_NOW
            SEC
            SBC   #1               ; MVN vuole (conteggio-1)
MVN_INSTR   MVN   $00,$00          ; sorgente banco 0; dest patchato sopra
MVN_DEST_PATCH EQU MVN_INSTR+1     ; byte destinazione nel codice oggetto

            PHK
            PLB                    ; MVN ha cambiato DBR: ripristina banco $00

            REP   #$30
            MX    %00
            LDA   DEST_OFF
            CLC
            ADC   CHUNK_NOW
            STA   DEST_OFF

            CLC
            RTS
:rc_err     SEC
            RTS

; ---------------------------------------------------------------------
; Helper MLI (modalita' emulazione per la chiamata, poi si torna in
; nativa - stesso schema gia' usato in EXIT_DEMO di tl4x.s)
; ---------------------------------------------------------------------
MLI_OPEN    SEC
            XCE
            JSR   $BF00
            DFB   $C8
            DA    OPEN_PARAMS
            BCS   :mo_err
            CLC
            XCE
            REP   #$30
            MX    %00
            LDA   OPEN_REFNUM
            AND   #$00FF
            STA   REF_NUM
            STA   READ_REFNUM
            STA   CLOSE_REFNUM
            CLC
            RTS
:mo_err     CLC
            XCE
            REP   #$30
            MX    %00
            SEC
            RTS

MLI_READ    SEC
            XCE
            JSR   $BF00
            DFB   $CA
            DA    READ_PARAMS
            BCS   :mr_err
            CLC
            XCE
            REP   #$30
            MX    %00
            CLC
            RTS
:mr_err     CLC
            XCE
            REP   #$30
            MX    %00
            SEC
            RTS

MLI_CLOSE   SEC
            XCE
            JSR   $BF00
            DFB   $CC
            DA    CLOSE_PARAMS
            CLC
            XCE
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; Nomi file (byte di lunghezza + testo, come vuole ProDOS). Modifica
; qui se sul disco si chiamano diversamente.
; ---------------------------------------------------------------------
PATH_PLAYER DFB   9
            ASC   'NTPPLAYER'
PATH_RAIN   DFB   8
            ASC   'RAIN.NTP'

; ---------------------------------------------------------------------
; Blocchi parametri MLI
; ---------------------------------------------------------------------
OPEN_PARAMS    DFB   3
OPEN_PATHPTR   DA    0
               DA    IO_BUFFER
OPEN_REFNUM    DFB   0

READ_PARAMS    DFB   4
READ_REFNUM    DFB   0
               DA    STAGE_BUF
READ_COUNT     DA    0
               DA    0            ; trans_count (output, non usato)

CLOSE_PARAMS   DFB   1
CLOSE_REFNUM   DFB   0

            END
