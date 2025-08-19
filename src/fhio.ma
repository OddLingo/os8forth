	.TITLE Forth I/O Interface
// This module is an interface between the Forth
// World in Fields 0 and 1 and the OS8 I/O world
// in Field 2.
   .NOLIST
   .INCLUDE COMMON.MA
   .LIST

	.EXTERNAL TIB, ENGINE
	.XSECT FHIDX
	FIELD 2
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
FADDR,	0
FLEN,	0

	.DSECT FHBUF
	FIELD 2
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
GETFB$:	TAD (FILES)
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

// A way for the ENGINE to set the current file,
// to be followed immediately by a read/write call.
// Local routines can call SETFIB directly.
	.ENTRY SETFID
SETFID,	0
	CIF .
	JMS SETFIB
	CDF TIB
	CIF ENGINE
	JMP I SETFID

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

// Get device information
GETHDL,	0
	CLA
	TAD SBDEV	/ Copy device name
	DCA INFO$
	TAD SBDEV+1
	DCA INFO$+1
	CDF .
	CALUSR 12	/ INQUIRE request
INFO$:	DEVICE DSK
ENTRY$:	0
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
	DCA DNAME$
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
LOOP$:	CDF TIB	/ Read from dictionary
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
// Open file. Filename ptr in AC, length in MQ.
FHOPEN,	0
	DCA FADDR
	MQA
	DCA FLEN
	CDF .
	JMS NEWFIB	/ Get a free FIB
	SNA
	JMP FAIL$
	JMS SETFIB	/ Make it current

	JMS GETFN	/ Copy filename from F1
	TAD THEFIB+BUFADR	/ Parse it
	JMS $FPARSE
	JMS GETHDL	/ Make sure handler loaded
	JMS $FILEIO	/ Open the file
	2
	SBFILE		/ SB name pointer
	HLT

	JMS RSTFIB	/ Update our copy

	TAD FIBNUM	/ Return id number
	MQL
	CLA IAC		/ And ok status
	CDF TIB
	CIF ENGINE
	JMP I FHOPEN

FAIL$:	CLA
	JMP .-4

// Create file. Filename ptr in AC, length in MQ.
FHCRE,	0
	DCA FADDR	/ Save for later
	MQA
	DCA FLEN	/ Save name length
	CDF .
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

	JMS RSTFIB	/ Update our copy

	TAD FIBNUM	/ Return id number
	MQL
	CLA IAC		/ And ok status
	CDF TIB
	CIF ENGINE
	JMP I FHCRE

FAIL$:	CLA
	JMP .-4

// CLOSE-FILE ( id -- status )
	.ENTRY FHCLOS
FHCLOS,	0
	CDF .
	JMS SETFIB
	JMS $FILEIO
	13
	HLT
	CLA
	DCA THEFIB+FILFLG / Mark unused
	JMS RSTFIB	/ Copy it back
	CDF TIB
	CIF ENGINE
	JMP I FHCLOS

// FLUSH-FILE (	id -- status )
	.ENTRY FHFLUS
FHFLUS,	0
	CDF .
	JMS SETFIB
	JMS $FILEIO
	14
	HLT
	JMS RSTFIB
	CDF TIB
	CIF ENGINE
	JMP I FHFLUS

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
	CDF TIB
	AND (177)	/ Strip parity bit
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
	SKP
EOF$:	STA		/ -1 means end of file
	DCA CHAR	/ Stash length
	CDF .
	JMS RSTFIB	/ Save the FIB
	CDF TIB
	CIF ENGINE
	TAD CHAR	/ Length in AC
	JMP I FHRDL

// Read a block.
FHRD,	0
	CDF .
	CIF $FILEIO
	JMS $FILEIO
	5
	HLT
	JMS RSTFIB
	CDF TIB
	CIF ENGINE
	JMP I FHRD

// WRITE-LINE.  Address in AC, count in MQ.
// SETFIB must have been called first.
	.ENTRY FHWRL
FHWRL,	0
	TAD (-1)
	DCA INPTR	/ Src-1
	MQA
	CIA
	DCA LIMIT	/ Count
LOOP$:	CDF TIB
	TAD I INPTR
	JMS OCHAR$
	ISZ LIMIT
	JMP LOOP$
	TAD (15)	/ Append CRLF
	JMS OCHAR$
	TAD (12)
	JMS OCHAR$
DONE$:	JMS RSTFIB
	CDF TIB
	CIF ENGINE
	JMP I FHWRL

OCHAR$:	0
	CDF .
	JMS $FILEIO	/ OCHAR
	6
	JMP DONE$	/ Oops
	CLA
	JMP I OCHAR$
	/ AC >= 0: out of room
	/ AC<0: fatal
