; =====================================================================
; TIMELESS TUNNEL DEMO 320x200 (APPLE IIGS) - v60
; Target: Merlin32
;
; ATTENZIONE PRESTAZIONI: INIT_GNBGTBL fa 320*100*2 = 64000 chiamate a
; MULSHR8U, ognuna con un ciclo shift-add da 16 iterazioni: e' un
; calcolo ONE-TIME all'avvio (non per-frame), ma su un 65816 puo'
; volerci qualche secondo percepibile. E' il primo, ovvio bersaglio di
; ottimizzazione quando iniziamo a ottimizzare (idee: tabella di
; moltiplicazione precalcolata invece di shift-add, evitare il calcolo
; per meta' delle colonne sfruttando la simmetria di seno/coseno, ecc).
;
; ATTENZIONE RAM: servono banchi $02 e $03 liberi per intero (128KB in
; totale oltre al programma). Su un IIgs/emulatore con almeno 1MB di
; RAM configurata non ci sono problemi.
;
; GNBG_RENDER stesso e' scritto per chiarezza/correttezza, non per
; velocita': alterna spesso accumulatore a 8 e 16 bit (SEP/REP #$20).
; E' il secondo bersaglio di ottimizzazione naturale una volta
; verificato che il tunnel si vede giusto.
; =====================================================================

            DSK   TL61.SYS        ; *** TL61: FIX splash (modalita' CPU) - vedi START / LOAD_SPLASH
            TYP   $FF              ; Tipo file $FF = SYS
            ORG   $2000            ; Indirizzo ProDOS 8 standard
            MX  %11                 ; SYS programs start in emulation mode

; ---------------------------------------------------------------------
; DIRECT PAGE
; ---------------------------------------------------------------------
; --- Gruppo A: stato persistente (vista + mover), usati ogni frame ---
; *** TL45: stato di pesce e lumaca. Zona $00-$7F mai toccata da
; nessun'altra parte del programma (tutto il resto parte da $80).
FISH_X         EQU   $02
FISH_Y         EQU   $04
FISH_DX        EQU   $06
FISH_DY        EQU   $08
FISH_CNTR      EQU   $0A
FISH_FRAME     EQU   $0C

SNAIL_X        EQU   $0E
SNAIL_Y        EQU   $10
SNAIL_DX       EQU   $12
SNAIL_DY       EQU   $14
SNAIL_CNTR     EQU   $16
SNAIL_FRAME    EQU   $18
STAMP_TIMER    EQU   $1A       ; *** TL45: contatore per scaglionare le stampe extra su texture

; *** TL46: stato icona volante e petali
ICON_X         EQU   $1C
ICON_STEP      EQU   $1E       ; 0..139, indice in BOB_TABLE
ICON_INDEX     EQU   $20       ; 0..2, quale delle 3 icone
ICON_Y         EQU   $30
ICON_BOBTMP    EQU   $32

; *** TL55: PETAL0_X..PETAL_CNTR ($22-$40, versione semplificata a 6
; petali fissi di R_L1P90) RITIRATI - sostituiti dal motore vero
; (24 particelle vere in LEAFX_TABLE/LEAFY_TABLE, banco 0, piu' questi
; pochi campi scalari qui sotto). Tutti i nuovi campi sono tenuti "a 16
; bit sempre puliti" (mai SEP #$20 in R_L1P90/SWAP_RAIN_FRAMETBL: vedi
; il commento li' sul perche', dopo il crash della fase 5/rombo dovuto
; esattamente a un'etichetta raggiunta con lo stato 8/16 bit sbagliato).
; $2E-$33 e $38-$3E restano liberi (non servono altri campi per ora).
RAIN_DPHASE0   EQU   $22       ; "dphase[0]" - +7/chiamata, mod 256
RAIN_DPHASE1   EQU   $24       ; "dphase[1]" - +13/chiamata, mod 256
RAIN_CNTR      EQU   $26       ; "cntr" - 240->0, poi reset (turno di 240 chiamate)
RAIN_NUM       EQU   $28       ; "num" - 0..23, particelle attive-1
RAIN_NUMD      EQU   $2A       ; "numd" - +1/0/-1 (rampa di RAIN_NUM)
RAIN_TY        EQU   $2C       ; scratch transitorio "ty" (per particella)
RAIN_TX        EQU   $34       ; scratch transitorio "tx"/tx_delta (per particella)
RAIN_T         EQU   $36       ; scratch transitorio "t" - 0..7, indice frametbl

; *** TL48: indirizzi VRAM per le 3 righe extra sopra e le 3 sotto
; (oltre a WRITE_X1/WRITE_X2), dato che ogni campione ora ne copre 4+4
WRITE_X1B      EQU   $42
; *** TL53: WRITE_X1C/X1D/X2C/X2D non sono mai stati usati da nessuna
; routine (verificato) - erano riservati per una variante di GNBG_RENDER
; mai scritta. Li riuso per lo stato del dispatcher a fasi dell'intro
; (INTRO_STEP): 5 byte liberi qui, ne bastano 5.
INTRO_PHASE    EQU   $44       ; 0=curva,1=punti,2=linee,3=cluster margherite,4=finita
INTRO_JUMP_PTR EQU   $46       ; scratch per il salto indiretto (stesso pattern di UPDATE_L1)
WRITE_X2B      EQU   $48
DOTS_COUNTER   EQU   $4A       ; "counter" di r_p10 (0..255)
LINES_COUNTER  EQU   $4C       ; "counter" di r_p20 (0..127)

; *** TL50: stato faccine felici (l1p30) e icone orbitanti (l1p70)
HAPPY0_X       EQU   $50
HAPPY0_Y       EQU   $52
HAPPY1_X       EQU   $54
HAPPY1_Y       EQU   $56
HAPPY2_X       EQU   $58
HAPPY2_Y       EQU   $5A
HAPPY3_X       EQU   $5C
HAPPY3_Y       EQU   $5E
HAPPY_CNTR     EQU   $60       ; durata del turno (condivisa dalle 4 faccine)

ORBIT_X        EQU   $62       ; centro X dell'ellisse
ORBIT_PHASE    EQU   $64       ; 0..319, fa ruotare le 8 posizioni
ORBIT_INDEX    EQU   $66       ; 0..2, quale sprite sta orbitando
ORBIT_DX       EQU   $68       ; direzione (+2/-2), si inverte ad ogni bordo raggiunto
ORBIT_TMP      EQU   $6A       ; scratch per il calcolo seno/coseno con segno
ORBIT_SPRTMP   EQU   $6C       ; puntatore sprite corrente
ORBIT_I        EQU   $6E       ; 0..7, indice delle 8 posizioni sull'ellisse

; *** TL51: 0=STA_COPY_ONCE, 1=PEI_COPY_ONCE - alternati con SPAZIO
; (vedi CHECK_KEYBOARD), usati da PEI_BENCH_DISPATCH ogni frame.
; *** TL54: il confronto PEI/STA e' ritirato per ora (SPAZIO fa altro,
; vedi TEXTURE_PREVIEW_MODE sotto) - PEI_BENCH_DISPATCH/SET_BORDER_INDICATOR
; restano nel file ma non vengono piu' chiamati da nessuna parte: campo
; e routine dormienti, non cancellati (si puo' sempre tornare a usarli).
PEI_BENCH_MODE EQU   $70
; *** TL54: stesso campo di PEI_BENCH_MODE (mai piu' toccato da quel
; codice ora dormiente) riusato per il nuovo toggle SPAZIO: 0=vista
; tunnel normale (GNBG_RENDER), 1=anteprima diretta della texture
; 256x256 (SHOW_TEXTURE_DIRECT), per vedere come le fasi 1-5 la stanno
; preparando.
TEXTURE_PREVIEW_MODE EQU $70

; *** TL52: stato dell'intro "curva + pioggia di margherite" (porting
; di r_p00/r_p30 da timeless.c). $72-$7F erano liberi (14 byte fra
; PEI_BENCH_MODE a 16 bit e SAVED_SHADOW).
CURVE_LOC      EQU   $72       ; "loc" - posizione corrente nella texture (16 bit)
CURVE_LOCD     EQU   $74       ; "locd" - delta che raddoppia/ruota ad ogni step
CURVE_COLOR    EQU   $76       ; "color" - 0..63, passo 13
CURVE_COUNTER  EQU   $77       ; "counter" - 8 bit, -2 a chiamata, si ferma a 0
; *** TL53: CURVE_ACTIVE non serve piu' (il gating fasi e' passato a
; INTRO_PHASE/INTRO_STEP) - questo byte, confermato morto, ora e'
; STAMP_SCALE: fattore di ingrandimento (1,2,3,4...) usato da
; STAMP_TILE_SCALED per le margherite delle fasi 4 e 5. Va impostato
; dal chiamante (FILL_STEP/CHECKER_GROW_STEP) PRIMA di ogni stampa.
STAMP_SCALE    EQU   $78
FILL_LOC       EQU   $79       ; "d3loc" - prossima posizione margherita (16 bit)
FILL_LOCD      EQU   $7B       ; "d3locd" - delta ruotato di 5 bit
FILL_CNTR      EQU   $7D       ; quante margherite restano da piazzare
FILL_PACE      EQU   $7E       ; frame residui prima della prossima stampa
; *** TL54: FILL_ICONIDX non seleziona piu' solo un frame della
; margherita - seleziona quale FORMA in CLUSTER_ICON_TBL (margherita +
; le 3 icone di R_L1P50) usare per il prossimo cluster/margherita
; sparsa, cosi' le fasi 4/5 mostrano tutte le forme disponibili invece
; di restare fisse sulla sola margherita (vedi FILL_STAMP_AT).
FILL_ICONIDX   EQU   $7F       ; 0..3, quale forma in CLUSTER_ICON_TBL (ciclico)

SAVED_SHADOW   EQU   $80
VIEW_X         EQU   $82        ; = "vploc" byte basso (mosso dal mover X)
VIEW_Y         EQU   $84        ; = "vploc" byte alto  (mosso dal mover Y)
VIEW_DIR       EQU   $86        ; = "vpdir", 0..319 (indice colonna gnbgtbl)

MVX_AT         EQU   $88
MVX_MOVING     EQU   $8A
MVX_DELAY      EQU   $8C
MVX_PERIOD     EQU   $8E
MVX_WHICH      EQU   $90
MVY_AT         EQU   $92
MVY_MOVING     EQU   $94
MVY_DELAY      EQU   $96
MVY_PERIOD     EQU   $98
MVY_WHICH      EQU   $9A
MVD_AT         EQU   $9C
MVD_MOVING     EQU   $9E
MVD_DELAY      EQU   $A0
MVD_PERIOD     EQU   $A2
MVD_WHICH      EQU   $A4
MV_SCRATCH     EQU   $A6

; --- Gruppo B: scratch usato solo all'avvio da GENERATE_OFFSCREEN e
; INIT_GNBGTBL (moltiplicazione software). Libero per altri usi dopo. ---
GNBG_TMP       EQU   $A8
GNBG_TMP2      EQU   $AA
; *** TL51: GNBG_TMP4 e' scratch di INIT_PACKLUT (gira all'avvio, prima
; di MAIN_LOOP, come GENERATE_OFFSCREEN/INIT_GNBGTBL: stesso riuso di
; Gruppo B, libero subito dopo).
GNBG_TMP4      EQU   $AC
MULA           EQU   $AC        ; moltiplicando (unsigned, es. rtab[j])
MULB           EQU   $AE        ; moltiplicatore (signed, es. sin/cos)
MB_TMP         EQU   $B0
MCLO           EQU   $B2
MCHI           EQU   $B4
PRODLO         EQU   $B6        ; ATTENZIONE: PRODLO e PRODHI devono
PRODHI         EQU   $B8        ; restare consecutivi (vedi MULSHR8U)
MUL_SIGN       EQU   $BA
GNBG_I         EQU   $BC        ; indice colonna angolare 0..79 (1/4!)
GNBG_J         EQU   $BE        ; indice profondita' 0..99
GNBG_Y         EQU   $C0        ; Y assoluto colonna base (dopo MULSHR8U)
GNBG_X         EQU   $C2        ; X assoluto colonna base
GNBG_DY        EQU   $C4
GNBG_DX        EQU   $C6
; *** TL41: 4 puntatori/accumulatori, uno per ciascuna delle 4 colonne
; derivate per simmetria dalla colonna base i (i, i+80, i+160, i+240)
GNBG_PTR0      EQU   $C8
GNBG_PTR1      EQU   $CA
GNBG_PTR2      EQU   $CC
GNBG_PTR3      EQU   $CE
GNBG_ATY0      EQU   $D0
GNBG_ATX0      EQU   $D2
GNBG_ATY1      EQU   $D4
GNBG_ATX1      EQU   $D6
GNBG_ATY2      EQU   $D8
GNBG_ATX2      EQU   $DA
GNBG_ATY3      EQU   $DC
GNBG_ATX3      EQU   $DE

; *** TL55: nuove fasi L0 (DIAMOND_STEP/SINE50_STEP/WIPE_STEP, r_p40/
; r_p50/r_p60). Stato che deve sopravvivere da un frame all'altro va in
; $D4-$DB (= GNBG_ATY1..GNBG_ATX2 qui sopra): li scrive/legge SOLO
; INIT_GNBGTBL, una volta sola all'avvio, ben prima che l'intro
; cominci - stesso ragionamento gia' fatto per WRITE_X1C/D quando e'
; nato INTRO_PHASE (TL52). Scratch di lavoro PURAMENTE transitorio
; (vive solo dentro una singola chiamata a una di queste 3 routine, mai
; letto da un frame al successivo) riusa invece campi Gruppo B/A gia'
; noti per essere "dormienti" durante l'intro (vedi GNBG_TMP in
; CURVE_STEP): INTRO_TMP_A/B per DIAMOND_STEP (= GNBG_TMP4/MULA e MULB
; - DIAMOND_STEP non moltiplica mai, quindi sono liberi), SINE_EDI/
; SINE_EBP/SINE_DL per SINE50_STEP (= GNBG_I/GNBG_J e GNBG_TMP2).
DIAMOND_LOC    EQU   $D4       ; "loc" di r_p40 (16 bit)
DIAMOND_LOCD   EQU   $D6       ; "locd" di r_p40 (16 bit, con segno)
DIAMOND_LEN    EQU   $D8       ; "len" di r_p40 (8 bit, 1..0x41)
DIAMOND_LEND   EQU   $D9       ; "lend" di r_p40 (8 bit, con segno, +-1)
SINE50_CNTR    EQU   $DA       ; "cntr" di r_p50 (8 bit, 255->0 poi wrap)
WIPE_LOC       EQU   $DB       ; "loc" di r_p60 (8 bit, +0x20/chiamata)

INTRO_TMP_A    EQU   $AC       ; "di"/"si" transitori di DIAMOND_STEP
INTRO_TMP_B    EQU   $AE       ; (= GNBG_TMP4/MULA e MULB)
SINE_EDI       EQU   $BC       ; "edi" transitorio di SINE50_STEP (= GNBG_I)
SINE_EBP       EQU   $BE       ; "ebp" transitorio di SINE50_STEP (= GNBG_J)
SINE_DL        EQU   $AA       ; "dl" transitorio di SINE50_STEP (= GNBG_TMP2)

; --- Gruppo C: stato di GNBG_RENDER (per-frame) ---
BP_LEFT        EQU   $E0        ; puntatore nella gnbgtbl, colonna sx
BP_RIGHT       EQU   $E2        ; puntatore nella gnbgtbl, colonna dx
SXL            EQU   $E4
SYL            EQU   $E6
SXR            EQU   $E8
SYR            EQU   $EA
PAIR_IDX       EQU   $EC        ; 0..159 (coppie di colonne schermo)
YSTEP          EQU   $EE        ; 0..99 (passo di profondita' = riga)
WRITE_X1       EQU   $F0        ; *** TL41: offset VRAM riga y_step gia' pronto
WRITE_X2       EQU   $F2        ; *** TL41: offset VRAM riga specchiata gia' pronto
; *** TL51: CR_BYTE/CL_BYTE resi ADIACENTI (erano $F4/$F6) apposta per
; PACKLUT: una singola LDA a 16 bit da CR_BYTE legge CL_BYTE*256+
; CR_BYTE in un colpo solo (little-endian: basso=CR_BYTE, alto=
; CL_BYTE) - vedi GNBG_RENDER e INIT_PACKLUT piu' sotto.
CR_BYTE        EQU   $F4
CL_BYTE        EQU   $F5
PACK_BYTE      EQU   $F8
GNBG_TMP3      EQU   $FA
FRAME_CNT      EQU   $FC

; *** TL42: variabili del blit sprite. Riusano lo spazio di Group B
; (GNBG_TMP.. usato solo da GENERATE_OFFSCREEN/INIT_GNBGTBL, finiti
; ben prima che MAIN_LOOP arrivi a chiamare BLIT_SPRITE) per non dover
; allargare la direct page.
BLIT_PTR       EQU   $A8        ; puntatore ai dati sprite (bank 0)
BLIT_BASE_X    EQU   $AA        ; posizione sullo schermo
BLIT_BASE_Y    EQU   $AC
BLIT_LEN       EQU   $AE        ; lunghezza strip corrente
BLIT_X         EQU   $B0        ; x assoluta pixel corrente
BLIT_Y         EQU   $B2        ; y assoluta della strip
BLIT_ROWADDR   EQU   $B4        ; y*160 (offset di riga in VRAM)
BLIT_COLOR     EQU   $B6
BLIT_THEME     EQU   $B8        ; 0..3, indice palette/tema attivo
BLIT_SCRATCH   EQU   $BA
BLIT_SCRATCH2  EQU   $BC
BLIT_HINIB     EQU   $BE
THEME_CNT      EQU   $C0        ; *** TL42: contatore lento per ciclare i 4 temi

; *** TL43: dispatcher L1 (sequenze sprite) e stato della margherita
L1_INDEX       EQU   $C2
DAISY_X        EQU   $C4
DAISY_Y        EQU   $C6
DAISY_DX       EQU   $C8
DAISY_DY       EQU   $CA
DAISY_CNTR     EQU   $CC
DAISY_PHASE    EQU   $CE
DAISY_FRAME    EQU   $D0
L1_JUMP_PTR    EQU   $D2        ; *** TL43 FIX: scratch per il salto indiretto in UPDATE_L1

; *** TL49: variabili del loader musica (da TL44/loader_rain.s). Riusano
; lo spazio di Group B (scratch di GENERATE_OFFSCREEN/INIT_GNBGTBL): per
; costruzione MUSIC_INIT gira DOPO che quelle due routine hanno finito
; e PRIMA che BLIT_SPRITE/R_L1P00 inizino a usare questo stesso spazio.
REF_NUM        EQU   $A8
BYTES_LEFT     EQU   $AA
CHUNK_NOW      EQU   $AC
DEST_BANK_VAR  EQU   $AE
DEST_OFF       EQU   $B0

MUSIC_ENABLED  EQU   1          ; *** TL58A: acceso per testare il fix REP #$20->#$30

; ---------------------------------------------------------------------
; REGISTRI HARDWARE E MEMORIA
; ---------------------------------------------------------------------
MLI         EQU $BF00
KEY         EQU $C000
STROBE      EQU $C010
VBL         EQU $C019
HOME        EQU $FC58

* Bank-0 buffers (adjust to your memory map)
CHUNKSIZE   EQU $1000
NCHUNKS     EQU 8                   ; 8 * 4096 = 32768
SHRBASE     EQU $2000               ; destination offset in bank $E1
FADE_FRAMES EQU 3                   ; video frames per fade step (16 steps)

SHADOW        EQU   $C035
NEWVIDEO      EQU   $C029
BORDER        EQU   $C034
PALETTE       EQU   $E19E00
SCB_BASE      EQU   $E19D00

FAST_SHR      EQU   $2000            ; VRAM banco $01 (offset, per CLEAR_VRAM)
FAST_SHR_LONG EQU   $012000          ; VRAM banco $01 (indirizzo assoluto long)
OFFSCREEN_BASE EQU  $020000          ; texture 256x256, banco $02 intero
GNBGTBL_BASE  EQU   $030000          ; tabella gnbgtbl, banco $03 (16000 byte usati)
; *** TL51: tabella di packing nibble, banco $04 intero (65536 voci).
; PACKLUT[CL_BYTE*256+CR_BYTE] = ((CL&$0F)<<4)|(CR&$0F) - vedi
; INIT_PACKLUT e GNBG_RENDER.
PACKLUT_BASE  EQU   $040000

; *** TL49: costanti del loader musica
NinjaTrackerPlus EQU  $0F0000
NTPprepare       EQU  NinjaTrackerPlus
NTPplay          EQU  NinjaTrackerPlus+3
NTPstop          EQU  NinjaTrackerPlus+6

CHUNK_SIZE       EQU  4096
NTPPLAYER_SIZE   EQU  34672
RAIN_REMAINDER   EQU  23143       ; = 88679 - 65536

; *** TL59 FIX: IO_BUFFER e STAGE_BUF NON sono piu' EQU a indirizzi
; assoluti fissi ($6000/$6400). Quell'assunzione ("ben oltre la fine
; del programma") era sbagliata: CSPR0A_DATA/CSPR0B_DATA/CSPR0C_DATA/
; CSPR0D_DATA (dati sprite ala/icona, vedi WINGFRAME_TBL/CENTERCSPR_TBL)
; sono compilati esattamente in quell'intervallo. MUSIC_INIT, chiamata
; una volta sola in START prima di ogni inizializzazione sprite, legge
; RAIN.NTP a blocchi via ProDOS MLI_READ dentro STAGE_BUF - e la MLI_READ
; scriveva quindi sopra le tabelle sprite, in banco $00, una volta per
; ogni chunk letto (confermato con un breakpoint di scrittura su $6AD8:
; scattava 31 volte, tutte durante il caricamento musica, mai durante
; l'animazione - esattamente il numero di chunk letti per NTPPLAYER+
; RAIN.NTP). Per questo l'ala (e le foglie) uscivano corrotte o
; venivano scartate dalla rete di sicurezza di TL58F, sempre e comunque,
; anche dopo una ricompilazione pulita: non era una race condition,
; era una collisione statica di indirizzi.
;
; Ora IO_BUFFER e STAGE_BUF sono etichette DS, riservate dall'assemblatore
; in coda al file (vedi fondo pagina, prima di END) - il loro indirizzo
; vero lo decide Merlin32 in base a dove finisce davvero il programma,
; quindi non possono piu' collidere con nessuna tabella dati per
; costruzione. Tutti i riferimenti nel codice (LDX #STAGE_BUF, DA
; IO_BUFFER, DA STAGE_BUF) restano invariati: sono simbolici, prendono
; automaticamente il nuovo indirizzo.

; ---------------------------------------------------------------------
; MAIN ENTRY
; ---------------------------------------------------------------------
; *** TL61 FIX: le routine dello splash (LOAD_SPLASH, FADE_IN,
; FADE_OUT, BUILD_TABLE, ...) sono scritte per girare in EMULATION
; MODE a 8 bit, come all'ingresso di un SYS (e come in splash.s).
; In TL60 venivano chiamate gia' in nativo/16 bit: BUILD_TABLE con
; A a 16 bit leggeva "LDA CCMP" come parola (CCMP + byte seguente) e
; il confronto "CMP #16" non era mai vero -> il ciclo "STA FADETAB,X"
; continuava a scrivere in tutta la RAM fino a sovrascrivere il
; programma (BRK a 00/22A7, dentro BUILD_TABLE). Inoltre
; COPY_CHUNK/PAL_SAVE_BLACK/FADE_STEP finiscono con SEC/XCE, quindi
; al ritorno la CPU era in emulation mentre START proseguiva con
; codice assemblato a 16 bit. Ora lo splash gira PRIMA di entrare
; in modo nativo.
            MX    %11
START       PHK
            PLB                    ; DBR = $00 (programma in banco 0)
            JSR   LOAD_SPLASH      ; emulation mode, 8 bit
            BCS   :quit            ; codice errore in ERRCODE
            JSR   FADE_IN          ; emulation mode, 8 bit
            STA   $C010            ; Resetta strobe tastiera
            SEI                    ; Blocco Interrupts System 6
            CLC
            XCE                    ; Native Mode 65816
            PHK
            PLB
            REP   #$30             ; A, X, Y a 16 bit
            MX    %00

            LDA   #$0000
            TCD                    ; Direct Page = $0000

            PEA   $0000            ; Bilanciamento Stack (DBR = $00)
            PLB
            PLB

            JMP :inizio
            
:quit       JSR MLI                 ; QUIT to the ProDOS launcher
            DFB $65
            DA  QUIT_PARMS
            BRK $00  

            ; Vista iniziale: vploc=0x8080 (centrata), vpdir=0 (come Tran)
:inizio     LDA   #$0080
            STA   VIEW_X
            STA   VIEW_Y
            STZ   VIEW_DIR

            ; Init dei 3 mover "veri" (invariati da TL4)
            STZ   MVX_AT
            STZ   MVX_MOVING
            LDA   #$0020
            STA   MVX_DELAY
            LDA   #$0060
            STA   MVX_PERIOD
            STZ   MVX_WHICH

            STZ   MVY_AT
            STZ   MVY_MOVING
            LDA   #$0040
            STA   MVY_DELAY
            LDA   #$0040
            STA   MVY_PERIOD
            STZ   MVY_WHICH

            STZ   MVD_AT
            STZ   MVD_MOVING
            LDA   #$0030
            STA   MVD_DELAY
            LDA   #$0040
            STA   MVD_PERIOD
            STZ   MVD_WHICH

            ; 1. SHADOWING / SUPER HI-RES / BORDO NERO
            SEP   #$20
            MX    %10
            LDA   SHADOW
            STA   SAVED_SHADOW
            AND   #%11110111       ; Shadowing ON
            STA   SHADOW

            LDA   NEWVIDEO
            ORA   #%10000000       ; SHR ON
            STA   NEWVIDEO

            LDA   BORDER
            AND   #$F0             ; Bordo Nero
            STA   BORDER

            REP   #$30
            MX    %00

            ; 2. INIZIALIZZAZIONI GRAFICHE E TABELLE
            ; *** TL61: CLEAR_VRAM / INIT_SCB / INIT_PALETTE SPOSTATE
            ; dopo il FADE_OUT (vedi sotto, prima di MAIN_LOOP): qui
            ; distruggevano subito l'immagine dello splash (VRAM, SCB
            ; e palette sono la stessa memoria $E1:2000-$9FFF), che
            ; deve restare visibile durante le inizializzazioni lente.
            ; *** TL53: schermo pulito (colore piatto) invece della
            ; scacchiera di prova, cosi' curva/punti/linee/margherite
            ; si vedono bene fin dall'inizio (vedi CLEAR_OFFSCREEN_FLAT).
            JSR   CLEAR_OFFSCREEN_FLAT ; texture 256x256 in banco $02, pulita

            JSR   INIT_GNBGTBL        ; tabella tunnel vera in banco $03

            ; *** TL51: PACKLUT (banco $04) e buffer di prova del
            ; benchmark PEI. DEVONO stare qui, PRIMA dell'init L1 qui
            ; sotto, per lo stesso motivo di INIT_GNBGTBL: usano ancora
            ; lo scratch di Gruppo B (GNBG_TMP..), che l'init L1
            ; ricicla subito dopo per lo stato di margherita/dispatcher.
            JSR   INIT_PACKLUT        ; tabella packing nibble in banco $04
            JSR   INIT_PEI_BENCH      ; riempie PEI_SRC col pattern di prova
            STZ   PEI_BENCH_MODE      ; 0 = parte da STA_COPY_ONCE
            JSR   SET_BORDER_INDICATOR ; *** TL51 v4: bordo nero iniziale (modo 0)

            ; *** TL43 FIX: init dispatcher L1 e stato margherita (fase 0)
            ; DEVE stare dopo INIT_GNBGTBL: L1_INDEX/DAISY_* condividono
            ; indirizzi di direct page con lo scratch di inizializzazione
            ; (GNBG_X ecc), che altrimenti li sovrascrive con valori
            ; residui non appena INIT_GNBGTBL finisce (causava il crash
            ; con salto impazzito al primo frame).
            STZ   L1_INDEX
            STZ   DAISY_PHASE
            LDA   #280
            STA   DAISY_X
            LDA   #140
            STA   DAISY_Y
            LDA   #-4               ; *** TL50: velocita' raddoppiata (era -2)
            STA   DAISY_DX
            STZ   DAISY_DY
            LDA   #65                ; *** TL50: durata dimezzata (era 130)
            STA   DAISY_CNTR
            STZ   DAISY_FRAME

            ; *** TL50 FIX: MUSIC_INIT spostata QUI, PRIMA di tutte le
            ; inizializzazioni sprite (era dopo, appena prima di
            ; MAIN_LOOP). ProDOS 8 usa alcuni indirizzi di pagina zero
            ; per conto suo durante le chiamate MLI (OPEN/READ) - $40
            ; e' uno di questi, e per sfortuna coincideva con
            ; PETAL_CNTR: il contatore dei petali partiva con un byte
            ; alto sporco lasciato da ProDOS, decrementando da un
            ; numero enorme invece che da 40, dando l'impressione che
            ; il ciclo non finisse mai. Ora che l'inizializzazione
            ; delle nostre variabili avviene DOPO il caricamento
            ; musica, qualunque cosa ProDOS lasci in giro viene
            ; sovrascritta correttamente subito dopo.
            JSR   MUSIC_INIT

            ; *** TL52 FIX (ancora valida in TL53): l'init dell'intro va
            ; DOPO MUSIC_INIT, per lo STESSO motivo del fix TL50 appena
            ; sopra (PETAL_CNTR/$40 sporcato da ProDOS durante le
            ; chiamate MLI) - ProDOS puo' benissimo sporcare anche lo
            ; stato dell'intro se inizializzato prima.
            ; *** TL53: ora e' INIT_INTRO (imposta la fase 0 = curva);
            ; le fasi successive (punti/linee/margherite) si
            ; autoinizializzano quando il dispatcher le attiva.
            JSR   INIT_INTRO

            ; *** TL45: init pesce (entra da destra, esce a sinistra)
            LDA   #288
            STA   FISH_X
            LDA   #60
            STA   FISH_Y
            LDA   #-3
            STA   FISH_DX
            STZ   FISH_DY
            LDA   #96
            STA   FISH_CNTR
            STZ   FISH_FRAME

            ; *** TL45 FIX: lumaca parte dal BASSO (y~176) e sale
            ; verso l'alto (y=0), non piu' l'inverso
            LDA   #160
            STA   SNAIL_X
            LDA   #170              ; *** TL50: era 176 - sprite alti fino a 30px
            STA   SNAIL_Y           ; sporgevano 6px sotto lo schermo
            STZ   SNAIL_DX
            LDA   #-2
            STA   SNAIL_DY
            LDA   #85                ; *** TL50: era 88 (170/2=85 esatto)
            STA   SNAIL_CNTR
            STZ   SNAIL_FRAME
            STZ   STAMP_TIMER

            ; *** TL46: init icona volante (entra da destra, arco di volo)
            LDA   #288
            STA   ICON_X
            STZ   ICON_STEP
            STZ   ICON_INDEX

            ; *** TL55: init pioggia vera (r_l1p90) - LEAFX_TABLE/
            ; LEAFY_TABLE partono gia' con i valori calcolati una volta
            ; sola (vedi il loro commento in testa: sono lo stesso
            ; risultato del ciclo di inizializzazione "static...first"
            ; del C, gia' fatto girare con uno script Python), quindi
            ; qui basta azzerare lo stato scalare, come le static del C
            ; alla primissima chiamata.
            STZ   RAIN_DPHASE0
            STZ   RAIN_DPHASE1
            LDA   #120       ; *** TL59D: sequenza dimezzata (era 240)
            STA   RAIN_CNTR
            STZ   RAIN_NUM
            LDA   #1
            STA   RAIN_NUMD

            ; *** TL57: init pioggia vera (r_l1p80) e neve vera (r_l1p60)
            ; - stesso schema di RAIN_CNTR/NUM/NUMD sopra, ma su campi
            ; assoluti dedicati (RAIN2_*/SNOW_*), non in direct page.
            LDA   #120       ; *** TL59D: sequenza dimezzata (era 240)
            STA   RAIN2_CNTR
            STZ   RAIN2_NUM
            LDA   #1
            STA   RAIN2_NUMD

            LDA   #120       ; *** TL59D: sequenza dimezzata (era 240)
            STA   SNOW_CNTR
            STZ   SNOW_NUM
            LDA   #1
            STA   SNOW_NUMD

            ; *** TL58: init icona ali (r_l1p40)
            STZ   L1P40_LOC
            STZ   L1P40_FRAME0
            LDA   #2
            STA   L1P40_FRAME1
            STZ   L1P40_POSIDX
            STZ   L1P40_CTRIDX

            ; *** TL50: init faccine felici (4 posizioni sparse, deriva
            ; diagonale verso destra/basso)
            LDA   #20
            STA   HAPPY0_X
            LDA   #20
            STA   HAPPY0_Y
            LDA   #100
            STA   HAPPY1_X
            LDA   #60
            STA   HAPPY1_Y
            LDA   #200
            STA   HAPPY2_X
            LDA   #100
            STA   HAPPY2_Y
            LDA   #40
            STA   HAPPY3_X
            LDA   #150
            STA   HAPPY3_Y
            LDA   #75                ; *** TL50 v3: dimezzata (era 150)
            STA   HAPPY_CNTR

            ; *** TL50: init icone orbitanti (centro parte da sinistra)
            LDA   #60
            STA   ORBIT_X
            STZ   ORBIT_PHASE
            STZ   ORBIT_INDEX
            LDA   #2                ; *** TL50 FIX: era 100 (residuo di
            STA   ORBIT_DX          ; quando ORBIT_DX era ORBIT_CNTR) -
                                    ; un passo cosi' grande toccava il
                                    ; bordo dopo 2 frame, l'orbita si
                                    ; vedeva pochissimo

            STZ   FRAME_CNT

            ; uscita splash e lancio main loop
            ; *** TL61 FIX: FADE_OUT/SPLASH_OFF vanno chiamate in
            ; EMULATION mode (come FADE_IN). Interrupt mascherati per
            ; tutto il passaggio (l'IRQ del player musicale non deve
            ; arrivare mentre siamo in emulation). SPLASH_OFF ora
            ; ripristina il modo video originale CON SHR acceso.
            ; JSR HOME RIMOSSA: ($FC58) in nativo/16 bit crasha, e
            ; sporcherebbe la pagina zero $20-$2F, dove stanno i campi
            ; RAIN_* appena inizializzati; EXIT_DEMO la chiama gia'.
            PHP
            SEI
            SEC
            XCE                     ; -> emulation (stack in pagina 1)
            MX    %11
            JSR   FADE_OUT          ; palette -> 0: schermo nero
            JSR   SPLASH_OFF        ; NEWVIDEO = originale | SHR ON
            CLC
            XCE                     ; -> nativo
            PLP
            REP   #$30
            MX    %00

            ; schermo nero: ora si puo' pulire VRAM/SCB e caricare la
            ; palette del demo (prima erano all'inizio di START).
            JSR   CLEAR_VRAM
            JSR   INIT_SCB
            JSR   INIT_PALETTE

            JMP MAIN_LOOP
            ;


; ---------------------------------------------------------------------
; MAIN LOOP
; *** TL49 v3: la vera causa dei crash di ieri era un bug del loader
; (STA a 16 bit su un campo a 8 bit in MLI_OPEN, non l'interrupt) -
; ora corretto. Il SEI globale di v2 non serve piu' e anzi fa danno:
; blocca il player quasi tutto il frame, lasciandogli solo la breve
; finestra di WAIT_VBL per essere servito - lo spartito avanza
; a scatti lentissimi. Si torna a nessuna protezione (come senseiplay,
; che non ne ha bisogno): il player interrompe quando vuole, tutto il
; codice grafico regge comunque.
; ---------------------------------------------------------------------
MAIN_LOOP   REP   #$30
            MX    %00
            JSR   TS3_UPDATE_MOVERS

            ; increment frame counter (mod 16)
            LDA   FRAME_CNT
            CLC
            ADC   #1
            AND   #$0F
            STA   FRAME_CNT

            ; *** TL53: dispatcher a fasi dell'intro (curva -> punti ->
            ; linee -> margherite a cluster) - va PRIMA di GNBG_RENDER,
            ; cosi' i pixel appena disegnati in texture sono gia'
            ; visibili nel campionamento di questo stesso frame.
            JSR   INTRO_STEP
            JSR   DRAW_FRAME_MARKER
            JSR   WAIT_VBL

            ; *** TL54: SPAZIO (TEXTURE_PREVIEW_MODE) sceglie fra la vista
            ; tunnel normale e l'anteprima diretta della texture 256x256 -
            ; vedi CHECK_KEYBOARD. PEI_BENCH_DISPATCH non viene piu'
            ; chiamato da qui: era legato al vecchio significato di questo
            ; stesso campo (PEI_BENCH_MODE) e lo lasciamo dormiente invece
            ; di richiamarlo con un significato che non ha piu' (evita fra
            ; l'altro di riattivare PEI_COPY_ONCE, vedi nota SEI/CLI li').
            LDA   TEXTURE_PREVIEW_MODE
            AND   #$0001
            BEQ   :ml_tunnel
            JSR   SHOW_TEXTURE_DIRECT
            BRA   :ml_afterbg
:ml_tunnel  JSR   GNBG_RENDER
:ml_afterbg
            JSR   DRAW_SPRITES
            ; *** TL51 v4: l'indicatore a rettangolo in VRAM e' stato
            ; tolto - veniva comunque ricoperto dal ridisegno completo
            ; del frame successivo (giustamente: niente double
            ; buffering, si ridisegna tutto ogni giro). Sostituito dal
            ; colore del BORDO SCHERMO (SET_BORDER_INDICATOR),
            ; aggiornato in CHECK_KEYBOARD solo quando SPAZIO cambia
            ; modalita': un registro hardware che nessuna routine
            ; grafica puo' ricoprire.
            JSR   MUSIC_PLAY
            JSR   CHECK_KEYBOARD

            ; 
            BRA   MAIN_LOOP

; ---------------------------------------------------------------------
; Sincronizzazione al VBL
; *** TL49 v3: nessuna protezione SEI/CLI, il player puo' interrompere
; liberamente anche qui.
; ---------------------------------------------------------------------
WAIT_VBL    PHA
            SEP   #$20
            MX    %10
:wv_wait1   LDA   $C019
            BPL   :wv_wait1
:wv_wait2   LDA   $C019
            BMI   :wv_wait2
            REP   #$30
            MX    %00
            PLA
            RTS

*-----------------------------------------------------------
* LOAD_SPLASH
*-----------------------------------------------------------
LOAD_SPLASH
            MX  %11                 ; *** TL61: emulation mode, A/X/Y 8 bit
            LDA NEWVIDEO            ; remember the current video mode
            STA SAVEVID
            ORA #%01000000          ; linear SHR memory map BEFORE writing
            STA NEWVIDEO            ; to $E1 (otherwise 1 byte every 2)

            JSR BUILD_TABLE

            JSR MLI                 ; OPEN
            DFB $C8
            DA  OPEN_PARMS2
            BCS :err

            ; *** TL61: siamo in emulation mode, tutto a 8 bit
            LDA OPEN_REFNU2
            STA READ_REFNU2
            STA CLOSE_REFNU2

            STZ DEST                ; DEST = SHRBASE = $2000
            LDA #$20                ; (basso $00, alto $20)
            STA DEST+1
            LDA #NCHUNKS
            STA CHUNKS

:loop       JSR MLI                 ; READ 4096 bytes into CHUNK
            DFB $CA
            DA  READ_PARMS2
            BCS :errclose

            JSR COPY_CHUNK          ; bank 0 -> $E1:DEST
            DEC CHUNKS
            BNE :loop

            JSR MLI                 ; CLOSE
            DFB $CC
            DA  CLOSE_PARMS2
            BCS :err

            JSR PAL_SAVE_BLACK      ; palettes -> TARGET, screen palettes -> 0
            CLC
            RTS

:errclose   PHA
            JSR MLI
            DFB $CC
            DA  CLOSE_PARMS2
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
            LDA SAVEVID             ; *** TL61: modo video di prima dello
            ORA #%10000000          ; splash (bit 6 compreso), ma con SHR
            STA NEWVIDEO            ; acceso: il demo gira in SHR
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
:cp         LDA STAGE_BUF,Y         ; 16-bit read  (data bank = $00 under P8)
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
OPEN_PARMS2 DFB 3                   ; param count
            DA  PATHNAME
            DA  IO_BUFFER
OPEN_REFNU2 DFB 0

READ_PARMS2 DFB 4
READ_REFNU2 DFB 0
            DA  STAGE_BUF
            DA  CHUNKSIZE           ; request count
            DA  0                   ; bytes actually read

QUIT_PARMS2 DFB 4
            DFB 0
            DA  0
            DFB 0
            DA  0

CLOSE_PARMS2 DFB  1
CLOSE_REFNU2 DFB  0

* Full pathname so it works whatever the launcher left as prefix.
* Apostrophes = high bit off. Change to your volume/file name.
PATHNAME    STR '/SHR/TIMELESS.PIC'

; ---------------------------------------------------------------------
; Hook sprite/musica (stub, invariati da TL4)
; ---------------------------------------------------------------------
; *** TL43: DRAW_SPRITES non fa piu' il test a 4 temi (era in TL42,
; qui sotto per confronto/riferimento - utile finche' non abbiamo
; altre sequenze da testare allo stesso modo):
;   THEME_CNT ciclava 0..239, ogni 60 frame cambiava BLIT_THEME (0-3),
;   posizione fissa (144,84), un solo sprite (cspr00) blittato.
; Ora chiama semplicemente il dispatcher generico.
DRAW_SPRITES
            JSR   UPDATE_L1
            RTS

; ---------------------------------------------------------------------
; UPDATE_L1: dispatcher generico delle sequenze "layer 1" (sprite su
; schermo), ispirato a l1rout/l1setnext in timeless.c. L1_TABLE e' una
; tabella di indirizzi; L1_INDEX dice quale routine e' "attiva" questo
; frame. La routine di destinazione fa RTS direttamente al chiamante
; di UPDATE_L1 (qui, DRAW_SPRITES): e' un tail-call, niente indirizzo
; di ritorno intermedio da gestire.
;
; *** TL43 FIX: la prima versione usava "JMP (L1_TABLE,X)" (indicizzato
; indiretto assoluto) per fare il salto in un solo colpo. E' un
; indirizzamento valido sulla carta ma raro, e il crash (PC finito in
; banco $BD, salto impazzito) e' iniziato proprio al primo giro del
; dispatcher: sostituito con la forma standard "leggi l'indirizzo con
; indicizzazione assoluta normale, poi JMP indiretto di direct page"
; -- addressing mode molto piu' comune e sicuramente supportato.
;
; Per aggiungere una sequenza in futuro: scriverla (con RTS alla fine,
; e una chiamata a L1_SETNEXT quando decide di aver finito il turno),
; e aggiungerne l'indirizzo a L1_TABLE. Il dispatcher non cambia.
; ---------------------------------------------------------------------
UPDATE_L1   REP   #$30
            MX    %00
            LDA   L1_INDEX
            ASL   A
            TAX
            LDA   L1_TABLE,X        ; indicizzazione assoluta normale
            STA   L1_JUMP_PTR       ; -> scratch di direct page
            JMP   (L1_JUMP_PTR)     ; salto indiretto di direct page

; L1_SETNEXT: chiamata DALLA routine attiva quando ha finito il suo
; turno (es. una fase completata). Avanza L1_INDEX, ciclico.
L1_SETNEXT  REP   #$30
            MX    %00
            LDA   L1_INDEX
            CLC
            ADC   #1
            CMP   #L1_COUNT
            BCC   :l1_ok
            LDA   #0
:l1_ok      STA   L1_INDEX
            RTS
             
L1_COUNT    EQU   10              ; *** TL58: + icona ali/occhi (r_l1p40) - tutte e 10 le sequenze del C originale
L1_TABLE    DA    R_L1P00, R_L1P10, R_L1P20, R_L1P30, R_L1P40, R_L1P50, R_L1P60, R_L1P70, R_L1P80, R_L1P90

; ---------------------------------------------------------------------
; R_L1P00: "rolling daisy" (da r_l1p00 in timeless.c). Rotola lungo il
; perimetro di un rettangolo (angoli (20,20)-(280,140), 2px/frame),
; cambiando frame (cspr00/01/02) ad ogni passo per l'effetto di
; rotazione. 4 fasi (lato del rettangolo); ad ogni fase completata
; chiama L1_SETNEXT - con una sola voce in tabella per ora, il
; dispatcher torna semplicemente qui, ma la struttura e' quella giusta
; per quando ci saranno altre sequenze intervallate (come nell'originale,
; dove ogni sequenza gioca "a turno" invece che tutte insieme).
;
; Adattamento rispetto all'originale: li' il percorso usa coordinate
; anche negative/fuori schermo (un buffer con margine attorno ai 320x200
; visibili). Il nostro BLIT_SPRITE non fa ancora clipping, quindi ho
; scelto un rettangolo interamente dentro lo schermo. Stessa idea
; (rotola sul perimetro, cambia frame), percorso diverso.
; ---------------------------------------------------------------------
R_L1P00     REP   #$30
            MX    %00
            LDA   DAISY_X
            CLC
            ADC   DAISY_DX
            STA   DAISY_X
            LDA   DAISY_Y
            CLC
            ADC   DAISY_DY
            STA   DAISY_Y

            LDA   DAISY_FRAME
            CLC
            ADC   #1
            CMP   #3
            BCC   :dz_fok
            LDA   #0
:dz_fok     STA   DAISY_FRAME

            ; tema giallo (gruppo palette 2) per la margherita
            LDA   #2
            STA   BLIT_THEME
            LDA   DAISY_X
            STA   BLIT_BASE_X
            LDA   DAISY_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE

            LDA   DAISY_FRAME
            ASL   A
            TAX
            LDA   DAISY_SPRITE_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            LDA   DAISY_CNTR
            SEC
            SBC   #1
            STA   DAISY_CNTR
            BEQ   :dz_phase_done
            RTS

:dz_phase_done
            LDA   DAISY_PHASE
            CLC
            ADC   #1
            CMP   #4
            BCC   :dz_pok
            LDA   #0
:dz_pok     STA   DAISY_PHASE
            ASL   A
            TAX
            LDA   DAISY_X0_TBL,X
            STA   DAISY_X
            LDA   DAISY_Y0_TBL,X
            STA   DAISY_Y
            LDA   DAISY_DX_TBL,X
            STA   DAISY_DX
            LDA   DAISY_DY_TBL,X
            STA   DAISY_DY
            LDA   DAISY_CNT_TBL,X
            STA   DAISY_CNTR
            JSR   L1_SETNEXT
            RTS

; Le 4 fasi (lati del rettangolo, in senso orario partendo dal basso):
; lato inferiore (dx=-2), lato sinistro (dy=-2), lato superiore
; (dx=+2), lato destro (dy=+2). Durate scelte per chiudere il giro
; esattamente (260px/2=130, 120px/2=60).
; *** TL50: velocita' raddoppiata (4px/frame invece di 2) e durate
; dimezzate, stesso percorso ma il doppio piu' veloce - miglior effetto.
DAISY_X0_TBL  DA  280, 20, 20, 280
DAISY_Y0_TBL  DA  140, 140, 20, 20
DAISY_DX_TBL  DA  -4, 0, 4, 0
DAISY_DY_TBL  DA  0, -4, 0, 4
DAISY_CNT_TBL DA  65, 30, 65, 30

DAISY_SPRITE_TBL
            DA    CSPR00_DATA, CSPR01_DATA, CSPR02_DATA

FISH_SPRITE_TBL
            DA    CSPR03_DATA, CSPR04_DATA

SNAIL_SPRITE_TBL
            DA    CSPR05_DATA, CSPR06_DATA, CSPR07_DATA, CSPR08_DATA

; ---------------------------------------------------------------------
; R_L1P10: "pesce che nuota" (semplificato da r_l1p10 in timeless.c:
; li' nascono fino a 10 pesci pseudo-random contemporaneamente, qui
; per ora un solo pesce alla volta, un attraversamento per turno).
; Stessa struttura di R_L1P00 ma senza tabella di fasi: quando il
; contatore arriva a zero, si riparte dalla stessa posizione iniziale
; e si passa la mano (L1_SETNEXT).
; *** TL45: sprite veri (cspr03/cspr04, confermati dalla mappa) - solo
; 2 frame, non 3 come la margherita.
; ---------------------------------------------------------------------
R_L1P10     REP   #$30
            MX    %00
            LDA   FISH_X
            CLC
            ADC   FISH_DX
            STA   FISH_X
            LDA   FISH_Y
            CLC
            ADC   FISH_DY
            STA   FISH_Y

            LDA   FISH_FRAME
            CLC
            ADC   #1
            CMP   #2
            BCC   :fs_fok
            LDA   #0
:fs_fok     STA   FISH_FRAME

            LDA   #2                ; *** TL50: tema giallo (era blu/grigio), su richiesta
            STA   BLIT_THEME
            LDA   FISH_X
            STA   BLIT_BASE_X
            LDA   FISH_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE

            LDA   FISH_FRAME
            ASL   A
            TAX
            LDA   FISH_SPRITE_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            LDA   FISH_CNTR
            SEC
            SBC   #1
            STA   FISH_CNTR
            BEQ   :fs_done
            RTS
:fs_done    LDA   #288
            STA   FISH_X
            LDA   #60
            STA   FISH_Y
            LDA   #96
            STA   FISH_CNTR
            JSR   L1_SETNEXT
            RTS

; ---------------------------------------------------------------------
; R_L1P20: "lumaca che scende" (semplificato da r_l1p20 in timeless.c:
; li' scende a scatti di 2px con 6 frame di animazione; qui un
; passaggio verticale continuo per turno, stessa idea di massima).
; *** TL45: sprite veri (cspr05-cspr08, confermati dalla mappa) - 4
; frame, non 3 come la margherita.
; ---------------------------------------------------------------------
R_L1P20     REP   #$30
            MX    %00
            LDA   SNAIL_X
            CLC
            ADC   SNAIL_DX
            STA   SNAIL_X
            LDA   SNAIL_Y
            CLC
            ADC   SNAIL_DY
            STA   SNAIL_Y

            LDA   SNAIL_FRAME
            CLC
            ADC   #1
            CMP   #4
            BCC   :sn_fok
            LDA   #0
:sn_fok     STA   SNAIL_FRAME

            LDA   #3                ; tema verde
            STA   BLIT_THEME
            LDA   SNAIL_X
            STA   BLIT_BASE_X
            LDA   SNAIL_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE

            ; *** TL58E: stessa protezione di L1P40_DRAWPAIR (ala/icona) -
            ; stesso schema LDA/ASL/TAX/LDA tbl,X/STA BLIT_PTR a 16 bit,
            ; stessa vulnerabilita' se un interrupt corrompe A/X a 8 bit
            ; proprio qui in mezzo.
            SEI
            LDA   SNAIL_FRAME
            ASL   A
            TAX
            LDA   SNAIL_SPRITE_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            LDA   SNAIL_CNTR
            SEC
            SBC   #1
            STA   SNAIL_CNTR
            BEQ   :sn_done
            RTS
:sn_done    LDA   #170              ; *** TL50: era 176
            STA   SNAIL_Y
            LDA   #85                ; *** TL50: era 88
            STA   SNAIL_CNTR
            JSR   L1_SETNEXT
            RTS

ICON_SPRITE_TBL
            DA    CSPR09_DATA, CSPR16_DATA, CSPR22_DATA

; ---------------------------------------------------------------------
; R_L1P50: "icona che vola con rimbalzo" (da r_l1p50 in timeless.c).
; Scorre orizzontalmente da destra a sinistra seguendo un arco (via
; BOB_TABLE, 140 valori 0-30-0 generati con Python - stessa idea
; dell'heighttbl originale ma piu' corta), cambiando ICONA (non solo
; frame) ad ogni passaggio: cicla tra 3 sprite invece dei 6
; dell'originale. Tema rosso.
; ---------------------------------------------------------------------
R_L1P50     REP   #$30
            MX    %00
            LDA   ICON_X
            SEC
            SBC   #2
            STA   ICON_X
            LDA   ICON_STEP
            CLC
            ADC   #1
            STA   ICON_STEP
            CMP   #140
            BCC   :ic_go
            JMP   :ic_done
:ic_go
            ; Y = 100 - BOB_TABLE[ICON_STEP] (arco verso l'alto)
            STZ   ICON_BOBTMP      ; azzera anche il byte alto prima
            SEP   #$20             ; della scrittura a 8 bit sotto
            MX    %10
            LDX   ICON_STEP
            LDA   BOB_TABLE,X
            STA   ICON_BOBTMP
            REP   #$30
            MX    %00
            LDA   #100
            SEC
            SBC   ICON_BOBTMP
            STA   ICON_Y

            STZ   BLIT_THEME        ; tema rosso
            LDA   ICON_X
            STA   BLIT_BASE_X
            LDA   ICON_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE

            LDA   ICON_INDEX
            ASL   A
            TAX
            LDA   ICON_SPRITE_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE
            RTS

:ic_done    LDA   #288
            STA   ICON_X
            STZ   ICON_STEP
            LDA   ICON_INDEX
            CLC
            ADC   #1
            CMP   #3
            BCC   :ic_iok
            LDA   #0
:ic_iok     STA   ICON_INDEX
            JSR   L1_SETNEXT
            RTS

; nibble basso -> altezza dell'arco di volo (0..55, aumentato su
; richiesta), generato con Python: 55*sin(pi*i/139), simmetrico,
; stessa idea di heighttbl in timeless.c ma piu' corto
BOB_TABLE
            DFB   $00, $01, $02, $04, $05, $06, $07, $09, $0A, $0B, $0C, $0E, $0F, $10, $11, $12
            DFB   $13, $15, $16, $17, $18, $19, $1A, $1B, $1C, $1D, $1E, $20, $21, $22, $22, $23
            DFB   $24, $25, $26, $27, $28, $29, $2A, $2A, $2B, $2C, $2D, $2D, $2E, $2F, $2F, $30
            DFB   $31, $31, $32, $32, $33, $33, $34, $34, $34, $35, $35, $35, $36, $36, $36, $36
            DFB   $37, $37, $37, $37, $37, $37, $37, $37, $37, $37, $37, $37, $36, $36, $36, $36
            DFB   $35, $35, $35, $34, $34, $34, $33, $33, $32, $32, $31, $31, $30, $2F, $2F, $2E
            DFB   $2D, $2D, $2C, $2B, $2A, $2A, $29, $28, $27, $26, $25, $24, $23, $22, $22, $21
            DFB   $20, $1E, $1D, $1C, $1B, $1A, $19, $18, $17, $16, $15, $13, $12, $11, $10, $0F
            DFB   $0E, $0C, $0B, $0A, $09, $07, $06, $05, $04, $02, $01, $00

; *** TL55: LEAFX_TABLE/LEAFY_TABLE - le 24 particelle vere di r_l1p90
; (timeless.c), posizione iniziale calcolata 1:1 dal ciclo del C
; ("static...first", vedi commento in testa a R_L1P90) con uno script
; Python; da qui in poi ogni chiamata le fa evolvere (leggi/scrivi),
; quindi sono dati mutabili in banco 0 come TILE_REMAP_TABLE eccetera,
; non un banco dedicato (troppo piccole per giustificarne uno).
LEAFX_TABLE
            DA    152, 5, 175, 11, 164, 317, 136, 272
            DA    74, 193, 312, 97, 199, 301, 69, 154
            DA    239, 324, 75, 143, 211, 279, 13, 64

LEAFY_TABLE
            DA    137, 94, 40, 185, 120, 44, 167, 80
            DA    192, 94, 195, 86, 176, 56, 135, 4
            DA    72, 140, 208, 66, 123, 180, 27, 73

; *** TL55: RAIN_FRAME_TBL - frametbl[] di r_l1p90. Le prime 8 voci
; sono quelle davvero lette (indice "t" vale sempre 0..7, mai di piu':
; sincos0[]>>5 non supera 7); le 8 dopo sono un "polmone" che
; SWAP_RAIN_FRAMETBL scambia con le prime ogni 240 chiamate (r_l1p90 lo
; fa scambiando i puntatori del C - qui scambiamo il contenuto della
; tabella, stesso effetto). Sprite da sprites.c: cspr18..1c (gia' nel
; file, riciclati dalla vecchia versione semplificata) e cspr1d..21
; (nuovi, aggiunti insieme a quelli di R_L1P50 - vedi in fondo al file).
RAIN_FRAME_TBL
            DA    CSPR18_DATA, CSPR19_DATA, CSPR19_DATA, CSPR1A_DATA
            DA    CSPR1A_DATA, CSPR1B_DATA, CSPR1B_DATA, CSPR1C_DATA
            DA    CSPR1D_DATA, CSPR1E_DATA, CSPR1E_DATA, CSPR1F_DATA
            DA    CSPR1F_DATA, CSPR20_DATA, CSPR20_DATA, CSPR21_DATA

; ---------------------------------------------------------------------
; TL55: SWAP_RAIN_FRAMETBL - scambia le due meta' (8 sprite/16 byte
; ciascuna) di RAIN_FRAME_TBL. Richiamata da R_L1P90 ogni 240 chiamate:
; l'indice "t" con cui si legge la tabella vale sempre 0..7 (mai piu'),
; quindi la seconda meta' non viene mai letta direttamente - serve solo
; come "polmone" per questo scambio periodico, che cambia il set di
; sprite visibili (frametbl[i] <-> frametbl[i+8] nel C) senza toccare
; la logica di movimento delle particelle.
; ---------------------------------------------------------------------
SWAP_RAIN_FRAMETBL
            REP   #$30
            MX    %00
            LDX   #0
:sf_loop    LDA   RAIN_FRAME_TBL,X
            PHA
            LDA   RAIN_FRAME_TBL+16,X
            STA   RAIN_FRAME_TBL,X
            PLA
            STA   RAIN_FRAME_TBL+16,X
            INX
            INX
            CPX   #16
            BNE   :sf_loop
            RTS

; ---------------------------------------------------------------------
; TL55: R_L1P90 - "pioggia" vera (porting fedele di r_l1p90 in
; timeless.c): 24 particelle (LEAFX_TABLE/LEAFY_TABLE) mosse da due
; fasi sinusoidali indipendenti (RAIN_DPHASE0/1, +7/+13 a chiamata,
; lette su SINCOS0_TABLE - la tabella SENZA segno, diversa da
; SINCOS0S_TABLE usata da SINE50_STEP), col numero di particelle attive
; che sale e scende linearmente da 0 a 23 e ritorno (RAIN_NUM/RAIN_NUMD)
; ogni "turno" di 240 chiamate (RAIN_CNTR), al termine del quale si
; scambiano le due meta' di RAIN_FRAME_TBL (SWAP_RAIN_FRAMETBL) e si
; passa al prossimo pattern L1 (L1_SETNEXT). Sostituisce la versione
; semplificata precedente (6 petali fissi, uno sprite statico ciascuno).
;
; *** IMPORTANTE - lezione dal crash della fase 5 (rombo, tasto '6',
; vedi il fix in cima al file): un'etichetta raggiunta con lo stato 8/
; 16 bit sbagliato manda la macchina in testo/monitor. Per eliminare
; del tutto quella classe di bug qui, l'INTERA routine (e
; SWAP_RAIN_FRAMETBL sopra) resta SEMPRE a 16 bit: MAI un SEP #$20. Le
; letture di SINCOS0_TABLE (tabella di byte) si fanno con una LDA a 16
; bit, che legge anche il byte SUCCESSIVO (innocuo: e' un altro byte
; valido della stessa tabella o del testo dopo) nel byte alto, seguita
; da AND #$00FF per scartarlo - stesso risultato di una lettura a 8
; bit, senza mai cambiare M. Di conseguenza RAIN_DPHASE0/1/CNTR/NUM/NUMD
; sono qui campi a 16 bit "sempre puliti" (byte alto a zero, o $FFFF
; per NUMD=-1), non i classici campi a 8 bit di altre fasi del file.
;
; Sicurezza: BLIT_SPRITE non fa bound-check su BLIT_BASE_X/Y (letto il
; codice per verificarlo) - "ty-9"/"tx-13" vengono quindi bloccati a un
; minimo di 0 prima di passarli, una deviazione deliberata dalla
; fedelta' pixel-perfect per evitare scritture fuori dal banco VRAM.
; ---------------------------------------------------------------------
R_L1P90     REP   #$30
            MX    %00

            LDA   #2                ; tema giallo (come nella versione precedente)
            STA   BLIT_THEME

            LDA   RAIN_CNTR
            SEC
            SBC   #1
            STA   RAIN_CNTR
            BNE   :rn_active

            ; --- turno finito: reset cntr/num/numd, scambio meta'
            ; frametbl, prossimo pattern L1 - "if(!--cntr) { cntr=240;
            ; num=0; numd=1; <scambio>; l1setnext(); return; }" ---
            LDA   #120       ; *** TL59D: sequenza dimezzata (era 240)
            STA   RAIN_CNTR
            STZ   RAIN_NUM
            LDA   #1
            STA   RAIN_NUMD
            JSR   SWAP_RAIN_FRAMETBL
            JSR   L1_SETNEXT
            RTS

:rn_active
            ; if(cntr==23) numd=-1 - A vale ancora cntr (appena
            ; decrementato, non toccato da nulla dopo la STA sopra)
            CMP   #23
            BNE   :rn_noflip
            LDA   #$FFFF             ; numd = -1
            STA   RAIN_NUMD
:rn_noflip
            LDA   RAIN_NUM
            CLC
            ADC   RAIN_NUMD
            STA   RAIN_NUM
            BNE   :rn_notzero
            STZ   RAIN_NUMD
            BRA   :rn_numdone
:rn_notzero CMP   #23
            BNE   :rn_numdone
            STZ   RAIN_NUMD
:rn_numdone
            LDA   RAIN_DPHASE0
            CLC
            ADC   #7
            AND   #$00FF
            STA   RAIN_DPHASE0
            LDA   RAIN_DPHASE1
            CLC
            ADC   #13
            AND   #$00FF
            STA   RAIN_DPHASE1

            LDA   RAIN_NUM
            TAX                      ; X = i, scende da num a 0 incluso

:rn_loop    PHX
            TXA
            ASL   A
            TAY                      ; Y = 2*i, offset in LEAFX/LEAFY_TABLE

            ; ty = (sincos0[(dphase0+leafy[i])&0xff]>>6) + 1
            ; ty = leafy[i] + ty; if(ty>=210) ty-=210; leafy[i]=ty
            LDA   LEAFY_TABLE,Y
            STA   RAIN_TY
            CLC
            ADC   RAIN_DPHASE0
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X    ; 16 bit: legge anche il byte dopo,
            AND   #$00FF             ; scartato subito (vedi commento sopra)
            LSR   A
            LSR   A
            LSR   A
            LSR   A
            LSR   A
            LSR   A                  ; >>6 (0..3)
            CLC
            ADC   #1
            CLC
            ADC   RAIN_TY
            CMP   #210
            BCC   :rn_tyok
            SEC
            SBC   #210
:rn_tyok    STA   RAIN_TY
            STA   LEAFY_TABLE,Y

            ; t = sincos0[(dphase1+ty)&0xff]>>5 (0..7)
            ; tx = (t>>1)+1; tx = leafx[i]-tx; if(tx<0) tx+=334; leafx[i]=tx
            LDA   RAIN_TY
            CLC
            ADC   RAIN_DPHASE1
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            LSR   A
            LSR   A
            LSR   A
            LSR   A                  ; t = raw>>5 (0..7)
            STA   RAIN_T

            LSR   A                  ; t>>1
            CLC
            ADC   #1                 ; tx_delta = (t>>1)+1
            STA   RAIN_TX            ; scratch: per ora tx_delta

            LDA   LEAFX_TABLE,Y
            SEC
            SBC   RAIN_TX
            BPL   :rn_txok
            CLC
            ADC   #334
:rn_txok    STA   RAIN_TX            ; ora: tx vero
            STA   LEAFX_TABLE,Y

            ; disegna: BLIT_BASE_X=tx-13 (min 0), BLIT_BASE_Y=ty-9 (min
            ; 0 - BLIT_SPRITE non fa bound-check, vedi commento sopra),
            ; sprite = RAIN_FRAME_TBL[t]
            ;
            ; *** FIX (gia' validato in tl56d): manca clamp SUPERIORE.
            ; leafx arriva fino a 333 e leafy fino a 209 (costanti di wrap
            ; prese identiche dal C, che pero' li' avevano un margine
            ; extra nel buffer virtuale) - con tx-13/ty-9 questo porta
            ; BLIT_BASE_X fino a 320 e BLIT_BASE_Y fino a 200, cioe' 1
            ; pixel/riga oltre lo schermo reale (0..319/0..199).
            ; BLIT_SPRITE non taglia: con BLIT_BASE_Y=200 finisce a
            ; scrivere DENTRO la SCB (VRAM banco $01 offset $9D00+ =
            ; $019D00+, che per lo shadowing hardware IIgs e' la STESSA
            ; memoria fisica di SCB_BASE $E19D00) e poco oltre nella
            ; PALETTE ($E19E00) - causa "colori strani"/sfondo sporcato.
            ; Margine di sicurezza 30px (stesso valore gia' usato per
            ; SNAIL_Y in TL50 per lo stesso motivo).
            LDA   RAIN_TX
            SEC
            SBC   #13
            BPL   :rn_bxok
            LDA   #0
:rn_bxok    CMP   #290
            BCC   :rn_bxok2
            LDA   #290
:rn_bxok2   STA   BLIT_BASE_X

            LDA   RAIN_TY
            SEC
            SBC   #9
            BPL   :rn_byok
            LDA   #0
:rn_byok    CMP   #170
            BCC   :rn_byok2
            LDA   #170
:rn_byok2   STA   BLIT_BASE_Y

            JSR   SET_SCB_RANGE

            LDA   RAIN_T
            ASL   A
            TAX
            LDA   RAIN_FRAME_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            PLX
            DEX
            BMI   :rn_loopdone      ; *** il corpo del loop supera i 127
            JMP   :rn_loop          ; byte: BPL diretto non ci arriverebbe
                                    ; (Merlin32: "Bad Jump...Too long"),
                                    ; quindi salto corto sull'uscita e JMP
                                    ; (portata piena) per il rientro.
:rn_loopdone
            RTS

; ---------------------------------------------------------------------
; R_L1P30: "faccine felici" (semplificato da r_l1p30 in timeless.c: li'
; un buffer circolare di 16 posizioni con un generatore pseudo-casuale
; stile LCG che ne fa comparire una nuova ogni frame; qui 4 particelle
; indipendenti con la propria deriva diagonale, senza vero
; pseudo-casuale - stessa idea di massima, piu' semplice). Sprite:
; cspr09 (lo stesso dell'icona volante). Tema rosso.
; ---------------------------------------------------------------------
R_L1P30     REP   #$30
            MX    %00
            STZ   BLIT_THEME        ; tema rosso

            ; --- faccina 0 ---
            LDA   HAPPY0_X
            CLC
            ADC   #1
            CMP   #300
            BCC   :h0xok
            LDA   #0
:h0xok      STA   HAPPY0_X
            LDA   HAPPY0_Y
            CLC
            ADC   #1
            CMP   #180
            BCC   :h0yok
            LDA   #0
:h0yok      STA   HAPPY0_Y
            LDA   HAPPY0_X
            STA   BLIT_BASE_X
            LDA   HAPPY0_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE
            LDA   #CSPR09_DATA
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            ; --- faccina 1 ---
            LDA   HAPPY1_X
            CLC
            ADC   #1
            CMP   #300
            BCC   :h1xok
            LDA   #0
:h1xok      STA   HAPPY1_X
            LDA   HAPPY1_Y
            CLC
            ADC   #1
            CMP   #180
            BCC   :h1yok
            LDA   #0
:h1yok      STA   HAPPY1_Y
            LDA   HAPPY1_X
            STA   BLIT_BASE_X
            LDA   HAPPY1_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE
            LDA   #CSPR09_DATA
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            ; --- faccina 2 ---
            LDA   HAPPY2_X
            CLC
            ADC   #1
            CMP   #300
            BCC   :h2xok
            LDA   #0
:h2xok      STA   HAPPY2_X
            LDA   HAPPY2_Y
            CLC
            ADC   #1
            CMP   #180
            BCC   :h2yok
            LDA   #0
:h2yok      STA   HAPPY2_Y
            LDA   HAPPY2_X
            STA   BLIT_BASE_X
            LDA   HAPPY2_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE
            LDA   #CSPR09_DATA
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            ; --- faccina 3 ---
            LDA   HAPPY3_X
            CLC
            ADC   #1
            CMP   #300
            BCC   :h3xok
            LDA   #0
:h3xok      STA   HAPPY3_X
            LDA   HAPPY3_Y
            CLC
            ADC   #1
            CMP   #180
            BCC   :h3yok
            LDA   #0
:h3yok      STA   HAPPY3_Y
            LDA   HAPPY3_X
            STA   BLIT_BASE_X
            LDA   HAPPY3_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE
            LDA   #CSPR09_DATA
            STA   BLIT_PTR
            JSR   BLIT_SPRITE

            LDA   HAPPY_CNTR
            SEC
            SBC   #1
            STA   HAPPY_CNTR
            BEQ   :hp_done
            RTS
:hp_done    LDA   #20
            STA   HAPPY0_X
            LDA   #20
            STA   HAPPY0_Y
            LDA   #100
            STA   HAPPY1_X
            LDA   #60
            STA   HAPPY1_Y
            LDA   #200
            STA   HAPPY2_X
            LDA   #100
            STA   HAPPY2_Y
            LDA   #40
            STA   HAPPY3_X
            LDA   #150
            STA   HAPPY3_Y
            LDA   #75                ; *** TL50 v3: era 150
            STA   HAPPY_CNTR
            JSR   L1_SETNEXT
            RTS

ORBIT_SPRITE_TBL
            DA    CSPR16_DATA, CSPR0A_DATA, CSPR17_DATA

; ---------------------------------------------------------------------
; R_L1P70: "icone che orbitano" (semplificato da r_l1p70 in timeless.c:
; li' l'ellisse "respira" (raggi che oscillano); qui raggio fisso, per
; restare semplice). 8 icone disposte sull'ellisse, angoli calcolati
; ogni frame da SIN320/COS320 (gia' presenti per il tunnel) sfalsati
; di 40 posizioni l'uno dall'altro (320/8). Il centro scorre a
; sinistra/destra, invertendo direzione e cambiando sprite ad ogni
; bordo raggiunto - esattamente come fa l'originale (un JSR
; L1_SETNEXT per ogni inversione, non un contatore fisso).
; ---------------------------------------------------------------------
R_L1P70     REP   #$30
            MX    %00
            LDA   ORBIT_X
            CLC
            ADC   ORBIT_DX
            STA   ORBIT_X
            CMP   #60
            BEQ   :ob_edge
            CMP   #260
            BEQ   :ob_edge
            BRA   :ob_go
:ob_edge    LDA   ORBIT_DX
            EOR   #$FFFF
            CLC
            ADC   #1                ; nega ORBIT_DX (-ORBIT_DX)
            STA   ORBIT_DX
            LDA   ORBIT_INDEX
            CLC
            ADC   #1
            CMP   #3
            BCC   :ob_iok
            LDA   #0
:ob_iok     STA   ORBIT_INDEX
            JSR   L1_SETNEXT
            RTS

:ob_go      LDA   #1                ; *** TL50: tema rosso/giallo caldo (era blu/grigio)
            STA   BLIT_THEME
            LDA   ORBIT_PHASE
            CLC
            ADC   #5
            CMP   #320
            BCC   :ob_pok
            SEC
            SBC   #320
:ob_pok     STA   ORBIT_PHASE

            LDA   ORBIT_INDEX
            ASL   A
            TAX
            LDA   ORBIT_SPRITE_TBL,X
            STA   ORBIT_SPRTMP

            STZ   ORBIT_I
:ob_loop    LDA   ORBIT_I
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; * 32
            CLC
            ADC   ORBIT_PHASE
            ; *** TL50 FIX VERO: SIN320/COS320 sono tabelle di PAROLE
            ; (2 byte a voce, 320 voci) - l'indice logico va avvolto
            ; modulo 320 (non troncato a 256 con un AND, che copriva
            ; solo meta' del cerchio: da qui "l'arco" invece
            ; dell'ellisse intera) E RADDOPPIATO prima di usarlo come
            ; offset in byte (stesso schema gia' usato altrove nel
            ; file per ROWOFF_TABLE/MROWOFF_TABLE). Senza il
            ; raddoppio si leggevano parole sfalsate di un byte -
            ; valori spazzatura che potevano mandare BLIT_SPRITE a
            ; scrivere ben oltre la VRAM, corrompendo il programma un
            ; po' alla volta finche' qualcosa si rompeva.
            CMP   #320
            BCC   :ob_idxok
            SEC
            SBC   #320
:ob_idxok   ASL   A                  ; raddoppia: offset in byte, non indice
            TAX

            ; --- X = ORBIT_X + COS320[idx]/8, con segno (nega-scala-
            ; nega se il valore e' negativo, spostamento aritmetico
            ; corretto) ---
            LDA   COS320,X
            STA   ORBIT_TMP
            AND   #$8000
            BEQ   :ob_cpos
            LDA   #$0000
            SEC
            SBC   ORBIT_TMP
            LSR   A
            LSR   A
            LSR   A
            EOR   #$FFFF
            INC   A
            BRA   :ob_cdone
:ob_cpos    LDA   ORBIT_TMP
            LSR   A
            LSR   A
            LSR   A
:ob_cdone   CLC
            ADC   ORBIT_X
            STA   BLIT_BASE_X

            ; --- Y = 100 + SIN320[idx]/16, stesso metodo ---
            LDA   SIN320,X
            STA   ORBIT_TMP
            AND   #$8000
            BEQ   :ob_spos
            LDA   #$0000
            SEC
            SBC   ORBIT_TMP
            LSR   A
            LSR   A
            LSR   A
            LSR   A
            EOR   #$FFFF
            INC   A
            BRA   :ob_sdone
:ob_spos    LDA   ORBIT_TMP
            LSR   A
            LSR   A
            LSR   A
            LSR   A
:ob_sdone   CLC
            ADC   #100
            STA   BLIT_BASE_Y

            JSR   SET_SCB_RANGE
            REP   #$30              ; *** TL50 FIX: non fidarti che SET_SCB_RANGE
            MX    %00                ; torni gia' a 16 bit - il ciclo chiama
                                    ; BLIT_SPRITE 8 volte di fila, un solo
                                    ; ritorno sporco fa accumulare spazzatura
                                    ; nel byte alto di ORBIT_I e il confronto
                                    ; CMP #8 non scatta mai (ciclo infinito,
                                    ; MAIN_LOOP non torna piu' a CHECK_KEYBOARD)
            LDA   ORBIT_SPRTMP
            STA   BLIT_PTR
            JSR   BLIT_SPRITE
            REP   #$30              ; *** stessa protezione dopo BLIT_SPRITE
            MX    %00

            LDA   ORBIT_I
            CLC
            ADC   #1
            STA   ORBIT_I
            CMP   #8
            BCS   :ob_loop_done
            JMP   :ob_loop
:ob_loop_done
            RTS

; ---------------------------------------------------------------------
; TL57: dati e routine per R_L1P60 (neve vera) e R_L1P80 (pioggia
; vera) - le due sequenze mancanti individuate confrontando L1_TABLE
; nel C originale (10 routine, r_l1p00..r_l1p90) con la nostra (ne
; avevamo solo 7). A differenza di R_L1P90 (sprite pieni via
; BLIT_SPRITE/SET_SCB_RANGE), queste due disegnano pixel/segmenti
; DIRETTAMENTE in VRAM con un colore fisso preso dagli indici 6..15
; "sfondo tunnel" - IDENTICI in tutti e 4 i gruppi palette - quindi
; niente SET_SCB_RANGE: molto piu' leggere di un BLIT_SPRITE completo.
;
; Stato scalare (contatori) e tabelle di posizione NON in direct page
; per scelta deliberata: sono 22+896 byte, troppi per la zero page gia'
; satura di riusi, e non serve la velocita' della zero page qui (sono
; lette/scritte una volta per particella per frame, non nel loop
; interno critico). Zero rischio di collisione con altri campi.
; ---------------------------------------------------------------------
RAIN2_CNTR  DA    $0000
RAIN2_NUM   DA    $0000
RAIN2_NUMD  DA    $0000
SNOW_CNTR   DA    $0000
SNOW_NUM    DA    $0000
SNOW_NUMD   DA    $0000
L1_CNT_I    DA    $0000       ; scratch generico condiviso R_L1P60/80
L1_CNT_J    DA    $0000       ; (mai in uso contemporaneo: un solo L1
L1_CNT_TMP  DA    $0000       ; attivo per frame)
PB_X0       DA    $0000       ; scratch angolo per PLOT_SNOWFLAKE
PB_Y0       DA    $0000

; Tabelle di posizione iniziale, precalcolate in Python facendo girare
; UNA VOLTA (come lo "static...first" del C) esattamente le stesse
; formule di r_l1p80/r_l1p60 in timeless.c - nessun calcolo a runtime,
; stesso approccio gia' usato per LEAFX_TABLE/LEAFY_TABLE/SIN320/ecc.
; RAIN2_* = r_l1p80 (pioggia, 3 livelli 64/32/16 -> qui *_Y0/X0=64,
; *_Y1/X1=32, *_Y2/X2=16). SNOW_* = r_l1p60 (neve, stessa struttura).
RAIN2_Y0
            DA    192, 180, 160, 132, 96, 52, 0, 140
            DA    80, 12, 136, 60, 176, 92, 0, 100
            DA    0, 92, 184, 76, 160, 44, 120, 196
            DA    72, 140, 8, 68, 128, 188, 48, 100
            DA    152, 4, 48, 92, 136, 180, 24, 60
            DA    96, 132, 168, 4, 32, 60, 88, 116
            DA    144, 172, 0, 20, 40, 60, 80, 100
            DA    120, 140, 160, 180, 0, 12, 24, 36
RAIN2_X0
            DA    212, 40, 160, 280, 80, 172, 264, 36
            DA    100, 164, 228, 292, 36, 72, 108, 144
            DA    180, 216, 252, 288, 4, 12, 20, 28
            DA    36, 44, 52, 60, 68, 76, 84, 92
            DA    100, 108, 116, 124, 132, 140, 148, 156
            DA    164, 172, 180, 188, 196, 204, 212, 220
            DA    228, 236, 244, 252, 260, 268, 276, 284
            DA    292, 300, 308, 316, 4, -16, -36, -56
RAIN2_Y1
            DA    64, 160, 60, 152, 40, 128, 12, 96
            DA    176, 56, 132, 8, 80, 152, 24, 92
            DA    160, 28, 92, 156, 20, 80, 140, 0
            DA    56, 112, 168, 24, 76, 128, 180, 32
RAIN2_X1
            DA    200, 116, 32, 208, 124, 40, 156, 72
            DA    288, 204, 120, 36, 152, 68, 284, 200
            DA    116, 32, 148, 64, 280, 196, 112, 28
            DA    244, 160, 76, 292, 208, 124, 40, 256
RAIN2_Y2
            DA    132, 36, 132, 36, 132, 36, 132, 36
            DA    132, 36, 132, 36, 132, 36, 132, 36
RAIN2_X2
            DA    52, 68, 84, 100, 116, 132, 148, 164
            DA    180, 196, 212, 228, 244, 260, 276, 292
SNOW_Y0
            DA    0, 79, 158, 37, 113, 189, 65, 138
            DA    11, 81, 151, 21, 88, 155, 22, 86
            DA    150, 14, 75, 136, 197, 58, 116, 174
            DA    32, 87, 142, 197, 52, 104, 156, 8
            DA    57, 106, 155, 4, 50, 96, 142, 188
            DA    34, 77, 120, 163, 6, 46, 86, 126
            DA    166, 6, 43, 80, 117, 154, 191, 28
            DA    62, 96, 130, 164, 198, 32, 63, 94
SNOW_X0
            DA    0, 269, 218, 151, 68, 289, 190, 75
            DA    264, 133, 306, 159, 316, 153, 294, 115
            DA    240, 45, 154, 263, 52, 145, 238, 11
            DA    88, 165, 242, 319, 76, 137, 198, 259
            DA    0, 45, 90, 135, 180, 225, 270, 315
            DA    40, 69, 98, 127, 156, 185, 214, 243
            DA    272, 301, 10, 23, 36, 49, 62, 75
            DA    88, 101, 114, 127, 140, 153, 166, 179
SNOW_Y1
            DA    56, 151, 46, 135, 24, 107, 190, 73
            DA    150, 27, 98, 169, 40, 105, 170, 35
            DA    94, 153, 12, 65, 118, 171, 24, 71
            DA    118, 165, 12, 53, 94, 135, 176, 17
SNOW_X1
            DA    196, 114, 12, 210, 88, 266, 124, 282
            DA    120, 258, 76, 194, 312, 110, 208, 306
            DA    84, 162, 240, 318, 76, 134, 192, 250
            DA    308, 46, 84, 122, 160, 198, 236, 274
SNOW_Y2
            DA    132, 28, 116, 4, 84, 164, 44, 116
            DA    188, 60, 124, 188, 52, 108, 164, 20
SNOW_X2
            DA    52, 24, 288, 232, 148, 36, 216, 76
            DA    228, 60, 184, 308, 112, 208, 304, 80

; ---------------------------------------------------------------------
; PLOT_PIXEL: disegna UN pixel in VRAM (banco $01) usando BLIT_X/
; BLIT_Y come coordinate e BLIT_COLOR/BLIT_HINIB come colore (nibble
; basso / nibble alto preshiftato - stessi campi e stessa convenzione
; gia' collaudata in BLIT_SPRITE: sicuro da riusare, PLOT_PIXEL non
; gira mai nello stesso frame di BLIT_SPRITE, un solo L1 attivo alla
; volta). Il chiamante imposta BLIT_COLOR/BLIT_HINIB UNA VOLTA per
; chiamata a R_L1P60/80 (colore fisso per tutta la routine), non ad
; ogni pixel.
;
; *** LEZIONE da R_L1P90: qui il clipping e' VERO - se BLIT_Y>199 o
; BLIT_X fuori 0..319, il pixel viene SALTATO (RTS senza scrivere),
; niente clamp che "schiaccia" i pixel sul bordo e niente rischio di
; scrivere fuori dalle 200 righe reali dentro SCB/PALETTE.
; ---------------------------------------------------------------------
PLOT_PIXEL  REP   #$30
            MX    %00
            LDA   BLIT_Y
            BMI   :pp_skip
            CMP   #200
            BCS   :pp_skip
            LDA   BLIT_X
            BMI   :pp_skip
            CMP   #320
            BCS   :pp_skip

            LDA   BLIT_Y
            STA   BLIT_SCRATCH
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *128
            STA   BLIT_ROWADDR
            LDA   BLIT_SCRATCH
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *32
            CLC
            ADC   BLIT_ROWADDR
            STA   BLIT_ROWADDR

            LDA   BLIT_X
            AND   #$0001
            STA   BLIT_SCRATCH2
            LDA   BLIT_X
            LSR   A
            CLC
            ADC   BLIT_ROWADDR
            STA   BLIT_SCRATCH      ; byte offset in VRAM

            SEP   #$20
            MX    %10
            LDX   BLIT_SCRATCH
            LDA   >FAST_SHR_LONG,X
            LDX   BLIT_SCRATCH2
            BEQ   :pp_evenpix
            AND   #$F0
            ORA   BLIT_COLOR
            BRA   :pp_wb
:pp_evenpix AND   #$0F
            ORA   BLIT_HINIB
:pp_wb      LDX   BLIT_SCRATCH
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00
:pp_skip    RTS

; ---------------------------------------------------------------------
; PLOT_STREAK: disegna una striscia diagonale di BLIT_LEN pixel a
; partire da (BLIT_X,BLIT_Y) - un pixel in su e uno a destra ad ogni
; passo (coerente con "t - j*(ON_W-1)" nel C originale: al crescere di
; j, y cala di 1 e x cresce di 1). BLIT_LEN/BLIT_COLOR/BLIT_HINIB
; impostati dal chiamante prima della JSR.
; ---------------------------------------------------------------------
PLOT_STREAK REP   #$30
            MX    %00
:ps_loop    JSR   PLOT_PIXEL
            LDA   BLIT_Y
            SEC
            SBC   #1
            STA   BLIT_Y
            LDA   BLIT_X
            CLC
            ADC   #1
            STA   BLIT_X
            LDA   BLIT_LEN
            SEC
            SBC   #1
            STA   BLIT_LEN
            BNE   :ps_loop
            RTS

; ---------------------------------------------------------------------
; PLOT_SNOWFLAKE2X2: quadratino pieno 2x2 (livello medio di R_L1P60),
; angolo in alto a sinistra in BLIT_X/BLIT_Y.
; ---------------------------------------------------------------------
PLOT_SNOWFLAKE2X2
            REP   #$30
            MX    %00
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_Y
            JSR   PLOT_PIXEL
            DEC   BLIT_X
            JSR   PLOT_PIXEL
            DEC   BLIT_Y
            RTS

; ---------------------------------------------------------------------
; PLOT_SNOWFLAKE: fiocco "grande" di R_L1P60 - NON e' un quadrato 4x4
; pieno ma la sagoma esatta del C (4 memset a righe diverse): riga
; y+0 e y+3 strette (2px, offset+1), righe y+1 e y+2 piene (4px,
; offset+0) - un piccolo esagono/diamante. Angolo (x+0,y+0) in
; BLIT_X/BLIT_Y all'ingresso.
; ---------------------------------------------------------------------
PLOT_SNOWFLAKE
            REP   #$30
            MX    %00
            LDA   BLIT_Y
            STA   PB_Y0
            LDA   BLIT_X
            STA   PB_X0

            LDA   PB_Y0
            STA   BLIT_Y
            LDA   PB_X0
            CLC
            ADC   #1
            STA   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL

            LDA   PB_Y0
            CLC
            ADC   #1
            STA   BLIT_Y
            LDA   PB_X0
            STA   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL

            LDA   PB_Y0
            CLC
            ADC   #2
            STA   BLIT_Y
            LDA   PB_X0
            STA   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL

            LDA   PB_Y0
            CLC
            ADC   #3
            STA   BLIT_Y
            LDA   PB_X0
            CLC
            ADC   #1
            STA   BLIT_X
            JSR   PLOT_PIXEL
            INC   BLIT_X
            JSR   PLOT_PIXEL
            RTS

; ---------------------------------------------------------------------
; TL57: R_L1P80 - "vera pioggia" (porting fedele di r_l1p80 in
; timeless.c): a differenza di R_L1P90 (sprite pieni), disegna
; SEGMENTI DIAGONALI direttamente in VRAM (overlay davanti al tunnel,
; non dentro la texture deformata - ha piu' senso visivo cosi').
;
; Tre livelli come nel C: RAIN2_Y2/X2 (16 particelle, striscia 16px),
; RAIN2_Y1/X1 (32, striscia 8px), RAIN2_Y0/X0 (64 allocati, striscia
; 4px). RAIN2_NUM sale/scende 0..16 ogni turno di 240 chiamate
; (RAIN2_CNTR), stessa struttura di R_L1P90 ma tetto 16 (0x10) invece
; di 23 - preso identico dal C.
;
; *** NOTA FEDELTA': il livello piu' veloce (RAIN2_Y0/X0, 64 elementi
; allocati) nel C viene mosso e disegnato SOLO per i primi 32 indici
; ("for(i=0;i<32;++i)" anche se num*4 arriverebbe a 64) - sembra un
; limite/refuso dell'originale, riprodotto IDENTICO per fedelta' (non
; "corretto"): i restanti 32 elementi restano allocati ma mai usati,
; esattamente come nel C.
;
; *** SICUREZZA (lezione da R_L1P90): la y virtuale del C qui puo'
; arrivare oltre 199 (canvas originale piu' alto, ON_H=280) -
; PLOT_PIXEL salta il singolo pixel se cade fuori schermo invece di
; scriverlo comunque (clipping vero). La x invece resta sempre dentro
; 0..319 per costruzione (verificato a mano sulle costanti del C).
;
; Colore: nibble $0A (indice 10 = $05FF, ciano) - sfondo tunnel,
; niente SET_SCB_RANGE.
; ---------------------------------------------------------------------
R_L1P80     REP   #$30
            MX    %00

            LDA   RAIN2_CNTR
            SEC
            SBC   #1
            STA   RAIN2_CNTR
            BNE   :r8_active

            LDA   #120       ; *** TL59D: sequenza dimezzata (era 240)
            STA   RAIN2_CNTR
            STZ   RAIN2_NUM
            LDA   #1
            STA   RAIN2_NUMD
            JSR   L1_SETNEXT
            RTS

:r8_active
            CMP   #16
            BNE   :r8_noflip
            LDA   #$FFFF
            STA   RAIN2_NUMD
:r8_noflip
            LDA   RAIN2_NUM
            CLC
            ADC   RAIN2_NUMD
            STA   RAIN2_NUM
            BNE   :r8_notzero
            STZ   RAIN2_NUMD
            BRA   :r8_numdone
:r8_notzero CMP   #16
            BNE   :r8_numdone
            STZ   RAIN2_NUMD
:r8_numdone

            LDA   #$000A
            STA   BLIT_COLOR
            LDA   #$00A0
            STA   BLIT_HINIB

            ; --- livello grande/lento: 16 particelle, striscia 16px ---
            LDA   #16
            STA   L1_CNT_J
            STZ   L1_CNT_I
:r8_g2loop  LDA   L1_CNT_I
            ASL   A
            TAY
            LDA   RAIN2_Y2,Y
            CLC
            ADC   #16
            CMP   #208
            BCC   :r8_g2yok
            SEC
            SBC   #200
:r8_g2yok   STA   RAIN2_Y2,Y
            STA   BLIT_Y
            LDA   RAIN2_X2,Y
            SEC
            SBC   #16
            BPL   :r8_g2xok
            CLC
            ADC   #320
:r8_g2xok   STA   RAIN2_X2,Y
            STA   BLIT_X
            LDA   L1_CNT_I
            CMP   RAIN2_NUM
            BCS   :r8_g2skip
            LDA   #16
            STA   BLIT_LEN
            JSR   PLOT_STREAK
:r8_g2skip
            INC   L1_CNT_I
            LDA   L1_CNT_J
            SEC
            SBC   #1
            STA   L1_CNT_J
            BNE   :r8_g2loop

            ; --- livello medio: 32 particelle, striscia 8px ---
            LDA   #32
            STA   L1_CNT_J
            STZ   L1_CNT_I
:r8_g1loop  LDA   L1_CNT_I
            ASL   A
            TAY
            LDA   RAIN2_Y1,Y
            CLC
            ADC   #8
            CMP   #204
            BCC   :r8_g1yok
            SEC
            SBC   #200
:r8_g1yok   STA   RAIN2_Y1,Y
            STA   BLIT_Y
            LDA   RAIN2_X1,Y
            SEC
            SBC   #8
            BPL   :r8_g1xok
            CLC
            ADC   #320
:r8_g1xok   STA   RAIN2_X1,Y
            STA   BLIT_X
            LDA   RAIN2_NUM
            ASL   A
            STA   L1_CNT_TMP
            LDA   L1_CNT_I
            CMP   L1_CNT_TMP
            BCS   :r8_g1skip
            LDA   #8
            STA   BLIT_LEN
            JSR   PLOT_STREAK
:r8_g1skip
            INC   L1_CNT_I
            LDA   L1_CNT_J
            SEC
            SBC   #1
            STA   L1_CNT_J
            BNE   :r8_g1loop

            ; --- livello piccolo/veloce: SOLO 32 dei 64 slot (fedelta'
            ; al limite del C, vedi nota sopra), striscia 4px ---
            LDA   #32
            STA   L1_CNT_J
            STZ   L1_CNT_I
:r8_g0loop  LDA   L1_CNT_I
            ASL   A
            TAY
            LDA   RAIN2_Y0,Y
            CLC
            ADC   #4
            CMP   #202
            BCC   :r8_g0yok
            SEC
            SBC   #200
:r8_g0yok   STA   RAIN2_Y0,Y
            STA   BLIT_Y
            LDA   RAIN2_X0,Y
            SEC
            SBC   #4
            BPL   :r8_g0xok
            CLC
            ADC   #320
:r8_g0xok   STA   RAIN2_X0,Y
            STA   BLIT_X
            LDA   RAIN2_NUM
            ASL   A
            ASL   A
            STA   L1_CNT_TMP
            LDA   L1_CNT_I
            CMP   L1_CNT_TMP
            BCS   :r8_g0skip
            LDA   #4
            STA   BLIT_LEN
            JSR   PLOT_STREAK
:r8_g0skip
            INC   L1_CNT_I
            LDA   L1_CNT_J
            SEC
            SBC   #1
            STA   L1_CNT_J
            BNE   :r8_g0loop

            RTS

; ---------------------------------------------------------------------
; TL57: R_L1P60 - "vera neve" (porting fedele di r_l1p60 in
; timeless.c): stessa struttura a 3 livelli di R_L1P80, ma disegna
; fiocchi (non strisce). La y virtuale qui NON supera mai 199 (i tre
; contatori wrappano esattamente a 200, verificato a mano sulle
; costanti del C) - PLOT_PIXEL non deve mai scartare nulla per
; overflow verticale in questo effetto (lo fa comunque, innocuo). La
; x resta sempre 0..319 per costruzione, come in R_L1P80.
;
; Livelli: SNOW_Y2/X2 (16, fiocco 4x4 sagomato PLOT_SNOWFLAKE),
; SNOW_Y1/X1 (32, quadratino 2x2 PLOT_SNOWFLAKE2X2), SNOW_Y0/X0 (64,
; singolo pixel PLOT_PIXEL - qui, A DIFFERENZA di R_L1P80, il livello
; piccolo usa TUTTI e 64 gli slot: il C stesso usa "for(i=0;i<64;++i)"
; qui, nessuna incongruenza da riprodurre).
;
; Colore: nibble $0F (indice 15 = $0FFF, bianco) - sfondo tunnel,
; niente SET_SCB_RANGE.
; ---------------------------------------------------------------------
R_L1P60     REP   #$30
            MX    %00

            LDA   SNOW_CNTR
            SEC
            SBC   #1
            STA   SNOW_CNTR
            BNE   :r6_active

            LDA   #120       ; *** TL59D: sequenza dimezzata (era 240)
            STA   SNOW_CNTR
            STZ   SNOW_NUM
            LDA   #1
            STA   SNOW_NUMD
            JSR   L1_SETNEXT
            RTS

:r6_active
            CMP   #16
            BNE   :r6_noflip
            LDA   #$FFFF
            STA   SNOW_NUMD
:r6_noflip
            LDA   SNOW_NUM
            CLC
            ADC   SNOW_NUMD
            STA   SNOW_NUM
            BNE   :r6_notzero
            STZ   SNOW_NUMD
            BRA   :r6_numdone
:r6_notzero CMP   #16
            BCC   :r6_numdone
            STZ   SNOW_NUMD
:r6_numdone

            LDA   #$000F
            STA   BLIT_COLOR
            LDA   #$00F0
            STA   BLIT_HINIB

            ; --- fiocco grande: 16 particelle, sagoma 4x4 ---
            LDA   #16
            STA   L1_CNT_J
            STZ   L1_CNT_I
:r6_g2loop  LDA   L1_CNT_I
            ASL   A
            TAY
            LDA   SNOW_Y2,Y
            CLC
            ADC   #4
            CMP   #200
            BCC   :r6_g2yok
            SEC
            SBC   #200
:r6_g2yok   STA   SNOW_Y2,Y
            STA   BLIT_Y
            LDA   SNOW_X2,Y
            SEC
            SBC   #4
            BPL   :r6_g2xok
            CLC
            ADC   #320
:r6_g2xok   STA   SNOW_X2,Y
            STA   BLIT_X
            LDA   L1_CNT_I
            CMP   SNOW_NUM
            BCS   :r6_g2skip
            JSR   PLOT_SNOWFLAKE
:r6_g2skip
            INC   L1_CNT_I
            LDA   L1_CNT_J
            SEC
            SBC   #1
            STA   L1_CNT_J
            BNE   :r6_g2loop

            ; --- medio: 32 particelle, quadratino 2x2 ---
            LDA   #32
            STA   L1_CNT_J
            STZ   L1_CNT_I
:r6_g1loop  LDA   L1_CNT_I
            ASL   A
            TAY
            LDA   SNOW_Y1,Y
            CLC
            ADC   #2
            CMP   #200
            BCC   :r6_g1yok
            SEC
            SBC   #200
:r6_g1yok   STA   SNOW_Y1,Y
            STA   BLIT_Y
            LDA   SNOW_X1,Y
            SEC
            SBC   #2
            BPL   :r6_g1xok
            CLC
            ADC   #320
:r6_g1xok   STA   SNOW_X1,Y
            STA   BLIT_X
            LDA   SNOW_NUM
            ASL   A
            STA   L1_CNT_TMP
            LDA   L1_CNT_I
            CMP   L1_CNT_TMP
            BCS   :r6_g1skip
            JSR   PLOT_SNOWFLAKE2X2
:r6_g1skip
            INC   L1_CNT_I
            LDA   L1_CNT_J
            SEC
            SBC   #1
            STA   L1_CNT_J
            BNE   :r6_g1loop

            ; --- piccolo: 64 particelle, singolo pixel ---
            LDA   #64
            STA   L1_CNT_J
            STZ   L1_CNT_I
:r6_g0loop  LDA   L1_CNT_I
            ASL   A
            TAY
            LDA   SNOW_Y0,Y
            CLC
            ADC   #1
            CMP   #200
            BCC   :r6_g0yok
            SEC
            SBC   #200
:r6_g0yok   STA   SNOW_Y0,Y
            STA   BLIT_Y
            LDA   SNOW_X0,Y
            SEC
            SBC   #1
            BPL   :r6_g0xok
            CLC
            ADC   #320
:r6_g0xok   STA   SNOW_X0,Y
            STA   BLIT_X
            LDA   SNOW_NUM
            ASL   A
            ASL   A
            STA   L1_CNT_TMP
            LDA   L1_CNT_I
            CMP   L1_CNT_TMP
            BCS   :r6_g0skip
            JSR   PLOT_PIXEL
:r6_g0skip
            INC   L1_CNT_I
            LDA   L1_CNT_J
            SEC
            SBC   #1
            STA   L1_CNT_J
            BNE   :r6_g0loop

            RTS

; ---------------------------------------------------------------------
; SPRITE VERI: due icone in piu' per l'orbita (cspr0a/cspr17)
; ---------------------------------------------------------------------
; TL58: dati e routine per R_L1P40 (icona con occhi/ali che vola) -
; ultima sequenza L1 mancante rispetto al C originale (r_l1p00..r_l1p90,
; 10 in tutto - ora le abbiamo tutte e 10). Porting fedele di r_l1p40 +
; le 8 funzioni ausiliarie p40r0a/b..p40r3a/b in timeless.c: una
; singola "loc" condivisa avanza lungo un percorso a 8 tratti
; (posroutindex 0..7, ma solo 4 funzioni distinte per famiglia - "a" e
; "b" - ripetute due volte ciascuna, fedele all'originale: il C usa
; {p40r0a,p40r1a,p40r2a,p40r3a,p40r0a,p40r1a,p40r2a,p40r3a} come
; tabella a 8 voci). Ogni frame disegna DUE sprite sovrapposti (ala +
; icona centrale) in DUE punti (le due "ali" della figura), calcolati
; dalla stessa loc con formule diverse per famiglia "a" (fa avanzare
; loc) e "b" (legge la loc gia' avanzata e segnala la fine del tratto).
;
; *** SICUREZZA (stessa lezione di R_L1P90/R_L1P80/R_L1P60): il canvas
; originale e' 400x280 (ON_W/ON_H), il nostro schermo reale e' 320x200.
; Le formule del C producono x fino a ~393 e y fino a ~226, oltre i
; nostri bordi. BLIT_SPRITE non fa bound-check (vedi il bug gia'
; trovato su R_L1P90: scrivere oltre riga 199 nel banco $01 corrompe
; SCB/palette per lo shadowing hardware) quindi clampiamo (min 0, max
; scelto per tenere l'intero sprite dentro lo schermo) sia sulla base
; dell'ala (sprite piu' largo, fino a ~70px) sia su quella dell'icona
; centrale (sprite piccolo come cspr0a/17, stessi margini gia' usati
; da R_L1P90/orbita).
;
; Sprite: wingframe[] = cspr0b,cspr0c,cspr0d,cspr0c (ali, nuovi, da
; sprites.c); centercsprtbl[] = cspr0a,cspr17,cspr11,cspr10,cspr22
; (icona centrale - cspr0a/17 gia' presenti per l'orbita, cspr11/10
; nuovi, aggiunti in fondo al file insieme a cspr0b/0c/0d). Tema
; colore: BLIT_THEME=1 (stesso "caldo" gia' usato per l'orbita, che
; condivide cspr0a/17 con questa sequenza).
; ---------------------------------------------------------------------

; --- stato persistente (bank 0, fuori dalla zero page: stesso motivo
; di RAIN2_*/SNOW_* in TL57 - la zero page "Gruppo A" e' piena e
; questo stato deve sopravvivere turno-su-turno come RAIN_* per R_L1P90) ---
L1P40_LOC      DA    $0000     ; "loc" condivisa dalle 8 funzioni ausiliarie
L1P40_FRAME0   DA    $0000     ; "frame[0]" - inizializzato a 0 in START
L1P40_FRAME1   DA    $0000     ; "frame[1]" - inizializzato a 2 in START
L1P40_POSIDX   DA    $0000     ; "posroutindex" 0..7
L1P40_CTRIDX   DA    $0000     ; "centercspri" 0..4

; --- scratch (transitorio, ricalcolato ogni chiamata/passo) ---
L1P40_X        DA    $0000     ; "x" della funzione ausiliaria corrente
L1P40_Y        DA    $0000     ; "y" della funzione ausiliaria corrente
L1P40_RES      DA    $0000     ; valore di ritorno (0/1) delle funzioni "b"
L1P40_FRAME_CUR DA   $0000     ; quale frame[] usare nel disegno di questo passo

WINGFRAME_TBL   DA    CSPR0B_DATA, CSPR0C_DATA, CSPR0D_DATA, CSPR0C_DATA
CENTERCSPR_TBL  DA    CSPR0A_DATA, CSPR17_DATA, CSPR11_DATA, CSPR10_DATA, CSPR22_DATA

; ---------------------------------------------------------------------
; P40R0A/P40R0B .. P40R3A/P40R3B: le 8 funzioni ausiliarie (posrouttbl
; nel C) - ognuna calcola (x,y) a partire dalla loc condivisa, con la
; propria soglia di fine tratto. Famiglia "a": non segnala mai fine
; tratto (return 1) - fa sempre avanzare loc per prima. Famiglia "b":
; legge la stessa loc (gia' avanzata dalla "a" corrispondente nello
; stesso frame) e segnala la fine del tratto in L1P40_RES quando
; raggiunge la sua soglia. Lette da SINCOS0_TABLE (stessa tabella e
; stesso accesso a 16 bit + AND #$00FF gia' usato da R_L1P90).
; ---------------------------------------------------------------------
P40R0A      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            LDA   L1P40_LOC
            CLC
            ADC   #2
            STA   L1P40_LOC
            CMP   #50
            BCC   :p0a_done
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #131
            STA   L1P40_X
            LDA   L1P40_LOC
            SEC
            SBC   #50
            STA   L1P40_Y
:p0a_done   RTS

P40R0B      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            STZ   L1P40_RES
            LDA   L1P40_LOC
            CMP   #276
            BNE   :p0b_chk
            LDA   #1
            STA   L1P40_RES
            RTS
:p0b_chk    CMP   #226
            BCS   :p0b_done
            CLC
            ADC   #78            ; (loc-50+128) = loc+78
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF         ; *** NOTA: qui NIENTE >>1 (fedele al C,
                                  ; diverso da tutte le altre 7 funzioni)
            CLC
            ADC   #131
            STA   L1P40_X
            LDA   L1P40_LOC
            STA   L1P40_Y
:p0b_done   RTS

P40R1A      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            LDA   L1P40_LOC
            CLC
            ADC   #3
            STA   L1P40_LOC
            CMP   #80
            BCC   :p1a_done
            SEC
            SBC   #80
            STA   L1P40_X
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #49
            STA   L1P40_Y
:p1a_done   RTS

P40R1B      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            STZ   L1P40_RES
            LDA   L1P40_LOC
            CMP   #472
            BCC   :p1b_chk
            LDA   #1
            STA   L1P40_RES
            RTS
:p1b_chk    CMP   #392
            BCS   :p1b_done
            STA   L1P40_X        ; x = loc (A non cambiata dalla CMP)
            SEC
            SBC   #208           ; x-80-128
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #49
            STA   L1P40_Y
:p1b_done   RTS

P40R2A      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            LDA   L1P40_LOC
            CLC
            ADC   #2
            STA   L1P40_LOC
            CMP   #50
            BCC   :p2a_done
            SEC
            SBC   #50
            STA   L1P40_Y        ; y = loc-50 (temporaneo)
            SEC
            SBC   #178           ; y-50-128
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #131
            STA   L1P40_X
            LDA   #226
            SEC
            SBC   L1P40_Y
            STA   L1P40_Y        ; y = 226 - y
:p2a_done   RTS

P40R2B      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            STZ   L1P40_RES
            LDA   L1P40_LOC
            CMP   #276
            BNE   :p2b_chk
            LDA   #1
            STA   L1P40_RES
            RTS
:p2b_chk    CMP   #226
            BCS   :p2b_done
            SEC
            SBC   #178           ; loc-50-128
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #131
            STA   L1P40_X
            LDA   #224
            SEC
            SBC   L1P40_LOC
            STA   L1P40_Y
:p2b_done   RTS

P40R3A      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            LDA   L1P40_LOC
            CLC
            ADC   #3
            STA   L1P40_LOC
            CMP   #78
            BCC   :p3a_done
            SEC
            SBC   #78
            STA   L1P40_X        ; x = loc-78 (temporaneo)
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #49
            STA   L1P40_Y
            LDA   #396
            SEC
            SBC   L1P40_X
            STA   L1P40_X        ; x = 396 - x
:p3a_done   RTS

P40R3B      REP   #$30
            MX    %00
            STZ   L1P40_X
            STZ   L1P40_Y
            STZ   L1P40_RES
            LDA   L1P40_LOC
            CMP   #474
            BNE   :p3b_chk
            LDA   #1
            STA   L1P40_RES
            RTS
:p3b_chk    CMP   #396
            BCS   :p3b_done
            SEC
            SBC   #206           ; loc-78-128
            AND   #$00FF
            TAX
            LDA   SINCOS0_TABLE,X
            AND   #$00FF
            LSR   A
            CLC
            ADC   #49
            STA   L1P40_Y
            LDA   #393
            SEC
            SBC   L1P40_LOC
            STA   L1P40_X
:p3b_done   RTS

; ---------------------------------------------------------------------
; L1P40_DRAWPAIR: disegna ala + icona centrale.
; ---------------------------------------------------------------------
L1P40_DRAWPAIR
            REP   #$30
            MX    %00

            ; *** TL58H FIX v2: l'ala e l'icona centrale DEVONO restare
            ; alla stessa distanza relativa (+24 colonne, +9 righe)
            ; anche quando la posizione tocca il bordo schermo. Prima
            ; clampavo ala e icona SEPARATAMENTE con soglie diverse
            ; (240 per l'ala, 290 per l'icona): vicino al bordo destro
            ; l'ala restava ferma a 240 mentre l'icona (240+24=264, non
            ; ancora al suo limite di 290) continuava ad avanzare da
            ; sola - l'icona "scappava" a destra separandosi dall'ala,
            ; esattamente il difetto segnalato. Ora si clampa la
            ; posizione condivisa UNA SOLA VOLTA, prima di derivare ala
            ; e icona: entrambe restano sempre alla stessa distanza
            ; relativa, qualunque sia il valore grezzo (le formule del
            ; C arrivano a x~386, y~226, oltre i nostri 320x200).
            LDA   L1P40_X
            ORA   L1P40_Y
            BNE   :l40dp_go
            RTS
:l40dp_go
            LDA   L1P40_X
            CMP   #240             ; 240+71(ala piu' larga)=311<320,
            BCC   :l40dp_xok       ; 240+24+21(icona)=285<320: sicuro
            LDA   #240             ; per entrambe con lo stesso limite
:l40dp_xok  STA   L1P40_X
            LDA   L1P40_Y
            CMP   #169             ; 169+21(ala)=190<200,
            BCC   :l40dp_yok       ; 169+9+21(icona)=199<200: sicuro
            LDA   #169             ; per entrambe con lo stesso limite
:l40dp_yok  STA   L1P40_Y

            ; --- ala (posizione gia' clampata sopra) ---
            LDA   #1
            STA   BLIT_THEME
            LDA   L1P40_X
            STA   BLIT_BASE_X
            LDA   L1P40_Y
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE
            REP   #$30
            MX    %00
            ; *** TL58E: SEI qui, PRIMA di leggere/raddoppiare/usare
            ; L1P40_FRAME_CUR come indice - questo calcolo (LDA/ASL/TAX/
            ; LDA WINGFRAME_TBL,X/STA BLIT_PTR) e' un carico+deposito a
            ; 16 bit come un altro; se un interrupt del player arriva
            ; QUI e il suo rientro forza A/X a 8 bit (SEP #$30, vedi nota
            ; storica su BLIT_SPRITE), sia la STA BLIT_PTR sotto scrive
            ; SOLO il byte basso del puntatore, lasciando il byte alto
            ; quello VECCHIO del giro precedente - puntatore quasi giusto
            ; ma sbagliato, sprite "sporco" invece che ovviamente rotto.
            ; Non serve CLI esplicito: la JSR BLIT_SPRITE subito sotto fa
            ; gia' il suo SEI (innocuo, gia' attivo) e il suo CLI in
            ; uscita chiude la finestra aperta qui.
            SEI
            LDA   L1P40_FRAME_CUR
            ASL   A
            TAX
            LDA   WINGFRAME_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE
            REP   #$30
            MX    %00

            ; --- icona centrale, offset fisso +24/+9 dalla STESSA
            ; posizione (gia' clampata) usata per l'ala - niente
            ; secondo clamp indipendente, cosi' la distanza relativa
            ; non cambia mai ---
            LDA   L1P40_X
            CLC
            ADC   #24
            STA   BLIT_BASE_X
            LDA   L1P40_Y
            CLC
            ADC   #9
            STA   BLIT_BASE_Y
            JSR   SET_SCB_RANGE
            REP   #$30
            MX    %00
            ; *** TL58E: stessa protezione di poco sopra (ala), stesso
            ; motivo - vedi il commento li'.
            SEI
            LDA   L1P40_CTRIDX
            ASL   A
            TAX
            LDA   CENTERCSPR_TBL,X
            STA   BLIT_PTR
            JSR   BLIT_SPRITE
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
R_L1P40     REP   #$30
            MX    %00
            LDA   #1
            STA   BLIT_THEME        ; stesso tema "caldo" dell'orbita
                                     ; (condivide cspr0a/cspr17)

            ; --- passo 1: famiglia "a" ---
            LDA   L1P40_POSIDX
            AND   #$0003
            CMP   #1
            BEQ   :l40_a1
            CMP   #2
            BEQ   :l40_a2
            CMP   #3
            BEQ   :l40_a3
            JSR   P40R0A
            BRA   :l40_adone
:l40_a1     JSR   P40R1A
            BRA   :l40_adone
:l40_a2     JSR   P40R2A
            BRA   :l40_adone
:l40_a3     JSR   P40R3A
:l40_adone

            LDA   L1P40_FRAME0
            CLC
            ADC   #1
            AND   #$0003
            STA   L1P40_FRAME0
            STA   L1P40_FRAME_CUR

            JSR   L1P40_DRAWPAIR

            ; --- passo 2: famiglia "b" ---
            LDA   L1P40_POSIDX
            AND   #$0003
            CMP   #1
            BEQ   :l40_b1
            CMP   #2
            BEQ   :l40_b2
            CMP   #3
            BEQ   :l40_b3
            JSR   P40R0B
            BRA   :l40_bdone
:l40_b1     JSR   P40R1B
            BRA   :l40_bdone
:l40_b2     JSR   P40R2B
            BRA   :l40_bdone
:l40_b3     JSR   P40R3B
:l40_bdone

            LDA   L1P40_FRAME1
            CLC
            ADC   #1
            AND   #$0003
            STA   L1P40_FRAME1
            STA   L1P40_FRAME_CUR

            JSR   L1P40_DRAWPAIR

            ; fine tratto? (solo la "b" lo puo' segnalare)
            LDA   L1P40_RES
            BEQ   :l40_end
            LDA   L1P40_POSIDX
            CLC
            ADC   #1
            AND   #$0007
            STA   L1P40_POSIDX
            STZ   L1P40_LOC
            LDA   L1P40_CTRIDX
            CLC
            ADC   #1
            CMP   #5
            BCC   :l40_ctrok
            LDA   #0
:l40_ctrok  STA   L1P40_CTRIDX
            JSR   L1_SETNEXT
:l40_end    RTS



; ---------------------------------------------------------------------
; SET_SCB_RANGE: imposta la SCB (palette per riga) su BLIT_THEME per
; 32 righe a partire da BLIT_BASE_Y (altezza fissa dello sprite test).
; ---------------------------------------------------------------------
SET_SCB_RANGE
            ; *** TL58C: SEI in testa, CLI appena prima della RTS (unico
            ; punto di uscita) - nessun interrupt puo' arrivare durante
            ; il loop di 32 iterazioni, quindi il cambio A 8/16 bit qui
            ; dentro non e' piu' a rischio (anche se resta comunque
            ; corretto dal fix TL58B, che teniamo come rete di sicurezza).
            SEI
            REP   #$30
            MX    %00
            LDA   BLIT_BASE_Y
            STA   BLIT_SCRATCH
            LDA   #32
            STA   BLIT_SCRATCH2
:scb_loop   LDA   BLIT_SCRATCH
            CMP   #200
            BCS   :scb_next
            TAX
            SEP   #$20
            MX    %10
            LDA   BLIT_THEME
            STA   >SCB_BASE,X
            REP   #$30
            MX    %00
:scb_next   LDA   BLIT_SCRATCH
            CLC
            ADC   #1
            STA   BLIT_SCRATCH
            LDA   BLIT_SCRATCH2
            SEC
            SBC   #1
            STA   BLIT_SCRATCH2
            BNE   :scb_loop
            CLI
            RTS

; ---------------------------------------------------------------------
; BLIT_SPRITE: disegna DIRETTAMENTE in VRAM (banco $01) lo sprite
; puntato da BLIT_PTR (formato strip: lunghezza,x,y,colori... 0 finale)
; a partire dalla posizione BLIT_BASE_X/BLIT_BASE_Y. Ogni pixel e' un
; read-modify-write di nibble (2 pixel per byte in VRAM 4bpp). I colori
; raw (0xC0-0xEB) passano da REMAP_TABLE (nibble basso -> 1..5).
; ---------------------------------------------------------------------
; *** TL58A: ripartenza da TL58 (tl58h/tl59* abbandonati). Ipotesi
; sul crash con musica attiva: qui dentro (e in STAMP_TILE/
; STAMP_TILE_SCALED sotto) si alterna SEP #$20 (solo A a 8 bit, X
; resta a 16) / REP #$20 (solo A torna a 16). Se l'interrupt del
; player arriva durante la finestra a 8 bit e il suo ritorno forza
; SEP #$30 (A E X entrambi a 8, non solo A - vedi nota storica TL49
; piu' sopra nel file), il successivo "REP #$20" locale rimette a 16
; bit SOLO A: X resta bloccato a 8 bit senza che nessuno se ne accorga,
; e i successivi accessi indicizzati (STA >FAST_SHR_LONG,X) leggono/
; scrivono con l'indice troncato.
; *** TL58B: il fix di TL58A (solo qui + STAMP_TILE/STAMP_TILE_SCALED)
; non ha impedito un crash (BRK a 00/32DA, A=$A010 X=$A003, con le ali
; - R_L1P40 - come prima cosa disegnata). Trovato lo stesso identico
; schema SEP #$20/REP #$20 anche in SET_SCB_RANGE (:scb_loop, chiamata
; da OGNI routine sprite comprese le ali, in loop 32 volte a chiamata -
; bersaglio molto piu' facile da colpire) e in altre 47 posizioni sparse
; nel file (DOTS_PLOT16, LINES_HFILL/VFILL, PLOT_PIXEL/STREAK/
; SNOWFLAKE, GENERATE_OFFSCREEN, INIT_GNBGTBL, MULSHR8U/MUL16U, ecc).
; Verificato che X non serve MAI a 8 bit da solo in tutto il file
; (nessun "MX %01" da nessuna parte) - quindi rimettere anche X a 16
; bit e' sempre corretto e non costa nulla. Cambiati TUTTI i "REP #$20"
; del file (48 in piu' oltre ai 14 di TL58A, totale 62) in "REP #$30".
BLIT_SPRITE
            ; *** TL58C: riscritta da zero. Due cambi rispetto a TL58B:
            ;
            ; 1) SEI in testa, CLI appena prima delle due uscite (0 =
            ;    fine sprite, e la normale fine strip/pixel loop). Per
            ;    tutta la durata del disegno di QUESTO sprite nessun
            ;    interrupt del player puo' scattare - qualunque cosa
            ;    NTP corrompa al rientro (A/X a 8 bit, o altro) non ha
            ;    piu' importanza perche' non puo' proprio arrivare qui
            ;    in mezzo. E' una singola chiamata breve (un solo
            ;    sprite), non l'intero frame come GNBG_RENDER - quindi
            ;    non dovrebbe affamare la musica come tl58l/tl59l.
            ;
            ; 2) Lettura lunghezza/x/y della striscia senza piu' il giro
            ;    SEP #$20 / LDA / REP #$30 per ciascuno dei 3 campi:
            ;    "LDA (BLIT_PTR)" gia' a 16 bit legge byte[0]+byte[1],
            ;    "AND #$00FF" scarta il byte[1] (dato adiacente, mai
            ;    scritto ne' usato) e tiene solo byte[0] che serve -
            ;    stesso risultato, 3 cambi di modalita' in meno per
            ;    ogni striscia. NON tocco invece i due punti dove il 
            ;    passaggio a 8 bit e' necessario per correttezza (colore/
            ;    BLIT_HINIB e il read-modify-write di UN SOLO byte VRAM
            ;    in >FAST_SHR_LONG,X): un STA a 16 bit li' scriverebbe
            ;    per sbaglio anche il byte adiacente.
            SEI
            REP   #$30
            MX    %00
:bs_strip   LDA   (BLIT_PTR)        ; lunghezza strip (scarta byte adiacente)
            AND   #$00FF
            BNE   :bs_go             ; branch corto sicuro (:bs_done e' lontano)
            JMP   :bs_done           ; 0 = fine sprite
:bs_go
            STA   BLIT_LEN
            ; *** TL58F: rete di sicurezza - pensata quando il vero bug
            ; era ancora ignoto (collisione STAGE_BUF/IO_BUFFER con le
            ; tabelle sprite, risolta in TL59/TL59B): se la lunghezza
            ; strip letta e' assurda, meglio interrompere pulito questo
            ; sprite (salta a fine disegno) che proseguire alla cieca
            ; fino al crash.
            ;
            ; *** TL59E FIX: soglia 32 SBAGLIATA - era tarata solo su
            ; ala/lumaca/icona (max reale 26 li'), ma CSPR00_DATA (primo
            ; frame della margherita) ha una striscia reale lunga
            ; ESATTAMENTE 32 pixel, quindi veniva scartata ogni volta:
            ; e' la causa del frame di margherita "tagliato a meta'"
            ; segnalato dopo TL59D. Verificato con uno script su TUTTE
            ; le tabelle CSPRxx_DATA del gioco: il massimo reale assoluto
            ; e' 32 (solo in CSPR00), tutto il resto sta sotto 26. Soglia
            ; alzata a 48 - margine reale sopra il massimo vero, ma
            ; ancora ben lontana da poter leggere un puntatore/indice
            ; impazzito come lunghezza valida.
            CMP   #48
            BCC   :bs_lenok
            JMP   :bs_done
:bs_lenok
            INC   BLIT_PTR

            LDA   (BLIT_PTR)        ; x relativo
            AND   #$00FF
            CLC
            ADC   BLIT_BASE_X
            STA   BLIT_X
            INC   BLIT_PTR

            LDA   (BLIT_PTR)        ; y relativo
            AND   #$00FF
            CLC
            ADC   BLIT_BASE_Y
            STA   BLIT_Y
            INC   BLIT_PTR

            ; riga VRAM = y*160 (160=128+32)
            LDA   BLIT_Y
            STA   BLIT_SCRATCH
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *128
            STA   BLIT_ROWADDR
            LDA   BLIT_SCRATCH
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *32
            CLC
            ADC   BLIT_ROWADDR
            STA   BLIT_ROWADDR

:bs_pixel   SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)        ; colore raw (0xC0-0xEB)
            AND   #$0F
            TAX
            LDA   REMAP_TABLE,X
            STA   BLIT_COLOR
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            STA   BLIT_HINIB
            REP   #$30
            MX    %00
            INC   BLIT_PTR

            LDA   BLIT_X
            AND   #$0001
            STA   BLIT_SCRATCH2
            LDA   BLIT_X
            LSR   A
            CLC
            ADC   BLIT_ROWADDR
            STA   BLIT_SCRATCH

            SEP   #$20
            MX    %10
            LDX   BLIT_SCRATCH
            LDA   >FAST_SHR_LONG,X
            LDX   BLIT_SCRATCH2
            BEQ   :bs_evenpix
            ; *** TL42 FIX: X dispari = pixel di DESTRA della coppia
            ; -> nibble BASSO (stessa convenzione di GNBG_RENDER, dove
            ; PACK_BYTE=(CL<<4)|CR: sinistra=alto, destra=basso).
            ; Prima era invertito -> zig-zag visibile sullo sprite.
            AND   #$F0
            ORA   BLIT_COLOR
            BRA   :bs_wb
:bs_evenpix ; X pari = pixel di SINISTRA della coppia -> nibble ALTO
            AND   #$0F
            ORA   BLIT_HINIB
:bs_wb      LDX   BLIT_SCRATCH
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00

            LDA   BLIT_X
            CLC
            ADC   #1
            STA   BLIT_X
            LDA   BLIT_LEN
            SEC
            SBC   #1
            STA   BLIT_LEN
            BEQ   :bs_strip_next     ; branch corto sicuro
            JMP   :bs_pixel
:bs_strip_next
            JMP   :bs_strip
:bs_done    CLI
            RTS

; nibble basso del colore raw (0-15, livello di sfumatura dentro il
; "banco" da 16 della palette PC originale) -> nostri slot 1-5
REMAP_TABLE DFB   $01, $01, $01, $02, $02, $02, $03, $03
            DFB   $03, $04, $04, $04, $05, $05, $05, $05

; ---------------------------------------------------------------------
; STAMP_TILE: come BLIT_SPRITE ma scrive DENTRO la texture offscreen
; (banco $02, 256x256, un byte per texel - niente nibble da
; impacchettare, piu' semplice del blit su schermo) invece che in VRAM.
; Usa BLIT_PTR/BLIT_BASE_X/BLIT_BASE_Y (li' il chiamante mette
; puntatore sprite e posizione nella texture, 0-255) esattamente come
; BLIT_SPRITE - girano in momenti diversi (questa solo in START, prima
; che INIT_GNBGTBL/MAIN_LOOP tocchino di nuovo quello spazio), quindi
; il riuso e' sicuro.
;
; IMPORTANTE: qui NON possiamo usare gli slot 1-5 a tema come per gli
; sprite su schermo, perche' la texture viene campionata a posizioni
; che cambiano scanline per scanline mentre il tunnel gira - potrebbe
; finire su una riga con un tema diverso da quello con cui l'abbiamo
; stampata. Usiamo quindi TILE_REMAP_TABLE, che rimappa nei colori di
; SFONDO (slot 6-15, identici in tutti e 4 i temi) invece che nei
; colori sprite.
; ---------------------------------------------------------------------
STAMP_TILE  REP   #$30
            MX    %00
:st_strip   SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            REP   #$30
            MX    %00
            AND   #$00FF
            BNE   :st_go
            JMP   :st_done
:st_go      STA   BLIT_LEN
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

            SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            REP   #$30
            MX    %00
            AND   #$00FF
            CLC
            ADC   BLIT_BASE_X
            AND   #$00FF
            STA   BLIT_X
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

            SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            REP   #$30
            MX    %00
            AND   #$00FF
            CLC
            ADC   BLIT_BASE_Y
            AND   #$00FF
            STA   BLIT_Y
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

:st_pixel   SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            AND   #$0F
            TAX
            LDA   TILE_REMAP_TABLE,X
            STA   BLIT_COLOR
            REP   #$30
            MX    %00
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

            LDA   BLIT_Y
            AND   #$00FF
            XBA
            ORA   BLIT_X
            TAX

            SEP   #$20
            MX    %10
            LDA   BLIT_COLOR
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            LDA   BLIT_X
            CLC
            ADC   #1
            AND   #$00FF
            STA   BLIT_X

            LDA   BLIT_LEN
            SEC
            SBC   #1
            STA   BLIT_LEN
            BEQ   :st_strip_next
            JMP   :st_pixel
:st_strip_next
            JMP   :st_strip
:st_done    RTS

; ---------------------------------------------------------------------
; TL53: STS_MUL_SCALE - moltiplicazione ripetuta per addizione, usata
; solo qui: valore (0..31 tipico) * STAMP_SCALE (1..4 tipico). Con
; fattori cosi' piccoli una somma ripetuta e' piu' semplice di una vera
; routine di moltiplicazione e non serve altrove nel file.
; Ingresso: A (16 bit) = valore da moltiplicare.
; Uscita:   A (16 bit) = valore * STAMP_SCALE.
; Sporca:   BLIT_SCRATCH, BLIT_SCRATCH2, X.
; ---------------------------------------------------------------------
STS_MUL_SCALE
            REP   #$30
            MX    %00
            STA   BLIT_SCRATCH        ; valore originale
            LDA   STAMP_SCALE
            AND   #$00FF
            STA   BLIT_SCRATCH2       ; contatore = quante copie sommare
            LDA   #0
:sms_loop   LDX   BLIT_SCRATCH2
            BEQ   :sms_done
            CLC
            ADC   BLIT_SCRATCH
            DEC   BLIT_SCRATCH2
            BRA   :sms_loop
:sms_done   RTS

; ---------------------------------------------------------------------
; TL53: STS_DRAW_BLOCK - disegna un blocco STAMP_SCALE x STAMP_SCALE
; (tutti dello stesso colore BLIT_COLOR) con l'angolo in alto a
; sinistra in (BLIT_X, BLIT_Y). Questo e' il "pixel ingrandito": con
; STAMP_SCALE=1 disegna esattamente un pixel, come STAMP_TILE liscio.
; BLIT_X/BLIT_Y possono qui superare 255 (non ancora wrappati dal
; chiamante): li wrappiamo un byte alla volta dentro al ciclo, come
; gia' faceva STAMP_TILE per il caso non scalato.
; Sporca: BLIT_SCRATCH (righe/colonne totali - *** TL54 FIX: era BLIT_THEME,
; vedi nota piu' sotto), BLIT_HINIB (dy), BLIT_SCRATCH2 (dx), BLIT_ROWADDR
; (riga*256 corrente), X. Nessuno di questi campi serve al chiamante
; (STAMP_TILE_SCALED) durante la stampa del blocco.
; ---------------------------------------------------------------------
STS_DRAW_BLOCK
            REP   #$30
            MX    %00
            LDA   STAMP_SCALE
            AND   #$00FF
            ; *** TL54 FIX: la copia locale della scala (righe/colonne
            ; totali del blocco) va in BLIT_SCRATCH, non piu' in
            ; BLIT_THEME. BLIT_THEME e' il tema-palette (0..3) che
            ; SET_SCB_RANGE scrive nella SCB per 32 righe: riusarlo qui
            ; per un valore diverso (la scala, 1..4) lo lascia sporco per
            ; chi lo leggesse dopo senza riassegnarlo prima - collisione
            ; di significato fra due sotto-sistemi diversi che riusano lo
            ; stesso indirizzo di direct page. BLIT_SCRATCH e' libero qui
            ; (l'ultimo a scriverci e' STS_MUL_SCALE, gia' tornato prima
            ; che STS_DRAW_BLOCK parta) e non viene toccato dal resto di
            ; questa routine.
            STA   BLIT_SCRATCH       ; copia locale della scala (righe totali)
            STZ   BLIT_HINIB         ; dy = 0
:sdb_row    LDA   BLIT_HINIB
            CMP   BLIT_SCRATCH
            BCS   :sdb_done

            LDA   BLIT_Y
            CLC
            ADC   BLIT_HINIB
            AND   #$00FF
            XBA                      ; riga*256 nel byte alto di A
            STA   BLIT_ROWADDR

            STZ   BLIT_SCRATCH2      ; dx = 0
:sdb_col    LDA   BLIT_SCRATCH2
            CMP   BLIT_SCRATCH
            BCS   :sdb_col_done

            LDA   BLIT_X
            CLC
            ADC   BLIT_SCRATCH2
            AND   #$00FF
            ORA   BLIT_ROWADDR
            TAX

            SEP   #$20
            MX    %10
            LDA   BLIT_COLOR
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            LDA   BLIT_SCRATCH2
            CLC
            ADC   #1
            STA   BLIT_SCRATCH2
            BRA   :sdb_col
:sdb_col_done
            LDA   BLIT_HINIB
            CLC
            ADC   #1
            STA   BLIT_HINIB
            BRA   :sdb_row
:sdb_done   RTS

; ---------------------------------------------------------------------
; TL53: STAMP_TILE_SCALED - come STAMP_TILE (stessa lettura dello strip
; BLIT_PTR/BLIT_BASE_X/BLIT_BASE_Y, stesso remap via TILE_REMAP_TABLE),
; ma ogni pixel dello sprite sorgente diventa un blocco STAMP_SCALE x
; STAMP_SCALE (nearest-neighbor: nessun filtro, solo ripetizione), e
; anche gli scostamenti relativi x/y dentro lo strip vengono moltiplicati
; per STAMP_SCALE, cosi' l'intero sprite cresce in modo coerente invece
; di restare a dimensione fissa con pixel piu' grossi sovrapposti. Con
; STAMP_SCALE=1 il risultato e' identico a STAMP_TILE.
; ---------------------------------------------------------------------
STAMP_TILE_SCALED
            REP   #$30
            MX    %00
:sts_strip  SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            REP   #$30
            MX    %00
            AND   #$00FF
            BNE   :sts_go
            JMP   :sts_done
:sts_go     STA   BLIT_LEN
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

            SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            REP   #$30
            MX    %00
            AND   #$00FF
            JSR   STS_MUL_SCALE
            CLC
            ADC   BLIT_BASE_X
            STA   BLIT_X
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

            SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            REP   #$30
            MX    %00
            AND   #$00FF
            JSR   STS_MUL_SCALE
            CLC
            ADC   BLIT_BASE_Y
            STA   BLIT_Y
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

:sts_pixel  SEP   #$20
            MX    %10
            LDA   (BLIT_PTR)
            AND   #$0F
            TAX
            LDA   TILE_REMAP_TABLE,X
            STA   BLIT_COLOR
            REP   #$30
            MX    %00
            LDA   BLIT_PTR
            CLC
            ADC   #1
            STA   BLIT_PTR

            JSR   STS_DRAW_BLOCK

            LDA   STAMP_SCALE
            AND   #$00FF
            CLC
            ADC   BLIT_X
            STA   BLIT_X

            LDA   BLIT_LEN
            SEC
            SBC   #1
            STA   BLIT_LEN
            BEQ   :sts_strip_next
            JMP   :sts_pixel
:sts_strip_next
            JMP   :sts_strip
:sts_done   RTS

; nibble basso (0-15) -> colori di SFONDO condivisi (slot 6-15)
TILE_REMAP_TABLE
            DFB   6, 6, 7, 7, 8, 8, 9, 9
            DFB   10, 10, 11, 12, 12, 13, 14, 15

; ---------------------------------------------------------------------
; TL53: dispatcher a fasi dell'intro. Stesso pattern gia' collaudato
; in UPDATE_L1 (leggere l'indirizzo con indicizzazione assoluta in uno
; scratch di direct page, poi JMP indiretto di direct page) - vedi il
; commento storico li' sul crash causato da un'altra forma di salto
; indiretto. INTRO_STEP e' chiamato una volta a frame da MAIN_LOOP;
; ogni fase, quando ha finito, chiama INTRO_NEXT che avanza
; INTRO_PHASE e inizializza la fase successiva.
; ---------------------------------------------------------------------
INTRO_STEP  REP   #$30
            MX    %00
            LDA   INTRO_PHASE
            AND   #$00FF
            ASL   A
            TAX
            LDA   INTRO_TABLE,X
            STA   INTRO_JUMP_PTR
            JMP   (INTRO_JUMP_PTR)

; *** TL55: SINCOS0S_TABLE - porting 1:1 di sincos0s[] (data.c, CON la
; "s" finale - tabella diversa da sincos0[] senza "s", che servira' per
; R_L1P90/r_p70). 256 byte CON SEGNO (seno puro, ampiezza 127, non
; l'offset a 0x80 usato altrove) - usata da SINE50_STEP via MULSHR8S.
SINCOS0S_TABLE
            DFB   $00,$02,$05,$08,$0B,$0F,$12,$15,$18,$1B,$1E,$21,$24,$27,$2A,$2D
            DFB   $30,$33,$36,$38,$3B,$3E,$41,$43,$46,$49,$4B,$4E,$50,$52,$55,$57
            DFB   $59,$5C,$5E,$60,$62,$64,$66,$67,$69,$6B,$6D,$6E,$70,$71,$73,$74
            DFB   $75,$76,$77,$78,$79,$7A,$7B,$7C,$7C,$7D,$7D,$7E,$7E,$7E,$7F,$7F
            DFB   $7F,$7F,$7F,$7E,$7E,$7E,$7D,$7D,$7C,$7C,$7B,$7A,$79,$78,$77,$76
            DFB   $75,$74,$73,$71,$70,$6E,$6D,$6B,$69,$67,$66,$64,$62,$60,$5E,$5C
            DFB   $59,$57,$55,$52,$50,$4E,$4B,$49,$46,$43,$41,$3E,$3B,$38,$36,$33
            DFB   $30,$2D,$2A,$27,$24,$21,$1E,$1B,$18,$15,$12,$0F,$0B,$08,$05,$02
            DFB   $00,$FD,$FA,$F6,$F3,$F0,$ED,$EA,$E7,$E4,$E1,$DE,$DB,$D8,$D5,$D2
            DFB   $CF,$CC,$C9,$C6,$C4,$C1,$BE,$BB,$B9,$B6,$B4,$B1,$AF,$AC,$AA,$A8
            DFB   $A5,$A3,$A1,$9F,$9D,$9B,$99,$97,$96,$94,$92,$91,$8F,$8E,$8C,$8B
            DFB   $8A,$89,$87,$86,$86,$85,$84,$83,$82,$82,$81,$81,$81,$80,$80,$80
            DFB   $80,$80,$80,$80,$81,$81,$81,$82,$82,$83,$84,$85,$86,$86,$87,$89
            DFB   $8A,$8B,$8C,$8E,$8F,$91,$92,$94,$96,$97,$99,$9B,$9D,$9F,$A1,$A3
            DFB   $A5,$A8,$AA,$AC,$AF,$B1,$B4,$B6,$B9,$BB,$BE,$C1,$C4,$C6,$C9,$CC
            DFB   $CF,$D2,$D5,$D8,$DB,$DE,$E1,$E4,$E7,$EA,$ED,$F0,$F3,$F6,$FA,$FD

; *** TL55: SINCOS0_TABLE - porting 1:1 di sincos0[] (data.c, SENZA la
; "s" finale - tabella diversa da sincos0s[] sopra). 256 byte SENZA
; segno (seno con offset, ampiezza ~127 centrata a 127) - usata da
; R_L1P90 (r_l1p90) per il movimento delle particelle di pioggia,
; tramite letture a 16 bit + AND #$00FF (vedi il commento in testa a
; R_L1P90 sul perche' mai una vera SEP #$20 li').
SINCOS0_TABLE
            DFB   $7F, $83, $86, $89, $8C, $8F, $92, $95, $98, $9B, $9E, $A2, $A5, $A8, $AA, $AD
            DFB   $B0, $B3, $B6, $B9, $BC, $BE, $C1, $C4, $C6, $C9, $CC, $CE, $D1, $D3, $D5, $D8
            DFB   $DA, $DC, $DE, $E0, $E2, $E4, $E6, $E8, $EA, $EB, $ED, $EF, $F0, $F2, $F3, $F4
            DFB   $F6, $F7, $F8, $F9, $FA, $FB, $FB, $FC, $FD, $FD, $FE, $FE, $FF, $FF, $FF, $FF
            DFB   $FF, $FF, $FF, $FF, $FF, $FE, $FE, $FD, $FD, $FC, $FB, $FB, $FA, $F9, $F8, $F7
            DFB   $F6, $F4, $F3, $F2, $F0, $EF, $ED, $EB, $EA, $E8, $E6, $E4, $E2, $E0, $DE, $DC
            DFB   $DA, $D8, $D5, $D3, $D1, $CE, $CC, $C9, $C6, $C4, $C1, $BE, $BC, $B9, $B6, $B3
            DFB   $B0, $AD, $AA, $A8, $A5, $A2, $9E, $9B, $98, $95, $92, $8F, $8C, $89, $86, $83
            DFB   $7F, $7C, $79, $76, $73, $70, $6D, $6A, $66, $63, $60, $5D, $5A, $57, $54, $51
            DFB   $4E, $4C, $49, $46, $43, $40, $3E, $3B, $38, $36, $33, $31, $2E, $2C, $2A, $27
            DFB   $25, $23, $21, $1F, $1D, $1B, $19, $17, $15, $13, $12, $10, $0F, $0D, $0C, $0A
            DFB   $09, $08, $07, $06, $05, $04, $03, $03, $02, $01, $01, $00, $00, $00, $00, $00
            DFB   $00, $00, $00, $00, $00, $00, $01, $01, $02, $03, $03, $04, $05, $06, $07, $08
            DFB   $09, $0A, $0C, $0D, $0F, $10, $12, $13, $15, $17, $19, $1B, $1D, $1F, $21, $23
            DFB   $25, $27, $2A, $2C, $2E, $31, $33, $36, $38, $3B, $3E, $40, $43, $46, $49, $4C
            DFB   $4E, $51, $54, $57, $5A, $5D, $60, $63, $66, $6A, $6D, $70, $73, $76, $79, $7C

; *** TL55: 3 fasi in piu' (rombo/tenda/wipe) fra la scacchiera e il
; loop-back - vedi INTRO_NEXT sotto per l'ordine.
INTRO_TABLE DA    CURVE_STEP, DOTS_STEP, LINES_STEP, FILL_STEP, CHECKER_GROW_STEP, DIAMOND_STEP, SINE50_STEP, WIPE_STEP, INTRO_DONE
INTRO_DONE  RTS

; INTRO_NEXT: chiamata DALLA fase attiva quando ha finito. Avanza
; INTRO_PHASE e chiama l'init della fase successiva.
; *** TL54: su richiesta, dopo la fase 5 (scacchiera) l'intro non resta
; piu' ferma per sempre (INTRO_DONE) - si ripulisce la texture come
; all'avvio (CLEAR_OFFSCREEN_FLAT, stessa chiamata di START/
; DEBUG_JUMP_PHASE) e si riparte dalla fase 0 (curva), in loop
; continuo, invece di fermarsi sull'ultimo fotogramma.
INTRO_NEXT  REP   #$30
            MX    %00
            LDA   INTRO_PHASE
            CLC
            ADC   #1
            STA   INTRO_PHASE
            CMP   #1
            BEQ   :in_dots
            CMP   #2
            BEQ   :in_lines
            CMP   #3
            BEQ   :in_fill
            CMP   #4
            BEQ   :in_checker
            CMP   #5
            BEQ   :in_diamond
            CMP   #6
            BEQ   :in_sine
            CMP   #7
            BEQ   :in_wipe
            CMP   #8
            BEQ   :in_restart
            RTS
:in_dots    JSR   INIT_DOTS_PHASE
            RTS
:in_lines   JSR   INIT_LINES_PHASE
            RTS
:in_fill    JSR   INIT_FILL_PHASE
            RTS
:in_checker JSR   INIT_CHECKER_PHASE
            RTS
:in_diamond JSR   INIT_DIAMOND_PHASE
            RTS
:in_sine    JSR   INIT_SINE50_PHASE
            RTS
:in_wipe    JSR   INIT_WIPE_PHASE
            RTS
:in_restart JSR   CLEAR_OFFSCREEN_FLAT
            STZ   INTRO_PHASE
            JSR   INIT_CURVE_PHASE
            RTS

; ---------------------------------------------------------------------
; TL53: DEBUG_JUMP_PHASE - salto diretto a una fase (tasti 1/2/3/4/5 in
; CHECK_KEYBOARD), per confrontare al volo con l'originale senza
; aspettare le fasi precedenti. Ripulisce prima la texture a colore
; piatto con CLEAR_OFFSCREEN_FLAT (altrimenti si vedrebbero sovrapposti
; i disegni delle fasi gia' passate, o la vecchia scacchiera di prova) -
; la fase 5 (INIT_CHECKER_PHASE) ridisegna comunque la scacchiera sopra
; subito dopo, di suo.
; Ingresso: A (16 bit) = 0..4.
; ---------------------------------------------------------------------
DEBUG_JUMP_PHASE
            REP   #$30
            MX    %00
            AND   #$00FF
            STA   INTRO_PHASE
            PHA                      ; CLEAR_OFFSCREEN_FLAT sporca A/X
            JSR   CLEAR_OFFSCREEN_FLAT
            PLA
            CMP   #0
            BNE   :dj_1
            JSR   INIT_CURVE_PHASE
            RTS
:dj_1       CMP   #1
            BNE   :dj_2
            JSR   INIT_DOTS_PHASE
            RTS
:dj_2       CMP   #2
            BNE   :dj_3
            JSR   INIT_LINES_PHASE
            RTS
:dj_3       CMP   #3
            BNE   :dj_4
            JSR   INIT_FILL_PHASE
            RTS
:dj_4       CMP   #4
            BNE   :dj_5
            JSR   INIT_CHECKER_PHASE
            RTS
:dj_5       CMP   #5
            BNE   :dj_6
            JSR   INIT_DIAMOND_PHASE
            RTS
:dj_6       CMP   #6
            BNE   :dj_7
            JSR   INIT_SINE50_PHASE
            RTS
:dj_7       JSR   INIT_WIPE_PHASE
            RTS

; ---------------------------------------------------------------------
; TL53: INIT_INTRO - chiamata una sola volta in START (dopo MUSIC_INIT,
; vedi commento li'). Imposta solo la fase 0 (curva): le altre si
; autoinizializzano quando INTRO_NEXT/DEBUG_JUMP_PHASE le attivano.
; ---------------------------------------------------------------------
INIT_INTRO  REP   #$30
            MX    %00
            STZ   INTRO_PHASE
            JSR   INIT_CURVE_PHASE
            RTS

; Costanti iniziali di CURVE_LOC/CURVE_LOCD ($357C/$137E) copiate 1:1
; da r_p00 in timeless.c - non sono "magiche", sono solo il punto di
; partenza scelto dagli autori originali per far apparire la curva
; sempre uguale ad ogni avvio (deterministico, niente RNG vero).
INIT_CURVE_PHASE
            REP   #$30
            MX    %00
            LDA   #$357C
            STA   CURVE_LOC
            LDA   #$137E
            STA   CURVE_LOCD
            ; *** TL53 FIX: CURVE_COLOR ($76) e' seguito da CURVE_COUNTER
            ; ($77), a sua volta seguito da STAMP_SCALE ($78) - due STZ a
            ; 16 bit di fila scrivevano 4 byte ($76..$79), azzerando anche
            ; STAMP_SCALE (innocuo solo per puro caso, perche' FILL_STEP/
            ; CHECKER_GROW_STEP lo ricalcolano sempre prima di usarlo).
            ; Store a 8 bit, larghezza vera dei campi.
            SEP   #$20
            MX    %10
            STZ   CURVE_COLOR
            STZ   CURVE_COUNTER
            REP   #$30
            MX    %00
            RTS

INIT_DOTS_PHASE
            REP   #$30
            MX    %00
            STZ   DOTS_COUNTER
            RTS

INIT_LINES_PHASE
            REP   #$30
            MX    %00
            STZ   LINES_COUNTER
            RTS

; FILL_LOCD parte da $137E come in r_p30 (timeless.c); FILL_LOC da
; $53C7, anche quello identico al C.
; *** TL53 FIX: FILL_CNTR/FILL_PACE/FILL_ICONIDX sono 1 byte logico
; l'uno seguito dall'altro (e FILL_ICONIDX e' seguito da SAVED_SHADOW).
; Qui l'ordine di scrittura li rendeva innocui per puro caso (ognuno
; veniva risovrascritto subito dopo), ma non fidiamoci: store a 8 bit
; anche in init, per coerenza con FILL_STEP.
INIT_FILL_PHASE
            REP   #$30
            MX    %00
            LDA   #$53C7
            STA   FILL_LOC
            LDA   #$137E
            STA   FILL_LOCD
            LDX   #10                ; quanti cluster di 4 margherite piazzare
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_CNTR
            LDA   #4                 ; un cluster ogni 4 frame
            STA   FILL_PACE
            STZ   FILL_ICONIDX
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; TL52/53: CURVE_STEP - porting fedele di r_p00 (timeless.c). Disegna
; 64 pixel per chiamata nella texture offscreen seguendo una curva
; tipo dragon-curve (loc/locd a 16 bit, locd raddoppia/ruota ad ogni
; passo a seconda del bit 15). Si autoferma dopo 64 chiamate
; (CURVE_COUNTER parte da 0, -4 a chiamata, 8 bit: torna a 0
; esattamente dopo 64 passaggi), poi chiama INTRO_NEXT. Il colore
; (0..63, passo 13, esattamente come il C) viene compresso a un
; nibble con >>2 e rimappato negli slot di sfondo condivisi 6..15 via
; TILE_REMAP_TABLE, cosi' resta leggibile con qualunque tema attivo.
;
; *** TL54: su richiesta, fase accorciata a meta' del tempo (durava
; troppo ora che l'intro va in loop - vedi INTRO_NEXT) SENZA perdere
; densita': 64 pixel/chiamata invece di 32 e -4/chiamata invece di -2,
; cosi' il totale resta 4096 punti (64x64=128x32) ma in meta' dei
; fotogrammi. Il generatore di posizione (loc/locd) non cambia.
;
; *** TL53 FIX: mancava "locd += 0x1395" UNA VOLTA per chiamata (prima
; del giro di pixel), presente nel C ma persa nel porting iniziale.
; Senza questo, il resto della routine (^= una pura rotazione sinistra
; di 1 bit di locd, niente di piu') e' una permutazione: senza nuova
; "energia" iniettata ad ogni chiamata, locd ripete lo stesso ciclo di
; 16 rotazioni all'infinito, quindi loc si sposta sempre delle STESSE
; 16 quantita' in sequenza per tutte le chiamate - il risultato e'
; una manciata di punti che si ripetono quasi sulle stesse posizioni
; invece di una curva che si allarga, esattamente il "non si vede
; niente" segnalato. Con l'incremento ripristinato, locd non si
; ripete piu' e loc percorre l'intera texture come nell'originale.
; ---------------------------------------------------------------------
CURVE_STEP  REP   #$30
            MX    %00

            LDA   CURVE_LOCD
            CLC
            ADC   #$1395
            STA   CURVE_LOCD

            LDX   #64                  ; *** TL54: era 32, vedi nota sopra
:cv_loop    PHX                     ; salva il contatore dei pixel di questa chiamata

            SEP   #$20
            MX    %10
            LDA   CURVE_COLOR
            LSR   A
            LSR   A                 ; color>>2 -> nibble 0..15
            TAX
            LDA   TILE_REMAP_TABLE,X
            STA   GNBG_TMP          ; *** TL54 FIX: colore finale (6..15) in
                                    ; uno scratch di direct page invece che
                                    ; sullo stack (PHA/.../PLA) - vedi nota
                                    ; sotto, e' l'unico punto del file che
                                    ; teneva un valore sullo stack a cavallo
                                    ; di un cambio SEP/REP #$20.

            LDX   CURVE_LOC         ; X e' gia' a 16 bit (MX non l'ha toccato)
            LDA   GNBG_TMP
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            ; color = (color+13) & 63
            ; *** TL53 FIX: CURVE_COLOR ($76) e CURVE_COUNTER ($77) sono
            ; ADIACENTI di un solo byte. Una STA a 16 bit su CURVE_COLOR
            ; scrive ANCHE in CURVE_COUNTER (lo azzera), ad ogni pixel -
            ; per questo la curva non si fermava mai da sola dopo 128
            ; chiamate (il contatore veniva riportato a 0 prima ancora di
            ; essere decrementato). Portiamo il valore in X (che il resto
            ; del ciclo non usa) per attraversare il cambio di larghezza
            ; e scrivere un solo byte, come gia' si fa altrove nel file
            ; con PHX/PLX per l'indice a 16 bit.
            LDA   CURVE_COLOR
            CLC
            ADC   #13
            AND   #$003F
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   CURVE_COLOR
            REP   #$30
            MX    %00

            ; if(locd & 0x8000) {++loc; locd=(locd<<1)|1;} else locd<<=1;
            LDA   CURVE_LOCD
            BPL   :cv_noinc
            INC   CURVE_LOC
            ASL   A
            ORA   #$0001
            STA   CURVE_LOCD
            BRA   :cv_addloc
:cv_noinc   ASL   A
            STA   CURVE_LOCD
:cv_addloc  LDA   CURVE_LOC
            CLC
            ADC   CURVE_LOCD
            STA   CURVE_LOC

            PLX
            DEX
            BNE   :cv_loop

            ; counter -= 4 (8 bit, wrap); a 0 la curva e' finita.
            ; *** TL54: era -2 (128 chiamate) - vedi nota di testa sulla
            ; fase accorciata a 64 chiamate mantenendo lo stesso totale
            ; di punti disegnati.
            ; *** TL53 FIX: stesso discorso di CURVE_COLOR sopra - store
            ; a 8 bit, altrimenti si clobbera STAMP_SCALE ($78, innocuo
            ; qui ma meglio non fidarsi).
            LDA   CURVE_COUNTER
            AND   #$00FF
            SEC
            SBC   #4
            AND   #$00FF
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   CURVE_COUNTER
            REP   #$30
            MX    %00
            CPX   #0
            BNE   :cv_done
            JSR   INTRO_NEXT
:cv_done    RTS

; ---------------------------------------------------------------------
; TL53: DOTS_PLOT16 - disegna 16 "puntini" 2x2 (bx,bx+1,bx+256,bx+257)
; a partire da GNBG_TMP (bx iniziale, 16 bit), avanzando di GNBG_TMP4
; (passo, 16 bit) ad ogni punto e di 4 il colore grezzo GNBG_TMP2
; (0x40..0x7F), esattamente come il corpo del for(i<16) in r_p10. Il
; colore va rimappato una volta per punto (e' lo stesso per i 4 texel
; di quel punto, non uno diverso a texel): (raw-0x40)>>2 -> nibble
; 0..15 -> TILE_REMAP_TABLE.
; ---------------------------------------------------------------------
DOTS_PLOT16 REP   #$30
            MX    %00
            LDX   #16
:dp_loop    PHX

            LDA   GNBG_TMP2
            AND   #$00FF
            SEC
            SBC   #$40
            LSR   A
            LSR   A
            TAX
            SEP   #$20
            MX    %10
            LDA   TILE_REMAP_TABLE,X
            REP   #$30
            MX    %00
            AND   #$00FF
            STA   GNBG_TMP3         ; colore finale, condiviso dai 4 texel

            ; texel bx
            LDA   GNBG_TMP
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            ; texel bx+1
            LDA   GNBG_TMP
            CLC
            ADC   #1
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            ; texel bx+256
            LDA   GNBG_TMP
            CLC
            ADC   #256
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            ; texel bx+257
            LDA   GNBG_TMP
            CLC
            ADC   #257
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            ; ax += 4 ; bx += stride
            LDA   GNBG_TMP2
            CLC
            ADC   #4
            STA   GNBG_TMP2
            LDA   GNBG_TMP
            CLC
            ADC   GNBG_TMP4
            STA   GNBG_TMP

            PLX
            DEX
            BNE   :dp_loop
            RTS

; ---------------------------------------------------------------------
; TL53: DOTS_STEP - porting fedele di r_p10 (timeless.c). 4 gruppi di
; 16 punti 2x2 ciascuno, ogni gruppo con colore base e passo (stride)
; fissi ma posizione di partenza derivata da DOTS_COUNTER in modo
; diverso per gruppo - esattamente come il C. Passi (97*256+97,
; 17*256+223, 111*256+17, 203*256+117) precalcolati in esadecimale
; ($6161, $11DF, $6F11, $CB75). Si autoferma dopo 256 chiamate
; (DOTS_COUNTER 8 bit, +1 a chiamata, torna a 0 dopo 256 passaggi).
; ---------------------------------------------------------------------
DOTS_STEP   REP   #$30
            MX    %00

            ; gruppo 0: ax=0x40, bx=counter, stride=97*256+97
            LDA   DOTS_COUNTER
            AND   #$00FF
            STA   GNBG_TMP
            LDA   #$0040
            STA   GNBG_TMP2
            LDA   #$6161
            STA   GNBG_TMP4
            JSR   DOTS_PLOT16

            ; gruppo 1: ax=0x42, bx=0x3300+((-counter)&255), stride=17*256+223
            SEP   #$20
            MX    %10
            LDA   #0
            SEC
            SBC   DOTS_COUNTER
            REP   #$30
            MX    %00
            AND   #$00FF
            ORA   #$3300
            STA   GNBG_TMP
            LDA   #$0042
            STA   GNBG_TMP2
            LDA   #$11DF
            STA   GNBG_TMP4
            JSR   DOTS_PLOT16

            ; gruppo 2: ax=0x41, bx=(counter<<8)|0x57, stride=111*256+17
            LDA   DOTS_COUNTER
            AND   #$00FF
            XBA
            ORA   #$0057
            STA   GNBG_TMP
            LDA   #$0041
            STA   GNBG_TMP2
            LDA   #$6F11
            STA   GNBG_TMP4
            JSR   DOTS_PLOT16

            ; gruppo 3: ax=0x43, bx=(((-counter)&255)<<8)|0xA9, stride=203*256+117
            SEP   #$20
            MX    %10
            LDA   #0
            SEC
            SBC   DOTS_COUNTER
            REP   #$30
            MX    %00
            AND   #$00FF
            XBA
            ORA   #$00A9
            STA   GNBG_TMP
            LDA   #$0043
            STA   GNBG_TMP2
            LDA   #$CB75
            STA   GNBG_TMP4
            JSR   DOTS_PLOT16

            ; counter += 1 (8 bit, wrap); a 0 la fase e' finita
            LDA   DOTS_COUNTER
            AND   #$00FF
            CLC
            ADC   #1
            AND   #$00FF
            STA   DOTS_COUNTER
            BNE   :ds_done
            JSR   INTRO_NEXT
:ds_done    RTS

; ---------------------------------------------------------------------
; TL53: LINES_VFILL - riempie una colonna intera (256 righe, passo
; 256) col colore in GNBG_TMP3. Ingresso: A (16 bit) = colonna 0..255.
; LINES_HFILL - riempie una riga intera (256 byte contigui) allo
; stesso modo. Ingresso: A (16 bit) = riga 0..255 (A<<8 = offset
; iniziale, via XBA visto che A e' gia' 0..255).
; ---------------------------------------------------------------------
LINES_VFILL REP   #$30
            MX    %00
            STA   GNBG_TMP4
            LDX   #256
:lv_loop    PHX
            LDA   GNBG_TMP4
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00
            LDA   GNBG_TMP4
            CLC
            ADC   #256
            STA   GNBG_TMP4
            PLX
            DEX
            BNE   :lv_loop
            RTS

LINES_HFILL REP   #$30
            MX    %00
            AND   #$00FF
            XBA                     ; A = riga*256
            STA   GNBG_TMP4
            LDX   #256
:lh_loop    PHX
            LDA   GNBG_TMP4
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00
            LDA   GNBG_TMP4
            CLC
            ADC   #1
            STA   GNBG_TMP4
            PLX
            DEX
            BNE   :lh_loop
            RTS

; ---------------------------------------------------------------------
; TL53: LINES_STEP - porting fedele di r_p20 (timeless.c). Ad ogni
; chiamata disegna una riga E una colonna pari (indice counter*2) e
; una riga E una colonna dispari (indice (counter^0x7f)*2+1), stesso
; colore per tutte e 4 (onda triangolare 0x80+counter / 0xff-counter,
; compressa a nibble con (val-0x80)>>2). Si autoferma dopo 128
; chiamate (LINES_COUNTER 7 bit, +1 a chiamata, torna a 0 dopo 128
; passaggi) - a quel punto tutte le 256 righe/colonne sono state
; toccate (128 pari + 128 dispari).
; ---------------------------------------------------------------------
LINES_STEP  REP   #$30
            MX    %00

            ; colore: counter<64 ? counter+0x80 : 0xff-counter
            LDA   LINES_COUNTER
            AND   #$00FF
            CMP   #64
            BCC   :ls_lo
            LDA   #$00FF
            SEC
            SBC   LINES_COUNTER
            BRA   :ls_colok
:ls_lo      LDA   LINES_COUNTER
            CLC
            ADC   #$0080
:ls_colok   SEC
            SBC   #$0080
            LSR   A
            LSR   A                 ; nibble 0..15
            TAX
            SEP   #$20
            MX    %10
            LDA   TILE_REMAP_TABLE,X
            REP   #$30
            MX    %00
            AND   #$00FF
            STA   GNBG_TMP3         ; colore finale, condiviso dalle 4 linee

            ; indice pari = counter*2 ; indice dispari = (counter^0x7f)*2+1
            LDA   LINES_COUNTER
            AND   #$00FF
            ASL   A
            STA   GNBG_TMP          ; indice pari

            LDA   LINES_COUNTER
            AND   #$00FF
            EOR   #$007F
            ASL   A
            INC   A
            STA   GNBG_TMP2         ; indice dispari

            LDA   GNBG_TMP
            JSR   LINES_VFILL
            LDA   GNBG_TMP
            JSR   LINES_HFILL
            LDA   GNBG_TMP2
            JSR   LINES_VFILL
            LDA   GNBG_TMP2
            JSR   LINES_HFILL

            ; counter = (counter+1)&127; a 0 la fase e' finita
            LDA   LINES_COUNTER
            AND   #$00FF
            CLC
            ADC   #1
            AND   #$007F
            STA   LINES_COUNTER
            BNE   :ls_done
            JSR   INTRO_NEXT
:ls_done    RTS

; ---------------------------------------------------------------------
; TL53/TL54: FILL_STAMP_AT - stampa la forma corrente (FILL_ICONIDX,
; indice in CLUSTER_ICON_TBL) alla posizione in A (16 bit,
; "riga*256+colonna" come FILL_LOC). Helper condiviso dalle 4 chiamate
; simmetriche di FILL_STEP e dalla stampa singola di CHECKER_GROW_STEP.
;
; *** TL54: CLUSTER_ICON_TBL - "d3tile con le icone": prima le fasi 4/5
; stampavano SEMPRE la margherita (DAISY_SPRITE_TBL). Ora FILL_ICONIDX
; cicla su 4 forme invece di 3 frame della stessa margherita: un frame
; margherita rappresentativo (CSPR01, quella "aperta" a meta' tabella)
; piu' le 3 icone gia' usate da R_L1P50 (CSPR09/16/22 - "icona volante
; con rimbalzo"). Stesso sprite pointer, stesso STAMP_TILE_SCALED: le
; icone crescono/si piazzano esattamente come faceva la margherita,
; solo con piu' varieta' invece di essere sempre la stessa forma per
; tutta la fase. Non e' ancora il d3tile "vero" del C (li' sono sfere
; 3D con ombreggiatura via scaletile, qui restano sprite piatti) ma
; porta a schermo tutte le forme disponibili, come richiesto.
CLUSTER_ICON_TBL
            DA    CSPR01_DATA, CSPR09_DATA, CSPR16_DATA, CSPR22_DATA
CLUSTER_ICON_COUNT EQU 4

; *** TL53 FIX: BLIT_PTR/BLIT_BASE_X/BLIT_BASE_Y sono alias delle stesse
; celle di DP di GNBG_TMP/GNBG_TMP2/GNBG_TMP4 (risparmio di spazio, vedi
; sopra "GNBG_TMP.. usato solo da GENERATE_OFFSCREEN/INIT_GNBGTBL, finiti
; prima che servano BLIT_*"). Qui pero' ci servono ENTRAMBI nella stessa
; chiamata (la posizione in ingresso, poi lo sprite pointer), quindi la
; posizione va salvata altrove: usiamo CURVE_LOC, libero perche' la fase
; curva e' sempre gia' finita quando gira FILL_STEP (anche via debug jump,
; che re-inizializza ogni fase per conto proprio).
FILL_STAMP_AT
            REP   #$30
            MX    %00
            STA   CURVE_LOC

            LDA   FILL_ICONIDX
            AND   #$00FF
            ASL   A
            TAX
            LDA   CLUSTER_ICON_TBL,X
            STA   BLIT_PTR

            LDA   CURVE_LOC
            AND   #$00FF
            STA   BLIT_BASE_X
            LDA   CURVE_LOC
            XBA
            AND   #$00FF
            STA   BLIT_BASE_Y
            ; *** TL53: STAMP_TILE_SCALED invece di STAMP_TILE, cosi' le
            ; margherite CRESCONO davvero (STAMP_SCALE impostato dal
            ; chiamante prima di ogni stampa) invece di restare sempre
            ; alla dimensione originale dello sprite.
            JSR   STAMP_TILE_SCALED
            RTS

; ---------------------------------------------------------------------
; TL53: FILL_STEP - generatore di posizione di r_p30 (timeless.c),
; fedele (stesso +0x4377, stessa rotazione sinistra di 5 bit vera,
; stesso "+ (locd&1)"). Pianta la forma corrente di CLUSTER_ICON_TBL
; (*** TL54: margherita + le 3 icone di R_L1P50, non piu' solo la
; margherita - vedi FILL_STAMP_AT) in 4 copie simmetriche (alto sx/dx,
; basso sx/dx) attorno alla posizione pseudo-casuale, esattamente come
; l'originale, e ora CRESCE davvero via STAMP_TILE_SCALED: STAMP_SCALE
; aumenta di 1 ogni 3 cluster (1 per i primi 3, poi 2, poi 3, poi 4 per
; l'ultimo), e lo scostamento fra le 4 copie cresce di pari passo
; (FILL_SIZE*STAMP_SCALE) cosi' restano separate invece di sovrapporsi
; sempre di piu'. Non e' il raddoppio esponenziale di scaletile() nel C
; (qui restiamo lineari e capped a x4 per stare dentro alla texture
; 256x256), ma l'effetto "cresce nel tempo" richiesto e' quello vero.
; Un cluster ogni FILL_PACE frame, finche' FILL_CNTR non arriva a 0,
; poi chiama INTRO_NEXT.
; ---------------------------------------------------------------------
FILL_SIZE   EQU   16        ; meta' misura approssimativa dello sprite margherita (scala 1)
FILL_TOTAL  EQU   10        ; deve combaciare con l'LDA #10 di INIT_FILL_PHASE

FILL_STEP   REP   #$30
            MX    %00
            LDA   FILL_CNTR
            AND   #$00FF
            BNE   :fs_go
            RTS

; *** TL53 FIX (grave): FILL_PACE ($7E) e' seguito da FILL_ICONIDX
; ($7F), e FILL_CNTR ($7D) e' seguito da FILL_PACE stesso. Ogni STA a
; 16 bit su uno di questi campi da "1 byte logico" scrive ANCHE nel
; campo successivo. Risultato concreto: appena un cluster scattava,
; STA FILL_CNTR (fine ciclo, vedi sotto) azzerava FILL_PACE subito
; dopo che era stato appena rimesso a 4 - al giro seguente il
; countdown ripartiva da 0-1=255 invece che da 4, quindi il cluster
; SUCCESSIVO non arrivava piu' per 255 frame invece di 4 (da cui
; l'impressione che la fase 4 "non facesse niente" dopo il primo
; gruppetto di margherite). Stesso meccanismo faceva si' che
; FILL_ICONIDX leggesse sempre 0 (azzerato dalla STA FILL_PACE appena
; sopra) e che STZ/STA FILL_ICONIDX azzerasse SAVED_SHADOW. Fix:
; portiamo ogni valore in X (16 bit, libero qui) per attraversare il
; cambio di larghezza e scrivere un solo byte con SEP/STA/REP, come
; gia' fatto sopra in CURVE_STEP.
:fs_go      LDA   FILL_PACE
            AND   #$00FF
            SEC
            SBC   #1
            AND   #$00FF
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_PACE
            REP   #$30
            MX    %00
            CPX   #0
            BEQ   :fs_pace_hit    ; *** TL53 FIX: BNE :fs_done era troppo
            JMP   :fs_done        ; lontano (>127 byte) dopo tutte le
                                  ; aggiunte di questa versione - salto
                                  ; corto+JMP invece del BNE diretto.
:fs_pace_hit
            LDX   #4
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_PACE
            REP   #$30
            MX    %00

            ; d3locd += 0x4377
            LDA   FILL_LOCD
            CLC
            ADC   #$4377
            STA   FILL_LOCD

            ; rotazione sinistra di 5 bit (vera, bit15 rientra in bit0)
            LDX   #5
:fs_rot     ASL   FILL_LOCD
            BCC   :fs_rotok
            LDA   FILL_LOCD
            ORA   #$0001
            STA   FILL_LOCD
:fs_rotok   DEX
            BNE   :fs_rot

            ; d3loc = d3loc + d3locd + (d3locd & 1)
            LDA   FILL_LOCD
            AND   #$0001
            STA   GNBG_TMP          ; scratch libero: siamo prima di GNBG_RENDER
            LDA   FILL_LOC
            CLC
            ADC   FILL_LOCD
            CLC
            ADC   GNBG_TMP
            STA   FILL_LOC

            ; scala del cluster corrente: cluster_index = FILL_TOTAL -
            ; FILL_CNTR (FILL_CNTR qui e' ancora il conteggio PRIMA del
            ; decremento a fine ciclo, cioe' 0-based sul cluster che
            ; stiamo per disegnare adesso). scale = 1 + cluster_index/4.
            ; *** TL53 FIX: FILL_CNTR va letto mascherato a parte (non
            ; con una SBC diretta a 16 bit sul suo indirizzo) perche' il
            ; byte successivo e' FILL_PACE, che ora contiene un valore
            ; vero (4..1) invece di restare sempre a 0 come prima del
            ; fix qui sopra - una SBC a 16 bit lo includerebbe per
            ; errore come byte alto.
            LDA   FILL_CNTR
            AND   #$00FF
            STA   GNBG_TMP          ; scratch libero, gia' consumato sopra
            LDA   #FILL_TOTAL
            SEC
            SBC   GNBG_TMP
            LSR   A
            LSR   A
            CLC
            ADC   #1
            ; NOTA: FILL_TOTAL-1=9, 9/4=2, +1=3 col solo LSR LSR (/4);
            ; per arrivare a x4 sull'ultimo cluster serviva /3, che non
            ; e' una potenza di 2 - usiamo la divisione per 4 (piu'
            ; semplice in assembly) e viviamo con una crescita 1,1,1,1,
            ; 2,2,2,2,3,3 invece di 1,1,1,2,2,2,3,3,3,4: ugualmente
            ; visibile, solo l'ultimo scatto in meno.
            ; *** TL53 FIX: store a 8 bit - STAMP_SCALE ($78) e' seguito
            ; da FILL_LOC ($79), che serve ANCORA fra un attimo per le 4
            ; stampe: una STA a 16 bit qui lo azzererebbe.
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   STAMP_SCALE
            REP   #$30
            MX    %00

            ; scostamento fra le 4 copie = FILL_SIZE * STAMP_SCALE,
            ; ricalcolato ad ogni cluster cosi' cresce insieme a loro.
            LDA   #FILL_SIZE
            JSR   STS_MUL_SCALE
            STA   GNBG_TMP2          ; scostamento orizzontale scalato
            XBA                      ; byte alto=valore, byte basso=0 -> *256
            STA   GNBG_TMP4          ; scostamento verticale scalato

            ; 4 copie simmetriche attorno a FILL_LOC
            LDA   FILL_LOC
            SEC
            SBC   GNBG_TMP4
            SEC
            SBC   GNBG_TMP2
            JSR   FILL_STAMP_AT      ; alto sinistra

            LDA   FILL_LOC
            SEC
            SBC   GNBG_TMP4
            JSR   FILL_STAMP_AT      ; alto destra

            LDA   FILL_LOC
            SEC
            SBC   GNBG_TMP2
            JSR   FILL_STAMP_AT      ; basso sinistra

            LDA   FILL_LOC
            JSR   FILL_STAMP_AT      ; basso destra

            ; *** TL53 FIX: store a 8 bit - FILL_ICONIDX ($7F) e' seguito
            ; da SAVED_SHADOW ($80, valore SHADOW originale da ripristinare
            ; in uscita), FILL_CNTR ($7D) e' seguito da FILL_PACE ($7E,
            ; appena rimesso a un valore vero da :fs_go). Vedi la nota
            ; grande sopra su FILL_PACE/FILL_ICONIDX.
            LDA   FILL_ICONIDX
            AND   #$00FF
            CLC
            ADC   #1
            CMP   #CLUSTER_ICON_COUNT   ; *** TL54: 4 forme invece di 3 frame margherita
            BNE   :fs_iok
            LDA   #0
:fs_iok     TAX
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_ICONIDX
            REP   #$30
            MX    %00

            LDA   FILL_CNTR
            AND   #$00FF
            SEC
            SBC   #1
            AND   #$00FF
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_CNTR
            REP   #$30
            MX    %00
            CPX   #0
            BNE   :fs_done
            JSR   INTRO_NEXT
:fs_done    RTS

; ---------------------------------------------------------------------
; TL53: fase 5 - CHECKER_GROW_STEP. Richiesta dall'utente dopo aver
; visto le fasi 1-4: ridisegna la scacchiera di GENERATE_OFFSCREEN come
; sfondo e ci pianta sopra forme SINGOLE di CLUSTER_ICON_TBL (*** TL54:
; margherita + le 3 icone, non piu' solo margherite - vedi
; FILL_STAMP_AT; non in cluster da 4) a posizioni sparse (stesso motore
; pseudo-casuale di r_p30, ma con un seme diverso da FILL_STEP cosi' la
; traiettoria non e' identica) e a dimensione CRESCENTE (STAMP_SCALE
; aumenta ogni CHECKER_TOTAL/4 forme, come in FILL_STEP). Riusa gli
; stessi campi di stato di FILL_STEP (FILL_LOC/FILL_LOCD/FILL_CNTR/
; FILL_PACE/FILL_ICONIDX): le due fasi non girano mai insieme (un solo
; INTRO_PHASE alla volta), quindi non serve nuovo spazio di direct page.
; ---------------------------------------------------------------------
CHECKER_TOTAL EQU 14        ; quante margherite sparse piazzare in totale

INIT_CHECKER_PHASE
            REP   #$30
            MX    %00
            JSR   GENERATE_OFFSCREEN  ; sfondo a scacchiera, come richiesto
            LDA   #$2468               ; seme diverso da FILL_STEP ($53C7)
            STA   FILL_LOC
            LDA   #$0ACF               ; seme diverso da FILL_STEP ($137E)
            STA   FILL_LOCD
            LDX   #CHECKER_TOTAL
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_CNTR
            LDA   #5                   ; una margherita ogni 5 frame
            STA   FILL_PACE
            STZ   FILL_ICONIDX
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; TL55: INIT_DIAMOND_PHASE/INIT_SINE50_PHASE/INIT_WIPE_PHASE - stato
; iniziale delle 3 nuove fasi, valori copiati 1:1 dalle static di
; r_p40/r_p50/r_p60 in timeless.c.
; ---------------------------------------------------------------------
INIT_DIAMOND_PHASE
            REP   #$30
            MX    %00
            LDA   #$7E7E
            STA   DIAMOND_LOC
            LDA   #$FFFE             ; -2
            STA   DIAMOND_LOCD
            SEP   #$20
            MX    %10
            LDA   #1
            STA   DIAMOND_LEN
            STA   DIAMOND_LEND
            REP   #$30
            MX    %00
            RTS

INIT_SINE50_PHASE
            REP   #$30
            MX    %00
            SEP   #$20
            MX    %10
            LDA   #255
            STA   SINE50_CNTR
            REP   #$30
            MX    %00
            RTS

INIT_WIPE_PHASE
            REP   #$30
            MX    %00
            SEP   #$20
            MX    %10
            STZ   WIPE_LOC
            REP   #$30
            MX    %00
            RTS

CHECKER_GROW_STEP
            REP   #$30
            MX    %00
            LDA   FILL_CNTR
            AND   #$00FF
            BNE   :cg_go
            RTS

:cg_go      LDA   FILL_PACE
            AND   #$00FF
            SEC
            SBC   #1
            AND   #$00FF
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_PACE
            REP   #$30
            MX    %00
            CPX   #0
            BEQ   :cg_pace_hit    ; *** TL53 FIX: BNE :cg_done troppo lontano
            JMP   :cg_done
:cg_pace_hit
            LDX   #5
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_PACE
            REP   #$30
            MX    %00

            ; stesso motore di posizione pseudo-casuale di r_p30
            ; (+0x4377, rotazione sinistra vera di 5 bit, +locd&1)
            LDA   FILL_LOCD
            CLC
            ADC   #$4377
            STA   FILL_LOCD
            LDX   #5
:cg_rot     ASL   FILL_LOCD
            BCC   :cg_rotok
            LDA   FILL_LOCD
            ORA   #$0001
            STA   FILL_LOCD
:cg_rotok   DEX
            BNE   :cg_rot
            LDA   FILL_LOCD
            AND   #$0001
            STA   GNBG_TMP
            LDA   FILL_LOC
            CLC
            ADC   FILL_LOCD
            CLC
            ADC   GNBG_TMP
            STA   FILL_LOC

            ; scala crescente, stessa logica di FILL_STEP
            LDA   FILL_CNTR
            AND   #$00FF
            STA   GNBG_TMP
            LDA   #CHECKER_TOTAL
            SEC
            SBC   GNBG_TMP
            LSR   A
            LSR   A
            CLC
            ADC   #1
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   STAMP_SCALE
            REP   #$30
            MX    %00

            ; una sola margherita per volta qui, non un cluster di 4
            LDA   FILL_LOC
            JSR   FILL_STAMP_AT

            LDA   FILL_ICONIDX
            AND   #$00FF
            CLC
            ADC   #1
            CMP   #CLUSTER_ICON_COUNT   ; *** TL54: 4 forme invece di 3 frame margherita
            BNE   :cg_iok
            LDA   #0
:cg_iok     TAX
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_ICONIDX
            REP   #$30
            MX    %00

            LDA   FILL_CNTR
            AND   #$00FF
            SEC
            SBC   #1
            AND   #$00FF
            TAX
            SEP   #$20
            MX    %10
            TXA
            STA   FILL_CNTR
            REP   #$30
            MX    %00
            CPX   #0
            BNE   :cg_done
            JSR   INTRO_NEXT
:cg_done    RTS

; ---------------------------------------------------------------------
; TL55: STAMP4_AT - scrive il colore in GNBG_TMP3 (8 bit, gia' pronto
; dal chiamante) ai 4 texel base+0, base+1, base+256, base+257 (base =
; GNBG_TMP, 16 bit, wrap naturale mod 65536 dato che X e' sempre 16
; bit). Stesso schema a 4 texel gia' usato in DOTS_PLOT16, qui estratto
; come subroutine perche' DIAMOND_STEP lo richiama piu' volte a
; chiamata (una per "di", una per "si", per ogni iterazione del
; rombo). Ogni store torna a REP #$30 (non solo REP #$20) dopo il
; blocco a 8 bit: stessa cautela di SHOW_TEXTURE_DIRECT (TL54) contro
; l'interrupt del player musicale che forza A/X a 8 bit.
; ---------------------------------------------------------------------
STAMP4_AT   REP   #$30
            MX    %00
            LDA   GNBG_TMP
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            LDA   GNBG_TMP
            CLC
            ADC   #1
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            LDA   GNBG_TMP
            CLC
            ADC   #256
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            LDA   GNBG_TMP
            CLC
            ADC   #257
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; TL55: DIAMOND_STEP - porting di r_p40 (timeless.c): un rombo (4
; segmenti diagonali speculari, "di" e "si") cresce da un punto
; centrale fino a una dimensione massima, poi si restringe di nuovo
; fino a sparire; a quel punto richiama INTRO_NEXT e resetta lo stato
; per il prossimo giro di loop dell'intro. Stato: DIAMOND_LOC ("loc",
; 16 bit), DIAMOND_LOCD ("locd", 16 bit con segno), DIAMOND_LEN ("len",
; 8 bit, 1..0x41), DIAMOND_LEND ("lend", 8 bit con segno, +1 mentre
; cresce/-1 mentre si restringe).
;
; Colore: color=(0x41-len)&0xff; if(color<0x40) ++color; color+=0x3f
; (range risultante 0x40..0x7F, stesso "banco" grezzo di r_p10/r_p30),
; poi nibble=(color-0x40)>>2 -> TILE_REMAP_TABLE, come in DOTS_PLOT16.
; ---------------------------------------------------------------------
DIAMOND_STEP
            REP   #$30
            MX    %00

            ; ---- colore (vedi sopra), calcolato in 8 bit poi ripreso
            ; in 16 bit SOLO dopo un esplicito AND #$00FF (niente TAX
            ; "al volo" sotto SEP #$20: qui l'eventuale byte alto
            ; residuo del registro non e' garantito a zero) ----
            SEP   #$20
            MX    %10
            LDA   #$41
            SEC
            SBC   DIAMOND_LEN
            STA   GNBG_TMP2
            CMP   #$40
            BCS   :dm_col2
            INC   GNBG_TMP2
:dm_col2    REP   #$30
            MX    %00
            LDA   GNBG_TMP2
            AND   #$00FF
            CLC
            ADC   #$3F           ; colore grezzo finale, 0x40..0x7F
            SEC
            SBC   #$40
            LSR   A
            LSR   A
            AND   #$000F
            TAX
            SEP   #$20
            MX    %10
            LDA   TILE_REMAP_TABLE,X
            STA   GNBG_TMP3      ; colore finale, pronto per STAMP4_AT
            REP   #$30
            MX    %00

            LDA   DIAMOND_LOC
            STA   INTRO_TMP_A    ; "di"
            STA   INTRO_TMP_B    ; "si"

            ; ---- primo giro: i=0..len-1 ----
            SEP   #$20
            MX    %10
            LDA   DIAMOND_LEN
            STA   GNBG_TMP2
            REP   #$30
            MX    %00
            LDA   GNBG_TMP2
            AND   #$00FF
            TAX                   ; X = len (16 bit, pulito)

:dm_loop1   PHX
            LDA   INTRO_TMP_A
            STA   GNBG_TMP
            JSR   STAMP4_AT
            LDA   INTRO_TMP_B
            STA   GNBG_TMP
            JSR   STAMP4_AT

            LDA   INTRO_TMP_A
            CLC
            ADC   #$0202
            STA   INTRO_TMP_A
            LDA   INTRO_TMP_B
            SEC
            SBC   #$01FE
            STA   INTRO_TMP_B

            PLX
            DEX
            BNE   :dm_loop1

            ; ---- if(len!=1): secondo giro, i=1..len-1 (len-1 volte),
            ; continuando "di"/"si" da dove li ha lasciati il primo
            ; giro (non si riparte da loc) ----
            SEP   #$20
            MX    %10
            LDA   DIAMOND_LEN
            CMP   #1
            BEQ   :dm_skip2
            REP   #$30
            MX    %00

            LDA   INTRO_TMP_A
            SEC
            SBC   #$0400
            STA   INTRO_TMP_A
            LDA   INTRO_TMP_B
            CLC
            ADC   #$0400
            STA   INTRO_TMP_B

            SEP   #$20
            MX    %10
            LDA   DIAMOND_LEN
            SEC
            SBC   #1
            STA   GNBG_TMP2
            REP   #$30
            MX    %00
            LDA   GNBG_TMP2
            AND   #$00FF
            TAX

:dm_loop2   PHX
            LDA   INTRO_TMP_A
            STA   GNBG_TMP
            JSR   STAMP4_AT
            LDA   INTRO_TMP_B
            STA   GNBG_TMP
            JSR   STAMP4_AT

            LDA   INTRO_TMP_A
            SEC
            SBC   #$01FE
            STA   INTRO_TMP_A
            LDA   INTRO_TMP_B
            CLC
            ADC   #$0202
            STA   INTRO_TMP_B

            PLX
            DEX
            BNE   :dm_loop2
            BRA   :dm_after2

:dm_skip2   REP   #$30
            MX    %00

:dm_after2
            ; ---- loc += locd; len += lend (8 bit, wrap naturale) ----
            LDA   DIAMOND_LOC
            CLC
            ADC   DIAMOND_LOCD
            STA   DIAMOND_LOC

            SEP   #$20
            MX    %10
            LDA   DIAMOND_LEN
            CLC
            ADC   DIAMOND_LEND
            STA   DIAMOND_LEN
            BNE   :dm_notzero

            ; len wrappato a 0: rombo sparito del tutto - reset dello
            ; stato (per il prossimo giro di loop dell'intro) e avanti
            REP   #$30
            MX    %00
            LDA   #$7E7E
            STA   DIAMOND_LOC
            LDA   #$FFFE
            STA   DIAMOND_LOCD
            SEP   #$20
            MX    %10
            LDA   #1
            STA   DIAMOND_LEN
            STA   DIAMOND_LEND
            REP   #$30
            MX    %00
            JSR   INTRO_NEXT
            RTS

; *** TL55 FIX: qui si arriva SOLO via il BNE qui sopra (mai per fall-
; through), con A/M ancora a 8 bit (dal SEP #$20 di qualche riga fa) -
; ma testualmente l'ultima direttiva MX prima di questa etichetta era
; quella del ramo "len azzerato" (MX %00, 16 bit), quindi Merlin32
; assemblava "CMP #$42" come immediato a 16 bit (3 byte: C9 42 00).
; A runtime pero' la CPU e' davvero a 8 bit qui, quindi quel terzo
; byte ($00) veniva eseguito come istruzione a se' - un BRK! - subito
; dopo la CMP/BCC, ed e' esattamente quello che mandava la macchina nel
; monitor/testo non appena si provava la fase 5 (rombo, tasto '6').
; La direttiva MX qui sotto non genera alcun byte: dice solo
; all'assemblatore lo stato VERO della CPU in questo punto, cosi'
; "CMP #$42" torna a essere l'immediato a 8 bit che deve essere (2
; byte: C9 42), coerente con l'SBC/ADC a 8 bit di poco sopra.
:dm_notzero MX    %10
            CMP   #$42
            BCC   :dm_nomax
            ; len ha raggiunto la dimensione massima: si inverte la
            ; direzione (comincia a restringersi)
            REP   #$30
            MX    %00
            LDA   #$FE7E
            STA   DIAMOND_LOC
            LDA   #$0002
            STA   DIAMOND_LOCD
            SEP   #$20
            MX    %10
            LDA   #$41
            STA   DIAMOND_LEN
            LDA   #$FF            ; -1
            STA   DIAMOND_LEND
:dm_nomax   REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; TL55: MULSHR8S - variante di MULSHR8U (vedi piu' sotto) con ENTRAMBI
; gli operandi con segno: r_p50 moltiplica sincos0s[] (con segno) per
; ebp (anch'esso con segno), mentre MULSHR8U esistente assume MULA
; sempre positivo (era gia' cosi' per come lo usa INIT_GNBGTBL).
; A (16 bit - il chiamante isola il byte col solito AND #$00FF, stessa
; convenzione di MULSHR8U) = (MULA*MULB)>>8, entrambi trattati come
; signed 16 bit. Stessa tecnica di MULSHR8U: valori assoluti in
; MUL16U, poi segno combinato (XOR dei due segni) riapplicato al
; prodotto a 32 bit finale.
; ---------------------------------------------------------------------
MULSHR8S    LDA   MULA
            BPL   :m8s_apos
            EOR   #$FFFF
            INC   A
            STA   MULA
            LDA   #1
            BRA   :m8s_asto
:m8s_apos   LDA   #0
:m8s_asto   STA   MUL_SIGN
            LDA   MULB
            BPL   :m8s_bpos
            EOR   #$FFFF
            INC   A
            STA   MULB
            LDA   MUL_SIGN
            EOR   #1
            BRA   :m8s_bsto
:m8s_bpos   LDA   MUL_SIGN
:m8s_bsto   STA   MUL_SIGN
            JSR   MUL16U
            LDA   MUL_SIGN
            BEQ   :m8s_noneg
            LDA   PRODLO
            EOR   #$FFFF
            STA   PRODLO
            LDA   PRODHI
            EOR   #$FFFF
            STA   PRODHI
            INC   PRODLO
            BNE   :m8s_noneg
            INC   PRODHI
:m8s_noneg  LDA   PRODLO+1
            RTS

; ---------------------------------------------------------------------
; TL55: SINE50_STEP - porting di r_p50 (timeless.c): due bande
; diagonali sinusoidali "in controfase" scorrono sull'intera texture,
; una passata di 256 texel a chiamata, pilotate da un solo contatore a
; 8 bit (SINE50_CNTR, 255->0, wrap dopo 256 chiamate). Tutte le altre
; variabili del C (edi, ebp, dl) sono ricalcolate da zero ad ogni
; chiamata: vivono solo in scratch transitorio (SINE_EDI/SINE_EBP/
; SINE_DL, dormienti durante l'intro come GNBG_TMP - vedi CURVE_STEP),
; non serve stato persistente dedicato oltre al contatore.
;
; ebx = sincos0s[dl]*ebp, ENTRAMBI gli operandi con segno (MULSHR8S).
; Il byte alto del prodotto con segno (bit 8..15, esattamente "ebx>>8"
; del C dopo il suo "ebx&=0xff00" - la mascheratura in piu' del C non
; serve qui: contribuirebbe solo a bit oltre il 16esimo, persi
; comunque nel "&0xffff" finale) serve due volte: come offset di riga
; (XBA lo porta nel byte alto di un 16 bit, sommato a edi con wrap
; naturale a 16 bit - ogni riga e' 256 byte) e come base del colore
; (+0xa0). Colore rimappato a nibble con (byte_alto+0x10)>>1 & $0F -
; banda larga 32 invece di 64 come le altre fasi, perche' qui il
; valore oscilla di +-16 intorno a 0xa0 (0xa0-0x90=0x10, e /2 invece di
; /4 perche' la banda e' meta' larga) - poi TILE_REMAP_TABLE come
; sempre.
; NOTA: sincos0s[] tocca -128 in un paio di punti, quindi nei casi
; estremi (sincos0s=-128 ED ebp=-32 nello stesso texel, molto raro) il
; byte alto puo' arrivare a 0x10 anziche' fermarsi a +-15: l'AND #$000F
; lo fa avvolgere a nibble 0 invece di restare al massimo (15) per quel
; singolo texel - imperfezione minima e rarissima, stesso livello di
; approssimazione gia' accettato altrove nella quantizzazione a 16
; colori, non corretta apposta per non complicare il calcolo.
; ---------------------------------------------------------------------
SINE50_STEP
            REP   #$30
            MX    %00

            ; edi = cntr<<8 (byte alto=cntr, byte basso=0)
            SEP   #$20
            MX    %10
            LDA   SINE50_CNTR
            REP   #$30
            MX    %00
            AND   #$00FF
            XBA
            STA   SINE_EDI

            ; ebp = cntr&0x7f; if(ebp>=0x40) ebp^=0x7f; ebp-=0x20
            SEP   #$20
            MX    %10
            LDA   SINE50_CNTR
            AND   #$7F
            CMP   #$40
            BCC   :s5_noxor
            EOR   #$7F
:s5_noxor   STA   GNBG_TMP2       ; ebp grezzo (0..63), scratch 8 bit
            REP   #$30
            MX    %00
            LDA   GNBG_TMP2
            AND   #$00FF
            SEC
            SBC   #$20
            STA   SINE_EBP        ; ebp finale, con segno (-32..31)

            ; dl = 0 (campo 16 bit mantenuto sempre pulito)
            STZ   SINE_DL

            LDY   #256             ; 256 texel per chiamata
:s5_loop
            LDA   SINE_DL
            TAX
            SEP   #$20
            MX    %10
            LDA   SINCOS0S_TABLE,X
            STA   MULA
            BPL   :s5_apos
            LDA   #$FF
            BRA   :s5_ahi
:s5_apos    LDA   #$00
:s5_ahi     STA   MULA+1
            REP   #$30
            MX    %00

            LDA   SINE_EBP
            STA   MULB

            JSR   MULSHR8S
            AND   #$00FF           ; RAW = byte alto con segno (0..255)

            PHA                     ; salva RAW per il calcolo colore
            CLC
            ADC   #$0010
            AND   #$00FF
            LSR   A
            AND   #$000F
            TAX
            SEP   #$20
            MX    %10
            LDA   TILE_REMAP_TABLE,X
            STA   GNBG_TMP3        ; colore finale, condiviso dai 2 texel
            REP   #$30
            MX    %00
            PLA                     ; ripristina RAW

            XBA                     ; A = RAW<<8 (offset di riga)
            CLC
            ADC   SINE_EDI
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            TXA
            CLC
            ADC   #256
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP3
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00

            ; dl += 8 (mod 256)
            LDA   SINE_DL
            CLC
            ADC   #8
            AND   #$00FF
            STA   SINE_DL

            ; ++edi
            INC   SINE_EDI

            DEY
            BNE   :s5_loop

            ; if(!cntr--) INTRO_NEXT (verifica PRIMA di decrementare,
            ; poi il decremento avviene comunque, con wrap 0->255)
            SEP   #$20
            MX    %10
            LDA   SINE50_CNTR
            BNE   :s5_notlast
            DEC   SINE50_CNTR
            REP   #$30
            MX    %00
            JSR   INTRO_NEXT
            RTS
:s5_notlast DEC   SINE50_CNTR
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; TL55: WIPE_STEP - porting di r_p60 (timeless.c): una fascia di 32
; righe (0x2000 = 8192 byte) viene riempita con nibble 0 (rimappato
; via TILE_REMAP_TABLE come tutte le altre fasi), scorrendo verso il
; basso di 32 righe a chiamata - stesso schema "store a 16 bit, avanza
; di 2" di CLEAR_OFFSCREEN_FLAT (color|color<<8 in un colpo solo,
; invece di un byte alla volta). WIPE_LOC riparte da 0 automaticamente
; dopo 8 chiamate (0,32,64,...,224 poi di nuovo 0, 8 bit), momento in
; cui l'intera texture e' stata ripulita e si richiama INTRO_NEXT.
; ---------------------------------------------------------------------
WIPE_STEP   REP   #$30
            MX    %00

            SEP   #$20
            MX    %10
            LDA   #0
            TAX
            LDA   TILE_REMAP_TABLE,X
            STA   GNBG_TMP          ; colore singolo (nibble 0 rimappato)
            REP   #$30
            MX    %00

            ; parola di riempimento = colore | colore<<8
            LDA   GNBG_TMP
            AND   #$00FF
            STA   GNBG_TMP2
            XBA
            ORA   GNBG_TMP2
            STA   GNBG_TMP2         ; GNBG_TMP2 = parola doppia pronta

            ; offset iniziale = loc<<8
            SEP   #$20
            MX    %10
            LDA   WIPE_LOC
            REP   #$30
            MX    %00
            AND   #$00FF
            XBA
            TAX                      ; X = offset base (16 bit)

            LDY   #4096              ; 4096 store a 16 bit = 8192 byte
:wp_loop    LDA   GNBG_TMP2
            STA   >OFFSCREEN_BASE,X
            INX
            INX
            DEY
            BNE   :wp_loop

            ; loc += 0x20; se wrappa a 0 (8 chiamate) -> INTRO_NEXT
            SEP   #$20
            MX    %10
            LDA   WIPE_LOC
            CLC
            ADC   #$20
            STA   WIPE_LOC
            REP   #$30
            MX    %00
            LDA   WIPE_LOC
            AND   #$00FF
            BNE   :wp_done
            JSR   INTRO_NEXT
:wp_done    RTS

; ---------------------------------------------------------------------
; MUSIC_INIT: carica NTPPLAYER (banco $0F) e RAIN.NTP (banchi $0D/$0E)
; via ProDOS 8 MLI, poi avvia la riproduzione. Tutto guardato da
; MUSIC_ENABLED - se 0, questo corpo non viene nemmeno assemblato
; nella chiamata. In caso di errore la demo prosegue comunque SENZA
; musica, non si blocca.
; ---------------------------------------------------------------------
MUSIC_INIT
            DO    MUSIC_ENABLED
            REP   #$30
            MX    %00

; *** TL59F FIX: NTPPLAYER/RAIN.NTP vengono aperti con un path relativo
; (senza "/"), quindi dipendono dal prefix ProDOS corrente. Bitsy Bye
; imposta il prefix alla cartella sfogliata prima di lanciare il
; programma, ma BASIC.SYSTEM con "-tl59e.sys" NO (lo lascia vuoto) -
; confermato con una build diagnostica (GET_PREFIX a runtime tornava
; stringa vuota lanciando da BASIC.SYSTEM, mentre da Bitsy Bye il
; prefix risultava corretto): OPEN "NTPPLAYER" senza prefix non ha
; nulla su cui risolvere il path relativo, fallisce, e la rete di
; sicurezza sotto lo gestisce in silenzio -> niente musica, nessun
; crash. Fix: impostiamo NOI il prefix esplicitamente, qui, prima di
; aprire qualsiasi file, cosi' il risultato non dipende piu' da come
; il programma e' stato lanciato. Errore di SET_PREFIX ignorato
; deliberatamente: se fallisse, le OPEN sotto falliranno comunque e
; verranno gestite come sempre (niente musica, niente crash).
;
; *** IMPORTANTE: FIX_PREFIX_PATH sotto assume che TL59F.SYS,
; NTPPLAYER e RAIN.NTP stiano tutti nella cartella "/SHR/" (nome del
; volume visto durante il test). Se il disco/cartella reale e' diverso,
; aggiornare la stringa (byte di lunghezza incluso, DFB N prima di ASC).
            SEC
            XCE
            JSR   $BF00
            DFB   $C6
            DA    FIX_SETPFX_PARAMS
            CLC
            XCE
            REP   #$30
            MX    %00

            LDA   #PATH_PLAYER
            STA   OPEN_PATHPTR
            JSR   MLI_OPEN
            BCC   :mi_ok1
            JMP   :mi_done
:mi_ok1
            LDA   #NTPPLAYER_SIZE
            STA   BYTES_LEFT
            LDA   #$0F
            STA   DEST_BANK_VAR
            STZ   DEST_OFF
            JSR   READ_INTO_BANK
            BCC   :mi_ok2
            JMP   :mi_done
:mi_ok2
            JSR   MLI_CLOSE

            LDA   #PATH_RAIN
            STA   OPEN_PATHPTR
            JSR   MLI_OPEN
            BCC   :mi_ok3
            JMP   :mi_done
:mi_ok3
            LDA   #$0D
            STA   DEST_BANK_VAR
            STZ   DEST_OFF
            LDX   #16              ; 16 blocchi da 4096 = 65536 esatti
:mi_bank_d  LDA   #CHUNK_SIZE
            STA   CHUNK_NOW
            PHX
            JSR   READ_CHUNK_AND_COPY
            PLX
            BCC   :mi_ok4
            JMP   :mi_done
:mi_ok4
            DEX
            BNE   :mi_bank_d

            LDA   #$0E
            STA   DEST_BANK_VAR
            STZ   DEST_OFF
            LDA   #RAIN_REMAINDER
            STA   BYTES_LEFT
            JSR   READ_INTO_BANK
            BCC   :mi_ok5
            JMP   :mi_done
:mi_ok5
            JSR   MLI_CLOSE

            ; --- avvia il player ---
            REP   #$30
            MX    %00
            LDX   #$0000           ; offset iniziale rain.ntp
            LDY   #$000D           ; banco $0D
            LDA   #$0000           ; 0 = normale (2 oscillatori/traccia)
            JSL   NTPprepare
            BCS   :mi_done

            LDA   #$0000           ; 0 = ripeti il brano in loop
            JSL   NTPplay

:mi_done
            FIN
            RTS

MUSIC_PLAY  RTS         ; il player suona via interrupt, nulla da fare qui

; ---------------------------------------------------------------------
; Routine di caricamento file (da loader_rain.s/TL44) - guardate anche
; loro da MUSIC_ENABLED.
; ---------------------------------------------------------------------
            DO    MUSIC_ENABLED

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
            BCC   :rib_ok
            JMP   :rib_err
:rib_ok
            LDA   BYTES_LEFT
            SEC
            SBC   CHUNK_NOW
            STA   BYTES_LEFT
            BRA   :rib_loop
:rib_done   CLC
            RTS
:rib_err    SEC
            RTS

READ_CHUNK_AND_COPY
            REP   #$30
            MX    %00
            LDA   CHUNK_NOW
            STA   READ_COUNT
            JSR   MLI_READ
            BCC   :rc_ok
            JMP   :rc_err
:rc_ok
            ; *** TL49 FIX: forza DBR=$00 esplicitamente PRIMA della
            ; scrittura del banco destinazione in MVN_DEST_PATCH - non
            ; ci fidiamo che sia gia' $00 solo perche' dovrebbe esserlo.
            ; Se DBR fosse sbagliato in quell'istante, questa STA
            ; scriverebbe nel banco sbagliato, e se quel banco fosse
            ; $00 la successiva MVN scriverebbe i dati del file DIRETTO
            ; SOPRA il nostro stesso programma (che vive in banco $00
            ; a partire da $2000) - sospetto concreto per il crash con
            ; PC finito esattamente su CHECK_KEYBOARD corrotta a $00.
            PHK
            PLB

            SEP   #$20
            MX    %10
            LDA   DEST_BANK_VAR
            STA   MVN_DEST_PATCH
            REP   #$30
            MX    %00

            LDX   #STAGE_BUF
            LDY   DEST_OFF
            LDA   CHUNK_NOW
            SEC
            SBC   #1
MVN_INSTR   MVN   $00,$00
MVN_DEST_PATCH EQU MVN_INSTR+1

            PHK
            PLB

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
            PHK                     ; DBR=$00 esplicito prima di scrivere
            PLB
            ; *** TL49 FIX VERO: REF_NUM/READ_REFNUM/CLOSE_REFNUM sono
            ; campi da UN byte (ProDOS vuole cosi' il ref_num). Una STA
            ; con A a 16 bit ne scrive SEMPRE 2 - il secondo byte (il
            ; byte alto, sempre $00 dopo l'AND #$00FF) finiva dritto
            ; sopra il byte subito dopo in memoria. Per CLOSE_REFNUM,
            ; quel byte era il PRIMO di CHECK_KEYBOARD: ecco la vera
            ; causa di tutti i crash di oggi - non un interrupt, una
            ; scrittura a 16 bit su un campo a 8. Ora scriviamo a 8 bit,
            ; larghezza vera del campo.
            SEP   #$20
            MX    %10
            LDA   OPEN_REFNUM
            STA   REF_NUM
            STA   READ_REFNUM
            STA   CLOSE_REFNUM
            REP   #$30
            MX    %00
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

PATH_PLAYER DFB   9
            ASC   'NTPPLAYER'
PATH_RAIN   DFB   8
            ASC   'RAIN.NTP'

; *** TL59F FIX: vedi commento in cima a MUSIC_INIT. Path assoluto
; della cartella con TL59F.SYS/NTPPLAYER/RAIN.NTP - aggiornare se il
; disco/cartella reale e' diverso da "/SHR/".
FIX_SETPFX_PARAMS  DFB   1
                   DA    FIX_PREFIX_PATH
FIX_PREFIX_PATH    DFB   5
                    ASC   '/SHR/'

OPEN_PARAMS    DFB   3
OPEN_PATHPTR   DA    0
               DA    IO_BUFFER
OPEN_REFNUM    DFB   0

READ_PARAMS    DFB   4
READ_REFNUM    DFB   0
               DA    STAGE_BUF
READ_COUNT     DA    0
               DA    0

CLOSE_PARAMS   DFB   1
CLOSE_REFNUM   DFB   0

            FIN


; *** TL49 v3: nessuna protezione SEI/CLI qui - non serve, il player
; puo' interrompere in qualunque momento senza problemi (il vero bug
; di ieri era nel loader, non nell'interrupt).
CHECK_KEYBOARD
            REP   #$30
            MX    %00
            LDA   $C000
            AND   #$0080
            BEQ   :no_key
            STA   $C010
            LDA   $C000
            AND   #$007F
            CMP   #$001B           ; ESC premuto?
            BEQ   :ck_exit

            ; *** TL53: tasti 1/2/3/4/5 = salto diretto di fase (debug),
            ; vedi DEBUG_JUMP_PHASE. Ogni tasto azzera la scacchiera e
            ; riparte da zero nella fase scelta, cosi' si puo' confrontare
            ; subito con l'originale senza aspettare le fasi precedenti.
            CMP   #$0031           ; '1' = curva (r_p00)
            BEQ   :ck_key1
            CMP   #$0032           ; '2' = punti (r_p10)
            BEQ   :ck_key2
            CMP   #$0033           ; '3' = linee incrociate (r_p20)
            BEQ   :ck_key3
            CMP   #$0034           ; '4' = cluster margherite (r_p30)
            BEQ   :ck_key4
            CMP   #$0035           ; '5' = scacchiera + margherite sparse crescenti
            BEQ   :ck_key5
            CMP   #$0036           ; *** TL55: '6' = rombo (r_p40)
            BEQ   :ck_key6
            CMP   #$0037           ; *** TL55: '7' = tenda sinusoidale (r_p50)
            BEQ   :ck_key7
            CMP   #$0038           ; *** TL55: '8' = wipe a bande (r_p60)
            BEQ   :ck_key8
            ; *** TL55: su richiesta i tasti veloci restano pronti fino a
            ; 1-9-0 (10 fasi al massimo), ma '9' e '0' non sono ancora
            ; agganciati: non esiste ancora una 9a/10a fase in
            ; INTRO_TABLE, quindi un salto li' andrebbe fuori tabella.
            ; Aggiungere '9'/'0' qui e i corrispondenti :ck_key9/:ck_key0
            ; quando arrivera' la prossima fase.

            CMP   #$0020           ; *** TL54: SPAZIO = alterna anteprima texture
            BNE   :no_key

            ; *** TL51 v5: click udibile, indipendente da bordo/VRAM -
            ; tenuto anche in TL54 solo come conferma "il tasto e' stato
            ; letto", non e' piu' legato al bordo (vedi sotto).
            SEP   #$20
            MX    %10
            LDA   $C030            ; speaker toggle
            REP   #$30
            MX    %00

            ; *** TL54: SPAZIO non alterna piu' il benchmark PEI/STA (e
            ; quindi non tocca piu' il bordo schermo - niente piu' JSR
            ; SET_BORDER_INDICATOR qui, resta silenzioso/dormiente come
            ; richiesto). Ora alterna TEXTURE_PREVIEW_MODE, letto da
            ; MAIN_LOOP per decidere se mostrare il tunnel (GNBG_RENDER)
            ; o la texture 256x256 grezza (SHOW_TEXTURE_DIRECT).
            LDA   TEXTURE_PREVIEW_MODE
            EOR   #$0001
            STA   TEXTURE_PREVIEW_MODE
:no_key     RTS
:ck_exit    JMP   EXIT_DEMO

:ck_key1    LDA   #0
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key2    LDA   #1
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key3    LDA   #2
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key4    LDA   #3
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key5    LDA   #4
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key6    LDA   #5
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key7    LDA   #6
            JSR   DEBUG_JUMP_PHASE
            RTS
:ck_key8    LDA   #7
            JSR   DEBUG_JUMP_PHASE
            RTS

; ---------------------------------------------------------------------
; MOTION FIELD - mover "veri" stile Tran (invariati da TL4, tranne il
; wrap di VIEW_DIR che ora e' mod 320 come vpdir in timeless.c, non
; piu' mod 256)
; ---------------------------------------------------------------------
TS3_UPDATE_MOVERS
            REP   #$30
            MX    %00

            JSR   STEP_MVX
            JSR   STEP_MVY
            JSR   STEP_MVD

            LDA   VIEW_X
            CLC
            ADC   MVX_AT
            AND   #$00FF
            STA   VIEW_X

            LDA   VIEW_Y
            CLC
            ADC   MVY_AT
            AND   #$00FF
            STA   VIEW_Y

            ; VIEW_DIR: wrap 0..319 (non una potenza di 2, quindi
            ; niente AND: controlliamo segno e overflow esplicitamente,
            ; come "if(vpdir<0) +=320; if(vpdir>=320) -=320;" in C)
            LDA   VIEW_DIR
            CLC
            ADC   MVD_AT
            BPL   :dir_notneg
            CLC
            ADC   #320
            BRA   :dir_store
:dir_notneg CMP   #320
            BCC   :dir_store
            SEC
            SBC   #320
:dir_store  STA   VIEW_DIR
            RTS

STEP_MVX    LDA   MVX_MOVING
            BNE   :mx_step
            LDA   MVX_DELAY
            SEC
            SBC   #1
            STA   MVX_DELAY
            BNE   :mx_rts
            LDA   MVX_WHICH
            CLC
            ADC   #1
            AND   #7
            STA   MVX_WHICH
            LDA   MVX_PERIOD
            STA   MVX_DELAY
            LDA   #1
            STA   MVX_MOVING
            BRA   :mx_rts
:mx_step    LDA   MVX_WHICH
            ASL   A
            TAX
            LDA   MVX_WANTS,X
            STA   MV_SCRATCH
            LDA   MVX_AT
            SEC
            SBC   MV_SCRATCH
            BEQ   :mx_goal
            BMI   :mx_inc
            DEC   MVX_AT
            BRA   :mx_rts
:mx_inc     INC   MVX_AT
            BRA   :mx_rts
:mx_goal    STZ   MVX_MOVING
:mx_rts     RTS

STEP_MVY    LDA   MVY_MOVING
            BNE   :my_step
            LDA   MVY_DELAY
            SEC
            SBC   #1
            STA   MVY_DELAY
            BNE   :my_rts
            LDA   MVY_WHICH
            CLC
            ADC   #1
            AND   #7
            STA   MVY_WHICH
            LDA   MVY_PERIOD
            STA   MVY_DELAY
            LDA   #1
            STA   MVY_MOVING
            BRA   :my_rts
:my_step    LDA   MVY_WHICH
            ASL   A
            TAX
            LDA   MVY_WANTS,X
            STA   MV_SCRATCH
            LDA   MVY_AT
            SEC
            SBC   MV_SCRATCH
            BEQ   :my_goal
            BMI   :my_inc
            DEC   MVY_AT
            BRA   :my_rts
:my_inc     INC   MVY_AT
            BRA   :my_rts
:my_goal    STZ   MVY_MOVING
:my_rts     RTS

STEP_MVD    LDA   MVD_MOVING
            BNE   :md_step
            LDA   MVD_DELAY
            SEC
            SBC   #1
            STA   MVD_DELAY
            BNE   :md_rts
            LDA   MVD_WHICH
            CLC
            ADC   #1
            AND   #7
            STA   MVD_WHICH
            LDA   MVD_PERIOD
            STA   MVD_DELAY
            LDA   #1
            STA   MVD_MOVING
            BRA   :md_rts
:md_step    LDA   MVD_WHICH
            ASL   A
            TAX
            LDA   MVD_WANTS,X
            STA   MV_SCRATCH
            LDA   MVD_AT
            SEC
            SBC   MV_SCRATCH
            BEQ   :md_goal
            BMI   :md_inc
            DEC   MVD_AT
            BRA   :md_rts
:md_inc     INC   MVD_AT
            BRA   :md_rts
:md_goal    STZ   MVD_MOVING
:md_rts     RTS

MVX_WANTS   DA    1, -5, 1, -3, 3, -1, 5, -3
MVY_WANTS   DA    3, -1, 5, -3, 1, -5, 1, -3
MVD_WANTS   DA    5, -7, 6, -5, 9, -6, 7, -9

; ---------------------------------------------------------------------
; GENERATE_OFFSCREEN: riempie banco $02 (256x256 = 65536 byte) con una
; texture di prova (checkerboard a blocchi 16x16, valori 0x08/0x0C,
; nibble compatibili con la palette a 16 colori). Da sostituire in
; futuro con veri tile grafici (daisy/lightning/eyeball/ecc come in
; timeless.c) o con un pattern piu' elaborato.
; ---------------------------------------------------------------------
GENERATE_OFFSCREEN
            REP   #$30
            MX    %00
            LDY   #0
:go_row     LDX   #0
:go_col     TXA
            LSR   A
            LSR   A
            LSR   A
            LSR   A
            STA   GNBG_TMP2
            TYA
            LSR   A
            LSR   A
            LSR   A
            LSR   A
            EOR   GNBG_TMP2
            AND   #$0001
            BEQ   :go_dark
            LDA   #$000C
            BRA   :go_pack
:go_dark    LDA   #$0008
:go_pack    STA   GNBG_TMP        ; valore nibble del pattern

            TYA
            XBA
            STA   GNBG_TMP2
            TXA
            ORA   GNBG_TMP2       ; indice a 16 bit = riga*256+colonna

            PHX
            TAX
            LDA   GNBG_TMP
            SEP   #$20
            MX    %10
            STA   >OFFSCREEN_BASE,X
            REP   #$30
            MX    %00
            PLX

            INX
            CPX   #256
            BNE   :go_col
            INY
            CPY   #256
            BNE   :go_row
            RTS

; ---------------------------------------------------------------------
; TL53: CLEAR_OFFSCREEN_FLAT - riempie tutto il banco $02 (65536 byte,
; l'intera texture 256x256) con UN SOLO colore piatto, invece della
; scacchiera di GENERATE_OFFSCREEN.
; *** TL53 v2: era $08 (slot 8 = ciano pieno, vedi COLOR_DATA), ma
; l'originale di Tran ha sfondo NERO con i punti/linee che risaltano
; in bianco/blu sopra - vedi riferimento video mandato dall'utente.
; Slot 0 = $0000 in tutti e 4 i gruppi palette ("maschera/nero"),
; quindi $00 e' nero con qualunque tema attivo, senza bisogno di remap
; (stesso ragionamento di prima, solo con lo slot giusto).
;
; Sostituisce GENERATE_OFFSCREEN sia all'avvio (START) sia prima di
; ogni salto di fase col debug (DEBUG_JUMP_PHASE, tasti 1/2/3/4/5), cosi'
; curva/punti/linee/margherite si vedono su schermo pulito invece che
; sopra il pattern di prova a scacchi.
;
; Ciclo: X a 16 bit parte da 0 e avanza di 2 ad ogni store (STA a 16
; bit scrive 2 byte identici $00). Il buffer e' esattamente 65536
; byte = tutto lo spazio di un indice a 16 bit: non possiamo confrontare
; X con 65536 (non ci sta in 16 bit), quindi sfruttiamo il wraparound
; naturale di X, che torna a 0 da solo esattamente dopo 32768 store
; (32768*2 = 65536 byte, l'intero banco).
; ---------------------------------------------------------------------
CLEAR_OFFSCREEN_FLAT
            REP   #$30
            MX    %00
            LDX   #0
            LDA   #$0000
:cof_loop   STA   >OFFSCREEN_BASE,X
            INX
            INX
            CPX   #0                ; vero solo dopo il wraparound a 65536
            BEQ   :cof_done
            BRA   :cof_loop
:cof_done   RTS

; ---------------------------------------------------------------------
; INIT_GNBGTBL: costruisce la tabella tunnel di Tran in banco $03.
;
; *** TL41: SFRUTTA LA SIMMETRIA A 4 VIE del cerchio. Con Y(i)=
; RTAB[j]*sin(a_i), X(i)=RTAB[j]*cos(a_i), e sapendo che le 320 colonne
; corrispondono ad angoli equispaziati su un giro completo (320/4=80
; colonne per quarto di giro), valgono le identita' trigonometriche:
;   colonna i+80  (+90 gradi): Y=X(i),  X=-Y(i)
;   colonna i+160 (+180 gradi): Y=-Y(i), X=-X(i)
;   colonna i+240 (+270 gradi): Y=-X(i), X=Y(i)
; Quindi calcoliamo DAVVERO (con moltiplicazione) solo i=0..79, e le
; altre 3 colonne per ogni i le otteniamo da Y(i),X(i) gia' calcolati
; con solo scambi e cambi di segno (nessuna moltiplicazione). Le
; moltiplicazioni totali passano da 320*100*2=64000 a 80*100*2=16000.
;
; Ogni passo j scrive le 4 colonne derivate (dy,dx) nei rispettivi
; punti della tabella, ciascuna con il proprio accumulatore "at"
; (serve per calcolare i delta) e il proprio puntatore di scrittura.
;
; *** TL41: il delta Y include anche il "+1 post-incremento" che in
; GNBG_RENDER si applicava a runtime dopo ogni campionamento (vedi
; gnbg() in C: "sy++" dopo la lettura): fondendolo qui nel delta
; salvato (per ogni passo j>0) otteniamo la STESSA sequenza di sy
; campionati, ma GNBG_RENDER non deve piu' farlo ad ogni pixel.
; ---------------------------------------------------------------------
INIT_GNBGTBL
            REP   #$30
            MX    %00
            STZ   GNBG_I

:ig_outer   ; *** TL49: GNBG_PTR0 = GNBG_I * 100 (era *50 in TL48; 100
            ; = 4+32+64 ora che la profondita' e' 50 passi invece di 25)
            LDA   GNBG_I
            STA   GNBG_TMP
            ASL   A
            ASL   A                 ; *4
            STA   GNBG_PTR0
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *32
            CLC
            ADC   GNBG_PTR0
            STA   GNBG_PTR0         ; *36
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *64
            CLC
            ADC   GNBG_PTR0
            STA   GNBG_PTR0         ; = i*100

            LDA   GNBG_PTR0
            CLC
            ADC   #8000              ; *** TL49: colonna i+80 = i*100+8000
            STA   GNBG_PTR1          ; (era +4000 con lo stride a 50)
            CLC
            ADC   #8000
            STA   GNBG_PTR2
            CLC
            ADC   #8000
            STA   GNBG_PTR3

            STZ   GNBG_ATY0
            STZ   GNBG_ATX0
            STZ   GNBG_ATY1
            STZ   GNBG_ATX1
            STZ   GNBG_ATY2
            STZ   GNBG_ATX2
            STZ   GNBG_ATY3
            STZ   GNBG_ATX3

            STZ   GNBG_J

:ig_inner   ; --- Y,X assoluti della colonna base i = (RTAB[j]*SIN320[i],
            ; RTAB[j]*COS320[i]) >> 8: le UNICHE 2 moltiplicazioni ---
            LDA   GNBG_J
            ASL   A
            TAX
            LDA   RTAB,X
            STA   MULA
            LDA   GNBG_I
            ASL   A
            TAX
            LDA   SIN320,X
            STA   MULB
            JSR   MULSHR8U
            AND   #$00FF
            STA   GNBG_Y

            LDA   GNBG_J
            ASL   A
            TAX
            LDA   RTAB,X
            STA   MULA
            LDA   GNBG_I
            ASL   A
            TAX
            LDA   COS320,X
            STA   MULB
            JSR   MULSHR8U
            AND   #$00FF
            STA   GNBG_X

            JSR   IG_EMIT0          ; colonna i      : (Y, X)
            JSR   IG_EMIT1          ; colonna i+80   : (X, -Y)
            JSR   IG_EMIT2          ; colonna i+160  : (-Y, -X)
            JSR   IG_EMIT3          ; colonna i+240  : (-X, Y)

            LDA   GNBG_J
            CLC
            ADC   #1
            STA   GNBG_J
            CMP   #50               ; *** TL49: era 25 in TL48
            BEQ   :ig_inner_done
            JMP   :ig_inner
:ig_inner_done

            LDA   GNBG_I
            CLC
            ADC   #1
            STA   GNBG_I
            CMP   #80
            BEQ   :ig_outer_done
            JMP   :ig_outer
:ig_outer_done
            RTS

; --- IG_EMITn: calcola il delta (con fold del +1 per j>0), lo scrive
; nella gnbgtbl alla posizione GNBG_PTRn, aggiorna l'accumulatore
; GNBG_AT{Y,X}n e avanza GNBG_PTRn di 2. Ognuna usa una diversa
; combinazione di segno/scambio di GNBG_Y/GNBG_X (vedi commento sopra).
IG_EMIT0    LDA   GNBG_Y
            STA   GNBG_TMP
            LDA   GNBG_X
            STA   GNBG_TMP2
            LDA   GNBG_ATY0
            STA   MULA              ; riuso MULA/MULB come scratch a0/at
            LDA   GNBG_ATX0
            STA   MULB
            JSR   IG_STORE
            STA   GNBG_ATY0         ; (IG_STORE lascia Y in A)
            LDA   GNBG_TMP2
            STA   GNBG_ATX0
            LDA   GNBG_PTR0
            JSR   IG_WRITE
            STA   GNBG_PTR0
            RTS

IG_EMIT1    LDA   GNBG_X
            STA   GNBG_TMP          ; Y1 = X
            LDA   GNBG_Y
            EOR   #$00FF
            CLC
            ADC   #1
            AND   #$00FF
            STA   GNBG_TMP2         ; X1 = -Y
            LDA   GNBG_ATY1
            STA   MULA
            LDA   GNBG_ATX1
            STA   MULB
            JSR   IG_STORE
            STA   GNBG_ATY1
            LDA   GNBG_TMP2
            STA   GNBG_ATX1
            LDA   GNBG_PTR1
            JSR   IG_WRITE
            STA   GNBG_PTR1
            RTS

IG_EMIT2    LDA   GNBG_Y
            EOR   #$00FF
            CLC
            ADC   #1
            AND   #$00FF
            STA   GNBG_TMP          ; Y2 = -Y
            LDA   GNBG_X
            EOR   #$00FF
            CLC
            ADC   #1
            AND   #$00FF
            STA   GNBG_TMP2         ; X2 = -X
            LDA   GNBG_ATY2
            STA   MULA
            LDA   GNBG_ATX2
            STA   MULB
            JSR   IG_STORE
            STA   GNBG_ATY2
            LDA   GNBG_TMP2
            STA   GNBG_ATX2
            LDA   GNBG_PTR2
            JSR   IG_WRITE
            STA   GNBG_PTR2
            RTS

IG_EMIT3    LDA   GNBG_X
            EOR   #$00FF
            CLC
            ADC   #1
            AND   #$00FF
            STA   GNBG_TMP          ; Y3 = -X
            LDA   GNBG_Y
            STA   GNBG_TMP2         ; X3 = Y
            LDA   GNBG_ATY3
            STA   MULA
            LDA   GNBG_ATX3
            STA   MULB
            JSR   IG_STORE
            STA   GNBG_ATY3
            LDA   GNBG_TMP2
            STA   GNBG_ATX3
            LDA   GNBG_PTR3
            JSR   IG_WRITE
            STA   GNBG_PTR3
            RTS

; IG_STORE: dati GNBG_TMP=Yn, GNBG_TMP2=Xn, MULA=atYn, MULB=atXn
; (accumulatori precedenti), calcola i delta (con fold +1 su Y se
; GNBG_J>0), li mette in GNBG_DY/GNBG_DX. Ritorna A=Yn (da salvare
; come nuovo atYn dal chiamante).
IG_STORE    SEC
            LDA   GNBG_TMP
            SBC   MULA
            AND   #$00FF
            STA   GNBG_DY
            LDA   GNBG_J
            BEQ   :is_nofold
            LDA   GNBG_DY
            CLC
            ADC   #1
            AND   #$00FF
            STA   GNBG_DY
:is_nofold
            SEC
            LDA   GNBG_TMP2
            SBC   MULB
            AND   #$00FF
            STA   GNBG_DX
            LDA   GNBG_TMP
            RTS

; IG_WRITE: A=puntatore corrente (GNBG_PTRn); scrive GNBG_DY,GNBG_DX
; a quella posizione nella gnbgtbl; ritorna A=puntatore+2
IG_WRITE    STA   GNBG_TMP3
            LDX   GNBG_TMP3
            LDA   GNBG_DY
            SEP   #$20
            MX    %10
            STA   >GNBGTBL_BASE,X
            REP   #$30
            MX    %00
            INX
            LDA   GNBG_DX
            SEP   #$20
            MX    %10
            STA   >GNBGTBL_BASE,X
            REP   #$30
            MX    %00
            LDA   GNBG_TMP3
            CLC
            ADC   #2
            RTS

; ---------------------------------------------------------------------
; MULSHR8U: A = (MULA(unsigned 0..256) * MULB(signed -256..256)) >> 8
; Usa MUL16U (moltiplicazione unsigned 16x16->32 bit, shift-add) sui
; valori assoluti, poi corregge il segno sul prodotto a 32 bit finale.
; Il >>8 e' "gratis": si legge la parola a PRODLO+1 (byte alto di
; PRODLO + byte basso di PRODHI), poiche' PRODLO e PRODHI sono
; consecutivi in direct page.
; ---------------------------------------------------------------------
MULSHR8U    LDA   MULB
            BPL   :ms_pos
            EOR   #$FFFF
            INC   A
            STA   MULB
            LDA   #1
            STA   MUL_SIGN
            BRA   :ms_go
:ms_pos     STZ   MUL_SIGN
:ms_go      JSR   MUL16U
            LDA   MUL_SIGN
            BEQ   :ms_noneg
            LDA   PRODLO
            EOR   #$FFFF
            STA   PRODLO
            LDA   PRODHI
            EOR   #$FFFF
            STA   PRODHI
            INC   PRODLO
            BNE   :ms_noneg
            INC   PRODHI
:ms_noneg   LDA   PRODLO+1        ; = prodotto a 32 bit >> 8
            RTS

; MUL16U: PRODHI:PRODLO (32 bit) = MULA * MULB (entrambi trattati come
; unsigned 16 bit). Shift-add classico.
; *** TL41: 9 iterazioni invece di 16: MULA (rtab, max 256) e MULB
; (|sin|/|cos|, max 256) stanno entrambi in 9 bit (256 = bit 8), quindi
; oltre il 9deg bit MB_TMP e' sempre 0 e le iterazioni in piu' non
; farebbero nulla. -44% di lavoro per ogni moltiplicazione.
MUL16U      LDA   MULA
            STA   MCLO
            STZ   MCHI
            LDA   MULB
            STA   MB_TMP
            STZ   PRODLO
            STZ   PRODHI
            LDX   #9
:mu_loop    LSR   MB_TMP
            BCC   :mu_noadd
            CLC
            LDA   PRODLO
            ADC   MCLO
            STA   PRODLO
            LDA   PRODHI
            ADC   MCHI
            STA   PRODHI
:mu_noadd   ASL   MCLO
            ROL   MCHI
            DEX
            BNE   :mu_loop
            RTS

; ---------------------------------------------------------------------
; GNBG_RENDER: cammina gnbgtbl a partire dal punto di vista e disegna
; il tunnel, specchiato in alto/basso, esattamente come gnbg() in C.
; Elabora lo schermo a COPPIE di colonne (per impacchettare 2 pixel
; 4bpp in un byte VRAM), quindi 160 coppie x 25 campioni "veri" di
; profondita', ognuno duplicato su 4 righe sopra + 4 sotto (= 200
; righe totali, stessa copertura di prima).
; ---------------------------------------------------------------------
; *** TL41: ROWOFF/MROWOFF non si ricalcolano piu' a shift ogni riga:
; sono in ROWOFF_TABLE/MROWOFF_TABLE (precalcolate, vedi in fondo al
; file). Il "+1 post-incremento" e' stato fuso nei delta da
; INIT_GNBGTBL, quindi qui non serve piu'. Le sezioni a 8/16 bit sono
; raggruppate: 2 sole coppie SEP/REP per riga invece di 7.
; *** TL48: profondita' ridotta da 100 a 25 campioni "veri" per
; velocizzare - ognuno ora scrive 8 byte (4 righe sopra + 4 sotto,
; tutte identiche al campione appena calcolato) invece di 2, ma senza
; ricalcolare nulla: la parte cara (lettura gnbgtbl/texture,
; impacchettamento) capita 4 volte meno spesso.
GNBG_RENDER
            REP   #$30
            MX    %00

            ; --- offset iniziale nella tabella = VIEW_DIR * 100 (era
            ; *50; 100 = 4+32+64 ora che lo stride colonna e' 100 byte)
            LDA   VIEW_DIR
            STA   GNBG_TMP
            ASL   A
            ASL   A                 ; *4
            STA   BP_LEFT
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *32
            CLC
            ADC   BP_LEFT
            STA   BP_LEFT           ; *36
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                 ; *64
            CLC
            ADC   BP_LEFT
            STA   BP_LEFT           ; = VIEW_DIR*100

            JSR   GNBG_ADV100       ; BP_RIGHT = BP_LEFT + 100 (con wrap)
            STA   BP_RIGHT

            STZ   PAIR_IDX

:gr_pair    LDA   VIEW_Y
            AND   #$00FF
            STA   SXL
            STA   SXR
            LDA   VIEW_X
            AND   #$00FF
            STA   SYL
            STA   SYR
            STZ   YSTEP

:gr_row     ; --- indirizzi di scrittura VRAM gia' pronti (tabella) ---
            ; *** TL49: ogni campione ora copre 2 righe sopra (passi di
            ; 160 byte) + 2 sotto (era 4+4 in TL48, ora la profondita'
            ; e' 50 campioni invece di 25, quindi ne serve la meta')
            LDA   YSTEP
            ASL   A
            TAX
            LDA   ROWOFF_TABLE,X
            CLC
            ADC   PAIR_IDX
            STA   WRITE_X1
            CLC
            ADC   #160
            STA   WRITE_X1B

            LDA   MROWOFF_TABLE,X
            CLC
            ADC   PAIR_IDX
            STA   WRITE_X2
            SEC
            SBC   #160
            STA   WRITE_X2B

            ; --- blocco 8 bit #1: leggi i delta sx/dx per entrambe le
            ; colonne e aggiorna gli accumulatori SXL/SYL/SXR/SYR ---
            SEP   #$20
            MX    %10
            LDX   BP_LEFT
            LDA   >GNBGTBL_BASE,X   ; delta Y
            CLC
            ADC   SYL
            STA   SYL
            INX
            LDA   >GNBGTBL_BASE,X   ; delta X
            CLC
            ADC   SXL
            STA   SXL

            LDX   BP_RIGHT
            LDA   >GNBGTBL_BASE,X
            CLC
            ADC   SYR
            STA   SYR
            INX
            LDA   >GNBGTBL_BASE,X
            CLC
            ADC   SXR
            STA   SXR
            REP   #$30
            MX    %00

            ; --- costruisci i due indici nella texture offscreen ---
            LDA   SXL
            AND   #$00FF
            XBA
            ORA   SYL
            STA   GNBG_TMP          ; indice sinistro
            LDA   SXR
            AND   #$00FF
            XBA
            ORA   SYR
            STA   GNBG_TMP2         ; indice destro

            LDA   BP_LEFT
            CLC
            ADC   #2
            STA   BP_LEFT
            LDA   BP_RIGHT
            CLC
            ADC   #2
            STA   BP_RIGHT

            ; --- blocco 8 bit #2: campiona offscreen, impacchetta,
            ; scrive 2 righe sopra + 2 sotto (tutte identiche) ---
            SEP   #$20
            MX    %10
            LDX   GNBG_TMP
            LDA   >OFFSCREEN_BASE,X
            STA   CL_BYTE
            LDX   GNBG_TMP2
            LDA   >OFFSCREEN_BASE,X
            STA   CR_BYTE

            ; *** TL51: packing via PACKLUT invece di AND/ASL x4/ORA.
            ; CR_BYTE($F4)/CL_BYTE($F5) sono adiacenti: una LDA a 16 bit
            ; da CR_BYTE legge CL_BYTE*256+CR_BYTE in un colpo solo
            ; (little-endian) = indice diretto in PACKLUT, che contiene
            ; gia' ((CL&$0F)<<4)|(CR&$0F) - vedi INIT_PACKLUT.
            REP   #$30
            MX    %00
            LDA   CR_BYTE
            TAX
            SEP   #$20
            MX    %10
            LDA   >PACKLUT_BASE,X
            STA   PACK_BYTE

            LDX   WRITE_X1
            STA   >FAST_SHR_LONG,X
            LDX   WRITE_X1B
            STA   >FAST_SHR_LONG,X
            LDX   WRITE_X2
            STA   >FAST_SHR_LONG,X
            LDX   WRITE_X2B
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00

            LDA   YSTEP
            CLC
            ADC   #1
            STA   YSTEP
            CMP   #50                ; *** TL49: era 25 in TL48
            BEQ   :gr_row_done
            JMP   :gr_row
:gr_row_done

            ; *** TL41 FIX: bug preesistente (gia' in TL40) nella
            ; transizione tra coppie. Dopo il loop righe, BP_LEFT e'
            ; avanzato di 200 (= arrivato dove BP_RIGHT era all'inizio
            ; di QUESTA coppia) e BP_RIGHT e' avanzato di 200 (= la
            ; colonna DOPO). Tenerli cosi' com'erano faceva ripartire
            ; la coppia successiva dalla colonna destra di quella
            ; attuale invece che due colonne piu' avanti: le coppie si
            ; accavallavano di una colonna, 160 coppie coprivano solo
            ; ~161 colonne invece di 320, e il wrap di fine tabella
            ; cadeva nel punto sbagliato -> le cuciture visibili.
            ; La nuova sinistra e' l'attuale destra; la nuova destra e'
            ; nuova sinistra + 100 (*** TL49: era +50 in TL48, stride
            ; colonna tornato a 100 byte con la profondita' a 50 passi).
            LDA   BP_RIGHT
            JSR   GNBG_WRAP
            STA   BP_LEFT
            JSR   GNBG_ADV100
            STA   BP_RIGHT

            LDA   PAIR_IDX
            CLC
            ADC   #1
            STA   PAIR_IDX
            CMP   #160
            BEQ   :gr_pair_done
            JMP   :gr_pair
:gr_pair_done

            RTS

; *** TL49: A = (A+100) mod 32000 (era +50 mod 16000 in TL48, stride
; colonna tornato a 100 byte con la profondita' a 50 passi)
GNBG_ADV100 CLC
            ADC   #100
            CMP   #32000
            BCC   :adv_ok
            SEC
            SBC   #32000
:adv_ok     RTS

; *** TL49: A = A mod 32000 (era mod 16000 in TL48)
GNBG_WRAP   CMP   #32000
            BCC   :wrap_ok
            SEC
            SBC   #32000
:wrap_ok    RTS

; ---------------------------------------------------------------------
; TL54: SHOW_TEXTURE_DIRECT - anteprima diretta della texture 256x256
; (banco $02, un byte per pixel, valori 0..15) sullo schermo, chiamata
; da MAIN_LOOP AL POSTO di GNBG_RENDER quando TEXTURE_PREVIEW_MODE=1
; (SPAZIO, vedi CHECK_KEYBOARD). Serve a vedere direttamente come le
; fasi 1-5 stanno riempiendo la texture, senza la deformazione a
; tunnel - utile in fase di sviluppo/debug.
;
; Mostra solo "quello che ci sta": le prime 200 righe della texture
; (su 256 - lo schermo e' alto 200, il resto e' tagliato) e tutte le
; 256 colonne, impacchettate 2 per byte con la stessa tabella e la
; stessa convenzione di GNBG_RENDER (PACKLUT_BASE via CR_BYTE/CL_BYTE
; adiacenti: nibble alto = pixel sinistro, nibble basso = pixel
; destro). Le 32 colonne di schermo oltre la texture (256..319) sono
; azzerate a nero ad ogni riga, cosi' non resta a video la vecchia
; vista tunnel quando si passa in questa modalita'.
;
; Sporca: GNBG_TMP/2/3/4, CL_BYTE/CR_BYTE, PACK_BYTE, BLIT_SCRATCH/2 -
; tutti scratch gia' usati da GNBG_RENDER/i blit, nessuno vivo quando
; gira questa routine (mai in esecuzione insieme a GNBG_RENDER: la
; scelta fra le due e' un if/else nello stesso punto di MAIN_LOOP).
;
; *** TL54 FIX (fascia centrale mancante nell'anteprima): il gestore
; d'interrupt del player musicale forza A/X a 8 bit prima di tornare
; (vedi il commento storico in cima al file, "NOVITA' RISPETTO A
; TL48.S") - per questo ogni SEP #$20/.../REP #$20 di questo file va
; seguito da un REP #$30 pieno, non da un REP #$20 che ripristina solo
; l'accumulatore: se un interrupt arriva proprio dentro uno dei blocchi
; a 8 bit qui sotto, X resta forzato a 8 bit anche dopo, e la prossima
; TAX di questo ciclo tronca l'indirizzo a 16 bit (texture o VRAM) a un
; solo byte - scritture completamente fuori posto per il resto di
; questo passaggio, cioe' esattamente una "fascia" che sembra sempre
; vuota, sempre nello stesso punto (il player interrompe a ritmo
; regolare). Questa routine e' il ciclo piu' lungo del programma (200
; righe x 128+32 colonne, molti cambi SEP/REP) quindi e' quella che
; nota di piu' il problema, ma la stessa vulnerabilita' esiste in
; teoria ovunque nel file: qui la correggiamo con REP #$30 dopo ogni
; blocco a 8 bit, invece di avvolgere tutto in SEI/CLI (bloccherebbe la
; musica per un ciclo troppo lungo).
; ---------------------------------------------------------------------
SHOW_TEXTURE_DIRECT
            REP   #$30
            MX    %00
            STZ   GNBG_TMP3          ; riga corrente, 0..199

:std_row    LDA   GNBG_TMP3
            XBA                       ; riga*256 (byte alto=riga, basso=0)
            STA   GNBG_TMP           ; offset base nella texture (riga*256)

            LDA   GNBG_TMP3
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                  ; riga*32
            STA   GNBG_TMP2
            LDA   GNBG_TMP3
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A                  ; riga*128
            CLC
            ADC   GNBG_TMP2          ; +riga*32 = riga*160
            STA   GNBG_TMP4          ; offset base in VRAM (riga*160)

            STZ   BLIT_SCRATCH       ; colonna byte destinazione, 0..127

:std_col    LDA   BLIT_SCRATCH
            ASL   A                  ; colonna texture di partenza (x2)
            CLC
            ADC   GNBG_TMP
            TAX
            SEP   #$20
            MX    %10
            LDA   >OFFSCREEN_BASE,X
            STA   CL_BYTE            ; pixel sinistro del byte
            REP   #$30
            MX    %00
            INX
            SEP   #$20
            MX    %10
            LDA   >OFFSCREEN_BASE,X
            STA   CR_BYTE            ; pixel destro del byte
            REP   #$30
            MX    %00

            ; packing via PACKLUT (stesso trucco di GNBG_RENDER: CR_BYTE
            ; e CL_BYTE sono adiacenti, una LDA a 16 bit da CR_BYTE legge
            ; CL_BYTE*256+CR_BYTE in un colpo solo)
            LDA   CR_BYTE
            TAX
            SEP   #$20
            MX    %10
            LDA   >PACKLUT_BASE,X
            STA   PACK_BYTE
            REP   #$30
            MX    %00

            LDA   BLIT_SCRATCH
            CLC
            ADC   GNBG_TMP4
            TAX
            SEP   #$20
            MX    %10
            LDA   PACK_BYTE
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00

            LDA   BLIT_SCRATCH
            CLC
            ADC   #1
            STA   BLIT_SCRATCH
            CMP   #128
            BNE   :std_col

            ; azzera le 32 colonne di schermo oltre la texture (256..319)
            LDA   GNBG_TMP4
            CLC
            ADC   #128
            STA   GNBG_TMP2          ; riuso: offset base del bordo destro
            STZ   BLIT_SCRATCH2      ; contatore 0..31

:std_clr    LDA   BLIT_SCRATCH2
            CLC
            ADC   GNBG_TMP2
            TAX
            SEP   #$20
            MX    %10
            LDA   #$00
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00
            LDA   BLIT_SCRATCH2
            CLC
            ADC   #1
            STA   BLIT_SCRATCH2
            CMP   #32
            BNE   :std_clr

            LDA   GNBG_TMP3
            CLC
            ADC   #1
            STA   GNBG_TMP3
            CMP   #200
            BEQ   :std_done
            JMP   :std_row
:std_done   RTS

; ---------------------------------------------------------------------
; DRAW_FRAME_MARKER: disegna un piccolo blocco 4x4 in basso a destra
; usa FRAME_CNT (0..15) duplicato per byte (0x00,0x11,...,0xFF)
; ---------------------------------------------------------------------
DRAW_FRAME_MARKER
            REP   #$30
            MX    %00
            ; prepare duplicated nibble byte in GNBG_TMP (0xNN)
            LDA   FRAME_CNT
            AND   #$0F
            STA   GNBG_TMP
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ORA   GNBG_TMP
            STA   GNBG_TMP2

            ; draw 4 rows: y = 196..199 (bottom 4 rows)
            LDY   #196
:dfm_row
            ; compute WRITE_X1 = y * 160  (same method as GNBG_RENDER)
            TYA
            STA   GNBG_TMP       ; reuse GNBG_TMP for y
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            STA   WRITE_X1       ; *128
            LDA   GNBG_TMP
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            CLC
            ADC   WRITE_X1
            STA   WRITE_X1       ; +*32 -> *160

            ; write two bytes (pairs) for x pairs 158 and 159
            LDA   WRITE_X1
            CLC
            ADC   #158
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP2
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00

            ; second pair
            LDA   WRITE_X1
            CLC
            ADC   #159
            TAX
            SEP   #$20
            MX    %10
            LDA   GNBG_TMP2
            STA   >FAST_SHR_LONG,X
            REP   #$30
            MX    %00

            ; next row
            INY
            CPY   #200
            BNE   :dfm_row

            RTS

; ---------------------------------------------------------------------
; TL51 v4: SET_BORDER_INDICATOR - sostituisce DRAW_PEI_MODE_INDICATOR.
; Il rettangolo disegnato in VRAM, per quanto disegnato per ultimo,
; veniva comunque ricoperto dal frame successivo: giustamente, la demo
; non ha double buffering e ridisegna tutto ogni giro. Il colore del
; BORDO SCHERMO invece e' un registro hardware ($C034) che nessuna
; routine grafica tocca: una volta impostato resta stabile finche' non
; lo si cambia di nuovo, quindi e' a prova di bug.
;   PEI_BENCH_MODE = 0 (STA_COPY_ONCE attiva) -> bordo NERO   (indice 0)
;   PEI_BENCH_MODE = 1 (PEI_COPY_ONCE attiva) -> bordo BIANCO (indice 15)
; Indice 0 e 15 sono condivisi da tutti e 4 i temi colore (vedi nota
; originale in COLOR_DATA: primo e ultimo colore di ogni gruppo), quindi
; il bordo si vede sempre uguale qualunque tema stia girando. Chiamata
; una sola volta all'avvio e poi solo quando SPAZIO cambia modalita'
; (vedi CHECK_KEYBOARD) - non ogni frame, non serve.
; ---------------------------------------------------------------------
SET_BORDER_INDICATOR
            SEP   #$20
            MX    %10
            LDA   PEI_BENCH_MODE
            BEQ   :sbi_sta

            LDA   BORDER
            AND   #$F0
            ORA   #$0F              ; bianco = PEI_COPY_ONCE attiva
            STA   BORDER
            BRA   :sbi_done

:sbi_sta    LDA   BORDER
            AND   #$F0
            ORA   #$00              ; nero = STA_COPY_ONCE attiva
            STA   BORDER

:sbi_done   REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; ROUTINES DI SUPPORTO (invariate da TL4)
; ---------------------------------------------------------------------
EXIT_DEMO   REP   #$30
            MX    %00
            CLI                     ; *** TL49 v2: riapri gli interrupt,
            LDA   #$0000            ; potremmo arrivare qui con SEI attivo
            TCD                     ; da CHECK_KEYBOARD/MAIN_LOOP

            DO    MUSIC_ENABLED
            JSL   NTPstop          ; *** TL49: ferma il player prima di uscire
            FIN

            SEP   #$20
            MX    %10
            LDA   #$00
            PHA
            PLB

            LDA   SAVED_SHADOW
            STA   SHADOW

            LDA   NEWVIDEO
            AND   #$7F
            STA   NEWVIDEO

            STA   $C050
            STA   $C053
            STA   $C054
            STA   $C010

            SEC
            XCE

            JSR   $FC58

            JSR   $BF00
            DFB   $65
            DA    QUIT_PARMS

QUIT_PARMS  DFB   $04
            DFB   $00
            DA    $0000
            DFB   $00
            DA    $0000

CLOSE_PARMS DFB 1

CLEAR_VRAM  PHB
            SEP   #$20
            MX    %10
            LDA   #$01
            PHA
            PLB
            REP   #$30
            MX    %00

            LDX   #0
            LDA   #$0000
:c_loop     STA   FAST_SHR,X
            INX
            INX
            CPX   #32000
            BNE   :c_loop

            PLB
            RTS

INIT_SCB    REP   #$30
            MX    %00
            LDX   #0
            LDA   #$0000
:loop       STA   >SCB_BASE,X
            INX
            INX
            CPX   #200
            BNE   :loop
            RTS

; *** TL42: ora 4 gruppi di palette da 16 colori ciascuno (128 byte
; totali). Ogni gruppo IIgs occupa 32 byte consecutivi in PALETTE.
INIT_PALETTE
            SEP   #$20
            MX    %10
            LDX   #0
:pal_loop   LDA   COLOR_DATA,X
            STA   >PALETTE,X
            INX
            CPX   #128
            BNE   :pal_loop
            REP   #$30
            MX    %00
            RTS

; Layout per ciascun gruppo (16 colori): 0=maschera/nero, 1-5=sprite
; (tema), 6-15=sfondo tunnel (IDENTICI nei 4 gruppi, cosi' il tunnel
; e' uguale qualunque tema sia attivo sulla riga).
;
; Gruppo 0: sprite ROSSO
COLOR_DATA  DA    $0000, $0300, $0600, $0A00, $0E20, $0FF8, $004F, $00AF
            DA    $00FF, $05FF, $0AFF, $080F, $0A0F, $0C0F, $0E0F, $0FFF
; Gruppo 1: sprite ROSSO/GIALLO CALDO (era blu/grigio, ora libero -
; il pesce e' passato al giallo del gruppo 2 - ridisegnato su
; richiesta per l'orbita, gradiente rosso scuro -> arancio -> giallo)
            DA    $0000, $0400, $0800, $0C40, $0F80, $0FF0, $004F, $00AF
            DA    $00FF, $05FF, $0AFF, $080F, $0A0F, $0C0F, $0E0F, $0FFF
; Gruppo 2: sprite GIALLO
            DA    $0000, $0430, $0860, $0CA0, $0FE0, $0FFC, $004F, $00AF
            DA    $00FF, $05FF, $0AFF, $080F, $0A0F, $0C0F, $0E0F, $0FFF
; Gruppo 3: sprite VERDE (schiarito su richiesta: gamma piu' luminosa,
; meno cupa in basso)
            DA    $0000, $0250, $0470, $0690, $09C0, $0DF8, $004F, $00AF
            DA    $00FF, $05FF, $0AFF, $080F, $0A0F, $0C0F, $0E0F, $0FFF

; ---------------------------------------------------------------------
; TABELLE STATICHE precalcolate in Python (nessuna trig a runtime):
;   SIN320/COS320: seno/coseno di 320 angoli equispaziati, scala fissa
;                  *256 (valori interi -256..256)
;   RTAB: proiezione prospettica di Tran, 256*99/(16*99-15*f), f=0..99
;         (valori interi 16..256)
; ---------------------------------------------------------------------
; *** TL49: ROWOFF_TABLE[j]=(2j)*160, MROWOFF_TABLE[j]=(199-2j)*160,
; per j=0..49 (era 4j/25 campioni in TL48): ogni voce e' la riga di
; PARTENZA del blocco di 2 righe che il campione j copre (sopra e nel
; suo specchio sotto). Sostituiscono il calcolo a shift che GNBG_RENDER
; rifaceva ad ogni riga.
ROWOFF_TABLE
            DA    0, 320, 640, 960, 1280, 1600, 1920, 2240, 2560, 2880
            DA    3200, 3520, 3840, 4160, 4480, 4800, 5120, 5440, 5760, 6080
            DA    6400, 6720, 7040, 7360, 7680, 8000, 8320, 8640, 8960, 9280
            DA    9600, 9920, 10240, 10560, 10880, 11200, 11520, 11840, 12160, 12480
            DA    12800, 13120, 13440, 13760, 14080, 14400, 14720, 15040, 15360, 15680

MROWOFF_TABLE
            DA    31840, 31520, 31200, 30880, 30560, 30240, 29920, 29600, 29280, 28960
            DA    28640, 28320, 28000, 27680, 27360, 27040, 26720, 26400, 26080, 25760
            DA    25440, 25120, 24800, 24480, 24160, 23840, 23520, 23200, 22880, 22560
            DA    22240, 21920, 21600, 21280, 20960, 20640, 20320, 20000, 19680, 19360
            DA    19040, 18720, 18400, 18080, 17760, 17440, 17120, 16800, 16480, 16160

SIN320
            DA    0, 5, 10, 15, 20, 25, 30, 35, 40, 45
            DA    50, 55, 60, 65, 69, 74, 79, 84, 89, 93
            DA    98, 103, 107, 112, 116, 121, 125, 129, 134, 138
            DA    142, 146, 150, 155, 158, 162, 166, 170, 174, 177
            DA    181, 185, 188, 191, 195, 198, 201, 204, 207, 210
            DA    213, 216, 218, 221, 223, 226, 228, 230, 232, 235
            DA    237, 238, 240, 242, 243, 245, 246, 248, 249, 250
            DA    251, 252, 253, 254, 254, 255, 255, 256, 256, 256
            DA    256, 256, 256, 256, 255, 255, 254, 254, 253, 252
            DA    251, 250, 249, 248, 246, 245, 243, 242, 240, 238
            DA    237, 235, 232, 230, 228, 226, 223, 221, 218, 216
            DA    213, 210, 207, 204, 201, 198, 195, 191, 188, 185
            DA    181, 177, 174, 170, 166, 162, 158, 155, 150, 146
            DA    142, 138, 134, 129, 125, 121, 116, 112, 107, 103
            DA    98, 93, 89, 84, 79, 74, 69, 65, 60, 55
            DA    50, 45, 40, 35, 30, 25, 20, 15, 10, 5
            DA    0, -5, -10, -15, -20, -25, -30, -35, -40, -45
            DA    -50, -55, -60, -65, -69, -74, -79, -84, -89, -93
            DA    -98, -103, -107, -112, -116, -121, -125, -129, -134, -138
            DA    -142, -146, -150, -155, -158, -162, -166, -170, -174, -177
            DA    -181, -185, -188, -191, -195, -198, -201, -204, -207, -210
            DA    -213, -216, -218, -221, -223, -226, -228, -230, -232, -235
            DA    -237, -238, -240, -242, -243, -245, -246, -248, -249, -250
            DA    -251, -252, -253, -254, -254, -255, -255, -256, -256, -256
            DA    -256, -256, -256, -256, -255, -255, -254, -254, -253, -252
            DA    -251, -250, -249, -248, -246, -245, -243, -242, -240, -238
            DA    -237, -235, -232, -230, -228, -226, -223, -221, -218, -216
            DA    -213, -210, -207, -204, -201, -198, -195, -191, -188, -185
            DA    -181, -177, -174, -170, -166, -162, -158, -155, -150, -146
            DA    -142, -138, -134, -129, -125, -121, -116, -112, -107, -103
            DA    -98, -93, -89, -84, -79, -74, -69, -65, -60, -55
            DA    -50, -45, -40, -35, -30, -25, -20, -15, -10, -5

COS320
            DA    256, 256, 256, 256, 255, 255, 254, 254, 253, 252
            DA    251, 250, 249, 248, 246, 245, 243, 242, 240, 238
            DA    237, 235, 232, 230, 228, 226, 223, 221, 218, 216
            DA    213, 210, 207, 204, 201, 198, 195, 191, 188, 185
            DA    181, 177, 174, 170, 166, 162, 158, 155, 150, 146
            DA    142, 138, 134, 129, 125, 121, 116, 112, 107, 103
            DA    98, 93, 89, 84, 79, 74, 69, 65, 60, 55
            DA    50, 45, 40, 35, 30, 25, 20, 15, 10, 5
            DA    0, -5, -10, -15, -20, -25, -30, -35, -40, -45
            DA    -50, -55, -60, -65, -69, -74, -79, -84, -89, -93
            DA    -98, -103, -107, -112, -116, -121, -125, -129, -134, -138
            DA    -142, -146, -150, -155, -158, -162, -166, -170, -174, -177
            DA    -181, -185, -188, -191, -195, -198, -201, -204, -207, -210
            DA    -213, -216, -218, -221, -223, -226, -228, -230, -232, -235
            DA    -237, -238, -240, -242, -243, -245, -246, -248, -249, -250
            DA    -251, -252, -253, -254, -254, -255, -255, -256, -256, -256
            DA    -256, -256, -256, -256, -255, -255, -254, -254, -253, -252
            DA    -251, -250, -249, -248, -246, -245, -243, -242, -240, -238
            DA    -237, -235, -232, -230, -228, -226, -223, -221, -218, -216
            DA    -213, -210, -207, -204, -201, -198, -195, -191, -188, -185
            DA    -181, -177, -174, -170, -166, -162, -158, -155, -150, -146
            DA    -142, -138, -134, -129, -125, -121, -116, -112, -107, -103
            DA    -98, -93, -89, -84, -79, -74, -69, -65, -60, -55
            DA    -50, -45, -40, -35, -30, -25, -20, -15, -10, -5
            DA    0, 5, 10, 15, 20, 25, 30, 35, 40, 45
            DA    50, 55, 60, 65, 69, 74, 79, 84, 89, 93
            DA    98, 103, 107, 112, 116, 121, 125, 129, 134, 138
            DA    142, 146, 150, 155, 158, 162, 166, 170, 174, 177
            DA    181, 185, 188, 191, 195, 198, 201, 204, 207, 210
            DA    213, 216, 218, 221, 223, 226, 228, 230, 232, 235
            DA    237, 238, 240, 242, 243, 245, 246, 248, 249, 250
            DA    251, 252, 253, 254, 254, 255, 255, 256, 256, 256

; *** TL49: RTAB portata a 50 campioni (era 25 in TL48, per provare
; una resa un po' piu' morbida mantenendo comunque meta' del costo
; originale a 100), stessa curva 256*99/(16*99-15*f)
RTAB
            DA    16, 16, 17, 17, 17, 18, 18, 18, 19, 19
            DA    20, 20, 21, 21, 22, 22, 23, 24, 24, 25
            DA    26, 27, 28, 29, 30, 31, 32, 33, 34, 36
            DA    38, 39, 41, 43, 46, 48, 51, 55, 59, 63
            DA    68, 74, 81, 90, 101, 115, 133, 159, 196, 256

; ---------------------------------------------------------------------
; SPRITE DI TEST: cspr00 convertito da sprites.c (formato originale:
; lunghezza,x,y,colori...; 0 = fine sprite). I colori restano quelli
; originali 0xC1-0xCF: REMAP_TABLE li comprime nei nostri 1-5 al volo,
; in BLIT_SPRITE, leggendo solo il nibble basso (vedi commento sopra
; REMAP_TABLE). Gli altri 34 sprite si aggiungeranno con lo stesso
; procedimento quando affrontiamo lo scheduler.
; ---------------------------------------------------------------------
CSPR00_DATA
            DFB   $02, $0F, $00, $C1, $C1, $04, $0E, $01, $C1, $C2, $C1, $C2, $06, $0D, $02, $C1
            DFB   $C2, $C3, $C2, $C3, $C2, $02, $05, $03, $C1, $C1, $06, $0D, $03, $C2, $C3, $C4
            DFB   $C3, $C4, $C2, $02, $19, $03, $C1, $C1, $06, $04, $04, $C1, $C1, $C3, $C3, $C2
            DFB   $C2, $08, $0C, $04, $C2, $C3, $C4, $C4, $C4, $C4, $C3, $C2, $06, $17, $04, $C1
            DFB   $C2, $C1, $C1, $C2, $C1, $08, $03, $05, $C1, $C2, $C3, $C3, $C4, $C4, $C3, $C3
            DFB   $08, $0C, $05, $C2, $C3, $C4, $C5, $C5, $C5, $C3, $C3, $08, $15, $05, $C1, $C2
            DFB   $C4, $C3, $C3, $C3, $C2, $C1, $1A, $03, $06, $C1, $C2, $C3, $C4, $C4, $C5, $C4
            DFB   $C4, $C4, $C2, $C3, $C4, $C5, $C5, $C5, $C4, $C3, $C1, $C2, $C3, $C4, $C5, $C4
            DFB   $C3, $C3, $C1, $19, $04, $07, $C3, $C3, $C4, $C5, $C5, $C6, $C5, $C4, $C2, $C4
            DFB   $C5, $C6, $C6, $C6, $C5, $C1, $C2, $C3, $C4, $C5, $C5, $C4, $C3, $C2, $C2, $18
            DFB   $04, $08, $C2, $C3, $C4, $C5, $C6, $C6, $C5, $C5, $C2, $C3, $C5, $C6, $C6, $C6
            DFB   $C1, $C2, $C4, $C4, $C6, $C5, $C5, $C5, $C4, $C3, $18, $04, $09, $C2, $C3, $C4
            DFB   $C5, $C6, $C6, $C6, $C5, $C2, $C4, $C5, $C6, $C6, $C5, $C2, $C4, $C5, $C6, $C6
            DFB   $C6, $C6, $C5, $C3, $C2, $16, $05, $0A, $C2, $C3, $C4, $C5, $C6, $C6, $C6, $C2
            DFB   $C3, $C4, $C6, $C6, $C1, $C3, $C4, $C5, $C6, $C6, $C6, $C5, $C5, $C3, $15, $06
            DFB   $0B, $C2, $C3, $C5, $C5, $C5, $C5, $C2, $C3, $C4, $C4, $C5, $C2, $C3, $C4, $C4
            DFB   $C5, $C5, $C5, $C4, $C3, $C3, $17, $06, $0C, $C2, $C1, $C2, $C4, $C5, $C4, $C1
            DFB   $C3, $C8, $C9, $C9, $C8, $C8, $C1, $C2, $C2, $C2, $C1, $C2, $C2, $C2, $C1, $C1
            DFB   $1C, $03, $0D, $C2, $C3, $C3, $C4, $C4, $C2, $C2, $C4, $C3, $C3, $C9, $CA, $CB
            DFB   $CB, $CA, $CA, $C8, $C3, $C4, $C4, $C4, $C3, $C4, $C3, $C4, $C2, $C2, $C1, $1F
            DFB   $01, $0E, $C1, $C2, $C2, $C4, $C4, $C5, $C5, $C5, $C2, $C2, $C2, $C8, $CA, $CB
            DFB   $CD, $CD, $CC, $CB, $C9, $C4, $C5, $C5, $C5, $C5, $C5, $C4, $C4, $C3, $C3, $C2
            DFB   $C1, $1F, $01, $0F, $C1, $C3, $C3, $C4, $C5, $C5, $C5, $C6, $C6, $C6, $C1, $C9
            DFB   $CB, $CC, $CE, $CF, $CD, $CC, $CA, $C8, $C6, $C6, $C6, $C6, $C5, $C5, $C5, $C4
            DFB   $C3, $C2, $C1, $20, $00, $10, $C1, $C2, $C3, $C3, $C4, $C5, $C6, $C6, $C6, $C6
            DFB   $C6, $C5, $C9, $CB, $CD, $CE, $CF, $CE, $CC, $CA, $C8, $C5, $C6, $C6, $C6, $C6
            DFB   $C5, $C4, $C4, $C3, $C2, $C2, $1F, $01, $11, $C2, $C3, $C3, $C4, $C5, $C5, $C6
            DFB   $C6, $C6, $C5, $C4, $C9, $CA, $CC, $CD, $CE, $CD, $CB, $CA, $C8, $C2, $C1, $C6
            DFB   $C5, $C6, $C4, $C4, $C4, $C3, $C2, $C1, $1E, $01, $12, $C1, $C1, $C2, $C3, $C4
            DFB   $C4, $C4, $C4, $C4, $C4, $C4, $C8, $C9, $CB, $CC, $CC, $CC, $CA, $C8, $C3, $C4
            DFB   $C3, $C2, $C4, $C5, $C4, $C3, $C3, $C2, $C2, $1A, $03, $13, $C2, $C2, $C3, $C3
            DFB   $C3, $C2, $C2, $C3, $C2, $C2, $C8, $C9, $CA, $CA, $CA, $C9, $C2, $C4, $C4, $C5
            DFB   $C3, $C2, $C4, $C3, $C2, $C1, $14, $06, $14, $C1, $C1, $C1, $C1, $C1, $C5, $C5
            DFB   $C4, $C2, $C8, $C8, $C8, $C4, $C3, $C5, $C5, $C4, $C4, $C2, $C2, $16, $05, $15
            DFB   $C2, $C4, $C4, $C5, $C6, $C6, $C6, $C4, $C4, $C2, $C5, $C5, $C5, $C5, $C2, $C1
            DFB   $C6, $C6, $C5, $C5, $C3, $C2, $17, $05, $16, $C3, $C4, $C4, $C6, $C6, $C6, $C6
            DFB   $C5, $C3, $C2, $C5, $C6, $C6, $C5, $C3, $C1, $C6, $C6, $C6, $C5, $C4, $C2, $C2
            DFB   $19, $04, $17, $C1, $C3, $C4, $C5, $C6, $C6, $C6, $C4, $C4, $C2, $C5, $C5, $C6
            DFB   $C6, $C5, $C2, $C1, $C6, $C6, $C6, $C6, $C4, $C4, $C2, $C1, $19, $04, $18, $C2
            DFB   $C3, $C4, $C5, $C5, $C6, $C5, $C3, $C2, $C1, $C5, $C6, $C6, $C6, $C5, $C3, $C1
            DFB   $C5, $C6, $C6, $C6, $C5, $C4, $C3, $C1, $1A, $03, $19, $C2, $C2, $C3, $C4, $C5
            DFB   $C5, $C4, $C4, $C2, $C1, $C4, $C4, $C6, $C6, $C6, $C4, $C3, $C1, $C4, $C4, $C4
            DFB   $C5, $C4, $C4, $C3, $C1, $1A, $03, $1A, $C1, $C2, $C2, $C4, $C4, $C4, $C3, $C2
            DFB   $C1, $C3, $C3, $C4, $C5, $C6, $C5, $C4, $C2, $C1, $C4, $C3, $C4, $C4, $C4, $C3
            DFB   $C3, $C1, $06, $04, $1B, $C1, $C2, $C3, $C2, $C2, $C1, $07, $0D, $1B, $C3, $C4
            DFB   $C4, $C4, $C5, $C4, $C3, $07, $16, $1B, $C3, $C3, $C3, $C3, $C2, $C2, $C1, $04
            DFB   $04, $1C, $C1, $C2, $C2, $C1, $07, $0D, $1C, $C2, $C3, $C3, $C4, $C4, $C3, $C2
            DFB   $05, $17, $1C, $C1, $C2, $C2, $C2, $C2, $07, $0D, $1D, $C2, $C3, $C3, $C3, $C3
            DFB   $C3, $C1, $05, $0E, $1E, $C1, $C2, $C2, $C1, $C2, $03, $0F, $1F, $C1, $C1, $C1
            DFB   $00


CSPR01_DATA
            DFB   $01, $0B, $01, $C1, $05, $0A, $02, $C1, $C2, $C1, $C2, $C2, $04, $15, $02, $C1
            DFB   $C1, $C2, $C1, $06, $09, $03, $C1, $C2, $C3, $C2, $C3, $C2, $07, $13, $03, $C1
            DFB   $C2, $C2, $C3, $C3, $C1, $C1, $07, $09, $04, $C2, $C3, $C4, $C3, $C3, $C3, $C3
            DFB   $07, $13, $04, $C3, $C3, $C4, $C4, $C3, $C3, $C2, $07, $09, $05, $C2, $C3, $C4
            DFB   $C4, $C4, $C4, $C3, $09, $11, $05, $C1, $C2, $C4, $C4, $C5, $C4, $C3, $C2, $C2
            DFB   $01, $03, $06, $C2, $01, $05, $06, $C1, $10, $09, $06, $C3, $C4, $C5, $C5, $C5
            DFB   $C4, $C4, $C3, $C2, $C3, $C4, $C5, $C5, $C5, $C4, $C3, $07, $01, $07, $C2, $C2
            DFB   $C2, $C3, $C3, $C2, $C3, $11, $09, $07, $C2, $C3, $C4, $C5, $C5, $C6, $C5, $C1
            DFB   $C2, $C5, $C5, $C5, $C5, $C5, $C4, $C3, $C2, $18, $01, $08, $C2, $C2, $C3, $C4
            DFB   $C4, $C3, $C3, $C4, $C2, $C4, $C5, $C6, $C6, $C6, $C5, $C2, $C2, $C4, $C6, $C6
            DFB   $C6, $C4, $C4, $C3, $19, $00, $09, $C1, $C2, $C3, $C3, $C4, $C4, $C4, $C4, $C4
            DFB   $C1, $C3, $C5, $C6, $C6, $C5, $C5, $C2, $C4, $C6, $C6, $C6, $C5, $C5, $C4, $C3
            DFB   $1C, $01, $0A, $C2, $C3, $C4, $C5, $C5, $C6, $C6, $C5, $C1, $C2, $C5, $C6, $C6
            DFB   $C6, $C1, $C3, $C4, $C5, $C6, $C5, $C5, $C1, $C1, $C2, $C1, $C2, $C1, $C1, $1D
            DFB   $01, $0B, $C1, $C3, $C4, $C5, $C5, $C5, $C6, $C6, $C5, $C2, $C4, $C4, $C6, $C5
            DFB   $C2, $C3, $C4, $C5, $C1, $C2, $C1, $C2, $C3, $C3, $C3, $C3, $C2, $C2, $C1, $1D
            DFB   $02, $0C, $C1, $C4, $C4, $C5, $C6, $C6, $C6, $C6, $C2, $C4, $C4, $C4, $C8, $C8
            DFB   $C8, $C3, $C2, $C2, $C3, $C4, $C4, $C4, $C4, $C4, $C4, $C3, $C3, $C2, $C1, $1C
            DFB   $03, $0D, $C2, $C3, $C4, $C5, $C5, $C6, $C6, $C5, $C3, $C8, $C9, $CA, $CA, $CA
            DFB   $C8, $C8, $C4, $C4, $C5, $C6, $C6, $C5, $C5, $C4, $C4, $C3, $C2, $C1, $1B, $04
            DFB   $0E, $C1, $C2, $C2, $C4, $C5, $C4, $C4, $C2, $CA, $CB, $CC, $CC, $CC, $CB, $CA
            DFB   $C8, $C6, $C6, $C6, $C6, $C6, $C5, $C4, $C3, $C3, $C2, $C1, $1A, $04, $0F, $C3
            DFB   $C2, $C1, $C2, $C2, $C4, $C3, $C8, $CA, $CB, $CE, $CE, $CD, $CC, $CA, $C8, $C5
            DFB   $C6, $C6, $C6, $C5, $C5, $C5, $C4, $C2, $C2, $1A, $03, $10, $C2, $C3, $C4, $C5
            DFB   $C1, $C2, $C2, $C2, $C9, $CA, $CC, $CD, $CF, $CF, $CD, $CB, $C9, $C1, $C1, $C5
            DFB   $C5, $C5, $C4, $C3, $C3, $C2, $19, $02, $11, $C2, $C3, $C3, $C5, $C4, $C5, $C6
            DFB   $C5, $C5, $C8, $CA, $CC, $CE, $CE, $CE, $CC, $CB, $C8, $C2, $C3, $C2, $C2, $C1
            DFB   $C4, $C3, $19, $01, $12, $C1, $C3, $C4, $C4, $C5, $C6, $C6, $C6, $C6, $C5, $C8
            DFB   $CA, $CC, $CC, $CD, $CD, $CC, $CA, $C8, $C4, $C4, $C5, $C4, $C2, $C2, $1C, $00
            DFB   $13, $C1, $C2, $C3, $C4, $C4, $C6, $C6, $C6, $C6, $C6, $C5, $C4, $C8, $C9, $CB
            DFB   $CB, $CB, $CA, $C9, $C2, $C5, $C5, $C4, $C5, $C5, $C3, $C2, $C2, $1D, $00, $14
            DFB   $C1, $C2, $C3, $C4, $C4, $C5, $C5, $C5, $C5, $C4, $C4, $C3, $C3, $C8, $C9, $C9
            DFB   $C9, $C8, $C4, $C3, $C2, $C5, $C6, $C6, $C5, $C4, $C3, $C3, $C2, $1E, $00, $15
            DFB   $C1, $C2, $C3, $C3, $C4, $C4, $C4, $C4, $C3, $C2, $C3, $C2, $C2, $C4, $C3, $C2
            DFB   $C5, $C6, $C5, $C3, $C2, $C5, $C6, $C6, $C6, $C6, $C4, $C4, $C2, $C1, $1C, $02
            DFB   $16, $C2, $C2, $C2, $C3, $C2, $C2, $C2, $C1, $C1, $C5, $C4, $C4, $C4, $C2, $C6
            DFB   $C6, $C6, $C4, $C2, $C1, $C6, $C6, $C6, $C6, $C5, $C4, $C2, $C1, $01, $04, $17
            DFB   $C1, $18, $07, $17, $C4, $C4, $C5, $C6, $C6, $C5, $C5, $C3, $C2, $C6, $C6, $C6
            DFB   $C4, $C2, $C1, $C5, $C6, $C6, $C5, $C4, $C4, $C3, $C2, $C1, $18, $06, $18, $C2
            DFB   $C4, $C5, $C6, $C6, $C6, $C5, $C4, $C2, $C2, $C6, $C6, $C6, $C5, $C4, $C2, $C3
            DFB   $C5, $C4, $C5, $C3, $C3, $C3, $C2, $18, $06, $19, $C3, $C3, $C5, $C6, $C6, $C6
            DFB   $C4, $C4, $C2, $C4, $C6, $C6, $C5, $C5, $C3, $C2, $C3, $C3, $C3, $C3, $C3, $C3
            DFB   $C2, $C1, $10, $06, $1A, $C3, $C4, $C5, $C5, $C6, $C5, $C3, $C2, $C4, $C4, $C5
            DFB   $C5, $C6, $C5, $C4, $C3, $04, $19, $1A, $C1, $C2, $C2, $C1, $10, $06, $1B, $C3
            DFB   $C3, $C4, $C5, $C5, $C4, $C3, $C2, $C3, $C3, $C4, $C5, $C4, $C5, $C3, $C2, $07
            DFB   $06, $1C, $C2, $C3, $C4, $C4, $C4, $C3, $C2, $07, $0F, $1C, $C3, $C3, $C4, $C4
            DFB   $C4, $C3, $C2, $07, $05, $1D, $C1, $C2, $C2, $C3, $C3, $C3, $C2, $07, $0F, $1D
            DFB   $C1, $C2, $C4, $C3, $C3, $C2, $C1, $06, $06, $1E, $C2, $C2, $C1, $C1, $C1, $C1
            DFB   $05, $11, $1E, $C2, $C2, $C2, $C2, $C1, $03, $07, $1F, $C1, $C1, $C1, $03, $11
            DFB   $1F, $C1, $C1, $C1, $00

CSPR02_DATA
            DFB   $04, $11, $00, $C1, $C2, $C1, $C1, $06, $10, $01, $C1, $C2, $C3, $C2, $C1, $C2
            DFB   $07, $0F, $02, $C1, $C3, $C3, $C4, $C3, $C3, $C2, $03, $07, $03, $C1, $C1, $C1
            DFB   $07, $0F, $03, $C1, $C3, $C5, $C4, $C3, $C3, $C2, $06, $06, $04, $C1, $C2, $C2
            DFB   $C3, $C3, $C2, $08, $0E, $04, $C1, $C2, $C4, $C5, $C5, $C5, $C4, $C2, $07, $06
            DFB   $05, $C1, $C3, $C3, $C3, $C4, $C3, $C2, $08, $0E, $05, $C2, $C4, $C4, $C6, $C5
            DFB   $C5, $C4, $C3, $10, $06, $06, $C1, $C3, $C4, $C4, $C4, $C4, $C4, $C3, $C2, $C3
            DFB   $C5, $C6, $C6, $C6, $C5, $C4, $04, $18, $06, $C2, $C2, $C2, $C1, $17, $06, $07
            DFB   $C2, $C3, $C4, $C5, $C5, $C5, $C4, $C4, $C2, $C4, $C5, $C6, $C6, $C5, $C4, $C1
            DFB   $C2, $C3, $C3, $C2, $C3, $C2, $C1, $17, $06, $08, $C2, $C4, $C4, $C5, $C6, $C6
            DFB   $C6, $C4, $C3, $C4, $C6, $C6, $C6, $C5, $C1, $C3, $C3, $C4, $C4, $C4, $C3, $C3
            DFB   $C1, $16, $07, $09, $C3, $C3, $C5, $C6, $C6, $C6, $C5, $C2, $C5, $C5, $C5, $C1
            DFB   $C2, $C2, $C3, $C4, $C4, $C5, $C4, $C4, $C3, $C2, $1A, $03, $0A, $C1, $C3, $C3
            DFB   $C3, $C2, $C3, $C4, $C6, $C6, $C6, $C1, $C2, $C4, $C4, $C5, $C2, $C4, $C4, $C5
            DFB   $C6, $C5, $C6, $C4, $C4, $C2, $C2, $1C, $01, $0B, $C1, $C3, $C3, $C3, $C3, $C4
            DFB   $C4, $C2, $C3, $C5, $C6, $C6, $C6, $C2, $C3, $C1, $C2, $C3, $C4, $C5, $C6, $C6
            DFB   $C6, $C5, $C5, $C4, $C3, $C2, $1C, $00, $0C, $C1, $C2, $C3, $C4, $C5, $C5, $C5
            DFB   $C5, $C1, $C2, $C4, $C4, $C6, $C5, $C8, $C8, $CA, $C9, $C4, $C4, $C6, $C6, $C6
            DFB   $C6, $C4, $C4, $C3, $C2, $1B, $00, $0D, $C2, $C3, $C3, $C4, $C5, $C6, $C6, $C6
            DFB   $C5, $C2, $C3, $C4, $C8, $C9, $CB, $CA, $CB, $CA, $C9, $C8, $C5, $C5, $C5, $C5
            DFB   $C5, $C4, $C3, $1C, $00, $0E, $C1, $C3, $C4, $C4, $C5, $C6, $C6, $C6, $C6, $C5
            DFB   $C2, $C3, $C8, $C9, $CC, $CD, $CC, $CC, $CB, $C9, $C1, $C2, $C3, $C2, $C2, $C1
            DFB   $C1, $C1, $1F, $00, $0F, $C1, $C3, $C3, $C4, $C4, $C6, $C6, $C6, $C6, $C5, $C5
            DFB   $C2, $C9, $CB, $CD, $CE, $CF, $CD, $CC, $CA, $C2, $C3, $C4, $C4, $C4, $C3, $C3
            DFB   $C3, $C2, $C2, $C1, $1E, $01, $10, $C1, $C2, $C4, $C3, $C4, $C5, $C4, $C5, $C5
            DFB   $C4, $C3, $C9, $CC, $CC, $CE, $CF, $CD, $CC, $C9, $C3, $C4, $C4, $C4, $C5, $C4
            DFB   $C4, $C4, $C4, $C2, $C2, $1D, $03, $11, $C2, $C2, $C2, $C2, $C2, $C3, $C3, $C4
            DFB   $C2, $C9, $CB, $CC, $CE, $CE, $CD, $CC, $C9, $C8, $C2, $C5, $C6, $C6, $C6, $C6
            DFB   $C5, $C5, $C4, $C3, $C2, $1A, $06, $12, $C1, $C2, $C2, $C2, $C1, $C5, $C8, $CA
            DFB   $CB, $CC, $CC, $CB, $CB, $C8, $C4, $C2, $C1, $C5, $C6, $C6, $C6, $C6, $C5, $C4
            DFB   $C3, $C2, $1B, $05, $13, $C3, $C4, $C5, $C5, $C6, $C6, $C6, $C4, $C8, $C9, $CA
            DFB   $CA, $CA, $C8, $C4, $C5, $C3, $C3, $C1, $C6, $C5, $C6, $C5, $C4, $C4, $C2, $C2
            DFB   $1C, $04, $14, $C1, $C3, $C4, $C5, $C5, $C6, $C6, $C6, $C5, $C4, $C3, $C8, $C8
            DFB   $C8, $C5, $C5, $C5, $C4, $C4, $C2, $C4, $C4, $C4, $C4, $C4, $C2, $C3, $C2, $1B
            DFB   $04, $15, $C2, $C4, $C4, $C5, $C6, $C6, $C6, $C5, $C5, $C4, $C3, $C1, $C3, $C2
            DFB   $C6, $C6, $C6, $C5, $C4, $C3, $C1, $C4, $C3, $C3, $C3, $C2, $C2, $17, $03, $16
            DFB   $C1, $C3, $C3, $C4, $C5, $C5, $C6, $C5, $C4, $C2, $C2, $C5, $C4, $C4, $C3, $C2
            DFB   $C5, $C6, $C6, $C5, $C4, $C3, $C1, $17, $03, $17, $C2, $C3, $C3, $C4, $C5, $C4
            DFB   $C4, $C4, $C2, $C1, $C5, $C6, $C5, $C5, $C2, $C2, $C6, $C6, $C6, $C5, $C4, $C3
            DFB   $C1, $17, $03, $18, $C2, $C2, $C3, $C3, $C4, $C4, $C2, $C2, $C1, $C5, $C6, $C6
            DFB   $C6, $C4, $C2, $C1, $C5, $C6, $C5, $C5, $C5, $C3, $C2, $17, $03, $19, $C1, $C2
            DFB   $C2, $C3, $C2, $C2, $C2, $C1, $C4, $C5, $C6, $C6, $C6, $C5, $C2, $C4, $C4, $C4
            DFB   $C5, $C4, $C4, $C3, $C2, $01, $05, $1A, $C1, $11, $0A, $1A, $C2, $C4, $C4, $C6
            DFB   $C5, $C5, $C4, $C2, $C2, $C3, $C3, $C4, $C4, $C3, $C3, $C1, $C1, $08, $0A, $1B
            DFB   $C3, $C3, $C4, $C5, $C5, $C5, $C3, $C2, $06, $14, $1B, $C3, $C3, $C4, $C2, $C2
            DFB   $C2, $08, $0A, $1C, $C2, $C4, $C4, $C4, $C5, $C4, $C3, $C2, $05, $15, $1C, $C2
            DFB   $C2, $C2, $C2, $C1, $06, $0B, $1D, $C3, $C4, $C4, $C4, $C3, $C2, $01, $17, $1D
            DFB   $C1, $05, $0B, $1E, $C2, $C3, $C3, $C3, $C2, $03, $0C, $1F, $C1, $C2, $C1, $00

; ---------------------------------------------------------------------
; SPRITE VERI: pesce (cspr03/cspr04) e lumaca (cspr05-cspr08),
; confermati dalla mappa fornita dall'utente.
; ---------------------------------------------------------------------
CSPR03_DATA
            DFB   $03, $09, $01, $C9, $C8, $C9, $03, $08, $02, $C9, $C8, $C9, $01, $12, $02, $C9
            DFB   $07, $05, $03, $CA, $C9, $CA, $C9, $CA, $C8, $C9, $02, $11, $03, $CA, $C9, $0B
            DFB   $03, $04, $C8, $CA, $C9, $CB, $CB, $CC, $CB, $CC, $CA, $CA, $C8, $02, $11, $04
            DFB   $CA, $CC, $0D, $02, $05, $C9, $CA, $C9, $CC, $CB, $CE, $CD, $CE, $CD, $CE, $CB
            DFB   $CB, $C8, $03, $10, $05, $CA, $CC, $CB, $12, $01, $06, $C9, $CA, $C7, $C7, $CB
            DFB   $CE, $CD, $CF, $CE, $CF, $CD, $CE, $CB, $CB, $C9, $CA, $CB, $C9, $13, $00, $07
            DFB   $C8, $CA, $CA, $C1, $C7, $CE, $CE, $CF, $CE, $CF, $CE, $CF, $CD, $CE, $C9, $CA
            DFB   $CA, $CC, $CC, $13, $00, $08, $CA, $C9, $CC, $CD, $CE, $CE, $CF, $CE, $CF, $CE
            DFB   $CF, $CE, $CE, $CD, $CB, $C9, $CA, $CB, $C9, $13, $00, $09, $C9, $CA, $CB, $CE
            DFB   $CD, $CF, $CE, $CF, $CE, $CF, $CE, $CF, $CD, $CE, $C9, $CA, $CA, $CC, $CB, $12
            DFB   $01, $0A, $C9, $CA, $CA, $CE, $CD, $CF, $CE, $CF, $CE, $CF, $CE, $CE, $CD, $CB
            DFB   $C8, $CA, $CA, $CC, $0D, $02, $0B, $C8, $CA, $CA, $CC, $CD, $CE, $CD, $CE, $CD
            DFB   $CE, $CD, $CB, $C9, $02, $11, $0B, $CA, $C9, $0B, $03, $0C, $C8, $CA, $CA, $CB
            DFB   $CA, $CB, $CA, $CB, $CA, $CB, $C9, $07, $05, $0D, $CA, $C8, $CA, $C8, $CA, $C8
            DFB   $CA, $03, $08, $0E, $C9, $C8, $C9, $03, $09, $0F, $C9, $C8, $C9, $00

CSPR04_DATA
            DFB   $02, $0A, $00, $C9, $C8, $02, $09, $01, $C9, $C8, $03, $08, $02, $C9, $C8, $C9
            DFB   $07, $05, $03, $CA, $C9, $CA, $C9, $CA, $C8, $C9, $01, $12, $03, $C8, $0B, $03
            DFB   $04, $C8, $CA, $C9, $CB, $CB, $CC, $CB, $CC, $CA, $CA, $C8, $02, $11, $04, $CB
            DFB   $CB, $0D, $02, $05, $C9, $CA, $C9, $CC, $CB, $CE, $CD, $CE, $CD, $CE, $CB, $CB
            DFB   $C9, $03, $10, $05, $CB, $CB, $CD, $12, $01, $06, $C9, $CA, $C7, $C7, $CB, $CE
            DFB   $CD, $CF, $CE, $CF, $CD, $CE, $CB, $CB, $C9, $CB, $CD, $CC, $13, $00, $07, $C8
            DFB   $CA, $CA, $C1, $C7, $CE, $CE, $CF, $CE, $CF, $CE, $CF, $CD, $CE, $CA, $CA, $CB
            DFB   $CC, $CB, $13, $00, $08, $CA, $C9, $CC, $CD, $CE, $CE, $CF, $CE, $CF, $CE, $CF
            DFB   $CE, $CE, $CD, $CB, $C9, $CB, $CD, $CD, $13, $00, $09, $C9, $CA, $CB, $CE, $CD
            DFB   $CF, $CE, $CF, $CE, $CF, $CE, $CF, $CD, $CE, $CA, $CA, $CB, $CC, $CB, $12, $01
            DFB   $0A, $C9, $CA, $CA, $CE, $CD, $CF, $CE, $CF, $CE, $CF, $CE, $CE, $CD, $CB, $C9
            DFB   $CB, $CD, $CC, $0D, $02, $0B, $C8, $CA, $CA, $CC, $CD, $CE, $CD, $CE, $CD, $CE
            DFB   $CD, $CB, $CA, $03, $10, $0B, $CB, $CB, $CD, $0B, $03, $0C, $C8, $CA, $CA, $CB
            DFB   $CA, $CB, $CA, $CB, $CA, $CB, $C9, $02, $11, $0C, $CB, $CB, $07, $05, $0D, $CA
            DFB   $C8, $CA, $C8, $CA, $C8, $CA, $01, $12, $0D, $C8, $03, $08, $0E, $C9, $C8, $C9
            DFB   $02, $09, $0F, $C9, $C8, $02, $0A, $10, $C9, $C8, $00

CSPR05_DATA
            DFB   $02, $01, $09, $C7, $C0, $02, $0E, $09, $C0, $C7, $04, $00, $0A, $D0, $C7, $C7
            DFB   $D0, $04, $0D, $0A, $D0, $C7, $C7, $D0, $04, $00, $0B, $D1, $D0, $D0, $D1, $04
            DFB   $0D, $0B, $D1, $D2, $D0, $D1, $03, $00, $0C, $D2, $D2, $D2, $03, $0E, $0C, $D3
            DFB   $D2, $D3, $03, $00, $0D, $D2, $D4, $D4, $03, $0E, $0D, $D3, $D4, $D3, $03, $01
            DFB   $0E, $D2, $D4, $D1, $03, $0D, $0E, $D2, $D4, $D4, $03, $01, $0F, $D2, $D4, $D3
            DFB   $03, $0D, $0F, $D1, $D4, $D3, $03, $02, $10, $D3, $D3, $D2, $03, $0C, $10, $D1
            DFB   $D3, $D3, $0D, $02, $11, $D1, $D2, $D2, $D1, $D1, $D2, $D2, $D2, $D2, $D1, $D2
            DFB   $D2, $D2, $0B, $03, $12, $D1, $D1, $D1, $D2, $D3, $D3, $D3, $D2, $D1, $D1, $D1
            DFB   $0D, $02, $13, $D0, $D1, $D1, $D2, $D3, $D4, $D4, $D4, $D4, $D2, $D1, $D1, $D1
            DFB   $0F, $01, $14, $D0, $D1, $D2, $D3, $D3, $D4, $D4, $D4, $D4, $D4, $D3, $D3, $D2
            DFB   $D1, $D0, $11, $00, $15, $D0, $D0, $D1, $D2, $D2, $D3, $D3, $D4, $D4, $D4, $D4
            DFB   $D3, $D3, $D2, $D1, $D1, $D0, $11, $00, $16, $C0, $D0, $D1, $D2, $D2, $D3, $D3
            DFB   $D3, $D3, $D3, $D3, $D3, $D3, $D2, $D1, $D1, $D0, $11, $00, $17, $C0, $D0, $D1
            DFB   $D2, $D2, $D2, $D3, $D3, $D3, $D3, $D3, $D3, $D2, $D2, $D1, $D0, $D0, $11, $00
            DFB   $18, $C0, $D0, $D1, $D1, $D1, $D2, $D2, $D2, $D2, $D2, $D2, $D2, $D2, $D1, $D1
            DFB   $D0, $D0, $11, $00, $19, $C0, $D0, $D0, $D1, $D1, $D2, $D2, $D2, $D2, $D2, $D2
            DFB   $D2, $D1, $D1, $D0, $D0, $C0, $0F, $01, $1A, $C0, $D0, $D0, $D0, $D1, $D1, $D1
            DFB   $D1, $D1, $D1, $D1, $D1, $D0, $D0, $C0, $0D, $02, $1B, $C0, $C0, $D0, $D0, $D1
            DFB   $D1, $D1, $D1, $D1, $D1, $D0, $D0, $C0, $0B, $03, $1C, $C0, $C0, $C0, $D0, $D0
            DFB   $D0, $D0, $D0, $D0, $C0, $C0, $07, $05, $1D, $C0, $C0, $C0, $C0, $C0, $C0, $C0
            DFB   $00

CSPR06_DATA
            DFB   $02, $01, $06, $C7, $C0, $02, $0E, $06, $C0, $C7, $04, $00, $07, $D0, $C7, $C7
            DFB   $D0, $04, $0D, $07, $D0, $C7, $C7, $D0, $04, $00, $08, $D1, $D0, $D0, $D1, $04
            DFB   $0D, $08, $D1, $D2, $D0, $D1, $03, $00, $09, $D2, $D2, $D2, $03, $0E, $09, $D3
            DFB   $D2, $D3, $03, $00, $0A, $D2, $D4, $D4, $03, $0E, $0A, $D3, $D4, $D3, $03, $01
            DFB   $0B, $D2, $D4, $D1, $03, $0D, $0B, $D2, $D4, $D4, $03, $01, $0C, $D2, $D4, $D3
            DFB   $03, $0D, $0C, $D1, $D4, $D3, $03, $02, $0D, $D3, $D3, $D2, $05, $06, $0D, $D2
            DFB   $D1, $D1, $D1, $D1, $03, $0C, $0D, $D1, $D3, $D3, $0D, $02, $0E, $D1, $D2, $D2
            DFB   $D1, $D2, $D2, $D2, $D2, $D2, $D1, $D2, $D2, $D2, $0B, $03, $0F, $D1, $D1, $D1
            DFB   $D2, $D3, $D3, $D3, $D2, $D1, $D1, $D1, $0B, $03, $10, $D1, $D1, $D2, $D3, $D4
            DFB   $D4, $D4, $D3, $D2, $D1, $D1, $0D, $02, $11, $D1, $D2, $D2, $D3, $D4, $D4, $D4
            DFB   $D4, $D4, $D3, $D2, $D1, $D0, $0D, $02, $12, $D1, $D1, $D2, $D3, $D4, $D4, $D4
            DFB   $D4, $D4, $D3, $D2, $D1, $D0, $0D, $02, $13, $D0, $D2, $D2, $D3, $D3, $D4, $D4
            DFB   $D4, $D3, $D3, $D2, $D2, $D0, $0F, $01, $14, $D0, $D1, $D2, $D2, $D3, $D3, $D4
            DFB   $D4, $D4, $D3, $D3, $D2, $D2, $D1, $D0, $0F, $01, $15, $D0, $D1, $D2, $D2, $D2
            DFB   $D3, $D3, $D3, $D3, $D3, $D3, $D2, $D1, $D1, $D0, $0F, $01, $16, $D0, $D1, $D1
            DFB   $D2, $D2, $D3, $D3, $D3, $D3, $D3, $D2, $D2, $D1, $D0, $D0, $0D, $02, $17, $D0
            DFB   $D1, $D1, $D2, $D2, $D2, $D2, $D2, $D2, $D2, $D1, $D1, $D0, $0D, $02, $18, $C0
            DFB   $D0, $D1, $D1, $D2, $D2, $D2, $D2, $D2, $D2, $D1, $D0, $D0, $0D, $02, $19, $C0
            DFB   $D0, $D1, $D1, $D1, $D1, $D1, $D1, $D1, $D1, $D1, $D0, $C0, $0B, $03, $1A, $C0
            DFB   $D0, $D1, $D1, $D1, $D1, $D1, $D1, $D1, $D0, $D0, $0B, $03, $1B, $C0, $C0, $D0
            DFB   $D0, $D0, $D0, $D0, $D0, $D0, $D0, $C0, $09, $04, $1C, $C0, $C0, $C0, $D0, $D0
            DFB   $D0, $D0, $C0, $C0, $05, $06, $1D, $C0, $C0, $C0, $C0, $C0, $00

CSPR07_DATA
            DFB   $02, $02, $03, $C7, $C0, $02, $0D, $03, $C0, $C7, $04, $01, $04, $D0, $C7, $C7
            DFB   $D0, $04, $0C, $04, $D0, $C7, $C7, $D0, $04, $01, $05, $D1, $D0, $D0, $D1, $04
            DFB   $0C, $05, $D1, $D2, $D0, $D1, $03, $01, $06, $D2, $D2, $D2, $03, $0D, $06, $D3
            DFB   $D2, $D3, $03, $01, $07, $D2, $D4, $D4, $03, $0D, $07, $D3, $D4, $D3, $03, $02
            DFB   $08, $D2, $D4, $D1, $03, $0C, $08, $D2, $D4, $D4, $03, $02, $09, $D2, $D4, $D3
            DFB   $05, $06, $09, $D1, $D1, $D1, $D1, $D0, $03, $0C, $09, $D1, $D4, $D3, $0B, $03
            DFB   $0A, $D3, $D3, $D2, $D1, $D2, $D2, $D2, $D1, $D1, $D3, $D3, $0B, $03, $0B, $D1
            DFB   $D2, $D2, $D1, $D3, $D3, $D2, $D1, $D2, $D2, $D2, $09, $04, $0C, $D1, $D1, $D1
            DFB   $D2, $D3, $D2, $D1, $D1, $D1, $09, $04, $0D, $D2, $D1, $D2, $D4, $D4, $D4, $D2
            DFB   $D1, $D0, $0B, $03, $0E, $D2, $D2, $D3, $D4, $D4, $D4, $D4, $D3, $D2, $D1, $D0
            DFB   $0B, $03, $0F, $D2, $D2, $D3, $D4, $D4, $D4, $D4, $D3, $D2, $D1, $D0, $0B, $03
            DFB   $10, $D1, $D2, $D3, $D4, $D4, $D4, $D4, $D3, $D3, $D1, $D0, $0B, $03, $11, $D1
            DFB   $D2, $D3, $D3, $D4, $D4, $D4, $D3, $D3, $D2, $D1, $0D, $02, $12, $D1, $D2, $D2
            DFB   $D3, $D3, $D3, $D4, $D3, $D3, $D3, $D2, $D1, $D0, $0D, $02, $13, $D1, $D2, $D2
            DFB   $D2, $D3, $D3, $D3, $D3, $D3, $D2, $D1, $D1, $D0, $0D, $02, $14, $D1, $D1, $D2
            DFB   $D2, $D3, $D3, $D3, $D3, $D3, $D2, $D2, $D0, $D0, $0B, $03, $15, $D0, $D1, $D2
            DFB   $D2, $D3, $D3, $D3, $D2, $D2, $D2, $D0, $0B, $03, $16, $D0, $D1, $D2, $D2, $D2
            DFB   $D2, $D2, $D2, $D2, $D1, $D0, $0B, $03, $17, $D0, $D1, $D1, $D2, $D2, $D2, $D2
            DFB   $D2, $D1, $D1, $D0, $0B, $03, $18, $D0, $D0, $D1, $D1, $D1, $D1, $D1, $D1, $D1
            DFB   $D1, $D0, $09, $04, $19, $D0, $D1, $D1, $D1, $D1, $D1, $D1, $D1, $D0, $09, $04
            DFB   $1A, $D0, $D0, $D0, $D1, $D1, $D1, $D0, $D0, $D0, $09, $04, $1B, $C0, $D0, $D0
            DFB   $D0, $D0, $D0, $D0, $D0, $C0, $07, $05, $1C, $C0, $C0, $D0, $D0, $D0, $C0, $C0
            DFB   $05, $06, $1D, $C0, $C0, $C0, $C0, $C0, $00

CSPR08_DATA
            DFB   $02, $02, $00, $C7, $C0, $02, $0D, $00, $C0, $C7, $04, $01, $01, $D0, $C7, $C7
            DFB   $D0, $04, $0C, $01, $D0, $C7, $C7, $D0, $04, $01, $02, $D1, $D0, $D0, $D1, $04
            DFB   $0C, $02, $D1, $D2, $D0, $D1, $03, $01, $03, $D2, $D2, $D2, $03, $0D, $03, $D3
            DFB   $D2, $D3, $03, $01, $04, $D2, $D4, $D4, $03, $07, $04, $D0, $D0, $D0, $03, $0D
            DFB   $04, $D3, $D4, $D3, $03, $02, $05, $D2, $D4, $D1, $05, $06, $05, $D1, $D1, $D1
            DFB   $D1, $D0, $03, $0C, $05, $D2, $D4, $D4, $03, $02, $06, $D2, $D4, $D3, $05, $06
            DFB   $06, $D1, $D2, $D2, $D2, $D1, $03, $0C, $06, $D1, $D4, $D3, $0B, $03, $07, $D3
            DFB   $D3, $D2, $D1, $D2, $D2, $D2, $D2, $D1, $D3, $D3, $0B, $03, $08, $D1, $D2, $D2
            DFB   $D1, $D3, $D3, $D3, $D1, $D2, $D2, $D2, $09, $04, $09, $D1, $D1, $D1, $D2, $D3
            DFB   $D2, $D1, $D1, $D1, $07, $05, $0A, $D1, $D2, $D3, $D4, $D3, $D2, $D1, $07, $05
            DFB   $0B, $D2, $D3, $D4, $D4, $D3, $D2, $D0, $07, $05, $0C, $D2, $D3, $D4, $D4, $D3
            DFB   $D2, $D0, $07, $05, $0D, $D2, $D3, $D4, $D4, $D4, $D3, $D1, $09, $04, $0E, $D2
            DFB   $D3, $D3, $D4, $D4, $D4, $D3, $D2, $D0, $09, $04, $0F, $D1, $D2, $D3, $D4, $D4
            DFB   $D4, $D3, $D2, $D1, $09, $04, $10, $D1, $D2, $D3, $D3, $D4, $D3, $D3, $D2, $D1
            DFB   $09, $04, $11, $D1, $D2, $D3, $D3, $D3, $D3, $D3, $D2, $D1, $09, $04, $12, $D1
            DFB   $D2, $D2, $D3, $D3, $D3, $D2, $D1, $D1, $09, $04, $13, $D1, $D1, $D2, $D3, $D3
            DFB   $D3, $D2, $D1, $D1, $07, $05, $14, $D1, $D2, $D2, $D3, $D2, $D2, $D1, $07, $05
            DFB   $15, $D1, $D2, $D2, $D2, $D2, $D2, $D1, $07, $05, $16, $D1, $D1, $D2, $D2, $D2
            DFB   $D1, $D1, $07, $05, $17, $D0, $D1, $D1, $D2, $D1, $D1, $D0, $07, $05, $18, $D0
            DFB   $D0, $D1, $D1, $D1, $D1, $D0, $05, $06, $19, $D0, $D1, $D1, $D1, $D1, $05, $06
            DFB   $1A, $D0, $D0, $D0, $D0, $D0, $05, $06, $1B, $D0, $D0, $D0, $D0, $D0, $05, $06
            DFB   $1C, $C0, $C0, $C0, $C0, $C0, $03, $07, $1D, $C0, $C0, $C0, $00

; ---------------------------------------------------------------------
; SPRITE VERI: icona volante (cspr09/16/22) e petali (cspr18/19/1a)
; ---------------------------------------------------------------------
CSPR09_DATA
            DFB   $07, $04, $00, $CB, $CF, $CF, $CF, $CF, $CF, $CB, $0B, $02, $01, $CB, $CF, $CF
            DFB   $CF, $CE, $CE, $CE, $CE, $CE, $CE, $CA, $0D, $01, $02, $CB, $CF, $CF, $CA, $CA
            DFB   $CA, $CE, $CA, $CA, $CA, $CE, $CE, $CA, $0D, $01, $03, $CB, $CF, $CA, $CA, $CA
            DFB   $CA, $CE, $C9, $CA, $CA, $C9, $CD, $C9, $0F, $00, $04, $CB, $CF, $CF, $CA, $CA
            DFB   $CA, $C9, $CD, $C9, $CA, $CA, $C8, $CC, $CC, $C8, $0F, $00, $05, $CB, $CF, $CE
            DFB   $CE, $CE, $CD, $CD, $CD, $CD, $CC, $CC, $CC, $CC, $CC, $C8, $0F, $00, $06, $CB
            DFB   $CF, $CE, $CA, $CA, $CA, $CA, $CA, $CA, $CA, $CA, $C8, $CC, $CC, $C8, $0D, $01
            DFB   $07, $CB, $CE, $CA, $CA, $CA, $CA, $CA, $CA, $CA, $CA, $C8, $CC, $C8, $0D, $01
            DFB   $08, $CB, $CF, $CE, $C9, $CA, $CA, $CA, $CA, $CA, $C8, $CC, $CC, $C8, $0B, $02
            DFB   $09, $CB, $CE, $CD, $CD, $C9, $CA, $C8, $CC, $CC, $CC, $C8, $07, $04, $0A, $CA
            DFB   $CD, $CD, $CC, $CC, $CC, $C8, $00

CSPR16_DATA
            DFB   $05, $00, $00, $C2, $C2, $C2, $C2, $C2, $05, $10, $00, $C2, $C2, $C2, $C2, $C2
            DFB   $09, $00, $01, $C2, $C0, $C0, $C0, $C1, $C1, $C2, $C2, $C2, $09, $0C, $01, $C2
            DFB   $C2, $C2, $C4, $C5, $C6, $C6, $C6, $C2, $15, $00, $02, $C2, $C0, $C0, $C0, $C0
            DFB   $C0, $C0, $C0, $C1, $C1, $C2, $C4, $C5, $C6, $C6, $C6, $C6, $C6, $C6, $C6, $C2
            DFB   $15, $00, $03, $C2, $C0, $DA, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C2, $C6, $C6
            DFB   $C6, $C6, $C6, $C6, $C6, $DE, $C6, $C2, $15, $00, $04, $C2, $C0, $DB, $DB, $DA
            DFB   $C0, $C0, $C0, $C0, $C0, $C2, $C6, $C6, $C6, $C6, $C6, $DE, $DD, $DD, $C6, $C2
            DFB   $15, $00, $05, $C2, $C0, $DA, $DF, $DF, $DB, $DA, $C0, $C0, $C0, $C2, $C6, $C6
            DFB   $C6, $DE, $DD, $DF, $DF, $DE, $C6, $C2, $15, $00, $06, $C2, $C0, $C0, $DA, $DB
            DFB   $DF, $DF, $DA, $C0, $C0, $C2, $C6, $C6, $DE, $DF, $DF, $DD, $DE, $C6, $C6, $C2
            DFB   $15, $00, $07, $C2, $C0, $C0, $C0, $C0, $DA, $DB, $DB, $DA, $C0, $C2, $C6, $DE
            DFB   $DD, $DD, $DE, $C6, $C6, $C6, $C6, $C2, $15, $00, $08, $C2, $C1, $C0, $C0, $C0
            DFB   $C0, $C0, $C0, $C0, $C0, $C2, $C6, $C6, $C6, $C6, $C6, $C6, $C6, $C6, $C5, $C2
            DFB   $13, $01, $09, $C1, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C2, $C6, $C6, $C6
            DFB   $C6, $DE, $C6, $C6, $C6, $C4, $13, $01, $0A, $C2, $C0, $C0, $C0, $C0, $C0, $C0
            DFB   $C0, $C0, $C2, $C6, $C6, $C6, $C6, $DD, $C6, $C6, $C6, $C2, $13, $01, $0B, $C2
            DFB   $C1, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C2, $C6, $C6, $C6, $DD, $DF, $DD, $C6
            DFB   $C5, $C2, $11, $02, $0C, $C1, $C0, $C0, $C0, $C0, $C0, $C0, $C0, $C2, $C6, $C6
            DFB   $C6, $DE, $DD, $DE, $C6, $C4, $11, $02, $0D, $C2, $C1, $C0, $C0, $C0, $C0, $C0
            DFB   $C0, $C2, $C6, $C6, $C6, $C6, $C6, $C6, $C5, $C2, $0F, $03, $0E, $C2, $C1, $C0
            DFB   $C0, $C0, $C0, $C0, $C2, $C6, $C6, $C6, $C6, $C6, $C5, $C2, $0D, $04, $0F, $C2
            DFB   $C1, $C0, $C0, $C0, $C0, $C2, $C6, $C6, $C6, $C6, $C5, $C2, $0B, $05, $10, $C2
            DFB   $C1, $C0, $C0, $C0, $C2, $C6, $C6, $C6, $C5, $C2, $09, $06, $11, $C2, $C1, $C1
            DFB   $C0, $C2, $C6, $C5, $C4, $C2, $05, $08, $12, $C2, $C2, $C2, $C2, $C2, $01, $0A
            DFB   $13, $C2, $00

CSPR22_DATA
            DFB   $07, $07, $00, $CF, $CF, $CF, $CF, $CF, $CE, $CE, $0B, $05, $01, $CF, $CF, $CE
            DFB   $CC, $CC, $CC, $CC, $CC, $CC, $CC, $CE, $0F, $03, $02, $CF, $CF, $CE, $CC, $CC
            DFB   $CB, $CB, $CC, $CB, $CB, $CB, $CC, $CC, $CC, $CE, $11, $02, $03, $CF, $CE, $CC
            DFB   $CC, $CB, $CA, $CA, $CA, $CB, $CA, $CA, $CA, $CB, $CB, $CC, $CB, $CC, $13, $01
            DFB   $04, $CF, $CE, $CC, $CB, $C9, $C9, $C9, $C9, $C9, $CB, $C9, $C9, $C9, $C9, $C9
            DFB   $CB, $CC, $CB, $C9, $13, $01, $05, $CF, $CC, $CB, $C9, $C9, $C9, $C9, $C9, $C9
            DFB   $CB, $C9, $C9, $C9, $C9, $C9, $C9, $CB, $CB, $CB, $15, $00, $06, $CF, $CE, $CC
            DFB   $CA, $C9, $C9, $C9, $C9, $C9, $C9, $CB, $C9, $C9, $C9, $C9, $C9, $C9, $CA, $CB
            DFB   $CB, $C9, $15, $00, $07, $CF, $CC, $CB, $CA, $C9, $C9, $C9, $C9, $C9, $C9, $CB
            DFB   $C9, $C9, $C9, $C9, $C9, $C9, $CA, $CB, $CB, $C8, $15, $00, $08, $CF, $CC, $CC
            DFB   $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CB, $CC
            DFB   $CB, $C8, $15, $00, $09, $CF, $CC, $CB, $CA, $C9, $C9, $C9, $C9, $C9, $C9, $C9
            DFB   $C9, $C9, $C9, $C9, $C9, $C9, $CA, $CB, $CB, $C8, $15, $00, $0A, $CE, $CC, $CB
            DFB   $CA, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $CA, $CB
            DFB   $C8, $C8, $13, $01, $0B, $CD, $CC, $CB, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9
            DFB   $C9, $C9, $C9, $C9, $C9, $CB, $CB, $C8, $13, $01, $0C, $CE, $CC, $CC, $CB, $C9
            DFB   $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $CB, $CC, $C8, $C8, $11, $02
            DFB   $0D, $CC, $CC, $CC, $CB, $CA, $C9, $C9, $C9, $C9, $C9, $C9, $C9, $CA, $CB, $CC
            DFB   $C8, $C8, $0F, $03, $0E, $C9, $CB, $CC, $CB, $CB, $CA, $CA, $CA, $CA, $CA, $CB
            DFB   $CB, $C9, $C8, $C8, $0B, $05, $0F, $C9, $CB, $CC, $CB, $CB, $CB, $CB, $CB, $C9
            DFB   $C8, $C8, $07, $07, $10, $C9, $C8, $C8, $C8, $C8, $C8, $C8, $00

CSPR18_DATA
            DFB   $01, $0C, $00, $C0, $01, $0B, $01, $C0, $01, $0A, $02, $C0, $05, $06, $03, $C9
            DFB   $CB, $CB, $C9, $C0, $07, $04, $04, $C9, $CB, $CC, $CD, $CC, $CC, $C9, $08, $03
            DFB   $05, $C8, $CB, $CD, $CC, $CC, $CC, $CB, $C9, $08, $03, $06, $CB, $CD, $CC, $CC
            DFB   $CC, $CB, $C9, $C9, $07, $03, $07, $CA, $CC, $CB, $CC, $CB, $C9, $C9, $07, $02
            DFB   $08, $CB, $CB, $CB, $CA, $C8, $C9, $C8, $04, $02, $09, $C0, $C9, $C9, $C9, $00

CSPR19_DATA
            DFB   $01, $0C, $01, $C0, $03, $05, $02, $CB, $CD, $CC, $01, $0B, $02, $C0, $08, $03
            DFB   $03, $C9, $CB, $CB, $CB, $CD, $CC, $C8, $C0, $07, $03, $04, $C8, $CD, $CD, $CD
            DFB   $CC, $CC, $C9, $08, $02, $05, $CA, $CC, $CC, $CC, $CC, $CC, $CB, $C9, $09, $01
            DFB   $06, $CB, $CB, $CC, $CC, $CD, $CC, $CB, $C9, $CA, $08, $01, $07, $C0, $CB, $CB
            DFB   $CC, $CB, $C9, $C8, $C9, $04, $03, $08, $C0, $C9, $C9, $C8, $00

CSPR1A_DATA
            DFB   $06, $03, $03, $CA, $CA, $CA, $CB, $CA, $CC, $08, $02, $04, $CB, $CC, $CC, $CB
            DFB   $CD, $CD, $CC, $CD, $02, $0C, $04, $C0, $C0, $0C, $00, $05, $CB, $CA, $CA, $CC
            DFB   $CC, $CC, $CC, $CC, $CA, $CA, $C0, $C0, $0A, $00, $06, $C8, $CC, $CB, $CD, $CC
            DFB   $CB, $CB, $CB, $CA, $C8, $08, $01, $07, $C0, $CA, $CB, $CB, $CC, $C9, $CA, $C9
            DFB   $04, $03, $08, $C0, $C9, $C8, $C8, $00

; ---------------------------------------------------------------------
; SPRITE VERI: due petali in piu' (cspr1b/cspr1c), per i petali extra
; ---------------------------------------------------------------------
CSPR1B_DATA
            DFB   $02, $05, $02, $CB, $CC, $07, $02, $03, $C9, $CA, $CB, $C9, $CD, $CC, $C9, $07
            DFB   $02, $04, $C9, $CC, $CC, $CC, $CD, $CB, $CC, $08, $02, $05, $C9, $CC, $CC, $CD
            DFB   $CC, $CC, $CC, $CB, $08, $02, $06, $C0, $CD, $CB, $CC, $CC, $CC, $CC, $C0, $01
            DFB   $0C, $06, $C0, $08, $04, $07, $C9, $CC, $CB, $CC, $CC, $C9, $C0, $C0, $05, $05
            DFB   $08, $C0, $C8, $C8, $C9, $C9, $00

CSPR1C_DATA
            DFB   $05, $01, $02, $CA, $CD, $CC, $CB, $CA, $07, $01, $03, $C9, $CA, $CC, $CB, $CD
            DFB   $CC, $CA, $08, $01, $04, $C8, $CC, $CD, $CC, $CD, $CD, $CD, $CB, $07, $02, $05
            DFB   $C9, $CB, $CB, $CC, $CC, $CB, $CC, $07, $03, $06, $C9, $CD, $CC, $CC, $CC, $CC
            DFB   $CA, $07, $04, $07, $C9, $CB, $CD, $CC, $C9, $C0, $C0, $04, $05, $08, $C0, $C8
            DFB   $C8, $C9, $02, $0B, $08, $C0, $C0, $00

; ---------------------------------------------------------------------
; TL55: sprite nuovi cspr1d..21 (sprites.c), gli altri 4 frame della
; pioggia/neve vera (R_L1P90) oltre a cspr18..1c gia' presenti sopra.
; ---------------------------------------------------------------------
CSPR1D_DATA
            DFB   $03,$03,$02,$DB,$DB,$DC,$03,$07,$02,$DC,$DB,$C8,$09,$02,$03,$C8
            DFB   $DC,$C7,$E1,$E0,$DF,$DC,$DB,$C0,$09,$02,$04,$C8,$DC,$E0,$E1,$E1
            DFB   $E0,$DC,$DB,$C0,$09,$02,$05,$C8,$DC,$DF,$E0,$E0,$DF,$DC,$DB,$C0
            DFB   $07,$03,$06,$C0,$DC,$DF,$DC,$DC,$C8,$C0,$05,$04,$07,$DB,$DC,$DB
            DFB   $C0,$C0,$03,$04,$08,$C0,$C8,$C0,$01,$05,$09,$C0,$00

CSPR1E_DATA
            DFB   $03,$04,$02,$C8,$DB,$DC,$03,$08,$02,$DC,$DB,$C0,$09,$03,$03,$DB
            DFB   $DC,$C7,$E0,$E0,$DF,$DC,$C8,$C0,$09,$03,$04,$C8,$DF,$E1,$E1,$E1
            DFB   $DF,$DC,$DB,$C0,$09,$03,$05,$C8,$DC,$DF,$E1,$E0,$DF,$DF,$C8,$C0
            DFB   $07,$04,$06,$DB,$DC,$DF,$DC,$DC,$DB,$C0,$05,$04,$07,$C0,$DC,$DB
            DFB   $C0,$C0,$02,$05,$08,$DB,$C0,$01,$05,$09,$C0,$00

CSPR1F_DATA
            DFB   $03,$04,$02,$DC,$DF,$DC,$03,$08,$02,$DC,$C8,$C0,$09,$03,$03,$DB
            DFB   $DF,$C7,$E0,$E0,$DF,$DC,$C8,$C0,$0A,$02,$04,$C8,$DF,$E1,$E1,$E1
            DFB   $E0,$DF,$DC,$C8,$C0,$09,$02,$05,$C8,$DF,$E0,$E0,$E0,$DF,$DC,$DB
            DFB   $C8,$07,$03,$06,$DB,$DF,$DF,$DC,$DB,$DB,$C0,$05,$03,$07,$C0,$DC
            DFB   $DB,$C0,$C0,$02,$04,$08,$DB,$C0,$01,$04,$09,$C0,$00

CSPR20_DATA
            DFB   $03,$05,$01,$DB,$DB,$C8,$02,$09,$01,$DB,$C0,$08,$04,$02,$DC,$E0
            DFB   $C7,$E0,$DF,$DF,$C8,$C0,$08,$04,$03,$DC,$E0,$E1,$E1,$E0,$DC,$C8
            DFB   $C0,$07,$04,$04,$DF,$E0,$E1,$E0,$DF,$DB,$C0,$07,$03,$05,$DB,$DC
            DFB   $DF,$DF,$DC,$DC,$C0,$05,$03,$06,$DB,$DC,$DC,$C8,$C8,$03,$03,$07
            DFB   $C8,$C8,$C8,$01,$03,$08,$C0,$00

CSPR21_DATA
            DFB   $02,$06,$00,$DB,$DB,$03,$09,$00,$C8,$C8,$C0,$08,$05,$01,$DC,$DF
            DFB   $DC,$DF,$DF,$DB,$C8,$C0,$08,$05,$02,$DF,$C7,$E1,$DF,$DF,$DC,$DB
            DFB   $C0,$08,$04,$03,$DC,$E1,$E1,$E1,$E0,$DC,$DB,$C0,$07,$04,$04,$E0
            DFB   $E0,$E0,$DF,$DC,$DB,$C0,$06,$03,$05,$DF,$E0,$DF,$DC,$C8,$C8,$05
            DFB   $02,$06,$C8,$DC,$DC,$C8,$C8,$03,$01,$07,$C0,$C0,$C8,$00

; ---------------------------------------------------------------------
; SPRITE VERI: due icone in piu' per l'orbita (cspr0a/cspr17)
; ---------------------------------------------------------------------
CSPR0A_DATA
            DFB   $07, $07, $00, $C3, $C3, $C3, $DB, $C3, $C3, $C3, $0B, $05, $01, $DB, $C3, $C4
            DFB   $C4, $C4, $C4, $DC, $C4, $C4, $C3, $DB, $0F, $03, $02, $C3, $C3, $C4, $C4, $C5
            DFB   $C5, $C5, $C5, $DD, $C5, $C5, $DC, $C4, $C3, $C3, $11, $02, $03, $C3, $C3, $C4
            DFB   $DD, $C5, $C5, $C6, $C6, $DE, $C6, $DE, $C5, $C5, $C5, $C4, $C3, $DB, $13, $01
            DFB   $04, $DB, $DB, $DC, $DD, $C5, $C6, $C6, $C6, $C6, $C6, $C6, $C6, $C6, $C6, $C5
            DFB   $C5, $C4, $DB, $C3, $13, $01, $05, $C3, $C4, $C5, $C5, $DE, $C6, $C6, $D9, $D9
            DFB   $D9, $D9, $D9, $C6, $C6, $C6, $C5, $DD, $DC, $C3, $15, $00, $06, $C3, $C4, $C5
            DFB   $C5, $C5, $C6, $DE, $D9, $D9, $D8, $D8, $D8, $D8, $D7, $C6, $DE, $DD, $C5, $DD
            DFB   $C4, $DB, $15, $00, $07, $C3, $DC, $DD, $C5, $C6, $C6, $D9, $D9, $D8, $C0, $C0
            DFB   $C0, $D7, $D7, $D6, $C6, $C6, $C5, $DD, $C4, $C3, $15, $00, $08, $DB, $C4, $C5
            DFB   $C5, $C6, $C6, $D9, $D8, $D9, $C0, $C0, $C0, $D7, $D7, $D6, $C6, $C6, $C5, $C5
            DFB   $C4, $C3, $15, $00, $09, $C3, $C4, $C5, $C5, $C6, $C6, $D9, $D9, $D7, $C0, $C0
            DFB   $C0, $D7, $D6, $D6, $C6, $C6, $C5, $DD, $C4, $C3, $15, $00, $0A, $C3, $C4, $C5
            DFB   $C5, $DD, $C6, $C6, $D8, $D7, $D7, $D7, $D6, $D6, $D6, $DE, $C6, $C5, $C5, $DD
            DFB   $DC, $DB, $13, $01, $0B, $C3, $C4, $DD, $DD, $C6, $C6, $C6, $D7, $D7, $D6, $D6
            DFB   $D5, $C6, $DE, $C6, $C5, $DD, $C4, $C3, $13, $01, $0C, $DB, $DB, $C4, $C5, $DD
            DFB   $C6, $C6, $C6, $DE, $C6, $DE, $C6, $C6, $DE, $C5, $C5, $C4, $C3, $C3, $11, $02
            DFB   $0D, $C3, $C3, $C4, $C5, $C5, $C5, $C6, $C6, $DE, $C6, $C6, $DD, $DD, $DD, $C4
            DFB   $C3, $C3, $0F, $03, $0E, $C3, $C3, $C4, $C4, $C5, $C5, $C5, $DD, $C5, $C5, $C5
            DFB   $C4, $C4, $DB, $DB, $0B, $05, $0F, $DB, $C3, $C4, $DC, $C4, $C4, $DC, $C4, $C4
            DFB   $C3, $C3, $07, $07, $10, $C3, $DB, $C3, $C3, $DB, $C3, $DB, $00

CSPR17_DATA
            DFB   $04, $04, $00, $DB, $E0, $E0, $DB, $04, $0D, $00, $DB, $E0, $DC, $DB, $08, $02
            DFB   $01, $DB, $E0, $E1, $E2, $E1, $E1, $E0, $DB, $08, $0B, $01, $DC, $E1, $E1, $E1
            DFB   $E1, $E0, $DC, $DB, $13, $01, $02, $DB, $E0, $E1, $E3, $E3, $E3, $E2, $E1, $E1
            DFB   $E1, $E1, $E2, $E3, $E3, $E2, $E1, $E0, $DF, $DB, $13, $01, $03, $E0, $E1, $E3
            DFB   $C7, $E3, $E3, $E2, $E2, $E1, $E1, $E2, $E3, $C7, $E3, $E2, $E1, $E0, $E0, $DF
            DFB   $15, $00, $04, $DB, $E0, $E2, $E3, $E3, $E3, $E2, $E2, $E1, $E1, $E1, $E1, $E2
            DFB   $E3, $E2, $E1, $E1, $E0, $DF, $DC, $DB, $15, $00, $05, $DC, $E1, $E2, $E3, $E2
            DFB   $E2, $E1, $E1, $E1, $E0, $E0, $E0, $E1, $E1, $E1, $E0, $E0, $DF, $DC, $DB, $DB
            DFB   $15, $00, $06, $DC, $E1, $E2, $E3, $E2, $E1, $E1, $E0, $E0, $E0, $E0, $E0, $E0
            DFB   $E0, $E0, $E0, $DF, $DF, $DC, $DB, $DA, $15, $00, $07, $DC, $E1, $E1, $E2, $E1
            DFB   $E1, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $DF, $DF, $DB, $DB, $DA
            DFB   $15, $00, $08, $DB, $E0, $E1, $E1, $E1, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0
            DFB   $E0, $E0, $DF, $DF, $DC, $DB, $DA, $C0, $13, $01, $09, $DB, $E0, $E1, $E1, $E0
            DFB   $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $DF, $DF, $DF, $DB, $DA, $DA, $13, $01
            DFB   $0A, $DB, $DF, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $E0, $DF, $DF, $DF
            DFB   $DC, $DB, $DA, $C0, $11, $02, $0B, $DB, $DF, $E0, $E0, $E0, $E0, $E0, $E0, $E0
            DFB   $DF, $DF, $DF, $DF, $DC, $DB, $DA, $DA, $0F, $03, $0C, $DB, $DC, $DF, $DF, $DF
            DFB   $DF, $DF, $DF, $DF, $DF, $DF, $DC, $DB, $DA, $DA, $0D, $04, $0D, $DB, $DC, $DF
            DFB   $DF, $DF, $DF, $DF, $DF, $DC, $DB, $DB, $DA, $DA, $0B, $05, $0E, $DB, $DC, $DC
            DFB   $DC, $DF, $DC, $DB, $DB, $DA, $DA, $DA, $09, $06, $0F, $DB, $DB, $DB, $DB, $DA
            DFB   $DA, $DA, $DA, $C0, $05, $08, $10, $DA, $DA, $DA, $DA, $C0, $01, $0A, $11, $DA
            DFB   $00

CSPR10_DATA
            DFB   $13,$01,$00,$CF,$CE,$CD,$CD,$CD,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC
            DFB   $CC,$CB,$CB,$CA,$C9,$CB,$13,$01,$01,$CC,$C0,$C0,$C0,$C1,$C2,$C1
            DFB   $C1,$C1,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$CC,$13,$01,$02,$CA
            DFB   $C0,$C0,$C2,$C5,$C3,$C2,$C1,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0
            DFB   $C0,$CA,$11,$02,$03,$CC,$C0,$C3,$C7,$C4,$C1,$C0,$C0,$C0,$C0,$C0
            DFB   $C0,$C0,$C0,$C0,$C0,$CC,$11,$02,$04,$CA,$C0,$C1,$C4,$C2,$C0,$C0
            DFB   $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$CA,$0F,$03,$05,$CA,$C0,$C0
            DFB   $C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$CA,$0D,$04,$06,$CA
            DFB   $CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CA,$0B,$05,$07,$CA
            DFB   $CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CF,$CA,$09,$06,$08,$C9,$CA,$CF
            DFB   $CF,$CF,$CF,$CF,$CA,$C9,$05,$08,$09,$CA,$CF,$CF,$CF,$CA,$03,$09
            DFB   $0A,$CC,$CF,$CA,$05,$08,$0B,$CA,$C0,$C9,$C0,$CA,$09,$06,$0C,$CA
            DFB   $C9,$C0,$C0,$C9,$C0,$C0,$C9,$CA,$0B,$05,$0D,$CA,$C1,$C2,$C1,$C0
            DFB   $C9,$C0,$C0,$C0,$C0,$CA,$0D,$04,$0E,$CA,$C1,$C3,$C7,$C4,$C1,$C9
            DFB   $C0,$C0,$C0,$C0,$C0,$CA,$0F,$03,$0F,$CA,$C1,$C3,$C7,$C4,$C2,$C0
            DFB   $C9,$C0,$C0,$C0,$C0,$C0,$C0,$CA,$11,$02,$10,$CC,$C0,$C2,$C7,$C5
            DFB   $C2,$C0,$C9,$CF,$C9,$C0,$C0,$C0,$C0,$C0,$C0,$CC,$11,$02,$11,$CA
            DFB   $C0,$C1,$C4,$C1,$C0,$C9,$CF,$CF,$CF,$C9,$C0,$C0,$C0,$C0,$C0,$CA
            DFB   $13,$01,$12,$CC,$C0,$C0,$C0,$C1,$C0,$C9,$CF,$CF,$CF,$CF,$CF,$C9
            DFB   $C0,$C0,$C0,$C0,$C0,$CC,$13,$01,$13,$CD,$C0,$C0,$C0,$C0,$C0,$CF
            DFB   $CF,$CF,$CF,$CF,$CF,$CF,$C0,$C0,$C0,$C0,$C0,$CD,$13,$01,$14,$CD
            DFB   $CD,$CD,$CD,$CD,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CC,$CB,$CB,$CA
            DFB   $C8,$C8,$00

CSPR11_DATA
            DFB   $07,$07,$00,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$0B,$05,$01,$C1,$C2,$C3
            DFB   $C4,$C4,$C5,$C4,$C4,$C3,$C2,$C1,$0F,$03,$02,$C0,$C1,$C3,$C4,$C5
            DFB   $C6,$C7,$C7,$C7,$C6,$C5,$C4,$C3,$C1,$C0,$11,$02,$03,$C0,$C1,$C2
            DFB   $C3,$C3,$C4,$C4,$C5,$C6,$C5,$C4,$C4,$C3,$C3,$C2,$C1,$C0,$13,$01
            DFB   $04,$C2,$C4,$C3,$C1,$C1,$C2,$C2,$C2,$C3,$C3,$C3,$C2,$C2,$C2,$C1
            DFB   $C1,$C3,$C4,$C2,$13,$01,$05,$C5,$C6,$C6,$C5,$C3,$C1,$C1,$C1,$C1
            DFB   $C1,$C1,$C1,$C1,$C1,$C3,$C5,$C6,$C6,$C5,$15,$00,$06,$C3,$C4,$C3
            DFB   $C3,$C3,$C4,$C4,$C3,$C2,$C1,$C1,$C1,$C2,$C3,$C4,$C4,$C3,$C3,$C3
            DFB   $C4,$C3,$15,$00,$07,$C3,$C3,$C1,$DB,$C1,$C2,$C3,$C3,$C3,$C2,$C2
            DFB   $C2,$C3,$C3,$C3,$C2,$C1,$DB,$C1,$C3,$C3,$15,$00,$08,$C2,$C3,$DB
            DFB   $DF,$DB,$C1,$C1,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C1,$C1,$DB,$DF,$DB
            DFB   $C3,$C2,$15,$00,$09,$C2,$C3,$DA,$DB,$DF,$DF,$DF,$DB,$C1,$C2,$C4
            DFB   $C2,$C1,$DB,$DF,$DF,$DF,$DB,$DA,$C3,$C2,$15,$00,$0A,$C1,$C2,$C2
            DFB   $C1,$DB,$DB,$DB,$DA,$C1,$C3,$C5,$C3,$C1,$DA,$DB,$DB,$DB,$C1,$C2
            DFB   $C2,$C1,$13,$01,$0B,$C1,$C2,$C2,$C2,$C1,$C1,$C1,$C3,$C3,$C1,$C3
            DFB   $C3,$C1,$C1,$C1,$C2,$C2,$C2,$C1,$11,$02,$0C,$C1,$C2,$C2,$C2,$C2
            DFB   $C3,$C3,$C0,$C0,$C0,$C3,$C3,$C2,$C2,$C2,$C2,$C1,$11,$02,$0D,$C0
            DFB   $C1,$C1,$C2,$C2,$C1,$C1,$C0,$C0,$C0,$C1,$C1,$C2,$C2,$C1,$C1,$C0
            DFB   $0F,$03,$0E,$C0,$C1,$C1,$C2,$C2,$C1,$C1,$C1,$C1,$C1,$C2,$C2,$C1
            DFB   $C1,$C0,$0F,$03,$0F,$C0,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1,$C1
            DFB   $C1,$C1,$C1,$C0,$0D,$04,$10,$C0,$C1,$C1,$C0,$C0,$C0,$C0,$C0,$C0
            DFB   $C0,$C1,$C1,$C0,$0D,$04,$11,$C0,$C0,$C1,$C1,$C1,$C1,$C1,$C1,$C1
            DFB   $C1,$C1,$C0,$C0,$0B,$05,$12,$C0,$C0,$C1,$C1,$C1,$C1,$C1,$C1,$C1
            DFB   $C0,$C0,$09,$06,$13,$C0,$C0,$C1,$C0,$C0,$C0,$C1,$C0,$C0,$07,$07
            DFB   $14,$C0,$C0,$C0,$C0,$C0,$C0,$C0,$00

CSPR0B_DATA
            DFB   $02,$0F,$00,$C5,$C5,$02,$36,$00,$C5,$C5,$05,$0D,$01,$C5,$C5,$C6
            DFB   $C6,$C5,$05,$35,$01,$C5,$C6,$C6,$C5,$C5,$08,$0B,$02,$C5,$C5,$C5
            DFB   $C4,$C4,$C5,$C6,$C5,$08,$34,$02,$C5,$C6,$C5,$C4,$C4,$C5,$C5,$C5
            DFB   $0B,$09,$03,$C5,$C5,$C4,$C4,$C4,$C5,$C4,$C4,$C5,$C6,$C5,$0B,$33
            DFB   $03,$C5,$C6,$C5,$C4,$C4,$C5,$C4,$C4,$C4,$C5,$C5,$0D,$08,$04,$C1
            DFB   $C2,$C3,$C4,$C4,$C4,$C4,$C4,$C4,$C5,$C5,$C6,$C5,$0D,$32,$04,$C5
            DFB   $C6,$C5,$C5,$C4,$C4,$C4,$C4,$C4,$C4,$C3,$C2,$C1,$0E,$08,$05,$C2
            DFB   $C3,$C3,$C3,$C3,$C3,$C4,$C5,$C4,$C4,$C5,$C5,$C6,$C5,$0E,$31,$05
            DFB   $C5,$C6,$C5,$C5,$C4,$C4,$C5,$C4,$C3,$C3,$C3,$C3,$C3,$C2,$0F,$08
            DFB   $06,$C2,$C2,$C2,$C2,$C2,$C3,$C4,$C4,$C4,$C4,$C4,$C5,$C5,$C6,$C5
            DFB   $0F,$30,$06,$C5,$C6,$C5,$C5,$C4,$C4,$C4,$C4,$C4,$C3,$C2,$C2,$C2
            DFB   $C2,$C2,$0F,$09,$07,$C2,$C2,$C2,$C2,$C3,$C4,$C4,$C4,$C4,$C4,$C4
            DFB   $C4,$C5,$C6,$C5,$0F,$2F,$07,$C5,$C6,$C5,$C4,$C4,$C4,$C4,$C4,$C4
            DFB   $C4,$C3,$C2,$C2,$C2,$C2,$0F,$0A,$08,$C2,$C3,$C3,$C3,$C2,$C3,$C3
            DFB   $C4,$C4,$C5,$C4,$C5,$C6,$C6,$C5,$0F,$2E,$08,$C5,$C6,$C6,$C5,$C4
            DFB   $C5,$C4,$C4,$C3,$C3,$C2,$C3,$C3,$C3,$C2,$10,$0A,$09,$C2,$C3,$C2
            DFB   $C2,$C3,$C3,$C3,$C2,$C4,$C4,$C5,$C4,$C4,$C5,$C6,$C5,$10,$2D,$09
            DFB   $C5,$C6,$C5,$C4,$C4,$C5,$C4,$C4,$C2,$C3,$C3,$C3,$C2,$C2,$C3,$C2
            DFB   $10,$0B,$0A,$C2,$C2,$C2,$C3,$C2,$C2,$C2,$C3,$C4,$C2,$C4,$C5,$C4
            DFB   $C5,$C6,$C5,$10,$2C,$0A,$C5,$C6,$C5,$C4,$C5,$C4,$C2,$C4,$C3,$C2
            DFB   $C2,$C2,$C3,$C2,$C2,$C2,$0F,$0D,$0B,$C2,$C2,$C2,$C2,$C3,$C3,$C3
            DFB   $C2,$C4,$C4,$C2,$C4,$C5,$C6,$C5,$0F,$2B,$0B,$C5,$C6,$C5,$C4,$C2
            DFB   $C4,$C4,$C2,$C3,$C3,$C3,$C2,$C2,$C2,$C2,$0C,$0F,$0C,$C2,$C2,$C2
            DFB   $C2,$C2,$C2,$C3,$C3,$C3,$C2,$C4,$C5,$0C,$2C,$0C,$C5,$C4,$C2,$C3
            DFB   $C3,$C3,$C2,$C2,$C2,$C2,$C2,$C2,$03,$11,$0D,$C2,$C2,$C2,$03,$15
            DFB   $0D,$C2,$C2,$C2,$01,$19,$0D,$C2,$01,$2D,$0D,$C2,$03,$2F,$0D,$C2
            DFB   $C2,$C2,$03,$33,$0D,$C2,$C2,$C2,$00

CSPR0C_DATA
            DFB   $05,$0B,$05,$C5,$C5,$C5,$C5,$C5,$05,$37,$05,$C5,$C5,$C5,$C5,$C5
            DFB   $0C,$06,$06,$C5,$C5,$C5,$C5,$C5,$C4,$C4,$C4,$C4,$C6,$C5,$C5,$0C
            DFB   $35,$06,$C5,$C5,$C6,$C4,$C4,$C4,$C4,$C5,$C5,$C5,$C5,$C5,$0F,$05
            DFB   $07,$C1,$C3,$C3,$C3,$C3,$C4,$C4,$C4,$C4,$C4,$C4,$C4,$C6,$C5,$C5
            DFB   $0F,$33,$07,$C5,$C5,$C6,$C4,$C4,$C4,$C4,$C4,$C4,$C4,$C3,$C3,$C3
            DFB   $C3,$C1,$11,$05,$08,$C2,$C2,$C2,$C2,$C3,$C3,$C3,$C3,$C4,$C4,$C4
            DFB   $C4,$C4,$C4,$C6,$C5,$C5,$11,$31,$08,$C5,$C5,$C6,$C4,$C4,$C4,$C4
            DFB   $C4,$C4,$C3,$C3,$C3,$C3,$C2,$C2,$C2,$C2,$12,$06,$09,$C2,$C2,$C2
            DFB   $C2,$C3,$C3,$C3,$C3,$C3,$C4,$C4,$C4,$C4,$C4,$C4,$C6,$C5,$C5,$12
            DFB   $2F,$09,$C5,$C5,$C6,$C4,$C4,$C4,$C4,$C4,$C4,$C3,$C3,$C3,$C3,$C3
            DFB   $C2,$C2,$C2,$C2,$13,$07,$0A,$C2,$C2,$C2,$C3,$C3,$C2,$C3,$C3,$C3
            DFB   $C3,$C3,$C4,$C4,$C4,$C4,$C5,$C6,$C5,$C5,$13,$2D,$0A,$C5,$C5,$C6
            DFB   $C5,$C4,$C4,$C4,$C4,$C3,$C3,$C3,$C3,$C3,$C2,$C3,$C3,$C2,$C2,$C2
            DFB   $14,$08,$0B,$C2,$C2,$C2,$C2,$C3,$C3,$C3,$C2,$C3,$C3,$C2,$C3,$C4
            DFB   $C4,$C4,$C5,$C5,$C6,$C5,$C5,$14,$2B,$0B,$C5,$C5,$C6,$C5,$C5,$C4
            DFB   $C4,$C4,$C3,$C2,$C3,$C3,$C2,$C3,$C3,$C3,$C2,$C2,$C2,$C2,$11,$0A
            DFB   $0C,$C2,$C2,$C3,$C2,$C2,$C2,$C3,$C3,$C2,$C2,$C3,$C3,$C2,$C4,$C4
            DFB   $C5,$C4,$11,$2C,$0C,$C4,$C5,$C4,$C4,$C2,$C3,$C3,$C2,$C2,$C3,$C3
            DFB   $C2,$C2,$C2,$C3,$C2,$C2,$0E,$0C,$0D,$C2,$C2,$C2,$C2,$C2,$C2,$C3
            DFB   $C2,$C2,$C3,$C2,$C2,$C2,$C3,$0E,$2D,$0D,$C3,$C2,$C2,$C2,$C3,$C2
            DFB   $C2,$C3,$C2,$C2,$C2,$C2,$C2,$C2,$03,$10,$0E,$C2,$C2,$C2,$03,$14
            DFB   $0E,$C2,$C2,$C2,$02,$18,$0E,$C2,$C2,$02,$2D,$0E,$C2,$C2,$03,$30
            DFB   $0E,$C2,$C2,$C2,$03,$34,$0E,$C2,$C2,$C2,$00

CSPR0D_DATA
            DFB   $04,$18,$0B,$C5,$C5,$C5,$C5,$04,$2B,$0B,$C5,$C5,$C5,$C5,$09,$12
            DFB   $0C,$C5,$C5,$C5,$C5,$C5,$C5,$C6,$C6,$C5,$09,$2C,$0C,$C5,$C6,$C6
            DFB   $C5,$C5,$C5,$C5,$C5,$C5,$04,$01,$0D,$C5,$C5,$C5,$C5,$0E,$0C,$0D
            DFB   $C5,$C5,$C5,$C5,$C5,$C5,$C6,$C4,$C5,$C4,$C4,$C4,$C5,$C5,$0E,$2D
            DFB   $0D,$C5,$C5,$C4,$C4,$C4,$C5,$C4,$C6,$C5,$C5,$C5,$C5,$C5,$C5,$04
            DFB   $42,$0D,$C5,$C5,$C5,$C5,$1A,$00,$0E,$C1,$C4,$C5,$C6,$C6,$C5,$C5
            DFB   $C5,$C5,$C5,$C5,$C5,$C6,$C5,$C4,$C4,$C5,$C4,$C4,$C4,$C4,$C4,$C2
            DFB   $C4,$C2,$C2,$1A,$2D,$0E,$C2,$C2,$C4,$C2,$C4,$C4,$C4,$C4,$C4,$C5
            DFB   $C4,$C4,$C5,$C6,$C5,$C5,$C5,$C5,$C5,$C5,$C5,$C6,$C6,$C5,$C4,$C1
            DFB   $19,$00,$0F,$C2,$C3,$C4,$C4,$C5,$C5,$C5,$C4,$C4,$C4,$C5,$C5,$C5
            DFB   $C4,$C4,$C3,$C4,$C3,$C3,$C4,$C3,$C3,$C2,$C2,$C2,$19,$2E,$0F,$C2
            DFB   $C2,$C2,$C3,$C3,$C4,$C3,$C3,$C4,$C3,$C4,$C4,$C5,$C5,$C5,$C4,$C4
            DFB   $C4,$C5,$C5,$C5,$C4,$C4,$C3,$C2,$17,$00,$10,$C2,$C3,$C3,$C4,$C3
            DFB   $C4,$C4,$C4,$C4,$C4,$C3,$C4,$C4,$C3,$C3,$C3,$C3,$C2,$C2,$C2,$C2
            DFB   $C2,$C2,$17,$30,$10,$C2,$C2,$C2,$C2,$C2,$C2,$C3,$C3,$C3,$C3,$C4
            DFB   $C4,$C3,$C4,$C4,$C4,$C4,$C4,$C3,$C4,$C3,$C3,$C2,$14,$01,$11,$C2
            DFB   $C3,$C2,$C2,$C3,$C4,$C3,$C3,$C3,$C3,$C3,$C2,$C3,$C2,$C2,$C2,$C2
            DFB   $C2,$C2,$C2,$14,$32,$11,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C3,$C2,$C3
            DFB   $C3,$C3,$C3,$C3,$C4,$C3,$C2,$C2,$C3,$C2,$10,$02,$12,$C2,$C2,$C2
            DFB   $C3,$C2,$C3,$C2,$C3,$C2,$C3,$C2,$C2,$C2,$C2,$C2,$C2,$10,$35,$12
            DFB   $C2,$C2,$C2,$C2,$C2,$C2,$C3,$C2,$C3,$C2,$C3,$C2,$C3,$C2,$C2,$C2
            DFB   $0C,$03,$13,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$0C
            DFB   $38,$13,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$C2,$06,$06
            DFB   $14,$C2,$C2,$C2,$C2,$C2,$C2,$06,$3B,$14,$C2,$C2,$C2,$C2,$C2,$C2
            DFB   $00

; =======================================================================
; TL51: TABELLA DI PACKING NIBBLE (PACKLUT) + BENCHMARK TECNICA PEI
; Vedi la spiegazione completa in cima al file (sezione NOVITA').
; =======================================================================

; ---------------------------------------------------------------------
; INIT_PACKLUT: riempie le 65536 voci del banco $04 con
; ((CL&$0F)<<4)|(CR&$0F), indicizzate da CL*256+CR. Sostituisce, in
; GNBG_RENDER, la sequenza AND/ASL x4/ORA per-pixel con un solo LDA
; long indicizzato. Gira una volta sola all'avvio: ~65536 iterazioni,
; stesso ordine di grandezza di INIT_GNBGTBL (64000) - qualche decimo
; di secondo, trascurabile.
; ---------------------------------------------------------------------
INIT_PACKLUT
            REP   #$30
            MX    %00
            STZ   GNBG_TMP          ; CL corrente, 0..255
:ip_cl
            LDA   GNBG_TMP
            AND   #$000F
            ASL   A
            ASL   A
            ASL   A
            ASL   A
            STA   GNBG_TMP2         ; (CL&$0F)<<4, pronto nel byte basso

            STZ   GNBG_TMP3         ; CR corrente, 0..255
:ip_cr
            LDA   GNBG_TMP3
            AND   #$000F
            ORA   GNBG_TMP2         ; valore finale del byte (0..255)
            STA   GNBG_TMP4         ; salvato da parte, ci serve A per l'indice

            LDA   GNBG_TMP          ; ricostruisci l'indice: A = CL*256+CR
            XBA                     ; CL era 0..255 (byte alto=0): XBA -> CL<<8
            ORA   GNBG_TMP3         ; + CR (0..255) = indice completo a 16 bit
            TAX

            LDA   GNBG_TMP4
            SEP   #$20
            MX    %10
            STA   >PACKLUT_BASE,X
            REP   #$30
            MX    %00

            LDA   GNBG_TMP3
            CLC
            ADC   #1
            STA   GNBG_TMP3
            CMP   #$0100
            BNE   :ip_cr

            LDA   GNBG_TMP
            CLC
            ADC   #1
            STA   GNBG_TMP
            CMP   #$0100
            BEQ   :ip_done
            JMP   :ip_cl
:ip_done
            RTS

; ---------------------------------------------------------------------
; INIT_PEI_BENCH: riempie PEI_SRC (128 byte, banco 0) con un pattern
; di prova (0..127) per il confronto PEI_COPY_ONCE / STA_COPY_ONCE.
; ---------------------------------------------------------------------
INIT_PEI_BENCH
            SEP   #$20
            MX    %10
            LDX   #$0000
:ipb_loop   TXA
            STA   PEI_SRC,X
            INX
            CPX   #128
            BNE   :ipb_loop
            REP   #$30
            MX    %00
            RTS

; ---------------------------------------------------------------------
; PEI_COPY_ONCE: la vera tecnica PEI di RAST.SCREEN.S (SCRLUP), portata
; fedelmente qui su due buffer di prova - D=puntatore SORGENTE
; (PEI_SRC), S=puntatore DESTINAZIONE (PEI_DST), un blocco LUP di 64
; PEI srotolato (nessun overhead di indice a runtime). SEI/CLI sono
; OBBLIGATORI: per tutta la durata della funzione S NON e' il vero
; stack pointer, un interrupt che arrivasse qui (es. il player NTP)
; scriverebbe PC/P dentro PEI_DST invece che nello stack vero - crash
; quasi certo.
; ---------------------------------------------------------------------
PEI_COPY_ONCE
            REP   #$30
            MX    %00
            SEI
            PHD
            TSC
            STA   PEI_REAL_S        ; salva il VERO stack pointer

            LDA   #PEI_SRC
            TCD                     ; D = sorgente

            LDA   #PEI_DST+127
            TCS                     ; S = destinazione (vedi nota sotto)

            ; il primo PEI (]ADR=126) legge PEI_SRC[126]/[127] e li
            ; scrive rispettivamente a PEI_DST+126/PEI_DST+127: perche'
            ; questo torni, S iniziale deve essere PEI_DST+127 (il byte
            ; ALTO della coppia va all'indirizzo S di partenza, il
            ; basso a S-1 - PEI/PHA a 16 bit spingono cosi'). Ad ogni
            ; PEI, S scende di 2 e ]ADR pure: restano sempre allineati.
]ADR        EQU   126
            LUP   64
            PEI   ]ADR
]ADR        EQU   ]ADR-2
            --^

            LDA   PEI_REAL_S
            TCS                     ; ripristina il VERO stack pointer
            PLD
            CLI
            RTS

; ---------------------------------------------------------------------
; STA_COPY_ONCE: stesso confronto ma con la tecnica "classica" -
; altrettanto srotolata (nessun registro indice, nessun overhead di
; loop da nessuna delle due parti: e' il confronto piu' onesto
; possibile fra le due tecniche).
; ---------------------------------------------------------------------
STA_COPY_ONCE
            REP   #$30
            MX    %00
]ADR2       EQU   0
            LUP   64
            LDA   PEI_SRC+]ADR2
            STA   PEI_DST+]ADR2
]ADR2       EQU   ]ADR2+2
            --^
            RTS

; ---------------------------------------------------------------------
; PEI_BENCH_DISPATCH: chiamata ogni frame da MAIN_LOOP. Ripete la
; copia di 128 byte PEI_BENCH_REPEATS volte con la tecnica scelta
; (PEI_BENCH_MODE, alternata con SPAZIO - vedi CHECK_KEYBOARD). Se il
; frame rate della demo cambia percepibilmente passando da una
; versione all'altra, questo dice se/quanto la tecnica PEI e' davvero
; piu' veloce per QUESTO TIPO di copia (byte fissi, nessun calcolo per
; byte) - NON e' una misura di GNBG_RENDER, che non puo' usarla (vedi
; NOVITA' in cima al file).
; ---------------------------------------------------------------------
; *** TL51 v2: alzato da 100 a 200 - con 100 la differenza fra le due
; tecniche (poche centinaia di cicli a ripetizione) era troppo piccola
; per notarsi a occhio sul framerate. Con 200 la demo rallenta parecchio
; in ENTRAMBE le modalita' (e' voluto, serve a rendere la differenza
; relativa evidente) ma STA dovrebbe risultare chiaramente piu' lenta
; di PEI. E' un valore di prova: alzalo/abbassalo pure, la stima dei
; cicli qui sopra e' fatta a mano, non misurata su hardware/emulatore.
PEI_BENCH_REPEATS EQU 200

PEI_BENCH_DISPATCH
            REP   #$30
            MX    %00
            LDA   PEI_BENCH_MODE
            BEQ   :pbd_sta

            LDY   #PEI_BENCH_REPEATS
:pbd_peiloop
            JSR   PEI_COPY_ONCE
            DEY
            BNE   :pbd_peiloop
            RTS

:pbd_sta    LDY   #PEI_BENCH_REPEATS
:pbd_staloop
            JSR   STA_COPY_ONCE
            DEY
            BNE   :pbd_staloop
            RTS

PEI_REAL_S  DA    0
PEI_SRC     DS    128
PEI_DST     DS    128

; *** TL59 FIX: vedi commento nel blocco costanti del loader musica.
; Riservati qui, in coda a tutto il resto del programma, cosi'
; l'assemblatore assegna loro indirizzi certamente liberi.
;
; *** TL59B FIX: con TL59 IO_BUFFER finiva a un indirizzo qualunque
; (00/7154 nella build provata) - ma la chiamata MLI OPEN di ProDOS 8
; richiede che io_buffer inizi su un confine di pagina (byte basso
; $00), requisito documentato nel Technical Reference Manual. Con
; l'allineamento sbagliato la OPEN falliva silenziosamente, e la
; gestione errori gia' presente in MUSIC_INIT (pensata per "niente
; musica ma niente crash" in caso di file mancante) saltava pulito a
; :mi_done - musica muta, nessun sintomo visibile. Il padding sotto
; porta l'indirizzo al prossimo multiplo di 256 PRIMA di IO_BUFFER,
; qualunque cosa succeda al resto del file in futuro (nessun numero
; scritto a mano da tenere aggiornato).
; Merlin32 non accetta parentesi nelle espressioni DS (visto in fase di
; assemblaggio) - stesso calcolo scomposto in passi separati, un solo
; operatore per riga, per non dipendere da nessuna precedenza implicita.
BUF_PAGE_PAD
BPP_A       EQU   BUF_PAGE_PAD+255
BPP_B       EQU   BPP_A/256
BPP_C       EQU   BPP_B*256
            DS    BPP_C-BUF_PAGE_PAD
IO_BUFFER   DS    1024      ; buffer I/O ProDOS (ora allineato a pagina)
STAGE_BUF   DS    4096      ; buffer di appoggio caricamento musica
FADETAB     DS    256       ; 256-byte fade table      
TARGET      DS    512       ; 512 bytes: target palettes 

            END
