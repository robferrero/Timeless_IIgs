*-----------------------------------------------------------
* SPLASH_FADE.S - Apple IIgs SHR splash: loader + palette fade
* Assembler: Merlin32      Output: ProDOS SYS file ($FF)
*
* Reusable routines (call in emulation mode, ProDOS 8, DP=0, DBR=0):
*   LOAD_SPLASH  load picture into $E1:2000, hide it (black palettes)
*                  out: C=0 ok / C=1 error, A = MLI error code
*   FADE_IN      turn SHR on and fade palettes up from black
*   FADE_OUT     fade palettes down to black
*   SPLASH_OFF   restore the previous $C029 value (text mode again)
*
* The picture file is a raw 32768-byte SHR PIC ($C1/$0000).
* The palettes ($E1:9E00-9FFF, 16 x 16 colors) are saved in TARGET,
* zeroed on screen, and rebuilt step by step by FADE_STEP.
*
* To use the routines in the demo: copy everything from LOAD_SPLASH
* down to the end, drop TYP/DSK/ORG and the START driver, and keep
* the EQUs. Buffers must not overlap anything else in bank 0.
*-----------------------------------------------------------

            TYP $FF                 ; ProDOS SYS
            DSK SPLASHFADE.SYS
            ORG $2000
            MX  %11                 ; SYS programs start in emulation mode

MLI         EQU $BF00
KEY         EQU $C000
STROBE      EQU $C010
VBL         EQU $C019
NEWVIDEO    EQU $C029
HOME        EQU $FC58

* Bank-0 buffers (adjust to your memory map)
IOBUF       EQU $4000               ; 1024 bytes, page aligned (for OPEN)
CHUNK       EQU $4400               ; 4096-byte read buffer ($4400-$53FF)
FADETAB     EQU $5400               ; 256-byte fade table      ($5400-$54FF)
TARGET      EQU $5500               ; 512 bytes: target palettes ($5500-$56FF)

CHUNKSIZE   EQU $1000
NCHUNKS     EQU 8                   ; 8 * 4096 = 32768
SHRBASE     EQU $2000               ; destination offset in bank $E1
FADE_FRAMES EQU 3                   ; video frames per fade step (16 steps)

*-----------------------------------------------------------
* Test driver: load, fade in, wait a key, fade out, quit
*-----------------------------------------------------------
START
            JSR LOAD_SPLASH
            BCS :quit               ; error code is in ERRCODE
            JSR FADE_IN
            STA STROBE
:wait       LDA KEY
            BPL :wait
            STA STROBE
            JSR FADE_OUT
            JSR SPLASH_OFF
            JSR HOME
:quit       JSR MLI                 ; QUIT to the ProDOS launcher
            DFB $65
            DA  QUIT_PARMS
            BRK $00                 ; never reached

*-----------------------------------------------------------
* LOAD_SPLASH
*-----------------------------------------------------------
LOAD_SPLASH
            LDA NEWVIDEO            ; remember the current video mode
            STA SAVEVID
            ORA #%01000000          ; linear SHR memory map BEFORE writing
            STA NEWVIDEO            ; to $E1 (otherwise 1 byte every 2)

            JSR BUILD_TABLE

            JSR MLI                 ; OPEN
            DFB $C8
            DA  OPEN_PARMS
            BCS :err

            LDA OPEN_REFNUM         ; copy refnum into READ/CLOSE blocks
            STA READ_REFNUM
            STA CLOSE_REFNUM

            LDA #<SHRBASE
            STA DEST
            LDA #>SHRBASE
            STA DEST+1
            LDA #NCHUNKS
            STA CHUNKS

:loop       JSR MLI                 ; READ 4096 bytes into CHUNK
            DFB $CA
            DA  READ_PARMS
            BCS :errclose

            JSR COPY_CHUNK          ; bank 0 -> $E1:DEST
            DEC CHUNKS
            BNE :loop

            JSR MLI                 ; CLOSE
            DFB $CC
            DA  CLOSE_PARMS
            BCS :err

            JSR PAL_SAVE_BLACK      ; palettes -> TARGET, screen palettes -> 0
            CLC
            RTS

:errclose   PHA
            JSR MLI
            DFB $CC
            DA  CLOSE_PARMS
            PLA
:err        STA ERRCODE
            SEC
            RTS

*-----------------------------------------------------------
* FADE_IN / FADE_OUT / SPLASH_OFF
*-----------------------------------------------------------
FADE_IN
            LDA NEWVIDEO            ; SHR on + linear (screen is black)
            ORA #%11000000
            STA NEWVIDEO
            LDA #0
            STA STEP
:f          JSR FADE_STEP
            JSR WAIT_FRAMES
            INC STEP
            LDA STEP
            CMP #16
            BNE :f                  ; last step applied = 15 = full colors
            RTS

FADE_OUT
            LDA #15
            STA STEP
:f          JSR FADE_STEP
            JSR WAIT_FRAMES
            DEC STEP
            BPL :f                  ; last step applied = 0 = black
            RTS

SPLASH_OFF
            LDA SAVEVID
            STA NEWVIDEO
            RTS

*-----------------------------------------------------------
* Wait FADE_FRAMES video frames. WAIT_EDGE waits for any change of
* the VBL bit, so it does not depend on the polarity of $C019;
* two edges = one frame.
*-----------------------------------------------------------
WAIT_FRAMES
            LDX #FADE_FRAMES
:w          JSR WAIT_EDGE
            JSR WAIT_EDGE
            DEX
            BNE :w
            RTS

WAIT_EDGE
            LDA VBL
            AND #$80
            STA TMP
:a          LDA VBL
            AND #$80
            CMP TMP
            BEQ :a
            RTS

*-----------------------------------------------------------
* BUILD_TABLE: FADETAB[s*16+c] = (c*s+7)/15  for s,c = 0..15
* (rounded, so s=15 gives exactly c and s=0 gives 0). 8-bit only:
* the maximum intermediate value is 15*15+7 = 232.
*-----------------------------------------------------------
BUILD_TABLE
            LDX #0                  ; table index
            LDA #0
            STA SCAL
:s          LDA #0
            STA CCMP
:c          LDA #7                  ; rounding
            LDY CCMP
            BEQ :div                ; c = 0
:mul        CLC
            ADC SCAL
            DEY
            BNE :mul                ; A = 7 + c*s
:div        LDY #0
:dl         CMP #15
            BCC :done
            SBC #15
            INY
            BRA :dl
:done       TYA                     ; quotient
            STA FADETAB,X
            INX
            INC CCMP
            LDA CCMP
            CMP #16
            BNE :c
            INC SCAL
            LDA SCAL
            CMP #16
            BNE :s
            RTS

*-----------------------------------------------------------
* PAL_SAVE_BLACK: copy the 512 palette bytes at $E1:9E00 to TARGET,
* then clear them on screen. Native mode inside this routine only.
*-----------------------------------------------------------
PAL_SAVE_BLACK
            PHP
            SEI
            CLC
            XCE                     ; native mode
            REP #$30
            MX  %00
            LDX #0
:p          DFB $BF,$00,$9E,$E1     ; LDA $E19E00,X   (16-bit)
            STA TARGET,X
            LDA #0
            DFB $9F,$00,$9E,$E1     ; STA $E19E00,X   (16-bit)
            INX
            INX
            CPX #512
            BCC :p
            SEP #$30
            MX  %11
            SEC
            XCE                     ; back to emulation mode
            PLP
            RTS

*-----------------------------------------------------------
* FADE_STEP: write the palettes scaled to level STEP (0..15).
* Color word = $0RGB: low byte = G<<4|B, high byte = R.
* A is 8-bit, X/Y are 16-bit here (MX %10); B (high byte of C) is
* kept at 0 so that TAY gives a clean 16-bit index.
*-----------------------------------------------------------
FADE_STEP
            PHP
            SEI
            CLC
            XCE                     ; native mode
            REP #$10                ; X,Y 16-bit; A stays 8-bit
            MX  %10
            LDA #0
            XBA                     ; B = 0
            LDA STEP
            ASL
            ASL
            ASL
            ASL
            STA BASE                ; BASE = STEP * 16
            LDX #0
:c          LDA TARGET,X            ; low byte = G<<4 | B
            PHA
            AND #$0F                ; B
            CLC
            ADC BASE
            TAY
            LDA FADETAB,Y
            STA NEWB
            PLA
            LSR
            LSR
            LSR
            LSR                     ; G
            CLC
            ADC BASE
            TAY
            LDA FADETAB,Y
            ASL
            ASL
            ASL
            ASL
            ORA NEWB                ; new low byte
            DFB $9F,$00,$9E,$E1     ; STA $E19E00,X
            INX
            LDA TARGET,X            ; high byte = R
            AND #$0F
            CLC
            ADC BASE
            TAY
            LDA FADETAB,Y
            DFB $9F,$00,$9E,$E1     ; STA $E19E00,X
            INX
            CPX #512
            BCC :c
            SEC
            XCE                     ; back to emulation mode
            MX  %11
            PLP
            RTS

*-----------------------------------------------------------
* COPY_CHUNK: CHUNKSIZE bytes from bank-0 CHUNK to $E1:DEST,
* then advance DEST. Native mode inside this routine only.
*-----------------------------------------------------------
COPY_CHUNK
            PHP
            SEI                     ; no interrupts while in native mode
            CLC
            XCE                     ; native mode
            REP #$30
            MX  %00
            LDY #0                  ; Y = offset inside CHUNK (source)
            LDX DEST                ; X = destination offset in bank $E1
:cp         LDA CHUNK,Y             ; 16-bit read  (data bank = $00 under P8)
            DFB $9F,$00,$00,$E1     ; STA $E10000,X (raw bytes: 16-bit write)
            INY
            INY
            INX
            INX
            CPY #CHUNKSIZE
            BCC :cp
            STX DEST                ; next destination
            SEP #$30
            MX  %11
            SEC
            XCE                     ; back to emulation mode
            PLP
            RTS

*-----------------------------------------------------------
* Variables (absolute memory, NOT zero page: MLI uses it as scratch)
*-----------------------------------------------------------
DEST        DW  0
CHUNKS      DFB 0
ERRCODE     DFB 0
SAVEVID     DFB 0
STEP        DFB 0
BASE        DFB 0
NEWB        DFB 0
TMP         DFB 0
SCAL        DFB 0
CCMP        DFB 0

*-----------------------------------------------------------
* MLI parameter blocks
*-----------------------------------------------------------
OPEN_PARMS  DFB 3                   ; param count
            DA  PATHNAME
            DA  IOBUF
OPEN_REFNUM DFB 0

READ_PARMS  DFB 4
READ_REFNUM DFB 0
            DA  CHUNK
            DA  CHUNKSIZE           ; request count
            DA  0                   ; bytes actually read

CLOSE_PARMS DFB 1
CLOSE_REFNUM DFB 0

QUIT_PARMS  DFB 4
            DFB 0
            DA  0
            DFB 0
            DA  0

* Full pathname so it works whatever the launcher left as prefix.
* Apostrophes = high bit off. Change to your volume/file name.
PATHNAME    STR '/SHR/TIMELESS.PIC'
