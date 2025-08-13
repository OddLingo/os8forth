	.TITLE Forth I/O Interface
// This module is an interface between the Forth
// World in Fields 0 and 1 and the OS8 I/O world
// in Field 2.
   .NOLIST
   .INCLUDE COMMON.MA
   .LIST

	.EXTERNAL DCTEND, RKSPOT
	.XSECT FHIDX
	FIELD 2
INPTR,	0
OUTPTR,	0

	.ZSECT FHCOM
	FIELD 2
FILES,	FIB1; FIB2
THEFIB,	0		/ Address of working FIB
FIBNUM,	0
LIMIT,	0
COUNT,	0
CHAR,	0

	.DSECT FHBUF
	FIELD 2
FIB1,	.FIB	,,INBUF
FIB2,	.FIB	,,OUTBUF
INBUF=.
	*.+400
OUTBUF=.
	*.+400

	.EXTERNAL $FILEIO, LCLFIB

	.RSECT FHIO
	FIELD 2
// Find an unused FIB by checking flag word.
NEWFIB,	0
	CLA
	DCA FIBNUM
	TAD (-3)
	DCA LIMIT
GETFB$:	TAD (FILES)
	TAD FIBNUM
	DCA THEFIB
	TAD I THEFIB
	DCA THEFIB
CHK$:	TAD THEFIB	/ In use?
	TAD FILFLG
	DCA CHAR
	TAD I CHAR
	SNA
	JMP THIS$	/ No, use this
	ISZ LIMIT	/ Yes, try next one
	JMP SKIP$
	CLA
	JMP I NEWFIB	/ Zero means none available
SKIP$:	TAD FIBNUM
	IAC
	DCA FIBNUM
	JMP GETFB$
THIS$:	TAD FIBNUM
	IAC
	JMP I NEWFIB

// Select active FIB by number.  For convenience,
// We copy it to LCLFIB.
	.ENTRY SETFIB
SETFIB,	0
	TAD (FILES-1)
	DCA THEFIB
	CDF .
	STA		/ Copy 20 words
	TAD I THEFIB
	DCA INPTR
	TAD (LCLFIB-1)
SETIT,	DCA OUTPTR
	TAD (-20)
	DCA LIMIT
FIBLP,	TAD I INPTR
	DCA I OUTPTR
	ISZ LIMIT
	JMP FIBLP
	JMP I SETFIB

// Restore out copy of the active FIB
RSTFIB,	0
	TAD .-1		/ Borrow return point
	DCA SETFIB
	TAD (LCLFIB-1)
	DCA INPTR
	TAD THEFIB
	JMP SETIT

// Load device handler.
	.ENTRY FHINIT
FHINIT,	0
	CLA
	TAD (SBDEV)	/ Device to ask about
	DCA INFO$
	CDF .
	CIF 10
	JMS I (7700)
	12    / INQUIRE request
INFO$:	DEVICE DSK
ENTRY$:	0
	HLT
	TAD INFO$+1	/ Save device number
	DCA LCLFIB+DEVNUM
	TAD ENTRY$	/ Is handler loaded?
	SNA
	JMS GETHDL	/ No, go load it
	DCA LCLFIB+DEVADR
	TAD FIB2+DEVNUM
	/ Now load handler for that device
	CDF .
	CIF 10
	JMS I (7700)
	1	/ FETCH request
ARG1$:	RKSPOT	      / Handler goes here
	HLT
	TAD ARG1$		/ Get entry point
	DCA LCLFIB+DEVADR
	TAD ARG1$
	DCA FIB2+DEVADR
	CDF DCTEND
	CIF 0
	JMP I FHINIT

GETHDL,	0
ENTRY$:	/ Load a handler
	JMP I GETHDL

/ Copy counted string from F1 to here then put
/ a NUL at the end.  Src address in AC, count in MQ.
/ We use the data buffer to hold the string for FPARSE.
GETFN,	0     / Fetch ASCII filename from F1
	CIA
	IAC
	CIA
	DCA INPTR	/ src-1
	MQA
	CIA
	DCA LIMIT
	STA		/ dest-1
	TAD LCLFIB+BUFADR
	DCA OUTPTR
LOOP$:	CDF DCTEND
	TAD I INPTR
	CDF .
	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$
	// Put a NUL at the end.
	DCA I OUTPTR
	JMP I GETFN

	PAGE
// Open file
	.ENTRY FHOPEN,FHRDL,FHRD
	.EXTERNAL $FPARSE, SBFILE, SBDEV
FHOPEN,	0
	JMS NEWFIB	/ Get a free FIB
	SNA
	JMP FAIL$
	JMS SETFIB	/ Make it current
	JMS GETFN
	TAD (LCLFIB+BUFADR)	/ Parse filespec
	JMS $FPARSE
	TAD LCLFIB+DEVADR	/ Is handler loaded?
	SNA CLA
	JMS GETHDL	/ No, go get it
	JMS $FILEIO
	2		/ IOPEN funtion
	SBFILE		/ SB name pointer
	CIF 00
	JMS RSTFIB	/ Restore FIB copy
	JMP I FHOPEN
FAIL$:	CLA
	JMP .-4

	.ENTRY FHCLOS
FHCLOS,	0
	JMS SETFIB
	JMS $FILEIO
	13
	HLT
	DCA LCLFIB+FILFLG	/ Clear flags
	JMS RSTFIB	/ Restore the FIB
	JMP I FHCLOS

	PAGE
// Read a line of text.  F1 buffer in AC, Length in MQ.
// This acts like ACCEPT.  Final length in AC, -1 if
// EOF.  Not counting CRLF.
FHRDL,	0
	TAD (-1)
	DCA OUTPTR
	MQA	/ Get max len
	CIA
	DCA LIMIT
	DCA COUNT
LOOP$:	CDF .
	JMS $FILEIO
	7		/ ICHAR
	JMP EOF$
	AND (177)	/ Strip parity bit
	DCA CHAR
	TAD CHAR
	TAD (-12)	/ Watch for end of line
	SNA
	JMP EOL$
	ISZ LIMIT	/ Watch for overflow
	JMP LOOP$
	TAD CHAR
	CDF DCTEND
	DCA I OUTPTR	/ Store and count it
	ISZ COUNT
	JMP LOOP$
EOL$:	TAD COUNT	/ Do not count CRLF
	TAD (-2)
	SKP
EOF$:	CLA CMA
	JMS RSTFIB	/ Save the FIB
	CIF 00
	JMP I FHRDL

// Read a block.
FHRD,	0
	CDF .
	CIF $FILEIO
	JMS $FILEIO
	5
	HLT
	CIF 00
	JMS RSTFIB
	JMP I FHRD

	PAGE
// WRITE-LINE.  Address in AC, count in MQ.
// SETFIB must have been called first.
	.ENTRY FHWRL
FHWRL,	0
	TAD (-1)
	DCA INPTR	/ Src-1
	MQA
	CIA
	DCA LIMIT	/ Count
LOOP$:	CDF DCTEND
	TAD I INPTR
	JMS OCHAR$
	ISZ LIMIT
	JMP LOOP$
	CDF .		/ Append CRLF
	TAD (15)
	JMS OCHAR$
	TAD (12)
	JMS OCHAR$
	CDF DCTEND
	CIF 00
	JMS RSTFIB
	JMP I FHWRL

OCHAR$:	0
	CDF .
	JMS $FILEIO	/ OCHAR
	6
	HLT
	CDF .
	JMP I OCHAR$
