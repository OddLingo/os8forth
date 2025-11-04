	.TITLE Forth I/O Interface
// This module is an interface between the Forth
// World in Fields 0 (the ENGINE) and 1 (the SYMBOL
// table) and the OS8 I/O world in Field 2.
	.EXTERNAL SYMBOL, ENGINE
	IOFLD=2

/ Get interfaces to the FILEIO package.
/	.NOLIST
/	.INCLUDE COMMON.MA
	.LIST
	.LIST MEB

	USR=17700	/ OS8 User Service Routine
	.MACRO OS8FUN FUNC
	CIF 10
	JMS USR
	FUNC
	.ENDM

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
X0,	0
X1,	0

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

	.MACRO FINFO B
	B
	ZBLOCK FIBLEN-1
	.ENDM

THEFIB=.	/ Active file information
BUFADR,	0	/ Address of 256 word buffer
HANDLR,	0	/ Device handler address
DEVNUM,	0	/ OS8 device number
BUFPOS,	0	/ 3-in-2 character position
BLOCKN,	0	/ Block# in file (1 origin)
FLAGS,	0	/ Flags
FIRST,	0	/ # first block in file
NBLKS,	0	/ # blocks in file
LAST,	0	/ # last block in file
DEVNAM,	0;0	/ Sixbit device name
FILNAM,	0;0;0	/ Sixbit filename
FILEXT,	0	/ Sixbit file extension
FILDAT,	0	/ Date
FIBLEN=.-THEFIB

/ Flag word layout:
/  4000 buffer has been modified
/  2000 file is open
/  0001 file is tentative - not yet closed

/ Used by low-level dispatcher
ARG,	0		/ Copy of input arg
LC,	0		/ Loop counter
TMP,	0
AC,	0		/ In-out AC value
FUNC,	0		/ Function code

/ Used by parser
T0,	0	/Tmp
T2,	0	/Tmp.
SRC,	0	/Source pointer.
DEST,	0	/Destination address.
TL,	0
OFFSET,	0
/ Filenames are copied to TEMP in normalized
/ form, not including separator characters.
TEMP,	ZBLOCK 14

.SBTTL Stack access routines

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

	.RSECT FTHIO
	FIELD 2
	.SBTTL Manage file info
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
	TAD (FLAGS)
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
	TAD FIBPTR	/ From 'the' FIB
	DCA FROM$
	CALL COPY
	-FIBLEN
FROM$:	0
	THEFIB
	JMP I SETFIB

// Restore our copy of the active FIB
RSTFIB,	0
	CLA
	TAD FIBPTR
	DCA DEST$
	CALL COPY
	-FIBLEN
	THEFIB
DEST$:	0
	JMP I RSTFIB

	.SBTTL Device information

// Get device information.  The device name must
// have already been parsed into DEVNAM, 2 sixbit
// words.
GETHDL,	0
	CLA
	CALL COPY
	-2
	DEVNAM
	INFO$
	CDF .
	OS8FUN 12	/ INQUIRE request
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

	CALL COPY	/ Copy device name
	-2
	DEVNAM
	DNAME$
	OS8FUN 1	/ FETCH request
DNAME$:	DEVICE DSK
ARG3$:	0	/ Handler load address
	HLT
	TAD ARG3$		/ entry point
	DCA HANDLR
	TAD DNAME$+1		/ device number
	DCA DEVNUM
	JMP I GETHDL

TOFIB$:	DCA HANDLR	/ Save entry
	TAD INFO$+1		/ Save number
	DCA DEVNUM
	JMP I GETHDL

// Load a device handler.  The device name is at DEVNAM.
HDSPOT,	7600
	PAGE
/ Copy counted string from Forth dictionary to here
/ then put a NUL at the end.  We use the data buffer
/ to hold the string for PARSE.
GETFN,	0
	STA
	TAD FADDR
	DCA INPTR	/ src-1
	TAD FLEN
	CIA
	DCA LIMIT	/ -Length
	STA		/ dest-1
	TAD BUFADR
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

	.SBTTL Forth file interface

	.ENTRY FHOPEN, FHRDL, FHRD, FHCRE
// OPEN-FILE ( addr len -- id status )
FHOPEN,	0
	ENTER		/ Sync stack
	POP FLEN	/ Length of name
	POP FADDR	/ Address of name
	JMS NEWFIB	/ Get a free FIB
	SNA 		/ Got one?
	JMP FAIL$	/ No
	JMS SETFIB	/ Make it current

	CALL COPY	/ Set default device
	-2
	DFLT$
	DEVNAM

	/ Copy filename from F1 into data buffer,
	/ then parse it into the info block.
	JMS GETFN
	TAD BUFADR	/ Parse it
	JMS PARSE
	JMS GETHDL	/ Make sure handler loaded

	/ $FILEIO returns status in AC:
	/   =0	  Sucess
	/   >=0	  FILE NOT FOUND. NEW FILE CREATED.
	/   <0	  FATAL DEVICE ERROR
	JMS $FILEIO	/ Open the file
	2
	FILNAM		/ SB name pointer
	JMP FAIL$

	JMS RSTFIB	/ Update our copy
	PUSH FIBNUM	/ Return id number
	PUSH		/ And ok status
	RETURN FHOPEN	/ Resync stack

FAIL$:	CLA IAC
	JMP .-4
DFLT$:	DEVICE DSK

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
	TAD BUFADR	/ Parse it
	JMS PARSE
	JMS GETHDL	/ Make sure handler loaded
	JMS $FILEIO	/ Create the file
	3
	FILNAM		/ SB name pointer
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
	DCA FLAGS / Mark unused
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
	TAD BUFPOS / BUFPOS goes 0 to 777
	AND [774]
	CLL RTR
	DCA LOW	 / Save shifted upper 7 bits
	/ LOW is now 0 to 177
	TAD BUFPOS
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
	TAD BLOCKN
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
	TAD BUFADR
	DCA OUTPTR
	TAD (-400)
	DCA LIMIT
LOOP$:	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$
	JMP I INIBUF

/ General purpose copy words locally.  Follow
/ call with negative count, from, and destination
/ addresses
COPY,	0
	TAD I COPY	/ Get negative count
	DCA LIMIT
	ISZ COPY
	STA
	TAD I COPY	/ Source minus 1
	DCA INPTR
	ISZ COPY
	STA
	TAD I COPY	/ Get destination minus 1
	DCA OUTPTR
LOOP$:	TAD I INPTR	/ Loop copying
	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$
	ISZ COPY	/ Skip last arg
	JMP I COPY


	.SBTTL PARSE filenames
	.ENABLE	7BIT
/ Parse an ASCII device:filename.ext into SIXBIT.
/ Source address in AC.  SIXBIT output to file info.

/ Based on FPARSE by Johnny Billquist 35 years ago
/ but integrated into the rest of the Forth I/O
/ environment to save space.
PARSE,	0
	DCA SRC		/Save as source pointer.
	TAD (DEVNAM)
	DCA DEST	/Save as dest. address.

	/ Zero out the temporary storage.
	TAD (TEMP-1)
	DCA OUTPTR
	TAD (-14)	/Set loop to 14.
	DCA LIMIT
ZLOOP$:	DCA I OUTPTR	/ Clear a word
	ISZ LIMIT
	JMP ZLOOP$	/Repeat.

	JMS GETDEV	/ Find device name
	JMP NODEV	/ No device found.
	TAD (TEMP)	/ Found so save it
	DCA T1
	/ GETDEV set t0
	JMS	CPYNAM	/Copy device T0->T1
	TAD	(-6)	/Total length is 6.
	DCA	TL
	TAD	(TEMP)	/Offset to start.
	DCA	OFFSET

DONAME,	JMS GETNAM	/Get file name.
	JMP EXT$	/No filename found. Pack result.
	TAD (TEMP+4) /Found. Set destination to tmp.
	DCA T1
	JMS CPYNAM	/Copy filename T0->T1

EXT$:	JMS GETEXT	/Get extension.
	JMP PACK$	/Not found. Pack result.
	TAD (TEMP+12)	/Found. Set dest to tmp.
	DCA T1
	JMS CPYNAM	/Copy extension T0->T1

// Pack TEMP to DEST
PACK$:	CLA
	TAD	OFFSET	/Time to pack... Set source to tmp.
	DCA	T2
	TAD	TL	/Set count to 6 words.
	DCA	LIMIT
LOOP$:	TAD I	T2	/Get char.
	ISZ	T2	/Bump source pointer.
	AND	(77)	/Make SIXBIT.
	BSW		/High char.
	DCA	T1	/Save it temporarily.
	TAD I	T2	/Get next char.
	ISZ	T2	/Bump source pointer.
	AND	(77)	/Make SIXBIT.
	TAD	T1	/Combine with first char.
	DCA I	DEST	/Save word.
	ISZ	DEST	/Bump destination pointer.
	ISZ	LIMIT	/Bump count.
	JMP	LOOP$	/Repeat.
	JMP I	PARSE	/Return.

	PAGE
GETEXT,	0		/Get extension.
	TAD	SRC	/Get source pointer.
	DCA	T0	/Save it in tmp.
	JMS	GETCHR	/Get char.
	SNA CLA		/Was it NUL?
	JMP I	GETEXT	/Yes. No extension.
	ISZ	SRC	/No. Bump source pointer.
	JMS	LOOK	/Search for NUL.
	TAD	(-1)	/Decr. length of string.
	SNA		/Empty string?
	JMP I	GETEXT	/Yes. No extension.
	TAD	(2)	/Limit length to 2.
	SPA
	CLA
	TAD	(-2)
	DCA	LIMIT	/Save as loop count.
	TAD	SRC	/Get source pointer.
	DCA	T0	/Save as from tmp.
	ISZ	GETEXT	/Bump return.
	JMP I	GETEXT	/Return.

	PAGE

// Copy from T0 to T1 while converting to uppercase.
CPYNAM,	0
LOOP$:	JMS	GETCHR	/Get char.
	TAD	(-140)	/Convert to uppercase...
	SMA
	TAD	(-40)
	TAD	(140)
	DCA I	T1	/Save it.
	ISZ	T1	/Bump pointer.
	ISZ	LIMIT	/Bump count.
	JMP LOOP$
	JMP I	CPYNAM	/Return.

GETCHR,	0
	TAD I	T0	/Get char.
	ISZ	T0	/Bump pointer.
	JMP I	GETCHR	/Return.

// Locate the device-name string up to a colon
// (if present).
GETDEV,	0		/Get device.
	TAD	(":)	/Seek device separator.
	JMS	LOOK
	TAD	(-1)	/Decr. string length.
	SNA		/Only ":" found?
	ISZ SRC		/Yes. Use default.
	SNA SPA		/Colon found and len>0?
	JMP I GETDEV	/No. not found. Return.
	TAD	(-4)	/Limit length to 4.
	SMA
	CLA
	TAD	(4)
	CIA
	DCA	LIMIT	/Save as loop count.
	TAD	SRC	/Get source pointer.
	DCA	T1	/Save it tmp.
	TAD	T0	/Get ptr to filename.
	DCA	SRC	/Save it as new source pointer.
	TAD	T1	/Get old source pointer.
	DCA	T0	/Save for copy.
	ISZ	GETDEV	/Bump return.
	JMP I	GETDEV	/Return.

	/No device found. Copy only filename at end.
NODEV,	CLA
	TAD	(-4)
	DCA	TL
	TAD	(TEMP+4)
	DCA	OFFSET
	IAC RAL CLL
	TAD	DEST
	DCA	DEST
	JMP	DONAME

LOOK,	0		/Search for char or EOS.
	CIA		/Make compare out of char.
	DCA	T1	/Save compare.
	TAD	SRC	/Get source pointer.
	DCA	T0	/Save as tmp pointer.
	DCA	LIMIT	/Clear count.
1$:	ISZ	LIMIT	/Bump count.
	JMS	GETCHR	/Get char.
	SNA		/EOS?
	JMP	2$	/Yes.
	TAD	T1	/Compare.
	SZA CLA		/Equals?
	JMP	1$	/No. Repeat.
	TAD	LIMIT	/Yes. Get count.
	JMP I	LOOK	/Return.
2$:	TAD	LIMIT	/EOS. Get count.
	CIA		/Negate.
	JMP I	LOOK	/And return.

// Locate the main filename string, up to the
// extention (if any).
GETNAM,	0		/Get file name.
	TAD	(".)	/Look out for extension separator.
	JMS	LOOK
	SMA		/If positive, make negative.
	CIA
	IAC		/Decr. length by one.
	SNA		/Zero length?
	JMP I	GETNAM	/Yes. Return. No filename.
	TAD	(6)	/Limit length to 6.
	SPA
	CLA
	TAD	(-6)
	DCA	LIMIT	/Save as loop count.
	TAD	SRC	/Get source pointer.
	DCA	T1	/Save tmp.
	CMA		/Get extension separator pointer.
	TAD	T0
	DCA	SRC	/Save as new source pointer.
	TAD	T1	/Get old source pointer.
	DCA	T0	/Save as from pointer for copy.
	ISZ	GETNAM	/Bump return.
	JMP I	GETNAM	/Return.


/ FILEIO IS A FILE I/O PACKAGE FOR OS/8
/ IT CONSISTS OF THE FOLLOWING ROUTINES:
/
/	#	FUNCTION	DESCRIPTION
/
/	1	LOOKUP	-	DIRECTORY LOOKUP
/	2	IOPEN	-	OPEN FILE FOR INPUT
/	3	OOPEN	-	OPEN FILE FOR OUTPUT
/	4	PUT	-	PUT BLOCK IN FILE
/	5	GET	-	GET BLOCK FROM FILE
/	6	OCHAR	-	OUTPUT CHAR TO FILE
/	7	ICHAR	-	INPUT CHAR FROM FILE
/	10	PRINT	-	PRINT STRING
/	11	POSIT	-	POSITIONING OF THE FILE POINTER
/	12	POSITP	-	POSITION OF THE FILE POINTER
/	13	CLOSE	-	CLOSE FILE
/	14	FLUSH	-	FLUSH OUTPUT BUFFER
/
/ NOTE: A STRING IS A SIXBIT STRING DELIMITED BY A NULL.
/		@ IS CONTROL QUOTE.
/
/ ALL FUNCTIONS ARE CALLED IN THE FORMAT:
/
/	TAD	VAL	(OPTIONAL)
/	CIF	FILEIO
/	JMS	FILEIO
/	<FUNCTION>
/	<ARG>		(NOT ALWAYS)
/	ERROR RETURN
/	NORMAL RETURN
/
/ The appropriate File Block must have been copied into
/ THEFIB before calling these routines.
/
	USR=7700
	.SBTTL Low level OS8 interfaces

	PAGE
/
/	FILEIO Dispatcher
/
$FILEIO,
	0		/ENTRY TO FILEIO.
	DCA AC		/SAVE AC
	TAD I $FILEIO	/GET FUNCTION
	DCA FUNC	/Save it
	ISZ $FILEIO
	TAD I $FILEIO	/GET ARG
	DCA ARG

	/ Check for device driver.
	TAD	HANDLR
	SZA CLA
	JMP	DOIT	/ Loaded, ok to dispatch
	CMA		/ Not loaded, fatal error.
	JMP	ERR1

DOIT,	TAD	FUNC	/GET FUNCTION CODE.
	SPA SNA		/IS IT >0?
	JMP	FERR	/NO. FUNCTION ERROR.
	TAD	(-MAXFUN	/IS IT >MAXFUN?
	SMA
	JMP	FERR	/YES. FUNCTION ERROR.

	/ Does the function require an open file?
	TAD	(MAXFUN-NOPFUN
	SPA CLA
	JMP	NOTFUN	/NO.

	TAD	FLAGS	/GET FLAGS.
	RTL
	SNL CLA		/IS FILE OPEN?
	JMP ERR1	/NO. OPEN ERROR.
NOTFUN,	TAD FUNC	/ Get function again
	CLL RAL		/MULTIPLY FUNCTION BY 2.
	TAD DODISP	/ADD ADDRESS OF TABLE.
	DCA TMP		/SAVE POINTER INTO TABLE.
	TAD I TMP	/ Get 1st word (ARGUSE)
	SZA CLA		/DOES THIS FUNCTION USE ARG?
	ISZ $FILEIO	/YES. BUMP RETURN ADDRESS.
	ISZ TMP		/POINT TO NEXT WORD (FUNC ADDRESS)
	TAD I TMP	/GET ADDRESS.
	DCA TMP		/SAVE IT.
	JMS I TMP	/JUMP TO IT.

XIT1,	ISZ $FILEIO	/NORMAL EXIT. BUMP RETURN ADDRESS
	SKP CLA		/SKIP ERROR ENTRY.
ERR1,	DCA AC		/ERROR ENTRY. SAVE ERROR CODE.
	/ Restore AC and return
	TAD	AC
	JMP I	$FILEIO

FERR,	CIF	10
	JMS	USR	/FUNCTION ERROR. USER ERROR 11.
	7
	11

/ The dispatch tabhle has two words for each function.
/ The first word is non-zero if the function needs
/ an open file.  The second word is the entry address.
DODISP,	DODISP;0
	-1;0 / LOOK1
	-1;IOPEN1
	-1;OOPEN1
	NOPFUN=.-DODISP%2
	0;PUT1
	0;GET1
	0;OCHAR1
	0;ICHAR1
	-1;0	/ Unused PRINT1
	-1;POSIT1
	-1;POSIP1
	0;CLOSE1
	0;FLUSH1
/
	MAXFUN=.-DODISP%2

	PAGE
	.SBTTL	IOPEN Open an existing file

/ 2	IOPEN
/
/ SBNAME contains SIXBIT file name and extension.
/
/ On error AC indicates reason:
/	>=0	FILE NOT FOUND. NEW FILE CREATED.
/	<0	FATAL DEVICE ERROR
IOPEN1,	0
	TAD (FILNAM)	/ Force filename addr
	DCA NAME$	/ ( it gets overwritten )
	TAD DEVNUM	/ Device num in AC
	OS8FUN 2	/ Lookup file on this device
NAME$:	0		/ Filename or 1st block
SIZE$:	0
	JMP ERRP

	/ NAME$ is now the first block
	/ SIZE$ is now the file size

	/ Initialize Info Block
	TAD (1000)	/ Means "empty"
	DCA BUFPOS	/ SET BUFFER offset
	DCA BLOCKN	/ SET FILE BLOCK#
	TAD (2000
	DCA FLAGS	/ SET FLAGS
	TAD NAME$
	DCA FIRST	/ set first block#
	TAD SIZE$
	CIA
	DCA NBLKS	/ Negative file size
	TAD NBLKS	/ last=first+size
	TAD FIRST
	DCA LAST
	JMP I IOPEN1

ERRP,/	CLA
/	JMS	OOP2	/NO FILE FOUND. TEST TO OPEN OUTPUT.
/	CLA IAC		/AC=1
	JMP	ERR1	/ERROR RETURN. 1 MEANS FILE CREATED.

	PAGE
	.SBTTL OOPEN Open a new file

/ 3	OOPEN
/
/ AC	MAX SIZE IN BLOCKS OF FILE
/
/ ERROR:
/	AC	>=0	NONFATAL ERROR
/		<0	FATAL ERROR
/
OOPEN1,	0
	TAD (FILNAM)	/ Parse puts name here
	DCA 1$
	TAD DEVNUM	/ Device #
	CIF	10
	JMS	USR	/CALL USR
	3		/ENTER
1$:	FILNAM		/ First output block
2$:	0		/ Neg out limit
	JMP	ERR1

	TAD (1000)
	DCA BUFPOS	/ Buffer offset
	DCA BLOCKN	/ Block# zero
	TAD (2001)
	DCA FLAGS	/ FILE FLAGS
	TAD 1$
	DCA FIRST	/ First blk in file
	DCA NBLKS	/ Zero size
	TAD 2$		/ Negative max len
	CIA
	TAD 1$		/ plus start
	DCA LAST	/ gives end block.

	TAD 7666	/ Current date
	DCA FILDAT	/SET FILE DATE
	JMP I OOPEN1

	PAGE
	.SBTTL PUT Write the current buffer
/
/ 4	PUT	Write current buffer
/
/ AC		RELATIVE BLOCK #
/
/ ERROR:
/	AC	>=0	NO MORE SPACE
/	AC	<0	FATAL DEVICE ERROR
/
PUT1,	0
	ISZ BLOCKN	/BUMP LAST.
	TAD AC			/GET REQUESTED BLOCK.
	SZA		/ZERO?
	DCA BLOCKN	/NO. SAVE AS DEFAULT.

	/ Unlock modern operating systems, OS/8
	/ does I/O with physical block numbers so
	/ we have to calculate it.
	STA 		/ Zero-origin block
	TAD BLOCKN	/ Relative block to write.
	TAD FIRST	/ Plus first block
	DCA OBLK$	/ is absolute device block.

	TAD LAST	/GET FILE END POINTER...
	CIA
	CLL CML
	TAD OBLK$	/COMPARE WITH FILE PTR...
	SNL CLA		/L=0 PTR OUT OF FILE SPACE.
	JMP ERR1	/YES. ERROR!
	TAD BUFADR	/NO. GET BLOCK ADDRESS
	DCA OADR$	/SAVE AS ADDRESS TO OUTPUT FROM.
	DCA OFUN$	/SAVE AS FUNCTION.
	CIF		/CALL DEVICE DRIVER WITH THIS INFO.
	JMS I HANDLR
OFUN$:	<4200+<IOFLD^10>> / Write one block from our field.
OADR$:	0		  / Buffer address
OBLK$:	0		  / Absolute block number
	JMP ERR1	/DEVICE ERROR.

	TAD FLAGS	/CLEAR MODIFIED FLAG.
	AND (3777
	DCA FLAGS
	TAD BLOCKN	/GET WRITTEN BLOCK.
	CIA CLL CML
	TAD NBLKS	/COMPARE WITH SIZE.
	SNL		/SIZE GROW?
	JMP 1$		/NO.
	CIA		/YES. ADD CHANGE.
	TAD NBLKS
	DCA NBLKS	/SAVE AS NEW SIZE.

1$:	CLA
	TAD BLOCKN	/GET AC.
	DCA AC	/SAVE BLOCK OPERATED FROM.

	JMP I PUT1	/RETURN
	.SBTTL	GET Read a block into the buffer

/
/	5	GET
/
/ AC		RELATIVE BLOCK #
/
/ ERROR:
/	AC	>=0	END OF FILE
/	AC	<0	FATAL DEVICE ERROR
/
GET1,	0
	TAD FLAGS	/GET FLAGS
	SMA CLA		/ Was old buffer modified?
	JMP 1$		/NO.

	/ Need to write out old block first.
	TAD AC		/YES. SAVE AC.
	DCA ACS
	TAD BLOCKN / SET UP FOR PUT TO OLD BLOCK.
	DCA AC
	JMS PUT1	/PUT BLOCK
	TAD ACS		/RESTORE AC
	DCA AC

1$:	TAD AC		/CHECK IF BLOCK ALREADY IN MEMORY...
	SNA
	JMP	2$	/BLOCK ZERO DOESN'T COUNT...
	CIA
	TAD BLOCKN
	SNA CLA
	JMP I GET1	/ALREADY IN MEMORY. DON'T READ IT!

2$:	ISZ BLOCKN	/BUMP DEFAULT.
	TAD AC			/GET AC.
	SZA		/ZERO?
	DCA BLOCKN	/NO. SAVE AS DEAFULT.

	CMA		/NO. CALCULATE ABSOLUTE ADDRESS.
	TAD BLOCKN	/ relative block
	TAD FIRST	/ plus first block
	DCA IBLK$	/SAVE IT.

	/ OS8 does not check file limit so we have to
	/ do it here.
	TAD LAST	/GET FILE END PTR.
	CIA
	CLL CML
	TAD IBLK$	/COMPARE WITH FILE PTR.
	SNL CLA		/L=0 MEANS OUT OF FILE BOUNDS. ERROR!
	JMP ERR1	/YES. ERROR.

	/ In range so proceed
	TAD BUFADR
	DCA IADR$	/TRANSFER ADDRESS...

	CIF		/CALL DEVICE DRIVER.
	JMS I HANDLR
	<0200+<IOFLD^10>> / Read one block into our field
IADR$:	0
IBLK$:	0
	JMP ERR1

	JMP I GET1	/RETURN

ACS,	0

// Get next sequential block in a file.
// ICHAR and OCHAR call this as required.
NXTBLK,	0
	CLA
	TAD BLOCKN	/GET LAST BLOCK.
	DCA AC	/SAVE AS AC FOR PUT ROUTINE.
	TAD FLAGS	/BUFFER MODIFIED?
	SPA CLA
	JMS PUT1	/PUT BLOCK.
	ISZ AC		/SET AC TO READ BLOCK
	TAD LAST	/GET END PTR.
	CIA
	CLL CML
	TAD AC		/GET BLOCK TO READ.
	TAD FIRST	/ADD ADDRESS.
	SNL SZA CLA	/ADDRESS > END?
	JMP ERR1	/YES. ERROR. NO MORE SPACE!

	CMA
	TAD AC	/GET PTR.
	CIA CLL CML
	TAD NBLKS	/COMPARE WITH SIZE.
	SNL SZA
	ISZ NXTBLK	/PTR <= SIZE. BUMP RETURN. READ DONE.
	SNL SZA CLA	/PTR > SIZE?
	JMS GET1	/NO. READ BLOCK.
	DCA BUFPOS /CLEAR OFFSET.
	TAD AC		/GET CURRENT BLOCK.
	DCA BLOCKN /SAVE CURRENT BLOCK.

	JMP I	NXTBLK	/RETURN
/
	PAGE
	.SBTTL	OCHAR Write one ASCII character

/
/ 6	OCHAR Write one ASCII character at
/ 	      current file position.
/ AC	CHARACTER
/
/ ERROR:
/	AC	>=0	NO MORE SPACE
/	AC	<0	FATAL DEVICE ERROR
/
ICHAR,
OCHAR1,	0
	TAD	AC	/GET CHARACTER
	DCA	OCHAR	/SAVE IT.

	TAD	BUFPOS	/GET OFFSET.
	TAD	(-1000)		/CHECK IF END OF BLOCK REACHED.
	SZA CLA
	JMP	1$		/NO.
	JMS	NXTBLK	/YES. NEXT BLOCK.
	NOP

1$:	TAD	BUFPOS	/GET COUNT
	AND	(1774)
	CLL RAR
	TAD BUFADR
	DCA ARG		/ POINTER TO DOUBLEWORD CONTANING CHAR
	TAD BUFPOS
	AND (3)
	TAD (-1)
	SNA		/0 = 2:ND CHAR...
	ISZ ARG	/2:ND CHAR IS IN 2:ND WORD.
	SMA SZA CLA	/3:RD CHAR?
	JMP OSPLIT	/3:RD...

	TAD I ARG	/GET WORD.
	AND (7400	/MASK CHAR.
	TAD OCHAR	/PUT IN NEW CHAR.
	DCA I ARG	/RESTORE.
OCRET,	ISZ BUFPOS	/BUMP POINTER.
	TAD FLAGS	/SET BUFFER MODIFIED BIT.
	RAL
	CLL CML RAR
	DCA	FLAGS
	TAD	BUFPOS	/CHECK IF BUFFER IS FULL.
	TAD	(-1000)
	SZA CLA
	JMP	1$		/IS NOT.
	TAD	BLOCKN	/IT IS. GET CURRENT BLOCK.
	DCA	AC
	JMS	PUT1		/OUTPUT CURRENT BLOCK

1$:	TAD	OCHAR		/GIVE OUTPUT CHARACTER BACK.
	DCA	AC
	JMP I	OCHAR1

OSPLIT,	CLA CLL CMA RAL	/REPEAT LOOP TWICE.
	DCA	LC
	TAD	OCHAR	/GET CHAR.
	RTL;RTL		/GET HIGH PART.
1$:	AND	(7400	/MASK.
	DCA	TMP	/SAVE IT.
	TAD I	ARG	/GET 1:ST WORD.
	AND	(377	/MASK AWAY PREVIOUS CHAR.
	TAD	TMP	/SAVE NEW CHAR.
	DCA I	ARG	/SAVE WORD.
	ISZ	ARG	/POINT AT NEXT WORD.
	TAD	OCHAR	/GET CHAR.
	RTR;RTR;RAR	/GET LOW PART
	ISZ	LC	/LOOP.
	JMP	1$
	CLA
	ISZ	BUFPOS
	JMP	OCRET	/CONTINUE.
	.SBTTL	ICHAR Read one ASCII character
/
/ 7	ICHAR Read next ASCII character
/
/ AC	The read character
/
/ ERROR:
/	AC	>=0	END OF FILE
/	AC	<0	FATAL DEVICE ERROR
OCHAR,
ICHAR1,	0
	TAD BUFPOS	/CHECK BUFFER COUNT.
	TAD (-1000)		/END?
	SZA CLA
	JMP 1$		/NO.
	JMS NXTBLK		/YES.
	JMP ERR1	/NO READ DONE. EOF.

1$:	TAD BUFPOS	/GET BUFFER COUNT.
	AND (1774)
	CLL RAR
	TAD BUFADR
	/ Save. First of two words of 3 chars.
	DCA ARG
	TAD BUFPOS
	AND (3)
	TAD (-1)
	SNA
	ISZ ARG
	SMA SZA CLA
	JMP ISPLIT	/ Go do third char
	TAD I ARG	/GET WORD.
	AND (377)	/ Mask 8 bit byte
PRET,	ISZ BUFPOS
	DCA AC	/SAVE CHAR.
	JMP I ICHAR1	/RETURN.

	/ Back up for 3rd of 3 chars.
ISPLIT,	TAD I ARG	/ High part in 1st word
	AND (7400	/MASK
	CLL RTR;RTR	/MOVE TO PLACE.
	DCA TMP		/SAVE.
	ISZ ARG
	TAD I ARG	/ Low part in 2nd word
	AND (7400	/MASK
	CLL RTL;RTL;RAL	/ Move thru link
	TAD TMP		/ Merge saved hi part
	ISZ BUFPOS
	JMP PRET	/CONTINUE.

	PAGE
	.SBTTL	POSIT Seek file to a place
/ 11	POSIT
/
/ ARG	POINTER TO POSITION (24BIT)
/
/ ERROR:
/	AC	>=0	END OF FILE
/		<0	FATAL DEVICE ERROR
/
POSIT1,	0
	TAD I	ARG	/GET ADDRESS OF ARGUMENT.
	DCA	TMP
	TAD I	TMP	/GET BLOCK #.
	ISZ	TMP
	DCA	AC
	TAD I	TMP	/GET OFFSET.
	DCA	BUFPOS
	CDF	.
	JMS	GET1	/READ IN BLOCK.
	JMP I	POSIT1	/RETURN
	.SBTTL	POSITP Report current file position
/
/ 12	POSITP
/
/ AC	RETURNED LOW PART OF POS.
/ ARG	POINTER TO ADDRESS FOR HIGH PART.
/
/	ERROR:
/	NONE

POSIP1,	0
	TAD I	ARG	/GET POINTER TO RESULT ADDRESS.
	DCA	TMP
	TAD	BLOCKN	/GET BLOCK.
	DCA I	TMP
	ISZ	TMP
	TAD	BUFPOS	/GET OFFSET.
	DCA I	TMP
	CDF	.
	JMP I	POSIP1	/RETURN
	.SBTTL	CLOSE the file
/ 13	CLOSE
/
/ ERROR:
/	AC	>=0	NO MORE SPACE
/		<0	FATAL DEVICE ERROR

CLOSE1,	0
	TAD FLAGS	/GET FLAGS.
	SMA CLA		/MODIFIED BLOCK?
	JMP 1$		/NO.
	TAD BLOCKN /YES. Write it
	DCA AC
	JMS PUT1

1$:	TAD FLAGS	/GET FLAGS.
	RAR
	SNL CLA		/ Tentative file?
	JMP ECLOS$	/ no

	TAD (FILNAM)
	DCA FNAM$	/ Filename ptr

	TAD NBLKS
	DCA FSIZ$	/ Final size

	TAD DEVNUM	/ Dev #
	CIF 10
	JMS USR		/ USR CLOSE.
	4
FNAM$:	0	/ Pointer to name
FSIZ$:	0	/ Blocks in file
	JMP	ERR1

ECLOS$:	DCA FLAGS	/CLEAR FILE FLAGS.
	JMP I CLOSE1	/RETURN

	.SBTTL	FLUSH write modified blocks
/ 14	FLUSH
/
/ OUTPUT:
/	AC		BLOCK #
/
/ ERROR:
/	AC	>=0	NO MORE SPACE
/		<0	FATAL DEVICE ERROR
/
FLUSH1,	0		/ENTRY TO FLUSH.
	DCA AC	/CLEAR AC.
	TAD FLAGS      / Was block modified?
	SMA CLA
	JMP I FLUSH1	/ No..

	/ Finish current packed word
PAD$:	TAD BUFPOS
	AND (3)		/GET BYTE OFFSET.
	SNA CLA		/OFFSET=0?
	JMP FILL$	/YES.
	JMS OCHAR1	/NO. OUTPUT A NUL.
	JMP PAD$	/REPEAT.

	/ Set up zeroing rest of block
FILL$:	TAD BUFPOS	/GET OFFSET.
	AND (1774)	/GET WORD OFFSET.
	CLL RAR
	DCA TMP		/SAVE OFFSET.
	TAD TMP
	TAD (-400) 	/GET COUNT.
	SNA
	JMP WRITE$	/ALREADY AT END OF BLOCK.
	DCA LC
	TAD TMP		/GET OFFSET.
	TAD BUFADR
	DCA TMP		/SAVE ADDRESS.

	/ Fill rest of block with zeros
LOOP$:	DCA I TMP	/CLEAR WORD.
	ISZ TMP		/BUMP POINTER.
	ISZ LC		/BUMP COUNTER.
	JMP LOOP$	/LOOP.

WRITE$:	TAD (1000)	/SET POINTER TO END OF BLOCK.
	DCA BUFPOS
	TAD BLOCKN	/GET CURRENT BLOCK #.
	DCA AC
	JMS PUT1	/OUTPUT CURRENT BLOCK #.
	JMP I FLUSH1

	.SBTTL Data buffers & file info
/ File Information Blocks and buffers.  There is one
/ buffer assigned to each file.
	.DSECT BLOCKS
	FIELD 2
FIB1,	FINFO BUF1
FIB2,	FINFO BUF2
BUF1=.; *.+400
BUF2=.; *.+400
