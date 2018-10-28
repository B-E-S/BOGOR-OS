; Author : Muhammad Quwais Safutra
; @git LeafyIsHereZ



DDPcmd = $42
DDPunit = $43
DDPbuflo = $44
DDPbufhi = $45
DDPblklo = $46
DDPblkhi = $47

CARD = $4E

*-------------------------------------------------
 jmp RW18
*-------------------------------------------------

OFFSET = 16 ;default offset

*-------------------------------------------------
*
* READ/WRITE 18 sectors!
*

READ lda #1
 hex 2C
WRITE lda #2
 sta DDPcmd

* Calculate starting block
* (OFFSET+track*9)

 lda track  ;0-34
 asl
 asl
 asl
 tax  ;x=lo

 lda #0
 rol
 tay  ;y=hi

 txa
 adc track
 tax

 tya
 adc #0
 tay

 txa
 adc #OFFSET
BOFFLO = *-1
 sta BLOCKLO

 tya
 adc #>OFFSET
BOFFHI = *-1
 sta BLOCKHI

* Loop for 18 sectors, 2 at a time.

 ldy #0
:0 tya
 pha

* Do 2 sectors

 lda BUFTABLE,Y
 sta ]rbuf0
 sta ]wbuf0
 ldx BUFTABLE+1,Y
 stx ]rbuf1
 stx ]wbuf1
 dex
 cpx ]rbuf0
 jsr RWSECTS

 pla
 tay

 bcs rts

* Next 2 sectors

 inc BLOCKLO
 bne :1
 inc BLOCKHI

:1 iny
 iny
 cpy #18
 bne :0

 clc
rts rts

*-----------
*
* Read or write 2 sectors
*
* If the two sectors are sequential
* then just go to the Device Driver.
*
RWSECTS beq JMPDD

 ldy DDPcmd
 dey
 bne WSECTS

* Read two non-contiguous sectors

RSECTS lda ]rbuf0
 ora ]rbuf1
 clc
 beq :rts

 jsr JMPDDBUF
 bcs :rts

* Now move them to where they belong

 ldx #$2C  ; bit ABS
 ldy #$99  ; sta ABS,Y

* If this sector is to be ignored,
* then change sta $FF00,Y to bit.

 sty ]rmod0
 lda ]rbuf0
 bne *+5
 stx ]rmod0

 sty ]rmod1
 lda ]rbuf1
 bne *+5
 stx ]rmod1

 ldy #0
:0 lda BLOCKBUF,Y
]rmod0 sta $FF00,Y
]rbuf0 = *-1
 lda BLOCKBUF+256,Y
]rmod1 sta $FF00,Y
]rbuf1 = *-1
 iny
 bne :0
:rts rts

*-----------
*
* Write two non-contiguous sectors
*

WSECTS ldy #0
:0 lda $FF00,Y
]wbuf0 = *-1
 sta BLOCKBUF,Y
 lda $FF00,Y
]wbuf1 = *-1
 sta BLOCKBUF+256,Y
 iny
 bne :0

JMPDDBUF lda #>BLOCKBUF

*-----------
*
* Jump to Device Driver
*
* Enter: A - address of buffer
*

JMPDD sta DDPbufhi

* Set block number

 lda #$11
BLOCKLO = *-1
 sta DDPblklo
 lda #$11
BLOCKHI = *-1
 sta DDPblkhi

* Get address of firmware

 lda slot
 sta DDPunit
 lsr
 lsr
 lsr
 lsr
 ora #$C0
 sta CARD+1
 lda #0
 sta CARD
 sta DDPbuflo

* Get address of Device Driver

 ldy #$FF
 lda (CARD),Y
 sta CARD

* Jump to it!!!

 jmp (CARD)

*------------------------------------------------- RW18
*
* Entry point into RW18
*

RW18 pla
 sta GOTBYTE+1
 pla
 sta GOTBYTE+2

 bit $CFFF

 jsr SWAPZPAG

 jsr GETBYTE
 sta command
 and #$0F
 asl
 tax

 lda cmdadr,X
 sta :1+1
 lda cmdadr+1,X
 sta :1+2
:1 jsr $FFFF

 lda GOTBYTE+2
 pha
 lda GOTBYTE+1
 pha

SWAPZPAG php
 ldx #0
:0 lda zpage,x
 ldy ZPAGSAVE,X
 sta ZPAGSAVE,X
 sty zpage,x
 inx
 cpx #zpagelen
 bne :0
 plp
 rts

cmdadr da SKIP2  ; CMDRIVON
 da rts  ; CMDRIVOF
 da CMseek
 da CMreadseq
 da CMreadgroup
 da CMwriteseq
 da CMwritegroup
 da CMid
 da CMoffset

*------------------------------------------------- CMseek
*
* SEEK
* <check disk for lastrack?>,
* <track>
*
CMseek jsr GETBYTE
 jsr GETBYTE
 sta track
 rts

*------------------------------------------------- CMreadseq
*------------------------------------------------- CMreadgroup
*
* Read sequence
* <buf adr>
*
* Read group
* <18 buf adr's>
*
CMreadseq ldx #1
 hex 2C
CMreadgroup ldx #18
 jsr CMADINFO

CMREAD2 jsr READ

*-------------------------------------------------
*
* READ/WRITE exit.
*
INCTRAK? bit command
 bcs WHOOP?

* If bit 6 set, then inc track

 bvc ]rts
 inc track
]rts rts

* If bit 7 set then whoop speaker
* WARNING:use only with READ

WHOOP? bpl ]rts
 ldy #0
:1 tya
 bit $C030
:2 sec
 sbc #1
 bne :2
 dey
 bne :1
 beq CMREAD2

*------------------------------------------------- CMwriteseq
*------------------------------------------------- CMwritegroup
*
* Same as READ
*

CMwriteseq ldx #1
 hex 2C
CMwritegroup ldx #18
 jsr CMADINFO
 jsr WRITE
 jmp INCTRAK?

*------------------------------------------------- CMid
*
* Change offset based on ID
*

CMid jsr GETBYTE
 sta :IDmod+1

 ldy #-3
:0 iny
 iny
 iny
 lda :IDlist,y
 beq :rts

:IDmod cmp #$11
 bne :0

 lda :IDlist+1,y
 sta BOFFLO
 lda :IDlist+2,y
 sta BOFFHI

:rts rts

:IDlist db $A9
 dw 16 ;side one

 db $AD
 dw 16+315 ;side two

 db 0 ;end of list

*------------------------------------------------- CMoffset
*
* Set new block offset
*

CMoffset jsr GETBYTE
 sta BOFFLO
 jsr GETBYTE
 sta BOFFHI
 rts

*-------------------------------------------------
*
* Get buffer info.
*

CMADINFO stx temp
 ldx #0
:0 jsr GETBYTE
 sta BUFTABLE,X
 inx
 cpx temp
 bcc :0
 tay

* If sequence, then fill table

:1 iny
 cpx #18
 beq :2
 tya
 sta BUFTABLE,X
 inx
 bne :1

:2 rts

*-------------------------------------------------
*
SKIP2 jsr GETBYTE
SKIP1

GETBYTE inc GOTBYTE+1
 bne GOTBYTE
 inc GOTBYTE+2
GOTBYTE lda $FFFF
 rts

*-------------------------------------------------

 sav rw1835

ZPAGSAVE ds $100
BUFTABLE ds 18
 ds \
BLOCKBUF ds 512

*-------------------------------------------------
