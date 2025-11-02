	.TITLE Forth I/O Interface
// This module is an interface between the Forth
// World in Fields 0 (the ENGINE) and 1 (the SYMBOL
// table) and the OS8 I/O world in Field 2.
	.EXTERNAL SYMBOL, ENGINE

/ Get interfaces to the FILEIO package.
	.NOLIST
	.INCLUDE COMMON.MA
	.LIST
	.LIST MEB

// OS8 normally stores 3 ASCII characters in two
// adjacent words.  This means that a 256-word
// "block" in the file system holds 384 characters,
	CHBLK=^D384    / Characters per block

	.MACRO CALL RTN
	JMS I [RTN]
	.ENDM

// Operate on the stack, which is part of the
// SYMBOL table.
	.MACRO PUSH VAL
	.IF NB VAL <TAD VAL
	>
	CALL PUSHS
	.ENDM

	.MACRO POP DEST
	.IF NB DEST <CALL POPS
	DEST>
	.IF BL DEST <CALL POPA>
	.ENDM

// The ENTER and RETURN macros synchronize use
// of the stack and address spaces.  They must
// be used as first and last lines in routines
// called from the ENGINE.
	.MACRO ENTER
	JMS GETSP
	.ENDM

	.MACRO RETURN FROM
	JMS PUTSP
	CIF ENGINE
	JMP I FROM
	.ENDM

	.XSECT FHIDX
	FIELD 2
/ Auto-index pointers for copying things.
INPTR,	0
OUTPTR,	0

	.ZSECT FHCOM
	FIELD 2
FILES,	FIB1; FIB2
MAXFIB,	-2
FIBPTR,	0	/ Address of selected FIB
FIBNUM,	0	/ The file-id
LIMIT,	0
COUNT,	0
CHAR,	0
FADDR,	0	/ Filename address
FLEN,	0	/ Filename length
HIGH,	0	/ High 12 bits
LOW,	0	/ Low 12 bits
OURSP,	0	/ Local copy of SP
REALSP,	SP	/ Real engine stack pointer
T1,	0

// Push the AC onto the Forth stack.
// The SP is in Field 0 and the stack is in
// Field 1.  This code is in Field 2.
	.EXTERNAL SP
// Synchronize real SP with local copy
GETSP,	0
	CDF ENGINE
	TAD I REALSP
	DCA OURSP
	CDF .
	JMP I GETSP

// Synchronize real SP from local copy
PUTSP,	0
	TAD OURSP
	CDF ENGINE
	DCA I REALSP
	CDF SYMBOL
	JMP I PUTSP

	.DSECT BLOCKS
	FIELD 2
/ File Information Blocks and buffers.
FIB1,	.FIB	,,BUF1
FIB2,	.FIB	,,BUF2
BUF1=.; *.+400
BUF2=.; *.+400

	.EXTERNAL $FILEIO, THEFIB
	.RSECT FHIO
	FIELD 2
// Find an unused FIB by checking flag word.
NEWFIB,	0
	CLA
	DCA FIBNUM	/ Start zero origin
	TAD MAXFIB
	DCA LIMIT
GETFB$:	TAD (FILES)	/ Scan list of FIBs
	TAD FIBNUM
	DCA FIBPTR
	TAD I FIBPTR
	DCA FIBPTR
CHK$:	TAD FIBPTR	/ In use?
	TAD (FILFLG)
	DCA CHAR
	TAD I CHAR
	SNA
	JMP THIS$	/ No, use this
	ISZ LIMIT	/ Yes, try next one
	JMP SKIP$
	CLA
	JMP I NEWFIB	/ Zero means none available
SKIP$:	ISZ FIBNUM
	JMP GETFB$
THIS$:	ISZ FIBNUM	/ Make it 1-origin
	TAD FIBNUM
	JMP I NEWFIB

// Select active FIB by number.  For convenience,
// We copy it to THEFIB.  Fib number origin 1.
SETFIB,	0
	CDF .
	TAD (FILES-1)	/ Get FIB addr from table
	DCA FIBPTR	/ Ptr into FIB table
	TAD I FIBPTR	/ Get FIB address
	DCA FIBPTR	/ Now it is 'the' FIB
	STA		/ Copy 20 words
	TAD FIBPTR	/ From 'the' FIB
	DCA INPTR
	TAD (THEFIB-1)	/ to the local FIB
SETIT,	DCA OUTPTR
	TAD (-20)
	DCA LIMIT
FIBLP,	TAD I INPTR
	DCA I OUTPTR
	ISZ LIMIT
	JMP FIBLP
	JMP I SETFIB

// Restore our copy of the active FIB
RSTFIB,	0
	CLA
	TAD RSTFIB	/ Borrow return point
	DCA SETFIB
	TAD (THEFIB-1)
	DCA INPTR
	STA
	TAD FIBPTR
	JMP SETIT

// Get device information.  The device name must
// have already been parsed into SBDEV, 2 sixbit
// words.
GETHDL,	0
	CLA
	TAD SBDEV	/ Copy device name
	DCA INFO$
	TAD SBDEV+1
	DCA INFO$+1
	CDF .
	CALUSR 12	/ INQUIRE request
INFO$:	DEVICE DSK
ENTRY$:	0		/ Handler addr appears here
	HLT
	TAD INFO$+1	/ Save device number
	DCA CHAR
	TAD ENTRY$	/ Is handler loaded?
	SZA
	JMP TOFIB$	/ Yes, set FIB

	/ No, Load handler for that device
	TAD HDSPOT	/ Find spot for it.
	TAD (-200)
	DCA HDSPOT
	TAD HDSPOT
	IAC
	DCA ARG3$

	TAD SBDEV	/ Copy device name
	DCA DNAME$	/ for FETCH request.
	TAD SBDEV+1
	DCA DNAME$+1
	CDF .
	CALUSR 1	/ FETCH request
DNAME$:	DEVICE DSK
ARG3$:	0	/ Handler load address
	HLT
	TAD ARG3$		/ entry point
	DCA THEFIB+DEVADR
	TAD DNAME$+1		/ device number
	DCA THEFIB+DEVNUM
	JMP I GETHDL

TOFIB$:	DCA THEFIB+DEVADR	/ Save entry
	TAD INFO$+1		/ Save number
	DCA THEFIB+DEVNUM
	JMP I GETHDL

// Load a device handler.  The device name is at SBDEV.
HDSPOT,	7600
	PAGE
/ Copy counted string from Forth dictionary to here
/ then put a NUL at the end.  We use the data buffer
/ to hold the string for FPARSE.
GETFN,	0
	CLA CMA
	TAD FADDR
	DCA INPTR	/ src-1
	TAD FLEN
	CIA
	DCA LIMIT	/ -Length
	STA		/ dest-1
	TAD THEFIB+BUFADR
	DCA OUTPTR
LOOP$:	CDF SYMBOL	/ Read from dictionary
	TAD I INPTR
	CDF .	/ Write here
	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$
	// Put a NUL at the end.
	DCA I OUTPTR
	JMP I GETFN

	.ENTRY FHOPEN, FHRDL, FHRD, FHCRE
	.EXTERNAL $FPARSE, SBFILE, SBDEV
// Open file.
FHOPEN,	0
	ENTER		/ Sync stack
	POP FLEN	/ Length of name
	POP FADDR	/ Address of name
	JMS NEWFIB	/ Get a free FIB
	SNA 		/ Got one?
	JMP FAIL$	/ No
	JMS SETFIB	/ Make it current

	/ Copy filename from F1 into data buffer,
	/ then parse it into SBNAME.
	JMS GETFN
	TAD THEFIB+BUFADR	/ Parse it
	JMS $FPARSE
	JMS GETHDL	/ Make sure handler loaded

	/ $FILEIO returns status in AC:
	/   =0	  Sucess
	/   >=0	  FILE NOT FOUND. NEW FILE CREATED.
	/   <0	  FATAL DEVICE ERROR
	JMS $FILEIO	/ Open the file
	2
	SBFILE		/ SB name pointer
	JMP FAIL$

	JMS RSTFIB	/ Update our copy
	PUSH FIBNUM	/ Return id number
	PUSH		/ And ok status
	RETURN FHOPEN	/ Resync stack

FAIL$:	CLA IAC
	JMP .-4

// CREATE-FILE( addr len mode -- id status )
// status=0 means ok.
FHCRE,	0
	ENTER
	POP		/ Ignore mode
	POP FLEN
	POP FADDR
	JMS NEWFIB	/ Get a free FIB
	SNA
	JMP FAIL$
	JMS SETFIB	/ Make it current

	JMS GETFN	/ Copy filename from F1
	TAD THEFIB+BUFADR	/ Parse it
	JMS $FPARSE
	JMS GETHDL	/ Make sure handler loaded
	JMS $FILEIO	/ Create the file
	3
	SBFILE		/ SB name pointer
	HLT

	JMS INIBUF	/ Empty buffer
	JMS RSTFIB	/ Update our copy

	PUSH FIBNUM	/ Return id number
DONE$:	PUSH		/ And ok status
	RETURN FHCRE

FAIL$:	STA		/ -1 means failed
	JMP DONE$

// CLOSE-FILE ( id -- status )
	.ENTRY FHCLOS
FHCLOS,	0
	ENTER		/ Sync stack
	POP		/ Get file-id
	JMS SETFIB	/ Select FIB
	JMS $FILEIO	/ Close it
	13
	HLT
	CLA
	DCA THEFIB+FILFLG / Mark unused
	JMS RSTFIB	/ Copy it back
	PUSH		/ Zero status
	RETURN FHCLOS

// FLUSH-FILE (	id -- status )
	.ENTRY FHFLUS
FHFLUS,	0
	ENTER
	POP
	JMS SETFIB	/ Get correct FIB
	JMS $FILEIO	/ Flush buffer
	14
	HLT
	JMS RSTFIB	/ Put it back
	RETURN FHFLUS

	PAGE
// READ-LINE ( addr len id -- len stat )
// Read a line of text.
// This acts like ACCEPT.  Final length in AC, -1 if
// EOF.  Not counting CRLF.
FHRDL,	0
	ENTER		/ Sync stack
	POP
	JMS SETFIB	/ Select FIB
	POP
	CIA
	DCA LIMIT	/ Get buffer size
	DCA COUNT
	POP
	TAD (-1)
	DCA OUTPTR	/ Buff addr minus 1
LOOP$:	CDF .
	JMS $FILEIO
	7		/ ICHAR
	JMP EOF$
	CDF SYMBOL
	AND [177]	/ Strip parity bit
	DCA CHAR
	TAD CHAR	/ Check EOF
	TAD (-32)
	SNA CLA
	JMP EOF$
	TAD CHAR	/ NUL is also EOF
	SNA
	JMP EOF$
	DCA I OUTPTR	/ Store and count it
	ISZ COUNT
	TAD CHAR
	TAD (-12)	/ Was it end of line?
	SNA CLA
	JMP EOL$
	ISZ LIMIT	/ Watch for overflow
	JMP LOOP$	/ Get another
	SKP 		/ Don't back up
EOL$:	TAD (-2)	/ Do not count CRLF
	TAD COUNT
	PUSH
	IAC
	PUSH
	PUSH
	JMP DONE$
EOF$:	PUSH		/ Len zero at EOF
	PUSH		/ Flag zero
	STA
	PUSH		/ ior -1
DONE$:	JMS RSTFIB	/ Save the FIB
	JMS PUTSP	/ resync stack
	RETURN FHRDL

// Read a block.
FHRD,	0
	CDF .
	CIF $FILEIO
	JMS $FILEIO
	5
	HLT
	JMS RSTFIB
	CDF SYMBOL
	CIF ENGINE
	JMP I FHRD

// WRITE-LINE ( addr len id -- stat )
	.ENTRY FHWRL
FHWRL,	0
	ENTER
	POP
	JMS SETFIB
	POP		/ Byte count
	CIA
	DCA LIMIT
	POP
	TAD (-1)
	DCA INPTR	/ Src-1
LOOP$:	CDF SYMBOL
	TAD I INPTR	/ Get next char
	JMS OCHAR$	/ add write it
	ISZ LIMIT
	JMP LOOP$
	TAD (15)	/ Append CRLF
	JMS OCHAR$
	TAD (12)
	JMS OCHAR$
	CLA	
DONE$:	PUSH		/ Status
	JMS RSTFIB
	RETURN FHWRL
ERR$:	STA
	JMP DONE$
OCHAR$:	0
	CDF .
	JMS $FILEIO	/ OCHAR
	6
	HLT		/ Oops
	CLA
	JMP I OCHAR$
	/ AC >= 0: out of room
	/ AC<0: fatal

	PAGE
// Get file position as character number.  This
// is a double-length value computed from block
// number and 3-in-2 position within block.
// File-id is on the stack.
	.ENTRY FHPOS
FHPOS,	0
	ENTER		/ Sync stack
	POP		/ Get file-id
	JMS SETFIB
	TAD THEFIB+BUFPOS / BUFPOS goes 0 to 777
	AND [774]
	CLL RTR
	DCA LOW	 / Save shifted upper 7 bits
	/ LOW is now 0 to 177
	TAD THEFIB+BUFPOS
	AND [3]
	DCA CHAR	/ 0,1,2
	TAD LOW / Upper bits times 3
	MQL MUY / Result is 0 to 575
	3
	MQA		/ Plus char offset
	TAD CHAR	/ Now 0 to 577
	DCA CHAR
	/ Now merge block and character
	STA		/ Relative blkno
	TAD THEFIB+FILBLK
	SPA SZA		/ Hack zero blk
	CLA
	MQL MUY		/ Block*384
	CHBLK
	DCA HIGH	/ High part
	MQA
	DCA LOW

	/ Now add 12bit byte offset to
	/ 24bit block offset
	CLL
	TAD LOW
	TAD CHAR
	DCA LOW
	SZL		/ Propagate carry bit
	ISZ HIGH

	PUSH LOW	/ Push doubleword total
	PUSH HIGH
	ISZ FHPOS	/ Skip error return
	RETURN FHPOS	/ Resync stack

// Set file position.  Stack has doubleword character
// position that we convert to block number and
// position within block, allowing for the 3-in-2
// special coding format.
FHSPOS,	0
	/ Get desired file position
	JMS GETSP
	POP HIGH	/ High 12 bits
	POP LOW		/ Low 12 bits
	JMS PUTSP

	/ Divide by 384 to get block number.
	TAD LOW
	MQL
	TAD HIGH
	DVI
	CHBLK		/ Chars per block
	DCA COUNT	/ Remainder is offset
	MQA
	IAC		/ We use 1-origin
	DCA HIGH	/ Quotient is block

	/ Compute our char position within the
	/ block, 3 characters per two words.
	TAD COUNT  	/ Divide chars by 3
	MQL
	DVI
	3
	DCA CHAR	/ Remainder is 0,1,2
	MQA 		/ Quotient is word offset
	CLL RTL		/ Make room for char pos
	TAD CHAR	/ Add it back in
	DCA LOW
	JMP I FHSPOS

	PAGE
// Push AC on Forth data stack
PUSHS,	0
	DCA T1
	STA
	TAD OURSP
	DCA OURSP
	TAD T1
	CDF SYMBOL		/ Stack is in other field
	DCA I OURSP
	CDF .
	JMP I PUSHS

// Pop data from Forth stack into local memory.
// Destination address is at PC+1.
POPS,	0
	TAD I POPS	/ Get destination
	DCA T1
	CDF SYMBOL
	TAD I OURSP	/ Fetch from stack
	ISZ OURSP
	CDF .
	DCA I T1	/ Store local
	ISZ POPS	/ Skip over arg
	JMP I POPS

POPA,	0
	CDF SYMBOL		/ Stack is in F1
	TAD I OURSP	/ Fetch from stack
	ISZ OURSP
	CDF .
	JMP I POPA

INIBUF,	0     / Fill buffer with NUL
	STA
	TAD THEFIB+BUFADR
	DCA OUTPTR
	TAD (-400)
	DCA LIMIT
LOOP$:	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$
	JMP I INIBUF
