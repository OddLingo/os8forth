 	.TITLE OS/8 FORTH Input and output
	.INCLUDE COMMON.MA

// OS/8 input output routines that managed the
// buffered system calls.  Routines with names
// starting "RK" or "TT" can be called from F0.
// Names starting "IO" can be called from here.
	.SBTTL I/O common areas

// Reserved areas for device handlers in Field 0
	.ASECT RKPARK
	FIELD 0
	.GLOBAL RKSPOT
	*7000
RKSPOT,	0
	*.+176

	.ASECT TTPARK
	FIELD 0
	.GLOBAL TTSPOT
	*7200
TTSPOT,	0
	*.+376

// Auto-index for I/O package
	.XSECT IOSCAN
	FIELD 2
INPTR,	0
OUTPTR,	0

	.ZSECT IOCOMM
	FIELD 2
RK1,	.FIB  RKSPOT,,RKIBUF
RK2,	.FIB  ,,RKOBUF

RESTDF,	CIF
RKNUM,	0      	    / DSK device number
TTNUM,	0	    / Console device number
TTHDLR,	0	    / Console handler in F0
RKHDLR,	0	    / DSK handler in F0
IOCHAR,	0	    / Character temp
T6,	0
T7,	0
WLIMIT,	0
ILIMIT,	0
FLIMIT,	0	/ Negative of filename part
TTPOS,	0
TTOPTR,	0
TTLIM,	0	/ Negative TT buffer left
RKOBLK,	0	/ Next file oputput block
RKIBLK,	0	/ Next file input block
RKSIZE,	0	/ Negative input blk count
F1ID,	0
F1DEV,	DEVICE RKA1
F1NAM,	FILENAME TEST.TX	/ Sixbit file name1
F2ID,	0
F2DEV,	DEVICE RKA1
F2NAME,	FILENAME TESTO.TX
TTNAM,	FILENAME TTY

// Macros for dealing with inter-field calls.
	.MACRO FARENT / Fixup far return
	CLA
	RDF
	TAD RESTDF
	DCA EXIT$
	.ENDM

	.MACRO FARETN
EXIT$:	HLT    		/ Replaced by CIF instruction
	.ENDM

	.SBTTL Disk I/O

	.RSECT INOUT
	FIELD 2

	.ENTRY RKINIT
DSKNAM,	DEVICE DSK

// Load device handler for file devices
RKINIT,	0		/ Initialize disk I/O
	FARENT
	.FETCH DSKNAM,RKSPOT
	DCA OUTPTR
	TAD I OUTPTR
	DCA RK1+DEVNUM
	TAD I OUTPTR
	DCA RK1+DEVADR
	FARETN
	JMP I RKINIT

	.ENTRY RKOPEN
// Open a named file. AC contains F1 address of
// 4 words in FILENAME format.
CPYFIL,	0     	       / Copy a filename
	DCA INPTR
	TAD (F1NAM)
	DCA OUTPTR
	TAD (-4)
	DCA FLIMIT
LOOP$:	CDF 1
	TAD I INPTR
	CDF .
	DCA I OUTPTR
	ISZ FLIMIT
	JMP I CPYFIL

RKOPEN,	0		/ Open file for reading
	FARENT
	/ Parse the string into 6-word block inside
	/ the FIB.  FORTH uses counted strings but
	/ .FPARSE expects a NUL terminator.
	.FPARSE ,RK1+FILSIZ	/ Parse string in AC
	.IOPEN	RK1,RK1+FILNAM,NOFIL$
	FARETN
	JMP I RKOPEN

	.ENTRY RKNEW
RKNEW,	0		/ Start new file
	FARENT
	TAD (F1NAM)
	DCA START$
	TAD RKNUM
	USRCALL UENTER
START$:	0
LIMIT$:	0
	HLT
	CLA
	TAD START$	/ Remember first block
	DCA RKOBLK
	TAD LIMIT$
	DCA RKSIZE	/ Max size to write
	FARETN
	JMP I RKNEW

	.ENTRY RKREAD
RKREAD,	0		/ Read one block
	TAD RKIBLK
	DCA BLOCK$
	TAD RKNUM
	CDF .
	CIF 00
	JMS I RKHDLR
	220		/  Read 2 records
	RKIBUF
BLOCK$:	0		/ Block to read
	HLT
	ISZ RKIBLK	/ Next block to read
	ISZ RKSIZE
	JMP I RKREAD
	HLT		/?? Reached EOF

	.ENTRY RKWRIT
RKWRIT,	0
	TAD RKOBLK
	DCA BNUM$
	TAD RKNUM
	CDF RKOBUF
	CIF 00
	JMS I RKHDLR
	4200		/ Write 2 records
	RKOBUF
BNUM$:	0		/ Block num
	HLT
	ISZ RKOBLK
	JMP I RKWRIT

	PAGE
// Unpack RKIBUF (3:2 format) into specified
// buffer in 1:1 format.  Do one line at a time.
UNPACK,	0		/ Unpack 3-in-2 format
	CLA CMA
	TAD (RKIBUF	/ Input buffer
	DCA INPTR
	CLA CMA
	TAD (TTOBUF	/ Output buffer
	DCA OUTPTR
	TAD (-100	/ Count of doublewords
	DCA WLIMIT

LOOP$:	TAD I INPTR
	DCA T6
	TAD I INPTR
	DCA T7
	/ Unpack the pair of words
	TAD T6	     / Right side of word 1
	AND (377)
	DCA I OUTPTR

	TAD T6		/ Preserve 3rd piece
	AND (7400)
	CLL RTR; RTR;
	DCA T6

	TAD T7		/ Right side  of word 2
	AND (377)
	DCA I OUTPTR

	TAD T7		/ Combine halves of word 3
	AND (7400)
	CLL RTR; RTR; RTR; RTR
	TAD T6
	AND (377)
	DCA I OUTPTR

	ISZ WLIMIT
	JMP LOOP$
	JMP I UNPACK

	.SBTTL Console I/O
	PAGE
// Handling a far call: DF is where call came from
// and IF is here.  After fetching any values from
// callers DF, save it in CALLDF.  When ready to
// return, set that to both DF and IF (CDI) before doing
// indirect return jump.
	.GLOBAL TTINIT
TTINIT,	0
	FARENT
	CLA IAC
	TAD (TTSPOT
	DCA WHERE$
        USRCALL UFETCH
        DEVICE TTY
WHERE$:	7001     / Becomes TT handler entry pt
        HLT
	CLA
	TAD WHERE$
	DCA TTHDLR

        USRCALL UINQUIRE / Get device number
NUM$:	DEVICE TTY	/ +1 becomes device num
        0
        HLT
	CLA
	TAD NUM$+1
	DCA TTNUM
	JMS SOL		/ Set up buffer
	FARETN
	JMP I TTINIT

// Output the character in AC to console.
	.ENTRY TTEMIT
TTEMIT,	0		/ Callable from F0
	DCA IOCHAR
	FARENT
	TAD IOCHAR
	JMS IOEMIT	/ Really do it
	FARETN
	JMP I TTEMIT

IOEMIT,	0	/ Local real TT output
	DCA I TTOPTR	/ To buffer
	ISZ TTOPTR	/ Bump pointer
	ISZ TTLIM	/ Check full
	JMP I IOEMIT
	JMS FLUSH	/ Buffer full
	JMP I IOEMIT

	.ENTRY TTCRLF
TTCRLF,	0
	TAD (15
	JMS IOEMIT
	TAD (12
	JMS IOEMIT
	JMS FLUSH
	JMP I TTCRLF

	.EXTERNAL TIB / Console input buffer in F1
FLUSH,	0
	TAD (32)	/ Mark end with CTRL-Z
	JMS IOEMIT
	TAD (TTOBUF
	JMS IOTYPE
	JMS SOL		/ Do start-of-line setup
	JMP I FLUSH

SOL,	0		/ Initialize TT buffer
	TAD (TTOBUF	/ Start of buffer
	DCA TTOPTR
	TAD (-117	/ Leave room for CTRL-Z
	DCA TTLIM
	JMP I SOL

/ Read a line. On return AC=0 means ok.  Non-zero
/ means CTRL-Z detected.
ACCEPT,	0
	TAD (TTIBUF)
	DCA BUF$
        CDF .
        CIF 00
	TAD TTNUM
        JMS I TTHDLR
	0100+EDF TTIBUF	/ READ 1 RECORD
BUF$:   0	/ BUFFER
	0       / START BLOCK
        HLT
	CLA
	JMP I ACCEPT
ERR$:	SPA
	HLT
	JMP I ACCEPT

IOTYPE,	0
	DCA BUF$
        CDF .
	TAD TTNUM
        JMS I TTHDLR
	4110	/ WRITE 1 RECORD
BUF$:   TTOBUF    / BUFFER
	0       / START BLOCK
        HLT
	CLA
	CDF 0
	JMP I IOTYPE

	.ENTRY TTDONE
TTDONE,	0   // Close the console
	FARENT
	TAD (TTNAM)
	DCA NAME$
	TAD TTNUM
        USRCALL UCLOSE
NAME$:  F1NAM		/ Name of file
	1		/ Max blocks written
        HLT
	FARETN
	JMP I TTDONE

	PAGE
RKDONE,	0   // Close a file
	FARENT
	TAD (F1NAM)
	DCA NAME$
	TAD RKSIZE
	DCA SIZE$
	TAD RKNUM
        USRCALL UCLOSE
NAME$:  F1NAM		/ Name of file
SIZE$:	1		/ Max blocks written
        HLT
	FARETN
	JMP I RKDONE

	.DSECT BUFFS
	FIELD 2
// File-devices pack 3 characters per two words and
// like to transfer one block (256 words) at a time.
// Non-file devices put one character per word and
// transfer one record (128 words) at a time.
RKIBUF,	ZBLOCK 400, 0	/ Disk input, 3:2 ASCII
RKOBUF,	ZBLOCK 400, 0	/ Disk output, 3:2 ASCII
TTIBUF,	ZBLOCK 200, 0	/ Console input, 1:1 ASCII
TTOBUF,	ZBLOCK 200, 0	/ Console output, 1:1 ASCII
