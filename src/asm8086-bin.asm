;asm8086-bin.asm

;To build with FASM (Flat Assembler)

;History:
;    31/12/15 23:56    First build.
;    13/01/16 07:47    Relocation types.
;    15/01/16 16:05    8086 translator.
;    16/01/16 07:36    Numeric base.
;             07:55    INT command.
;             08:02    ORG command.
;    17/01/16 08:20    String support.
;    18/01/16 19:02    PUSH/POP commands.
;             22:10    Math instructions (not tested).
;    19/01/16 13:54    INC,DEC,NEG,NOT,RCL,RCR,ROL,
;                      ROR,SAL,SAR,SHL,SHR (not tested).
;    27/03/16 23:49    Proved errors & alone handler.
;    28/03/16 00:26    Implemented hash table.
;    29/03/16 13:21    Implemented binary output.
;             21:45    This file contains 2820 lines.
;    30/03/16 03:51    Implemented object output.
;                      Now file contains 3043 lines.
;             04:14    After some errors were proved it
;                      made 68 bytes TEST.OBJ result.
;    31/03/16 --:--    Detected & proved one error more.
;    ...
;    11/04/16 23:04    Returned back to binary output.
;                      Next implement CALL/JMP and JCC
;                      handlers, complex types (STRUC)
;

	;err

;--------------[scan.inc]--------------;

TkEOL		= 0
TkSYM		= 1
TkNUM		= 2
TkSTR		= 3

TkLABEL 	= 4	;standaside
TkDATA		= 5	;freestyle
TkORG		= 6	;standalone
TkMOV		= 7
TkNOP		= 8
TkINT		= 9
TkPUPO		= 10
TkMATH		= 11
TkINCDEC	= 12
TkNEGNOT	= 13
TkSHIFT 	= 14
TkPTR		= 15	;others
TkTYPE		= 16
TkREG		= 17

TkEQUAL 	= '='
TkCOLON 	= ':'
TkCOMMA 	= ','
TkLBRA		= '['
TkRBRA		= ']'
TkLPAR		= '('
TkRPAR		= ')'
TkPLUS		= '+'
TkMINUS 	= '-'

;-------------[error.inc]--------------;

ERROR:
  .msg		= 0
  .line 	= 2
  .sizeof	= 4

nERROR		= 5

;------------[symbols.inc]------------;

SYMBOL:
  .Next 	= 0
  .Len		= 2
  .Type 	= 3
  .Ofs		= 4
  .Name 	= 6
  .sizeOf	= 6

  .NONE 	= 0
  .BYTE 	= 1
  .WORD 	= 2
  .NEAR 	= 81h

;--------------[word.inc]--------------;

rgBX		= 23h
rgBP		= 25h
rgSI		= 26h
rgDI		= 27h

sgES		= 30h
sgCS		= 31h
sgSS		= 32h
sgDS		= 33h

;-------------[opinfo.inc]-------------;

OPINFO:
  .ID		= 0
  .Segm 	= 1
  .Type 	= 2
  .Size 	= 3
  .rgA		= 4
  .rgB		= 5
  .Ofs		= 6
  .Sym		= 8
  .sizeOf	= 10

opREG		= 0
opMEM		= 1
opVAL		= 2

;--------------[file.inc]--------------;

O_READONLY	= 0
O_READWRITE	= 2

FA_READONLY	= 1
FA_READWRITE	= 0

;--------------[main.asm]--------------;

	use16
	org	100h

	call	process_params

	call	open_source
	call	open_binary

	call	init_reader
	call	init_errors
	call	init_symbols

	call	parse_file

	call	close_binary
	call	close_source

	call	show_statistic
	call	show_symbols_info

    exit:
	call	getch
	mov	ax, 4C00h
	int	21h

;--------------------------------------;

szfmtPassByte	db "%u passes, %u bytes.\n",0

show_statistic:
	push	[binsize]
	xor	ax, ax
	mov	al, [pass]
	push	ax
	mov	si, szfmtPassByte
	call	printf
	ret

;-------------[params.asm]-------------;

emUSAGE 	db "USAGE: asm8086 file.asm\n",0

skpspc:
    .0: mov	al, [si]
	inc	si
	cmp	al, ' '
	je	.0
	dec	si
	ret

skpsym:
    .0: mov	al, [si]
	inc	si
	cmp	al, ' '
	je	.1
	test	al, al
	jnz	.0
    .1: dec	si
	ret

process_params:
	xor	bx, bx		;#
	mov	bl, [80h]
	cmp	bl, 7Fh
	jae	.usage
	mov	si, 81h
	mov	[si+bx], bh
	call	skpspc		;#
	cmp	byte [si], 0
	je	.usage
	mov	[srcname], si
	call	skpsym		;#
	call	skpspc
	cmp	byte [si], 0
	jne	.usage
	cmp	word [si-4], '.a'
	jne	.usage
	cmp	word [si-2], 'sm'
	je	.end
    .usage:
	mov	si, emUSAGE
	call	printf
	jmp	exit
    .end:
	ret

;-------------[source.asm]-------------;

	align	2
srcname 	dw 0
srcfile 	dw -1
emOPENERR	db "can't open input",0

;#throws
open_source:
	mov	si, [srcname]
	mov	al, O_READONLY
	call	OpenFile
	jnc	.0
	push	emOPENERR	;#pre-error
	mov	si, szfmtFATAL
	call	printf
	jmp	exit
    .0: mov	[srcfile], ax
	ret

close_source:
	mov	bx, [srcfile]
	call	CloseFile
	mov	[srcfile], -1
	ret

reset_source:
	xor	ax, ax
	xor	dx, dx
	mov	bx, [srcfile]
	call	SetFilePos
	mov	[lineno], 0
	ret

;-------------[binary.asm]-------------;

	align	2
binname 	dw 0
binfile 	dw 0
binsize 	dw 0,0

loc		dw 0

binbuf		dw 0
binptr		dw 0
binlim		dw 0

emCREATE	db "can't create output",0
emADDRESS	db "code too long",0


open_binary:
	mov	si, [srcname]
	call	strlen
	inc	ax
	mov	cx, ax
	call	malloc
	mov	[binname], ax
    ;copy source name
       ;mov     si, [srcname]
	mov	di, ax
	call	strcpy
    ;change extention to ".bin"
	add	di, ax
	mov	word [di-3], 'bi'
	mov	byte [di-1], 'n'
    ;create object file
	mov	si, [binname]
	mov	al, FA_READWRITE
	call	CreateFile
	jnc	.file
	call	close_source
	push	emCREATE
	mov	si, szfmtFATAL
	call	printf
	jmp	exit
    .file:
	mov	[binfile], ax
    ;allocate buffers
	mov	cx, 32
	mov	[binlim], cx
	call	malloc
	mov	[binbuf], ax
	add	[binlim], ax
	mov	[binptr], ax
	mov	[loc], 0
	ret


reset_binary:
	xor	ax, ax
	xor	dx, dx
	mov	bx, [binfile]
	call	SetFilePos
	mov	ax, [binbuf]
	mov	[binptr], ax
	mov	[loc], 0
	ret


close_binary:
	call	flush_binary
	mov	bx, [binfile]
	mov	si, [binbuf]
	xor	cx, cx
	call	WriteFile
	call	GetFileSize
	mov	[binsize+0], ax
	mov	[binsize+2], dx
	call	CloseFile
	mov	[binfile], -1
	ret


kill_binary:
	mov	bx, [binfile]
	call	CloseFile
	mov	[binfile], -1
	mov	si, [binname]
	call	DeleteFile
	ret


;#return    SI = new buffer position
;#uses      AX,CX,BX,SI
flush_binary:
	push	ax cx
	mov	si, [binbuf]
	mov	cx, [binptr]
	sub	cx, si
	jz	.0
	push	bx
	mov	bx, [binfile]
	call	WriteFile
	mov	[binptr], si
	pop	bx
    .0: pop	cx ax
	ret


;#params    AL = byte to put
putbin:
	push	si
	mov	si, [binptr]
	inc	si
	cmp	si, [binlim]
	jb	.0
	call	flush_binary
	inc	si
    .0: mov	[si-1], al
	mov	[binptr], si
	add	[loc], 1
	jc	address_oveflow
	pop	si
	ret


;#params    AL = byte to put
;           CX = relocatable symbol
putbin_byte:
	jmp	putbin


;#params    AX = word to put
;           CX = relocatable symbol
putbin_word:
	call	putbin
	mov	al, ah
	jmp	putbin

address_oveflow:
	mov	ax, emADDRESS
	jmp	fatal

genbin:
	cmp	[fsegm], 0
	je	.segm
	mov	al, [segm]
	call	putbin
    .segm:
	mov	al, [opcode]
	call	putbin
	cmp	[fpost], 0
	je	.post
	mov	al, [post]
	call	putbin
    .post:
	mov	cx, [osym]
	mov	ax, [ofs]
	cmp	[osz], 1
	jb	.offs
	ja	.offs_word
	call	putbin_byte
	jmp	.offs
    .offs_word:
	call	putbin_word
    .offs:
	mov	cx, [vsym]
	mov	ax, [val]
	cmp	[vsz], 1
	jb	.value
	ja	.value_word
	call	putbin_byte
	jmp	.value
    .value_word:
	call	putbin_word
    .value:
	ret

;--------------[fatal.asm]-------------;

szfmtFATAL	db "FATAL: %s.\n",0

fatal:
	push	ax
	call	close_source
	call	kill_binary
	mov	si, szfmtFATAL
	call	printf
	call	show_errors
	jmp	exit

;--------------[error.asm]-------------;

	align	2
ErrNum		dw 0
ErrBuf		dw 0
ErrCnt		dw 0
ErrPtr		dw 0
emERRLIM	db "error limit exceeded",0
szfmtERROR	db "ERROR(%d): %s.\n",0


;#uses      AX,CX
init_errors:
	mov	[ErrNum], nERROR
	mov	ax, ERROR.sizeof
	mul	word [ErrNum]
	mov	cx, ax
	call	malloc
	mov	[ErrBuf], ax
	mov	[ErrPtr], ax
	mov	[ErrCnt], 0
	ret

;#params    AX = error message
;#throws
error:
	push	bx
	mov	bx, [ErrCnt]
	cmp	bx, [ErrNum]
	jb	.0
	mov	ax, emERRLIM
	jmp	fatal
    .0: inc	[ErrCnt]
	mov	bx, [ErrPtr]
	mov	[bx+ERROR.msg], ax
	mov	ax, [lineno]
	mov	[bx+ERROR.line], ax
	lea	bx, [bx+ERROR.sizeof]
	mov	[ErrPtr], bx
	pop	bx
	ret

;#uses      BX,CX,SI
show_errors:
	mov	cx, [ErrCnt]
	test	cx, cx
	jz	.0
	mov	bx, [ErrBuf]
	mov	si, szfmtERROR
    .1: push	word [bx+ERROR.msg]
	push	word [bx+ERROR.line]
	call	printf
	lea	bx, [bx+ERROR.sizeof]
	dec	cx
	jnz	.1
    .0: ret

;--------------------------------------;

	align	2
lineno		dw 0
linebuf 	dw 0
lineptr 	dw 0
emEMPTY 	db "source file empty",0


;#uses      ax,cx
init_reader:
	mov	cx, 80
	call	malloc
	mov	[linebuf], ax
	ret

readsource:
	call	readline
	jnz	.0
	mov	ax, emEMPTY
	jmp	fatal
    .0: ret

readline:
	mov	bx, [srcfile]
	mov	di, [linebuf]
	mov	cx, 80
	call	fgets
	test	cx, cx
	jz	.end
	inc	[lineno]
    .end:
	mov	ax, [linebuf]
	mov	[lineptr], ax
	test	cx, cx
	ret

; @params  BX - File Handle
;          DI - Destination Buffer
;          CX - Buffer Size/String Limit
; @return  BX,DI - Initial Values
;          AX,DX,BP - Used & not modified
;          CX - Number of Bytes were read
;          if CX == 0 then was EOF
; @note    Every read-in line ends with EOL 0Ah marker
fgets:
	push	bp
	push	ax
	push	dx
	push	di
	push	cx
	mov	bp, sp
	mov	dx, .ch
	mov	cx, 1
    .next:
	mov	ah, 3Fh
	int	21h
	jc	.err
	cmp	ax, cx
	jb	.done
	mov	al, [.ch]
	cmp	al, 0Ah
	je	.done
	mov	[di], al
	inc	di
	dec	word [bp]
	jnz	.next
	dec	di
	mov	cx, 1
	mov	dx, .ch
    .truncate:
	mov	ah, 3Fh
	int	21h
	jc	.err
	cmp	ax, cx
	jb	.done
	cmp	byte [.ch], 0Ah
	jne	.truncate
    .done:
	mov	byte [di], 0Ah
	mov	cx, di
	pop	di
	pop	di
	sub	cx, di
	pop	dx
	pop	ax
	pop	bp
	ret
    .err:
	mov	ax, emREADERROR
	jmp	fatal
    .ch:
	dw	0

emREADERROR	db "error reading input",0

;--------------[scan.asm]--------------;

	align	2
tokptr		dw 0
toklen		dw 0
tokval		dw 0
ahead		db 0

emILLINP	db "illegal input",0
emQUOTE 	db "missing end quote",0
emSTRLEN	db "empty string",0

scan:
	push	ax
	push	si
	mov	si, [lineptr]
	xor	ax, ax
	inc	ax
	mov	[toklen], ax
    .next:
	mov	[tokptr], si
	mov	al, [si]
	inc	si
	cmp	al, ' '
	je	.next
	cmp	al, 9
	je	.next
	cmp	al, 10
	je	.EOL
	cmp	al, 13
	je	.skip
	cmp	al, ';'
	je	.skip
	cmp	al, '"'
	je	.str
	cmp	al, "'"
	je	.str
	call	isalnum
	jnc	.seq
	call	issym
	je	.end
	mov	ax, emILLINP
	call	error
	jmp	.next
    .end:
	mov	[lineptr], si
    .quit:
	mov	[ahead], al
	pop	si
	pop	ax
	ret
    .skip:
	mov	al, [si]
	inc	si
	cmp	al, 10
	jne	.skip
    .EOL:
	dec	si
	mov	al, TkEOL
	jmp	.end
    .str:
	mov	[tokptr], si
	mov	ah, al
    .strloop:
	mov	al, [si]
	inc	si
	cmp	al, 10
	je	.strerr
	cmp	al, ah
	jne	.strloop
	lea	ax, [si-1]
	sub	ax, [tokptr]
	jz	.strlen
	mov	[toklen], ax
	mov	al, TkSTR
	jmp	.end
    .strlen:
	mov	ax, emSTRLEN
	jmp	fail
    .strerr:
	mov	ax, emQUOTE
	jmp	fail
    .seq:
	mov	al, [si]
	inc	si
	call	isalnum
	jnc	.seq
	push	cx
	lea	cx, [si-1]
	mov	[lineptr], cx
	mov	si, [tokptr]
	sub	cx, si
	mov	[toklen], cx
	mov	al, [si]
	call	isdigit
	jnc	.num
	call	lookup
	jnc	.word
	call	lookfor
	pop	cx
	mov	[tokval], ax
	mov	al, TkSYM
	jmp	.quit
    .word:
	pop	cx
	mov	byte [tokval], ah
	jmp	.quit
    .num:
	call	connum
	pop	cx
	mov	[tokval], ax
	mov	al, TkNUM
	jmp	.quit

;-------------[ctype.asm]--------------;

isalnum:
	cmp	al, '@'
	je	.0
	cmp	al, '$'
	je	.0
	cmp	al, '_'
	je	.0
	cmp	al, '?'
	je	.0
	cmp	al, '0'
	jb	.1
	cmp	al, '9'
	jbe	.0
	cmp	al, 'A'
	jb	.1
	cmp	al, 'Z'
	jbe	.0
	cmp	al, 'a'
	jb	.1
	cmp	al, 'z'
	ja	.1
    .0: clc
	ret
    .1: stc
	ret

isdigit:
	cmp	al, '0'
	jb	.1
	cmp	al, '9'
	ja	.1
    .0: clc
	ret
    .1: stc
	ret

issym:
	cmp	al, '='
	je	.0
	cmp	al, ':'
	je	.0
	cmp	al, ','
	je	.0
	cmp	al, '['
	je	.0
	cmp	al, ']'
	je	.0
	cmp	al, '('
	je	.0
	cmp	al, ')'
	je	.0
	cmp	al, '+'
	je	.0
	cmp	al, '-'
    .0: ret

;-------------[words.asm]--------------;

LWord:
	db 3, "mov",   TkMOV,	 0
	db 3, "nop",   TkNOP,	 90h
	db 3, "ret",   TkNOP,	 0C3h
	db 3, "int",   TkINT,	 0
	db 4, "push",  TkPUPO,	 0FFh
	db 3, "pop",   TkPUPO,	 8Fh
	db 3, "add",   TkMATH,	 0
	db 2, "or",    TkMATH,	 1
	db 3, "adc",   TkMATH,	 2
	db 3, "sbb",   TkMATH,	 3
	db 3, "and",   TkMATH,	 4
	db 3, "sub",   TkMATH,	 5
	db 3, "xor",   TkMATH,	 6
	db 3, "cmp",   TkMATH,	 7
	db 3, "inc",   TkINCDEC, 0
	db 3, "dec",   TkINCDEC, 1
	db 3, "not",   TkNEGNOT, 2
	db 3, "neg",   TkNEGNOT, 3
	db 3, "mul",   TkNEGNOT, 4
	db 4, "imul",  TkNEGNOT, 5
	db 3, "div",   TkNEGNOT, 6
	db 4, "idiv",  TkNEGNOT, 7
	db 3, "rol",   TkSHIFT,  0
	db 3, "ror",   TkSHIFT,  1
	db 3, "rcl",   TkSHIFT,  2
	db 3, "rcr",   TkSHIFT,  3
	db 3, "sal",   TkSHIFT,  4
	db 3, "shl",   TkSHIFT,  4
	db 3, "shr",   TkSHIFT,  5
	db 3, "sar",   TkSHIFT,  7
	db 2, "db",    TkDATA,	 1
	db 2, "dw",    TkDATA,	 2
	db 5, "label", TkLABEL,  0
	db 3, "org",   TkORG,	 0
	db 3, "ptr",   TkPTR,	 0
	db 4, "byte",  TkTYPE,	 SYMBOL.BYTE
	db 4, "word",  TkTYPE,	 SYMBOL.WORD
	db 4, "near",  TkTYPE,	 SYMBOL.NEAR
	db 2, "al",    TkREG,	 10h
	db 2, "cl",    TkREG,	 11h
	db 2, "dl",    TkREG,	 12h
	db 2, "bl",    TkREG,	 13h
	db 2, "ah",    TkREG,	 14h
	db 2, "ch",    TkREG,	 15h
	db 2, "dh",    TkREG,	 16h
	db 2, "bh",    TkREG,	 17h
	db 2, "ax",    TkREG,	 20h
	db 2, "cx",    TkREG,	 21h
	db 2, "dx",    TkREG,	 22h
	db 2, "bx",    TkREG,	 rgBX
	db 2, "sp",    TkREG,	 24h
	db 2, "bp",    TkREG,	 rgBP
	db 2, "si",    TkREG,	 rgSI
	db 2, "di",    TkREG,	 rgDI
	db 2, "es",    TkREG,	 sgES
	db 2, "cs",    TkREG,	 sgCS
	db 2, "ss",    TkREG,	 sgSS
	db 2, "ds",    TkREG,	 sgDS
	db 0

;@params  SI: const char*
;         AX: const int
;@return  CF=0,
;           AL: class
;           AH: value
lookup:
	push	bx
	push	di
	mov	di, LWord
    .Next:
	xor	bx, bx
	add	bl, [di]
	jz	.NotFound
	cmp	bx, cx
	je	.Check
	lea	di, [bx+di+1+2]
	jmp	.Next
    .Recover:
	add	di, cx
	inc	di
	inc	di
	jmp	.Next
    .Check:
	xor	bx, bx
	inc	di
    .Compare:
	mov	al, [bx+di]
	cmp	al, [bx+si]
	jne	.Recover
	inc	bx
	cmp	bx, cx
	jb	.Compare
    .Found:
	mov	ax, [bx+di]
	clc
	jmp	.End
    .NotFound:
	stc
    .End:
	pop	di
	pop	bx
	ret

;-------------[connum.asm]-------------;

connum:
	push	cx
	push	dx
	push	bx
	push	bp
	push	si
	mov	bp, cx
    ;check base
	mov	bx, 10
	cmp	bp, 2
	jb	.bas
	mov	al, [ds:si+(bp-1)]
	cmp	al, 'a'
	jb	.chk
	cmp	al, 'z'
	ja	.chk
	add	al, 'A'-'a'
    .chk:
	cmp	al, 'B'
	je	.bin
	cmp	al, 'O'
	je	.oct
	cmp	al, 'D'
	je	.dec
	cmp	al, 'H'
	jne	.bas
    .hex:
	mov	bl, 16
	jmp	.suf
    .bin:
	mov	bl, 2
	jmp	.suf
    .oct:
	mov	bl, 8
	jmp	.suf
    .dec:
	mov	bl, 10
    .suf:
	dec	bp
    .bas:
	xor	ax, ax
	xor	cx, cx
	xor	dx, dx
    .cnv:
	mov	cl, [si]
	inc	si
	cmp	cl, '_'
	je	.nxt
	cmp	cl, 'a'
	jb	.cnt
	cmp	cl, 'z'
	ja	.cnt
	add	cl, 'A'-'a'
    .cnt:
	sub	cl, '0'
	cmp	cl, 10
	jb	.dig
	sub	cl, 7
    .dig:
	cmp	cl, bl
	jae	.NaN
	mul	bx
	jc	.Overflow
       ;jo      .Overflow
	add	ax, cx
	js	.Overflow
    .nxt:
	dec	bp
	jnz	.cnv
    .ext:
	pop	si
	pop	bp
	pop	bx
	pop	dx
	pop	cx
	ret
    .NaN:
	mov	ax, emINVNUM
	jmp	.3
    .Overflow:
	mov	ax, emVALUE
    .3: call	error
	mov	ax, 0x7F
	jmp	.ext

emINVNUM	db "invalid number",0
emVALUE 	db "value too large",0

;------------[symbols.asm]-------------;

	align	2
hashmap 	dw 0
hashbuf 	dw 0
hashptr 	dw 0
hashlim 	dw 0
entcount	dw 0
symcount	dw 0
szfmtSYMINFO	db "Symbols Debug Information\n"
		db "    Number of entries: %u\n"
		db "    Number of symbols: %u\n"
		db "    Heap usage: %u of %u bytes\n",0
emHASHLIM	db "out of symbol hash",0


;#uses      AX,BX,CX,SI
init_symbols:
	mov	cx, 256*2	;#alloc
	call	malloc
	mov	[hashmap], ax
	mov	bx, ax		;#clear
	mov	si, (256-1)*2
	xor	ax, ax
    .0: mov	[bx+si], ax
	dec	si
	dec	si
	jns	.0
	mov	cx, 512 	;#alloc
	mov	[hashlim], cx
	call	malloc
	mov	[hashbuf], ax
	mov	[hashptr], ax
	add	[hashlim], ax
	ret

show_symbols_info:
	mov	ax, [hashlim]
	sub	ax, [hashbuf]
	push	ax
	mov	ax, [hashptr]
	sub	ax, [hashbuf]
	push	ax
	push	word [symcount]
	push	word [entcount]
	mov	si, szfmtSYMINFO
	call	printf
	ret

;#params    SI = name
;           CX = length
;#return    AX = symbol address
;#throws
lookfor:
	push	bx di
	call	fn$hashcode
	xor	bx, bx
	mov	bl, al
	shl	bx, 1
	add	bx, [hashmap]
	mov	di, [bx]
	test	di, di
	jnz	.search
	inc	word [entcount]
	call	fn$addsym
	mov	[bx], di
	jmp	.end
    .search:
	cmp	cl, [di+SYMBOL.Len]
	jne	.skip
	push	bx
	mov	bx, cx
	dec	bx
    .compare:
	mov	al, [si+bx]
	cmp	al, [di+SYMBOL.Name+bx]
	jne	.next
	dec	bx
	jns	.compare
	pop	bx
	jmp	.end
    .next:
	pop	bx
    .skip:
	cmp	word [di+SYMBOL.Next], 0
	je	.append
	mov	di, [di+SYMBOL.Next]
	jmp	.search
    .append:
	mov	bx, di
	call	fn$addsym
	mov	[bx+SYMBOL.Next], di
    .end:
	mov	ax, di
	pop	di bx
	ret

;#params    SI = name
;           CX = length
;#return    AL = hash code
fn$hashcode:
	push	bx
	xor	bx, bx
	xor	al, al
    .0: shl	al, 1
	xor	al, [si+bx]
	inc	bx
	cmp	bx, 4
	jae	.1
	cmp	bx, cx
	jb	.0
    .1: pop	bx
	ret

;#params    SI = name
;           CX = length
;#return    AX = symbol address
;#throws
fn$addsym:
	inc	word [symcount]
	mov	di, [hashptr]
	lea	ax, [di+SYMBOL.sizeOf]
	add	ax, cx
	cmp	ax, [hashlim]
	jbe	.bufok
	mov	ax, emHASHLIM
	jmp	fatal
    .bufok:
	mov	[hashptr], ax
	xor	ax, ax
	mov	[di+SYMBOL.Next], ax
	mov	[di+SYMBOL.Type], al
	mov	[di+SYMBOL.Ofs], ax
	mov	[di+SYMBOL.Len], cl
	push	bx
	mov	bx, cx
	dec	bx
    .copy:
	mov	al, [si+bx]
	mov	[di+SYMBOL.Name+bx], al
	dec	bx
	jns	.copy
	pop	bx
	ret

;-------------[parse.asm]--------------;

dirty		db 0
pass		db 0
maxpass 	db 0
emERROR 	db "source has errors",0
emPASS		db "pass limit exceeded",0
emINTERNAL	db "internal error",0

parse_file:
	mov	[maxpass], 4
	mov	[pass], 1
	mov	[dirty], 1
    .next:
	call	readsource
    .loop:
	call	parse
	call	readline
	jnz	.loop
	cmp	[ErrCnt], 0
	jne	.error
	cmp	[dirty], 0
	je	.end
    .cont:
	inc	[pass]		;#init_p1p2
	mov	al, [pass]
	cmp	al, [maxpass]
	ja	.pass
	mov	[dirty], 0
	call	reset_source
	call	reset_binary
	jmp	.next
    .error:
	mov	ax, emERROR
	jmp	fatal
    .pass:
	mov	ax, emPASS
	jmp	fatal
    .end:
	ret

;-------------[parse.asm]--------------;

sp_backup	dw 0

fail:
	call	error
	mov	sp, [sp_backup]
	ret

;--------------------------------------;

object_code_ready db 0
emJUNK		db "junk after operands",0

parse:
	mov	[sp_backup], sp
	xor	ax, ax
	mov	[fsegm], al
	mov	[fpost], al
	mov	[opcode], 90h
	mov	[osz], al
	mov	[vsz], al
	mov	[object_code_ready], al
    .begin:
	call	scan
	cmp	[ahead], TkSYM
	jne	.0
	mov	bx, [tokval]
	call	scan
	call	aside
	jmp	.1
    .0: cmp	[ahead], TkEOL
	je	.3
	call	alone
    .1: cmp	[ahead], TkEOL
	je	.2
	mov	ax, emJUNK
	call	error
    .2: cmp	[object_code_ready], 0
	jne	.3
	call	genbin
    .3: ret

;--------------------------------------;

emASIDE 	db "need ASIDE command",0

aside:
	mov	al, [ahead]
	cmp	al, TkCOLON
	je	.colon
	cmp	al, TkLABEL
	je	.label
	cmp	al, TkDATA
	je	.data
	mov	ax, emASIDE
	jmp	fail

    .colon:
       ;call    scan
	mov	al, SYMBOL.NEAR
	call	declare
	pop	ax
	jmp	parse.begin

    .label:
	call	scan
	cmp	[ahead], TkTYPE
	je	.type
	mov	al, SYMBOL.NEAR
	jmp	.typeok
    .type:
	mov	al, byte [tokval]
	call	scan
    .typeok:
	jmp	declare

    .data:
	mov	[object_code_ready], 1
	mov	al, byte [tokval]
	mov	[opsize], al
	call	scan
	call	declare
	jmp	varlist

;--------------------------------------;

emDEFINED	db "symbol already defined",0

declare:
	cmp	byte [bx+SYMBOL.Type], 0
	mov	[bx+SYMBOL.Type], al
	je	.0
	cmp	[pass], 1
	jne	.0
	mov	ax, emDEFINED
	call	error
    .0: mov	ax, [loc]
	cmp	[pass], 1
	je	.1
	cmp	ax, [bx+SYMBOL.Ofs]
	je	.1
	mov	[dirty], 1
    .1: mov	[bx+SYMBOL.Ofs], ax
	ret

;--------------------------------------;

	align	2
alone_map	dw asmvar,asmorg,asmmov,asmnop
		dw asmint,pushpop,asmmath,incdec
		dw negnot,shift

emALONE 	db "need ALONE command",0

alone:
	xor	bx, bx
	mov	bl, [ahead]
	cmp	bl, TkDATA
	jb	.0
	cmp	bl, TkSHIFT
	jbe	.1
    .0: mov	ax, emALONE
	jmp	fail
    .1: lea	bx, [bx-TkDATA]
	shl	bx, 1
	push	word [alone_map+bx]
	mov	ax, [tokval]
	mov	[opcode], al
	jmp	scan

asmvar:
	mov	[object_code_ready], 1
	mov	[opsize], al
	jmp	varlist

asmnop:
       ;mov     [opcode], al
	ret

asmint:
	mov	bx, target
	call	getea
	cmp	byte [bx+OPINFO.ID], opVAL
	je	.0
    .1: mov	ax, emOPERAND
	jmp	fail
    .0: cmp	word [bx+OPINFO.Sym], 0
	jne	.1
	mov	al, [bx+OPINFO.Ofs+1]
	test	al, 80h
	jnz	.1
	mov	[opsize], 1
	mov	[opcode], 0CDh
	mov	al, 0
	jmp	buildimm

asmorg:
	mov	[object_code_ready], 1
	mov	bx, target
	call	getea
	cmp	byte [bx+OPINFO.ID], opVAL
	je	.2
    .3: mov	ax, emOPERAND
	jmp	fail
    .2: cmp	word [bx+OPINFO.Sym], 0
	jne	.3
	mov	ax, [bx+OPINFO.Ofs]
	mov	[loc], ax
	ret

;------------[varlist.asm]-------------;

	align	2
saved:
  .lineptr	dw 0
  .tokptr	dw 0
  .toklen	dw 0
  .tokval	dw 0
  .ahead	db 0

emOPERAND	db "illegal operand",0

savetok:
	mov	ax, [lineptr]
	mov	[saved.lineptr], ax
	mov	ax, [tokptr]
	mov	[saved.tokptr], ax
	mov	ax, [toklen]
	mov	[saved.toklen], ax
	mov	ax, [tokval]
	mov	[saved.tokval], ax
	mov	al, [ahead]
	mov	[saved.ahead], al
	ret

loadtok:
	mov	ax, [saved.lineptr]
	mov	[lineptr], ax
	mov	ax, [saved.tokptr]
	mov	[tokptr], ax
	mov	ax, [saved.toklen]
	mov	[toklen], ax
	mov	ax, [saved.tokval]
	mov	[tokval], ax
	mov	al, [saved.ahead]
	mov	[ahead], al
	ret

varlist:
	sub	sp, OPINFO.sizeOf
	mov	bx, sp
    .0: cmp	[ahead], TkSTR
	jne	.2
	cmp	[opsize], 1
	jne	.2
	call	savetok
	call	scan
	cmp	[ahead], TkCOMMA
	je	.3
	cmp	[ahead], TkEOL
	je	.3
	call	loadtok
	jmp	.2
    .3: mov	si, [saved.tokptr]
	mov	cx, [saved.toklen]
    .4: mov	al, [si]
	inc	si
	push	cx
	call	putbin
	pop	cx
	dec	cx
	jnz	.4
	jmp	.5
    .2: call	e1
	call	chknum
	call	chkval
	call	outval
    .5: cmp	[ahead], TkCOMMA
	jne	.1
	call	scan
	jmp	.0
    .1: add	sp, OPINFO.sizeOf
	ret

chknum:
	cmp	byte [bx+OPINFO.rgA], 0
	je	.0
	mov	ax, emOPERAND
	jmp	fail
    .0: ret

chkval:
	cmp	word [bx+OPINFO.Sym], 0
	jne	.2
	mov	ax, [bx+OPINFO.Ofs]
	call	abs
	test	ah, ah
	jnz	.2
       ;cmp     ax, 127
       ;ja      .2
    .1: mov	al, 1
	jmp	.0
    .2: mov	al, 2
    .0: cmp	al, [opsize]
	jbe	.3
	mov	ax, emVALUE
	jmp	fail
    .3: ret

outval:
	mov	cx, [bx+OPINFO.Sym]
	mov	ax, [bx+OPINFO.Ofs]
	cmp	[opsize], 2
	jb	.b
	jmp	putbin_word
    .b: jmp	putbin_byte

;-------------[asmmov.asm]-------------;

	align	2
target		db OPINFO.sizeOf dup(0)
source		db OPINFO.sizeOf dup(0)

emSOURCE	db "need source operand",0
emBADSIZE	db "operands sizes disagree",0
emILLSIZE	db "illegal operation size",0
emOPSIZE	db "operation size not specified",0

asmmov:
	mov	bx, target
	call	getea
	mov	si, bx
	cmp	[ahead], TkCOMMA
	je	.comma
	mov	ax, emSOURCE
	jmp	fail
    .comma:
	call	scan
	mov	bx, source
	call	getea
	mov	al, [si+OPINFO.Size]
	mov	ah, [bx+OPINFO.Size]
	test	ax, ax
	jz	.nosize
	test	ah, ah
	jz	.sizeok
	test	al, al
	jnz	.check
	mov	al, ah
	jmp	.sizeok
    .check:
	cmp	al, ah
	je	.sizeok
	mov	ax, emBADSIZE
	jmp	fail
    .sizeok:
	cmp	al, [codesize]
	jbe	.legal
	mov	ax, emILLSIZE
	jmp	fail
    .legal:
	mov	[weight], 1
	cmp	al, 1
	jne	.opsizeok
	mov	[weight], 0
	jmp	.opsizeok
    .nosize:
	cmp	[pass], 1
	je	.forgive
	mov	ax, emOPSIZE
	jmp	fail
    .forgive:
	mov	al, [codesize]
	mov	[weight], 1
    .opsizeok:
	mov	[opsize], al
	cmp	byte [si+OPINFO.ID], opVAL
	jne	.targetok
	mov	ax, emOPERAND
	jmp	fail
    .targetok:
	cmp	byte [bx+OPINFO.ID], opVAL
	jne	.RM
    .RMI:
	cmp	byte [si+OPINFO.ID], opREG
	jne	.rmok
	mov	al, [si+OPINFO.rgA]
	and	al, 0xF0
	cmp	al, 0x10
	je	.rmok
	cmp	al, 0x20
	je	.rmok
	mov	ax, emOPERAND
	jmp	fail
    .rmok:
	mov	al, [weight]
	or	al, 0xC6
	mov	[opcode], al
	mov	al, 0
	call	buildimm
	mov	bx, si
	mov	al, 0
	jmp	buildrm
    .RM:
	mov	al, [si+OPINFO.ID]
	cmp	al, [bx+OPINFO.ID]
	jne	.xy
    .xx:
	cmp	al, opMEM
	jne	.xxok
	mov	ax, emOPERAND
	jmp	fail
    .xxok:
	mov	[dsv], 2
	mov	al, [bx+OPINFO.rgA]
	and	al, 0xF0
	cmp	al, 0x30
	jne	.xx.noswap
	mov	[dsv], 0
	xchg	bx, si
    .xx.noswap:
	mov	al, [bx+OPINFO.rgA]
	and	al, 0xF0
	cmp	al, 0x30
	jne	.xy.noswap
	mov	ax, emOPERAND
	jmp	fail
    .xy:
	mov	[dsv], 2
	cmp	byte [si+OPINFO.ID], opREG
	je	.xy.noswap
	mov	[dsv], 0
	xchg	bx, si
    .xy.noswap:
	mov	al, [si+OPINFO.rgA]
	and	al, 0xF0
	cmp	al, 0x30
	jne	.xy.gpreg
    .xy.spreg:
	mov	al, [dsv]
	or	al, 0x8C
	jmp	.xy.opcode
    .xy.gpreg:
	mov	al, [weight]
	or	al, [dsv]
	or	al, 0x88
    .xy.opcode:
	mov	[opcode], al
	mov	al, [si+OPINFO.rgA]
	jmp	buildrm

;------------[pushpop.asm]-------------;

;POP    8F /0   (07 sg)
;PUSH   FF /6   (06 sg)
pushpop:
	mov	bx, target
	call	getea
	mov	al, [bx+OPINFO.Size]
	test	al, al
	jz	.nosize
	cmp	al, 2
	je	.legal
	mov	ax, emILLSIZE
	jmp	fail
    .nosize:
	cmp	byte [bx+OPINFO.ID], opVAL
	je	.forgive
	cmp	[pass], 1
	je	.forgive
	mov	ax, emOPSIZE
	jmp	fail
    .forgive:
	mov	al, 2
    .legal:
	mov	[opsize], al
	cmp	[opcode], 8Fh
	jne	.push
    .pop:
	cmp	byte [bx+OPINFO.ID], opVAL
	jne	.yOK
	mov	ax, emOPERAND
	jmp	fail
    .yOK:
	cmp	byte [bx+OPINFO.ID], opREG
	jne	.popRM
	mov	al, [bx+OPINFO.rgA]
	and	al, 0F0h
	cmp	al, 30h
	jne	.popRM
    .popSEG:
	mov	al, [bx+OPINFO.rgA]
	cmp	al, sgCS
	jne	.ySRegOK
	mov	ax, emOPERAND
	jmp	fail
    .ySRegOK:
	and	al, 3
	shl	al, 3
	or	al, 7
	mov	[opcode], al
	ret
    .popRM:
       ;mov     [opcode], 8Fh
	mov	al, 0
	jmp	buildrm
    .push:
	cmp	byte [bx+OPINFO.ID], opVAL
	jne	.pushIND
	mov	al, 1
	call	buildimm
	mov	al, [dsv]
	or	al, 68h
	mov	[opcode], al
	ret
    .pushIND:
	cmp	byte [bx+OPINFO.ID], opREG
	jne	.pushRM
	mov	al, [bx+OPINFO.rgA]
	and	al, 0F0h
	cmp	al, 30h
	jne	.pushRM
	mov	al, [bx+OPINFO.rgA]
	and	al, 3
	shl	al, 3
	or	al, 6
	mov	[opcode], al
	ret
    .pushRM:
       ;mov     [opcode], 0FFh
	mov	al, 6
	jmp	buildrm

;------------[asmmath.asm]-------------;

;ADD     00dw, 80sw /0 (0*8=0)
;OR      08dw, 80sw /1 (1*8=8)
;ADC     10dw, 80sw /2 ...
;SBB     18dw, 80sw /3
;AND     20dw, 80sw /4
;SUB     28dw, 80sw /5
;XOR     30dw, 80sw /6
;CMP     38dw, 80sw /7 (7*8=38h)

asmmath:
	mov	bx, target
	call	getea
	mov	si, bx
	cmp	[ahead], TkCOMMA
	je	.comma
	mov	ax, emSOURCE
	jmp	fail
    .comma:
	call	scan
	mov	bx, source
	call	getea
	mov	al, [si+OPINFO.Size]
	mov	ah, [bx+OPINFO.Size]
	test	ax, ax
	jz	.nosize
	test	ah, ah
	jz	.sizeok
	test	al, al
	jnz	.check
	mov	al, ah
	jmp	.sizeok
    .check:
	cmp	al, ah
	je	.sizeok
	mov	ax, emBADSIZE
	jmp	fail
    .sizeok:
	cmp	al, [codesize]
	jbe	.legal
	mov	ax, emILLSIZE
	jmp	fail
    .legal:
	mov	[weight], 1
	cmp	al, 1
	jne	.opsizeok
	mov	[weight], 0
	jmp	.opsizeok
    .nosize:
	cmp	[pass], 1
	je	.forgive
	mov	ax, emOPSIZE
	jmp	fail
    .forgive:
	mov	al, [codesize]
	mov	[weight], 1
    .opsizeok:
	mov	[opsize], al
	cmp	byte [si+OPINFO.ID], opVAL
	jne	.targetok
	mov	ax, emOPERAND
	jmp	fail
    .targetok:
	cmp	byte [bx+OPINFO.ID], opVAL
	je	.RMI
    .RM:
	mov	[dsv], 2
	cmp	byte [si+OPINFO.ID], opREG
	je	.xy.noswap
	mov	[dsv], 0
	xchg	bx, si
    .xy.noswap:
	cmp	byte [si+OPINFO.ID], opREG
	je	.xy.ok
	mov	ax, emOPERAND
	jmp	fail
    .xy.ok:
	mov	al, [si+OPINFO.rgA]
	and	al, 0F0h
	cmp	al, 30h
	jne	.yok
	mov	ax, emOPERAND
	jmp	fail
    .yok:
	cmp	byte [bx+OPINFO.ID], opREG
	jne	.xok
	mov	al, [bx+OPINFO.rgA]
	and	al, 0F0h
	cmp	al, 30h
	jne	.xok
	mov	ax, emOPERAND
	jmp	fail
    .xok:
	mov	al, [opcode]
	shl	al, 3
	or	al, [weight]
	or	al, [dsv]
	mov	[opcode], al
	mov	al, [si+OPINFO.rgA]
	jmp	buildrm
    .RMI:
	cmp	byte [si+OPINFO.ID], opREG
	jne	.rmok
	mov	al, [si+OPINFO.rgA]
	and	al, 0F0h
	cmp	al, 30h
	jne	.rmok
	mov	ax, emOPERAND
	jmp	fail
    .rmok:
	mov	al, 1
	call	buildimm
	mov	ah, [opcode]
	mov	al, [weight]
	or	al, [dsv]
	or	al, 80h
	mov	[opcode], al
	mov	al, ah
	mov	bx, si
	jmp	buildrm

;-------------[incdec.asm]-------------;

;INC    FEw /0
;DEC    FEw /1
incdec:
	mov	bx, target
	call	getea
	cmp	byte [bx+OPINFO.ID], opVAL
	jne	.idOk
	mov	ax, emOPERAND
	jmp	fail
    .idOk:
	mov	al, [bx+OPINFO.Size]
	test	al, al
	jnz	.check
	cmp	[pass], 1
	je	.forgive
	mov	ax, emOPSIZE
	jmp	fail
    .forgive:
	mov	al, 2
	mov	[weight], 1
	jmp	.sizeok
    .check:
	cmp	al, 2
	jbe	.legal
	mov	ax, emILLSIZE
	jmp	fail
    .legal:
	mov	[weight], 1
	cmp	al, 2
	je	.sizeok
	mov	[weight], 0
    .sizeok:
	mov	[opsize], al
	mov	al, [opcode]
	call	buildrm
	mov	al, [weight]
	or	al, 0FEh
	mov	[opcode], al
	ret

;-------------[negnot.asm]-------------;

;NEG    F6w /3
;NOT    F6w /2
negnot:
	mov	bx, target
	call	getea
	cmp	byte [bx+OPINFO.ID], opVAL
	jne	.idOk
	mov	ax, emOPERAND
	jmp	fail
    .idOk:
	mov	al, [bx+OPINFO.Size]
	test	al, al
	jnz	.check
	cmp	[pass], 1
	je	.forgive
	mov	ax, emOPSIZE
	jmp	fail
    .forgive:
	mov	al, 2
	mov	[weight], 1
	jmp	.sizeok
    .check:
	cmp	al, 2
	jbe	.legal
	mov	ax, emILLSIZE
	jmp	fail
    .legal:
	mov	[weight], 1
	cmp	al, 2
	je	.sizeok
	mov	[weight], 0
    .sizeok:
	mov	[opsize], al
	mov	al, [opcode]
	call	buildrm
	mov	al, [weight]
	or	al, 0F6h
	mov	[opcode], al
	ret

;-------------[shift.asm]--------------;

shift:
	mov	bx, target
	call	getea
	mov	si, bx
	cmp	[ahead], TkCOMMA
	je	.commaok
	mov	ax, emSOURCE
	jmp	fail
    .commaok:
	call	scan
	mov	bx, source
	call	getea
	cmp	byte [si+OPINFO.ID], opVAL
	jne	.targetok
	mov	ax, emOPERAND
	jmp	fail
    .targetok:
	mov	al, [si+OPINFO.Size]
	test	al, al		;if(y.sz == 0)
	jnz	.check		;    if(pass != 1)
	cmp	[pass], 1	;        error("no size");
	je	.forgive	;    else
	mov	ax, emOPSIZE	;    {
	jmp	fail		;        y.sz = 2;
    .forgive:			;        weight = 1;
	mov	al, 2		;    }
	mov	[weight], 1	;else
	jmp	.sizeok 	;    if(y.sz > 2)
    .check:			;        error("illegal size");
	cmp	al, 2		;    else
	jbe	.legal		;    {
	mov	ax, emILLSIZE	;        weight = 0;
	jmp	fail		;        if(y.sz != 1)
    .legal:			;            weight = 1;
	mov	[weight], 0	;    }
	cmp	al, 1		;opsize = y.sz;
	je	.sizeok
	mov	[weight], 1
    .sizeok:
	mov	[opsize], al
	cmp	byte [bx+OPINFO.ID], opMEM
	jne	.sourceok
	mov	ax, emOPERAND
	jmp	fail
    .sourceok:
	cmp	byte [bx+OPINFO.ID], opREG
	jne	.RMI
    .RM:
	cmp	byte [bx+OPINFO.rgA], 11h
	je	.countok
	mov	ax, emOPERAND
	jmp	fail
    .countok:
	mov	al, [opcode]
	mov	bx, si
	call	buildrm
	mov	al, [weight]
	or	al, 0D2h
	mov	[opcode], al
	ret
    .RMI:
	cmp	word [bx+OPINFO.Sym], 0
	je	.icountok
	mov	ax, emOPERAND
	jmp	fail
    .icountok:
	cmp	word [bx+OPINFO.Ofs], 1
	jne	.RMIEx
	mov	al, [opcode]
	mov	bx, si
	call	buildrm
	mov	al, [weight]
	or	al, 0D0h
	mov	[opcode], al
	ret
    .RMIEx:
	cmp	byte [bx+OPINFO.Ofs+1], 0
	je	.excountok
	mov	ax, emVALUE
	jmp	fail
    .excountok:
	mov	al, [bx+OPINFO.Ofs]
	mov	byte [val], al
	mov	[vsz], 1
	mov	al, [opcode]
	mov	bx, si
	call	buildrm
	mov	al, [weight]
	or	al, 0C0h
	mov	[opcode], al
	ret

;-------------[getea.asm]--------------;

emINVARG	db "invalid operand",0
emILLSEG	db "illegal segment override",0

;op      -> reg
;         | reg ':[' e1 ']'
;         | type ptr '[' e1 ']'
;         | type ptr reg ':[' e1 ']'
;         | e1
getea:
	mov	byte [bx+OPINFO.Segm], 0
	mov	byte [bx+OPINFO.Type], 0
	mov	byte [bx+OPINFO.Size], 0
	;>>>>>>>> TYPE <<<<<<<<
	cmp	[ahead], TkTYPE
	jne	.typeok
	mov	al, byte [tokval]
	mov	[bx+OPINFO.Type], al
	test	al, 80h
	jnz	.sizeok
	mov	[bx+OPINFO.Size], al
    .sizeok:
	call	scan
	cmp	[ahead], TkPTR
	jne	.typeok
	call	scan
    .typeok:
	;>>>>>>>> SEGM <<<<<<<<
	cmp	[ahead], TkREG
	jne	.segmok
	mov	al, byte [tokval]
	call	scan
	cmp	[ahead], TkCOLON
	je	.segm
	;>>>>>>>> REG <<<<<<<<
	mov	[bx+OPINFO.rgA], al
	cmp	byte [bx+OPINFO.Type], 0
	je	.regok
	mov	ax, emINVARG
	call	error
      .regok:
	mov	byte [bx+OPINFO.ID], opREG
	mov	al, [bx+OPINFO.rgA]
	shr	al, 4
	cmp	al, 3
	jne	.regsizeok
	mov	al, 2
      .regsizeok:
	mov	[bx+OPINFO.Size], al
	ret
      .segm:
	call	scan
	mov	[bx+OPINFO.Segm], al
	and	al, 0F0h
	cmp	al, 30h
	je	.segmok
	mov	ax, emILLSEG
	call	error
	mov	byte [bx+OPINFO.Segm], 0
    .segmok:
	cmp	[ahead], TkLBRA
	jne	.nomem
	mov	byte [bx+OPINFO.ID], opMEM
	call	scan
	call	e1
	cmp	[ahead], TkRBRA
	je	.memok
	mov	ax, emINVARG
	jmp	fail
      .memok:
	mov	al, [bx+OPINFO.Type]
	test	al, al
	jnz	.memsizeok
	push	si
	mov	si, [bx+OPINFO.Sym]
	test	si, si
	jz	.symsizeok
	mov	al, [si+SYMBOL.Type]
	mov	[bx+OPINFO.Type], al
	test	al, 80h
	jnz	.symsizeok
	mov	[bx+OPINFO.Size], al
      .symsizeok:
	pop	si
      .memsizeok:
	jmp	scan
    .nomem:
	cmp	byte [bx+OPINFO.Type], 0
	jne	.nomembad
	cmp	byte [bx+OPINFO.Segm], 0
	je	.nomemok
      .nomembad:
	mov	ax, emINVARG
	call	error
	mov	byte [bx+OPINFO.Type], 0
	mov	byte [bx+OPINFO.Size], 0
	mov	byte [bx+OPINFO.Segm], 0
      .nomemok:
	mov	byte [bx+OPINFO.ID], opVAL
	call	e1
	cmp	byte [bx+OPINFO.rgA], 0
	je	.valok
	mov	ax, emINVARG
	jmp	fail
    .valok:
	ret

;------------[expr8086.asm]------------;

;e2      -> num
;         | sym
;         | reg
;         | '(' e1 ')'
;e1      -> e2 e1r
;         |
;e1r     -> '+' e2 e1r'
;         | '-' e2 e1r'
;         |

emINVEXP	db "invalid expression",0

;reg     -> 'bx'
;         | 'bp'
;         | 'si'
;         | 'di'
chkreg:
	cmp	al, rgBX
	je	.0
	cmp	al, rgBP
	je	.0
	cmp	al, rgSI
	je	.0
	cmp	al, rgDI
	je	.0
	mov	ax, emINVEXP
	jmp	fail
    .0: ret

;e2      -> num
;         | sym
;         | reg
;         | '(' e1 ')'
e2:
	xor	ax, ax
	mov	[bx+OPINFO.rgA], ax	;rgA,rgB
	mov	[bx+OPINFO.Ofs], ax
	mov	[bx+OPINFO.Sym], ax
	mov	al, [ahead]
	cmp	al, TkNUM
	je	.num
	cmp	al, TkSYM
	je	.sym
	cmp	al, TkSTR
	je	.str
	cmp	al, TkREG
	je	.reg
	cmp	al, TkLPAR
	je	.lpar
	mov	ax, emINVEXP
	jmp	fail

    .lpar:
	call	scan
	call	e1
	cmp	[ahead], TkRPAR
	je	.rpar_ok
	mov	ax, emINVEXP
	jmp	fail
    .rpar_ok:
	jmp	scan

    .reg:
	mov	al, byte [tokval]
	call	chkreg
	mov	[bx+OPINFO.rgA], al
	jmp	scan

    .num:
	mov	ax, [tokval]
	mov	[bx+OPINFO.Ofs], ax
	jmp	scan

    .sym:
	push	si
	mov	si, [tokval]
	mov	[bx+OPINFO.Sym], si
	mov	ax, [si+SYMBOL.Ofs]
	mov	[bx+OPINFO.Ofs], ax
	cmp	byte [si+SYMBOL.Type], 0
	jne	.sym_ok
	mov	[dirty], 1
    .sym_ok:
	pop	si
	jmp	scan

    .str:
	cmp	[toklen], 2
	jbe	.lenok
	mov	ax, emVALUE
	call	error
    .lenok:
	push	si
	mov	si, [tokptr]
	cmp	[toklen], 1
	je	.b
    .w: mov	ax, [si]
	jmp	.s
    .b: xor	ax, ax
	mov	al, [si]
    .s: pop	si
	mov	[bx+OPINFO.Ofs], ax
	jmp	scan

;e1      -> e2 e1r
;e1r     -> '+' e2 e1r'
;         | '-' e2 e1r'
;         |
e1:
	call	e2
	mov	al, [ahead]
	cmp	al, '+'
	je	.do_rest
	cmp	al, '-'
	jne	.exit
    .do_rest:
	push	si
	mov	si, bx
	sub	sp, OPINFO.sizeOf
	mov	bx, sp
    .repeat:
	push	ax
	call	scan
	call	e2
	pop	ax
	cmp	al, '-'
	je	.subtract

    .add:
	;>>>>>>>> REG <<<<<<<<
	cmp	byte [bx+OPINFO.rgA], 0
	je	.e1a_regok
	cmp	byte [bx+OPINFO.rgB], 0
	je	.e1a_addreg
	cmp	byte [si+OPINFO.rgA], 0
	je	.e1a_addmem
	mov	ax, emINVEXP
	jmp	fail
      .e1a_addmem:
	mov	ax, [bx+OPINFO.rgA]	;rgA,rgB
	mov	[si+OPINFO.rgA], ax
	jmp	.e1a_regok
      .e1a_addreg:
	cmp	byte [si+OPINFO.rgA], 0
	je	.e1a_addfirst
	cmp	byte [si+OPINFO.rgB], 0
	je	.e1a_addregok
	mov	ax, emINVEXP
	jmp	fail
      .e1a_addregok:
	mov	al, [si+OPINFO.rgA]
	cmp	al, rgBX
	je	.e1a_bxbp
	cmp	al, rgBP
	je	.e1a_bxbp
      .e1a_sidi:
	mov	al, [bx+OPINFO.rgA]
	cmp	al, rgBX
	je	.e1a_sidi_ok
	cmp	al, rgBP
	je	.e1a_sidi_ok
	mov	ax, emINVEXP
	jmp	fail
      .e1a_sidi_ok:
	mov	ah, [si+OPINFO.rgA]
	mov	[si+OPINFO.rgA], ax	;rgA,rgB
	jmp	.e1a_regsok
      .e1a_bxbp:
	mov	al, [bx+OPINFO.rgA]
	cmp	al, rgSI
	je	.e1a_bxbp_ok
	cmp	al, rgDI
	je	.e1a_bxbp_ok
	mov	ax, emINVEXP
	jmp	fail
      .e1a_bxbp_ok:
	mov	[si+OPINFO.rgB], al
      .e1a_regsok:
	jmp	.e1a_regok
      .e1a_addfirst:
	mov	al, [bx+OPINFO.rgA]
	mov	[si+OPINFO.rgA], al
      .e1a_regok:
	;>>>>>>>> SYM <<<<<<<<
	mov	ax, [bx+OPINFO.Sym]
	test	ax, ax
	jz	.e1a_symok
	cmp	word [si+OPINFO.Sym], 0
	je	.e1a_addsym
	mov	ax, emINVEXP
	jmp	fail
      .e1a_addsym:
	mov	[si+OPINFO.Sym], ax
      .e1a_symok:
	;>>>>>>>> NUM <<<<<<<<
	mov	ax, [bx+OPINFO.Ofs]
	add	[si+OPINFO.Ofs], ax
	jmp	.untill

    .subtract:
	;>>>>>>>> REG <<<<<<<<
	cmp	byte [bx+OPINFO.rgA], 0
	je	.e1s_regok
	mov	ax, emINVEXP
	jmp	fail
      .e1s_regok:
	;>>>>>>>> SYM <<<<<<<<
	cmp	word [bx+OPINFO.Sym], 0
	je	.e1s_symok
	cmp	word [si+OPINFO.Sym], 0
	jne	.e1s_symerr
	mov	word [si+OPINFO.Sym], 0
	jmp	.e1s_symok
      .e1s_symerr:
	mov	ax, emINVEXP
	jmp	fail
      .e1s_symok:
	;>>>>>>>> NUM <<<<<<<<
	mov	ax, [bx+OPINFO.Ofs]
	sub	[si+OPINFO.Ofs], ax

    .untill:
	mov	al, [ahead]
	cmp	al, '+'
	je	.repeat
	cmp	al, '-'
	je	.repeat
	mov	bx, si
	add	sp, OPINFO.sizeOf
	pop	si
    .exit:
	ret

;-------------[build.asm]--------------;

	align	2
opsize		db 0
weight		db 0
dsv		db 0
opcode		db 0
fsegm		db 0
segm		db 0
fpost		db 0
post		db 0
osz		db 0
vsz		db 0
ofs		dw 0
osym		dw 0
val		dw 0
vsym		dw 0
codesize	db 2

;#params    BX = memory operand
;           AL = register code
buildrm:
	mov	[fpost], 1
	and	al, 7
	shl	al, 3
	mov	[post], al
	cmp	byte [bx+OPINFO.ID], opREG
	jne	.rmMEM
  .rmREG:
	mov	al, [bx+OPINFO.rgA]
	and	al, 7
	or	al, 11000000b
	or	[post], al
	ret
  .rmMEM:
	mov	[osz], 2
	mov	ax, [bx+OPINFO.Ofs]
	mov	[ofs], ax
	mov	ax, [bx+OPINFO.Sym]
	mov	[osym], ax
	cmp	byte [bx+OPINFO.rgA], 0
	jne	.rmIND
	or	[post], 6
	ret
  .rmIND:
	cmp	byte [bx+OPINFO.rgB], 0
	je	.RxOnly
    .RbRx:
	xor	al, al
	cmp	byte [bx+OPINFO.rgA], rgBP
	jne	.RbOk
	or	al, 2
      .RbOk:
	cmp	byte [bx+OPINFO.rgB], rgDI
	jne	.RxOk
	or	al, 1
      .RxOk:
	jmp	.rmOk
    .RxOnly:
	mov	al, [bx+OPINFO.rgA]
	cmp	al, rgSI
	je	.SI
	cmp	al, rgDI
	je	.DI
	cmp	al, rgBP
	je	.BP
      .BX:
	mov	al, 7
	jmp	.rmOk
      .SI:
	mov	al, 4
	jmp	.rmOk
      .DI:
	mov	al, 5
	jmp	.rmOk
      .BP:
	mov	al, 6
    .rmOk:
	or	[post], al
    .chkSeg:
	cmp	byte [bx+OPINFO.Segm], 0
	je	.segOk
	cmp	byte [bx+OPINFO.Segm], sgSS
	jb	.doSeg
	je	.SS
      .DS:
	cmp	byte [bx+OPINFO.rgA], rgBP
	jne	.segOk
	jmp	.doSeg
      .SS:
	cmp	byte [bx+OPINFO.rgA], rgBP
	je	.segOk
      .doSeg:
	mov	[fsegm], 1
	mov	al, [bx+OPINFO.Segm]
	and	al, 3
	shl	al, 3
	or	al, 26h
	mov	[segm], al
    .segOk:
    .chkOfs:
	cmp	word [bx+OPINFO.Sym], 0
	jne	.wOfs
	mov	ax, [bx+OPINFO.Ofs]
	call	abs
	cmp	ax, 127
	ja	.wOfs
	test	ax, ax
	jnz	.bOfs
	mov	al, [post]
	and	al, 7
	cmp	al, 6
	jne	.noOfs
    .bOfs:
	mov	[osz], 1
	or	[post], 40h
	jmp	.ofsOk
    .wOfs:
       ;mov     [osz], 2
	or	[post], 80h
	jmp	.ofsOk
    .noOfs:
	mov	[osz], 0
    .ofsOk:
	ret

;@params    BX = immediate oeprand
;           AL = sign factor
buildimm:
	push	bp
	push	ax
	mov	bp, sp
	mov	[dsv], 0
	mov	al, [opsize]
	mov	[vsz], al
	mov	ax, [bx+OPINFO.Sym]
	mov	[vsym], ax
	mov	ax, [bx+OPINFO.Ofs]
	mov	[val], ax
	call	abs
	cmp	ax, 127
	mov	al, 2
	ja	.0
	mov	al, 1
    .0: cmp	al, [opsize]
	jbe	.1
	mov	ax, emVALUE
	call	error
	jmp	.2
    .1: cmp	[opsize], 1
	je	.2
	cmp	byte [bp], 0
	je	.2
	cmp	al, 1
	jne	.2
	mov	[dsv], 2
	mov	[vsz], al
    .2: pop	ax
	pop	bp
	ret

abs:
	neg	ax
	js	abs
	ret

;-------------[strlen.asm]-------------;

;#params    DS:SI = string
;#return    AX = length
strlen:
	push	bx
	xor	bx, bx
    .0: mov	al, [bx+si]
	inc	bx
	test	al, al
	jnz	.0
	lea	ax, [bx-1]
	pop	bx
	ret

;-------------[strcpy.asm]-------------;

;#params    DS:SI = (char*)pszSrcStr
;           DS:DI = (char*)pDst
;#return    AX = (word)nStrLen
strcpy:
	push	bx
	xor	bx, bx
    .0: mov	al, [si+bx]
	mov	[di+bx], al
	inc	bx
	test	al, al
	jnz	.0
	lea	ax, [bx-1]
	pop	bx
	ret

;--------------[file.asm]--------------;

;@params  DS:SI = (char*)&FileName
;            AL = (byte)OpenMode
OpenFile:
	push	cx
	push	dx
	mov	ah, 3Dh
	xor	cl, cl
	mov	dx, si
	int	21h
	pop	dx
	pop	cx
	ret

;@params  DS:SI = (char*)&FileName
;            AL = (byte)Attributes
CreateFile:
	push	cx
	push	dx
	mov	ah, 3Ch
	mov	cl, al
	mov	dx, si
	int	21h
	pop	dx
	pop	cx
	ret

;@params  DS:SI = (byte*)&Buffer
;            CX = (int)NumberOfBytes
;            BX = (int)File
WriteFile:
	push	dx
	mov	ah, 40h
	mov	dx, si
	int	21h
	pop	dx
	ret

;@params  DS:SI = (byte*)&Buffer
;            CX = (int)NumberOfBytes
;            BX = (int)File
ReadFile:
	push	dx
	mov	ah, 3Fh
	mov	dx, si
	int	21h
	pop	dx
	ret

;@params  DX:AX = (long)FilePos
;            BX = (int)File
SetFilePos:
	push	cx
	mov	cx, dx
	mov	dx, ax
	mov	ax, 4200h
	int	21h
	pop	cx
	ret

;@params     BX = (int)File
;@return  DX:AX = (long)FilePos
GetFilePos:
	push	cx
	xor	cx, cx
	xor	dx, dx
	mov	ax, 4201h
	int	21h
	pop	cx
	ret

;@params     BX = (int)File
;@return  DX:AX = (long)FileSize
GetFileSize:
	push	cx
	xor	cx, cx
	xor	dx, dx
	mov	ax, 4202h
	int	21h
	pop	cx
	ret

;@params  BX = (int)File
CloseFile:
	cmp	bx, -1
	je	.0
	cmp	bx, 2
	jbe	.0
	mov	ah, 3Eh
	int	21h
    .0: ret

;@params  DS:SI = (char*)&FileName
DeleteFile:
	push	dx
	mov	dx, si
	mov	ah, 41h
	int	21h
	pop	dx
	ret

;--------------[stdio.asm]-------------;

getch:
	push	bp
	push	ax
	mov	bp, sp
	mov	ah, 8
	int	21h
	mov	[bp], al
	pop	ax
	pop	bp
	ret

putchar:
	push	ax
	push	dx
	mov	dl, al
	mov	ah, 2
	int	21h
	pop	dx
	pop	ax
	ret

putstr:
	push	ax
	push	si
	mov	al, [si]
	test	al, al
	jz	.1
    .0: inc	si
	call	putchar
	mov	al, [si]
	test	al, al
	jnz	.0
    .1: pop	si
	pop	ax
	ret

wtoa:
	push	bx
	push	dx
	push	di
	mov	di, si
    .0: xor	dx, dx
	div	bx
	cmp	dl, 10
	jb	.1
	add	dl, 7
    .1: add	dl, '0'
	mov	[di], dl
	inc	di
	test	ax, ax
	jnz	.0
	mov	[di], al
	mov	ax, di
	sub	ax, si
	dec	di
	cmp	si, di
	jae	.3
	mov	bx, si
    .2: mov	dl, [bx]
	mov	dh, [di]
	mov	[bx], dh
	mov	[di], dl
	inc	bx
	dec	di
	cmp	bx, di
	jb	.2
    .3: pop	di
	pop	dx
	pop	bx
	ret

bNOSIGN 	= 1

;@model   FastCall, StdCall
;@params     SI: char *Format
;         STACK: word  Args,...
printf:
	push	bp
	push	bp
	mov	bp, sp
	push	ax
	push	si
	push	di
	sub	sp, 8
	lea	ax, [bp+4]
	mov	[bp+2], ax
	mov	di, 6
    .main:
	mov	al, [si]
	inc	si
	test	al, al
	jz	.end
	cmp	al, '%'
	je	.format
	cmp	al, '\'
	je	.escape
    .putchar:
	push	word(.main)
	jmp	putchar
    .escape:
	mov	al, [si]
	inc	si
	cmp	al, '\'
	je	.putchar
	cmp	al, 'a'
	je	.bell
	cmp	al, 'b'
	je	.bs
	cmp	al, 't'
	je	.tab
	cmp	al, 'n'
	jne	.main
    .crlf:
	mov	al, 13
	call	putchar
	mov	al, 10
	jmp	.putchar
    .bell:
	mov	al, 7
	jmp	.putchar
    .bs:
	mov	al, 8
	jmp	.putchar
    .tab:
	mov	al, 9
	jmp	.putchar
    .format:
	mov	al, [si]
	inc	si
	cmp	al, '%'
	je	.putchar
	cmp	al, 'c'
	je	.char
	cmp	al, 's'
	je	.string
	push	bx
	xor	bx, bx
	cmp	al, 'd'
	je	.dec
	cmp	al, 'u'
	je	.udec
	cmp	al, 'x'
	je	.hex
	pop	bx
	jmp	.main
    .udec:
	or	bh, bNOSIGN
    .dec:
	mov	bl, 10
	jmp	.num
    .hex:
	or	bh, bNOSIGN
	mov	bl, 16
    .num:
	push	ds
	push	si
	mov	ax, ss
	mov	ds, ax
	lea	si, [bp-14]
	mov	ax, [bp+di]
	test	bh, bNOSIGN
	jnz	.sgnok
	test	ah, 80h
	jz	.sgnok
	mov	al, '-'
	call	putchar
	mov	ax, [bp+di]
	neg	ax
    .sgnok:
	inc	di
	inc	di
	xor	bh, bh
	call	wtoa
	call	putstr
	pop	si
	pop	ds
	pop	bx
	jmp	.main
    .char:
	mov	ax, [bp+di]
	inc	di
	inc	di
	jmp	.putchar
    .string:
	push	si
	mov	si, [bp+di]
	inc	di
	inc	di
	call	putstr
	pop	si
	jmp	.main
    .end:
	cmp	di, 6
	jbe	.exit
	mov	ax, [bp+4]
	mov	[bp+di-2], ax
	lea	ax, [bp+di-2]
	mov	[bp+2], ax
    .exit:
	add	sp, 8
	pop	di
	pop	si
	pop	ax
	pop	bp
	pop	sp
	ret

;-------------[memory.asm]-------------;

	align	2
mm:
  .ptr		dw prog_end
  .lim		dw prog_end+2048

emMEMORY	db "not enough memory",0

;#params    CX = size in bytes
;#return    AX = block address
malloc:
	mov	ax, cx
	inc	ax
	and	al, 0FEh
	add	ax, [mm.ptr]
	cmp	ax, [mm.lim]
	jbe	.0
	push	emMEMORY
	mov	si, szfmtFATAL
	call	printf
	jmp	exit
    .0: push	cx
	mov	cx, [mm.ptr]
	mov	[mm.ptr], ax
	mov	ax, cx
	pop	cx
	ret

	align	2
prog_end: