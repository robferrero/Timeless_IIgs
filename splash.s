*-----------------------------------------------------------
* SPLASH.S  -  Apple IIgs SHR splash loader via ProDOS 8 MLI
* Assembler: Merlin32       Output: ProDOS SYS file ($FF)
*
* Loads a 32768-byte SHR picture (type $C1 PIC, $8000 bytes:
*   $0000-$7CFF pixels, $7D00-$7DC7 SCB, $7E00-$7FFF palettes)
* straight into $E1:2000, then switches to Super Hi-Res.
*
* The P8 MLI can only read into bank $00, so the file is read
* in 8 chunks of 4 KB into a bank-0 buffer and each chunk is
* copied to bank $E1 with MVN.
*-----------------------------------------------------------

            TYP $FF                 ; ProDOS SYS
            DSK SPLASH.SYS
            ORG $2000
            MX  %11                 ; SYS programs start in emulation mode

MLI         EQU $BF00
KEY         EQU $C000
STROBE      EQU $C010
NEWVIDEO    EQU $C029
HOME        EQU $FC58

IOBUF       EQU $4000               ; 1024 bytes, page aligned (for OPEN)
CHUNK       EQU $4400               ; 4096-byte bank-0 read buffer ($4400-$53FF)
CHUNKSIZE   EQU $1000
NCHUNKS     EQU 8                   ; 8 * 4096 = 32768
SHRBASE     EQU $2000               ; destination offset in bank $E1

*-----------------------------------------------------------
START
            LDA #0
            STA ERRCODE

            LDA NEWVIDEO            ; linear SHR memory map BEFORE writing to $E1
            ORA #%01000000          ; (bit 6). Without it, bank $E1 writes are
            STA NEWVIDEO            ; interleaved: 1 byte every 2

            JSR MLI                 ; OPEN
            DFB $C8
            DA  OPEN_PARMS
            BCS :err

            LDA OPEN_REFNUM         ; copy refnum into READ/CLOSE blocks
            STA READ_REFNUM         ; (8-bit store: refnum is ONE byte)
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

            LDA NEWVIDEO            ; show it: SHR on + linear memory
            ORA #%11000000
            STA NEWVIDEO

            STA STROBE
:wait       LDA KEY                 ; wait for a key
            BPL :wait
            STA STROBE

            LDA NEWVIDEO            ; back to text
            AND #%00111111
            STA NEWVIDEO
            JSR HOME                ; (we are in emulation mode, ROM call is OK)
            BRA :quit

:errclose   STA ERRCODE
            JSR MLI
            DFB $CC
            DA  CLOSE_PARMS
            BRA :quit
:err        STA ERRCODE             ; MLI error code (inspect in a monitor)

:quit       JSR MLI                 ; QUIT to the ProDOS launcher
            DFB $65
            DA  QUIT_PARMS
            BRK $00                 ; never reached

*-----------------------------------------------------------
* Copy CHUNKSIZE bytes from bank $00:CHUNK to bank $E1:DEST,
* then advance DEST. Native mode only inside this routine.
*-----------------------------------------------------------
COPY_CHUNK
            SEI                     ; no interrupts while in native mode
            CLC
            XCE                     ; native mode
            REP #$30
            MX  %00
            LDY #0                  ; Y = offset inside CHUNK (source)
            LDX DEST                ; X = destination offset in bank $E1
:cp         LDA CHUNK,Y             ; 16-bit read  (data bank = $00 under P8)
            DFB $9F,$00,$00,$E1     ; STA $E10000,X  (raw bytes: 16-bit write into bank $E1)
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
            CLI
            RTS

*-----------------------------------------------------------
* Variables (absolute memory, NOT zero page: MLI uses it as scratch)
*-----------------------------------------------------------
DEST        DW  0
CHUNKS      DFB 0
ERRCODE     DFB 0

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
