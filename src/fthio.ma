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

// The BEGIN and RETURN macros synchronize use
// of the stack and address spaces.  They must
// be used as first and last lines in routines
// called from the ENGINE.
	.MACRO BEGIN
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
FILES,	FILE1, FILE2
MAXFIB,	-2
FIBPTR,	0	/ Address of selected FIB
FIBNUM,	0	/ The file-id
LIMIT,	0	/ A negative loop counter
COUNT,	0	/ Positive counter
CHAR,	0	/ ASCII character
FADDR,	0	/ Filename address
FLEN,	0	/ Filename length
HIGH,	0	/ High 12 bits of dblword
LOW,	0	/ Low 12 bits of dblword
OURSP,	0	/ Local copy of SP
REALSP,	SP	/ F0 engine stack pointer
T1,	0

	.MACRO FINFO
	DATA$
	ZBLOCK FIBLEN-1
DATA$:	0
	*.+377
	.ENDM

THEFIB=.	/ Active file information
BUFADR,	0	/ Address of 256 word buffer
HANDLR,	0	/ Device handler address
DEVNUM,	0	/ OS8 device number
BUFPOS,	0	/ 3-in-2 character position
/ Relative block number of the current buffer
BLOCKN,	0	/ (1 origin)
FLAGS,	0	/ Flags
/ Absolute block number of file start
FIRST,	0	/ # first block in file
NBLKS,	0	/ # blocks in file
/ Absolute block number of file end
LAST,	0	/ # last block in file
/ SIXBIT device:filename.ext
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
	.SBTTL Open an existing file

// The FH* routines are called from the Forth ENGINE
// in Field 0.
	PAGE
	.ENTRY FHOPEN, FHRDL, FHCRE
// OPEN-FILE ( addr len -- id status )
FHOPEN,	0
	BEGIN		/ Sync stack
	POP FLEN	/ Length of name
	POP FADDR	/ Address of name
	JMS NEWFIB	/ Get a free FIB
	SNA 		/ Got one?
	JMP FAIL$	/ No
	CALL SETFIB	/ Make it current

	CALL COPY	/ Set default device
	-2
	DFLT$		/ to "DSK".
	DEVNAM

	/ Copy filename from F1 into data buffer,
	/ then parse it into the info block.
	JMS GETFN
	JMS PARSE	/ Parse it
	JMS GETHDL	/ Make sure handler loaded

	/ Tell OS8 where the filename is, and the
	/ device number.  It will look it up in the
	/ directory and return the first block number
	/ and the size.
	TAD (FILNAM)	/ Force filename addr
	DCA NAME$	/ ( it gets overwritten )
	TAD DEVNUM	/ Device num in AC
	OS8FUN 2	/ Lookup file on this device
NAME$:	0		/ Filename or 1st block
SIZE$:	0
	JMP FAIL$
	/ NAME$ is now the first block
	/ SIZE$ is now the NEGATIVE file size

	/ Initialize Info Block
	TAD (1000)	/ Buffer position to mean
	DCA BUFPOS	/ it is empty.
	DCA BLOCKN	/ BLOCK# zero
	TAD (2000	/ Set OPEN flag
	DCA FLAGS
	TAD NAME$	/ Save first block#
	DCA FIRST
	TAD SIZE$	/ Save POSITIVE size
	CIA
	DCA NBLKS
	TAD NBLKS	/ Compute last block from
	TAD FIRST	/ first + size
	DCA LAST

	CALL RSTFIB	/ Update our copy
	PUSH FIBNUM	/ Return id number
RET$:	PUSH		/ And ok status
	RETURN FHOPEN	/ Resync stack

FAIL$:	CLA IAC
	JMP RET$
DFLT$:	DEVICE DSK

	.SBTTL Create a new file
// CREATE-FILE( addr len mode -- id status )
// status=0 means ok.
FHCRE,	0
	BEGIN		/ Sync stack
	POP		/ Ignore mode
	POP FLEN
	POP FADDR
	JMS NEWFIB	/ Get a free FIB
	SNA
	JMP FAIL$	/ None left.
	CALL SETFIB	/ Make it current

	JMS GETFN	/ Copy filename from F1
	JMS PARSE	/ Parse it
	JMS GETHDL	/ Make sure handler loaded

	TAD (FILNAM)	/ Parse puts sixbit name here
	DCA NAME$
	DCA MAX$	/ Clear this
	TAD DEVNUM	/ Device # in AC with no max size
	OS8FUN 3	/ OS8 ENTER call
NAME$:	0 		/ First output block
MAX$:	0		/ Neg out limit
	JMP FAIL$

	/ Fill in the File Information
	TAD (1000)	/ Mark buffer empty
	DCA BUFPOS
	DCA BLOCKN	/ Block# zero to start
	TAD (2001)	/ Flag as open but pending
	DCA FLAGS
	TAD NAME$	/ First allocated block
	DCA FIRST
	DCA NBLKS	/ Zero size
	TAD MAX$	/ Negative max len
	CIA
	TAD FIRST	/ plus start
	DCA LAST	/ gives end block.

	TAD 7666	/ Get OS8 date
	DCA FILDAT

	JMS CLRBUF	/ Clear buffer
	CALL RSTFIB	/ Update our copy

	PUSH FIBNUM	/ Return id number
DONE$:	PUSH		/ And ok status
	RETURN FHCRE

FAIL$:	STA		/ -1 means failed
	JMP DONE$
	PAGE
	.SBTTL Close current file
// CLOSE-FILE ( id -- status )
	.ENTRY FHCLOS
FHCLOS,	0
	BEGIN		/ Sync stack
	POP		/ Get file-id
	CALL SETFIB	/ Select FIB

	TAD FLAGS	/ Was buffer modified?
	SPA CLA
	CALL WBLOCK	/ Yes

	TAD FLAGS	/ Is this a tentative file?
	RAR
	SNL CLA
	JMP ECLOS$	/ no

	/ We need to finalize the directory entry
	/ for "tentative" files.
	TAD (FILNAM)	/ Point to filename
	DCA FNAM$

	TAD NBLKS	/ Say final file size
	DCA FSIZ$

	TAD DEVNUM	/ Dev # in AC
	OS8FUN 4	/ OS8 CLOSE function
FNAM$:	0	/ Pointer to name
FSIZ$:	0	/ Blocks in file
	JMP ERR$

ECLOS$:	DCA FLAGS	/CLEAR FILE FLAGS.
	CALL RSTFIB	/ Copy it back
RET$:	PUSH		/ Zero status
	RETURN FHCLOS
ERR$:	STA
	JMP RET$
	PAGE
	.SBTTL Flush buffer to device
// FLUSH-FILE (	id -- status )
	.ENTRY FHFLUS
FHFLUS,	0
	BEGIN
	POP
	CALL SETFIB	/ Get correct FIB
	JMS FLUSH	/ Flush buffer
	HLT
	CALL RSTFIB	/ Put it back
	RETURN FHFLUS

	PAGE
	.SBTTL Read one line of text
// READ-LINE ( addr len id -- len stat )
// Read a line of text.
// This acts like ACCEPT.  Final length in AC, -1 if
// EOF.  Not counting CRLF.
FHRDL,	0
	BEGIN		/ Sync stack
	POP
	CALL SETFIB	/ Select FIB
	POP
	CIA
	DCA LIMIT	/ Get buffer size
	DCA COUNT
	POP
	TAD (-1)
	DCA OUTPTR	/ Buff addr minus 1
LOOP$:	CDF .
	JMS RCHAR
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
DONE$:	CALL RSTFIB	/ Save the FIB
	JMS PUTSP	/ resync stack
	RETURN FHRDL

	.SBTTL Write one line of text
// WRITE-LINE ( addr len id -- stat )
	.ENTRY FHWRL
FHWRL,	0
	BEGIN
	POP
	CALL SETFIB
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
	CALL RSTFIB
	RETURN FHWRL

ERR$:	STA
	JMP DONE$
OCHAR$:	0
	CDF .
	JMS WCHAR
	HLT		/ Oops
	CLA
	JMP I OCHAR$
	/ AC >= 0: out of room
	/ AC<0: fatal

	PAGE
	.SBTTL Get character position in file
// Get file position as character number.  This
// is a double-length value computed from block
// number and 3-in-2 position within block.
// File-id is on the stack.
	.ENTRY FHPOS
FHPOS,	0
	BEGIN		/ Sync stack
	POP		/ Get file-id
	CALL SETFIB
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

	.SBTTL Set character position in file
// Set file position.  Stack has doubleword character
// position that we convert to block number and
// position within block, allowing for the 3-in-2
// special coding format.
FHSPOS,	0
	BEGIN
	/ Get desired file position
	JMS GETSP
	POP HIGH	/ High 12 bits
	POP LOW		/ Low 12 bits
	JMS PUTSP

	/ Divide by 384 to get block number.
	TAD LOW	    	/ Low 12b to MQ
	MQL
	TAD HIGH	/ High 12b to AC
	DVI
	CHBLK		/ Chars per block
	DCA COUNT	/ Remainder is offset
	MQA 		/ Quotient is block #
	IAC		/ We use 1-origin
	DCA HIGH

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
	CALL RBLOCK	/ Get the HIGH block
	CALL RSTFIB
	RETURN FHSPOS

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

CLRBUF,	0     / Fill buffer with NUL
	STA
	TAD BUFADR
	DCA OUTPTR
	TAD (-400)
	DCA LIMIT
LOOP$:	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$
	JMP I CLRBUF

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
	PAGE

	.SBTTL PARSE filenames
	.ENABLE	7BIT
/ Parse an ASCII device:filename.ext into SIXBIT.
/ Source address in AC.  SIXBIT output to file info.

/ Based on FPARSE by Johnny Billquist 35 years ago
/ but integrated into the rest of the Forth I/O
/ environment to reduce copying and save space.
PARSE,	0
	TAD BUFADR	/ Filespec is in buffer
	DCA SRC		/ Save as source pointer.
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
	TAD T0
	DCA FROM$
	TAD LIMIT
	DCA DLEN$
	CALL COPY	/ Copy just the device
DLEN$:	0
FROM$:	0
	TEMP

	TAD (-6)	/Total length is 6.
	DCA TL
	TAD (TEMP)	/Offset to start.
	DCA OFFSET

DONAME,	JMS GETNAM	/Get file name.
	JMP EXT$	/No name found, go pack
	TAD T0
	DCA FROM$
	TAD LIMIT
	DCA NLEN$
	CALL COPY	/ Copy just the filename
NLEN$:	0
FROM$:	0
	TEMP+4		/ to just after the device

EXT$:	JMS GETEXT	/Get extension.
	JMP PACK$	/Not found. Pack result.
	TAD T0
	DCA EFRM$
	TAD LIMIT
	DCA XLEN$
	CALL COPY	/ Copy just the extension
XLEN$:	0
EFRM$:	0
	TEMP+12		/ to after the filename

// Convert ASCII in TEMP to sixbit at DEST.  We do
// not need to worry about lower case at this point.
PACK$:	CLA
	TAD OFFSET
	DCA T2
	TAD TL		/ dev+file+ext is 6 words
	DCA LIMIT
LOOP$:	TAD I T2	/ Get char.
	ISZ T2		/ Bump source pointer.
	AND (77)	/ Make SIXBIT.
	BSW		/ Swap high char.
	DCA T1		/ Save it temporarily.
	TAD I T2	/ Get next char.
	ISZ T2		/ Bump source pointer.
	AND (77)	/ Make SIXBIT.
	TAD T1		/ Combine with first char.
	DCA I DEST	/ Save word.
	ISZ DEST	/ Bump destination pointer.
	ISZ LIMIT	/ Bump count.
	JMP LOOP$	/ Repeat.
	JMP I PARSE	/ Return.

	PAGE
GETEXT,	0		/Get extension.
	TAD SRC		/Get source pointer.
	DCA T0 		/Save it in tmp.
	JMS GETCHR	/Get char.
	SNA CLA		/Was it NUL?
	JMP I GETEXT	/Yes. No extension.
	ISZ SRC		/No. Bump source pointer.
	JMS LOOK	/Search for NUL.
	TAD (-1)	/Decr. length of string.
	SNA		/Empty string?
	JMP I GETEXT	/Yes. No extension.
	TAD (2)		/Limit length to 2.
	SPA
	CLA
	TAD (-2)
	DCA LIMIT	/Save as loop count.
	TAD SRC		/Get source pointer.
	DCA T0		/Save as from tmp.
	ISZ GETEXT	/Bump return.
	JMP I GETEXT	/Return.

// Copy from T0 to T1 while converting to uppercase.
CPYNAM,	0
LOOP$:	JMS GETCHR	/Get char.
	DCA I T1	/Save it.
	ISZ T1		/Bump pointer.
	ISZ LIMIT	/Bump count.
	JMP LOOP$
	JMP I	CPYNAM	/Return.

GETCHR,	0
	TAD I T0	/Get char.
	ISZ T0		/Bump pointer.
	JMP I GETCHR	/Return.

// Locate the device-name string up to a colon
// (if present).
GETDEV,	0		/Get device.
	TAD (":)	/Seek device separator.
	JMS LOOK
	TAD (-1)	/Decr. string length.
	SNA		/Only ":" found?
	ISZ SRC		/Yes. Use default.
	SNA SPA		/Colon found and len>0?
	JMP I GETDEV	/No. not found. Return.
	TAD (-4)	/Limit length to 4.
	SMA
	CLA
	TAD (4)
	CIA
	DCA LIMIT	/Save as loop count.
	TAD SRC		/Get source pointer.
	DCA T1		/Save it tmp.
	TAD T0		/Get ptr to filename.
	DCA SRC		/Save it as new source pointer.
	TAD T1		/Get old source pointer.
	DCA T0		/Save for copy.
	ISZ GETDEV	/Bump return.
	JMP I GETDEV	/Return.

	/No device found. Copy only filename at end.
NODEV,	CLA
	TAD (-4)
	DCA TL
	TAD (TEMP+4)
	DCA OFFSET
	IAC RAL CLL
	TAD DEST
	DCA DEST
	JMP DONAME

LOOK,	0		/Search for char or EOS.
	CIA		/Make compare out of char.
	DCA T1		/Save compare.
	TAD SRC		/Get source pointer.
	DCA T0		/Save as tmp pointer.
	DCA LIMIT	/Clear count.
1$:	ISZ LIMIT	/Bump count.
	JMS GETCHR	/Get char.
	SNA		/EOS?
	JMP 2$		/Yes.
	TAD T1		/Compare.
	SZA CLA		/Equals?
	JMP 1$		/No. Repeat.
	TAD LIMIT	/Yes. Get count.
	JMP I LOOK	/Return.
2$:	TAD LIMIT	/EOS. Get count.
	CIA		/Negate.
	JMP I LOOK	/And return.

// Locate the main filename string, up to the
// extention (if any).
GETNAM,	0		/Get file name.
	TAD (".)	/Look out for extension separator.
	JMS LOOK
	SMA		/If positive, make negative.
	CIA
	IAC		/Decr. length by one.
	SNA		/Zero length?
	JMP I GETNAM	/Yes. Return. No filename.
	TAD (6)		/Limit length to 6.
	SPA
	CLA
	TAD (-6)
	DCA LIMIT	/Save as loop count.
	TAD SRC		/Get source pointer.
	DCA T1		/Save tmp.
	CMA		/Get extension separator pointer.
	TAD T0
	DCA SRC		/ new source pointer.
	TAD T1		/ old source pointer.
	DCA T0	/Save as from pointer for copy.
	ISZ GETNAM	/Bump return.
	JMP I GETNAM	/Return.

	PAGE
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

	.SBTTL Get device information

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
	SNA
	JMP LOAD$	/ No, load it.

	DCA HANDLR	/ Save entry point
	TAD INFO$+1	/ Save device number
	DCA DEVNUM
	JMP I GETHDL

	/ No, Load handler for that device
LOAD$:	TAD HDSPOT	/ Find spot for it.
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

// Where to load a device handler.
HDSPOT,	7600
	PAGE
/ Copy counted string from Forth dictionary to here,
/ converting to upper case and put a NUL at the end.
/ We use the data buffer to hold the string for PARSE.
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
	TAD (-140)	/ Convert to uppercase...
	SMA
	TAD (-40)
	TAD (140)
	CDF .	/ Write here
	DCA I OUTPTR
	ISZ LIMIT
	JMP LOOP$

	DCA I OUTPTR	/ Put a NUL at the end.
	JMP I GETFN

	PAGE
	.SBTTL Write the current buffer

/ The appropriate File Info must have been copied into
/ the active area before calling these routines.
/
	USR=7700
/ The 256 words at BUFADR get written to relative block
/ BLOCKN within the file.  Unlike modern operating
/ systems, OS/8 does I/O with physical block numbers so
/ we have to calculate it.

/ ON ERROR:
/	AC	>=0	NO MORE SPACE
/	AC	<0	FATAL DEVICE ERROR
WBLOCK,	0
	STA 		/ Zero-origin block
	TAD BLOCKN	/ Relative block to write.
	TAD FIRST	/ Plus first block
	DCA OBLK$	/ is absolute device block.

	TAD LAST	/ Last block in file
	CIA
	CLL CML
	TAD OBLK$	/COMPARE WITH FILE PTR...
	SNL CLA		/L=0 PTR OUT OF FILE SPACE.
	JMP ERR$	/YES. ERROR!
	TAD BUFADR	/ Set buffer address
	DCA OADR$

	/ Tell device handler to write the block.
	CIF 0
	JMS I HANDLR
OFUN$:	<4200+<IOFLD^10>> / Write one block from our field.
OADR$:	0		  / Buffer address
OBLK$:	0		  / Absolute block number
	JMP ERR$	/DEVICE ERROR.

	CIF .
	TAD FLAGS	/CLEAR MODIFIED FLAG.
	AND (3777
	DCA FLAGS
	TAD BLOCKN	/ Did we just extend the file?
	CIA CLL CML
	TAD NBLKS	/COMPARE WITH SIZE.
	SNL		/SIZE GROW?
	JMP DONE$	/NO.
	CIA		/YES. ADD CHANGE.
	TAD NBLKS
	DCA NBLKS	/SAVE AS NEW SIZE.
DONE$:	CLA
	JMP I WBLOCK	/RETURN
ERR$:	STA
	JMP I WBLOCK
	.SBTTL	Read a block into the buffer

/ Read a block (256 words) from the file.
/ Enter with desired RELATIVE block# in HIGH.
/
/ ERROR:
/	AC	>=0	END OF FILE
/	AC	<0	FATAL DEVICE ERROR
/
RBLOCK,	0
	TAD FLAGS	/ Was the old buffer modified?
	SPA CLA
	CALL WBLOCK	/ Yes, write current block

CLEAN$:	TAD HIGH	/ Desired block already here?
	SNA
	JMP NEXT$	/ Block 0 does not count
	CIA
	TAD BLOCKN
	SNA CLA
	JMP I RBLOCK	/ Already here. Done.

NEXT$:	ISZ BLOCKN	/BUMP DEFAULT.
	TAD HIGH
	SZA		/ZERO?
	DCA BLOCKN	/NO. SAVE AS DEAFULT.

	CMA		/ Calculate absolute address
	TAD BLOCKN	/ relative block
	TAD FIRST	/ plus first block
	DCA IBLK$	/ Put into request.

	/ OS8 does not check file limit so we have to
	/ do it here.
	TAD LAST	/ Get abs last block
	CIA
	CLL CML
	TAD IBLK$	/ Compare with wanted
	SNL CLA		/L=0 MEANS OUT OF FILE BOUNDS. ERROR!
	JMP ERR$	/YES. ERROR.

	/ In range so proceed
	TAD BUFADR
	DCA IADR$	/TRANSFER ADDRESS...

	CIF		/CALL DEVICE DRIVER.
	JMS I HANDLR
	<0200+<IOFLD^10>> / Read one block into our field
IADR$:	0
IBLK$:	0
	JMP ERR$
	ISZ RBLOCK	/ Ok skip return
	JMP I RBLOCK
ERR$:	STA
	JMP I RBLOCK	/ Error noskip return

	PAGE
// Get next sequential block in a file.
// RCHAR and WCHAR call this as required.
NXTBLK,	0
	CLA
	TAD BLOCKN	/ Which block now?
	DCA HIGH	/ Goal for WBLOCK
	TAD FLAGS	/ Was buffer modified?
	SPA CLA
	CALL WBLOCK	/ Yes, write it out
	ISZ HIGH	/ Advance to next
	TAD LAST	/GET END PTR.
	CIA
	CLL CML
	TAD HIGH	/ Get relative block
	TAD FIRST	/ Convert to absolute
	SNL SZA CLA	/ADDRESS > END?
	JMP ERR$	/YES. ERROR. NO MORE SPACE!

	CMA
	TAD HIGH	/ Are we going too far?
	CIA CLL CML
	TAD NBLKS	/ Compare with extent limit.
	SNL SZA
	ISZ NXTBLK	/PTR <= SIZE. BUMP RETURN. READ DONE.
	SNL SZA CLA	/PTR > SIZE?
	CALL RBLOCK	/ No, OK to read it.
	JMP ERR$
	DCA BUFPOS	/ Reset position within buffer
/	TAD AC		/GET CURRENT BLOCK.
/	DCA BLOCKN /SAVE CURRENT BLOCK.
	ISZ NXTBLK 	 / Ok skip return
	JMP I NXTBLK	/RETURN
ERR$:	STA
	JMP I NXTBLK	/ Error noskip return

	.SBTTL	Write one ASCII character

/ Write one ASCII character at current file position.
/ AC	CHARACTER
/
/ ERROR:
/	AC	>=0	NO MORE SPACE
/	AC	<0	FATAL DEVICE ERROR
/
WCHAR,	0
	DCA CHAR	/SAVE IT.

	/ Check if we have reached the end of the
	/ buffer.  This is 384 characters in, or
	/ 1000 in the 3-in-2 encoding.
	TAD BUFPOS
	TAD (-1000)
	SZA CLA
	JMP 1$		/NO.
	JMS NXTBLK	/YES. NEXT BLOCK.
	HLT

1$:	TAD BUFPOS	/GET COUNT
	AND (1774)
	CLL RAR
	TAD BUFADR
	DCA ARG		/ Ptr to dblword with char
	TAD BUFPOS
	AND (3)
	TAD (-1)
	SNA		/0 = 2:ND CHAR...
	ISZ ARG	/2:ND CHAR IS IN 2:ND WORD.
	SMA SZA CLA	/3:RD CHAR?
	JMP OSPLIT	/3:RD...

	TAD I ARG	/GET WORD.
	AND (7400	/MASK CHAR.
	TAD CHAR	/PUT IN NEW CHAR.
	DCA I ARG	/RESTORE.
OCRET,	ISZ BUFPOS	/BUMP POINTER.
	TAD FLAGS	/SET BUFFER MODIFIED BIT.
	RAL
	CLL CML RAR
	DCA FLAGS
	TAD BUFPOS	/CHECK IF BUFFER IS FULL.
	TAD (-1000)
	SNA CLA
	JMS WBLOCK	/ Yes, write it

	ISZ WCHAR	/ Ok, skip return
	JMP I WCHAR

OSPLIT,	CLA CLL CMA RAL	/ -2 for loop
	DCA LC
	TAD CHAR	/GET CHAR.
	RTL;RTL		/GET HIGH PART.
LOOP$:	AND (7400	/MASK.
	DCA TMP		/SAVE IT.
	TAD I ARG	/GET 1:ST WORD.
	AND (377	/MASK AWAY PREVIOUS CHAR.
	TAD TMP		/SAVE NEW CHAR.
	DCA I ARG	/SAVE WORD.
	ISZ ARG	/POINT AT NEXT WORD.
	TAD CHAR	/GET CHAR.
	RTR;RTR;RAR	/GET LOW PART
	ISZ LC		/LOOP.
	JMP LOOP$
	CLA
	ISZ BUFPOS
	JMP OCRET	/CONTINUE.

	PAGE
	.SBTTL	Read one ASCII character

/ Read one ASCII character at the current file
/ position.  At exit the character is in the AC.
/
/ ERROR:
/	AC	>=0	END OF FILE
/	AC	<0	FATAL DEVICE ERROR
RCHAR,	0
	TAD BUFPOS	/CHECK BUFFER COUNT.
	TAD (-1000)		/END?
	SZA CLA
	JMP GETC$		/NO.
	JMS NXTBLK		/YES.
	JMP ERR$	/NO READ DONE. EOF.

GETC$:	TAD BUFPOS	/GET BUFFER COUNT.
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
	JMP SPLIT$	/ Go do third char
	TAD I ARG	/GET WORD.
	AND (377)	/ Mask 8 bit byte
PRET$:	ISZ BUFPOS
	ISZ RCHAR     / Ok skip return
	JMP I RCHAR

	/ Back up for 3rd of 3 chars.
SPLIT$:	TAD I ARG	/ High part in 1st word
	AND (7400	/MASK
	CLL RTR;RTR	/MOVE TO PLACE.
	DCA TMP		/SAVE.
	ISZ ARG
	TAD I ARG	/ Low part in 2nd word
	AND (7400	/MASK
	CLL RTL;RTL;RAL	/ Move thru link
	TAD TMP		/ Merge saved hi part
	ISZ BUFPOS
	JMP PRET$	/CONTINUE.

ERR$:	STA
	JMP I RCHAR
	.SBTTL	FLUSH modified blocks
/ Write the current block to storage.  This
/ assumes that the file has been written in
/ "byte" mode.  For non-stream files, use
/ WBLOCK.
/
/ ERROR:
/	AC	>=0	NO MORE SPACE
/		<0	FATAL DEVICE ERROR
FLUSH,	0
	TAD FLAGS	/ Was block modified?
	SMA CLA
	JMP I FLUSH	/ No..

	/ Finish current packed word
PAD$:	TAD BUFPOS
	AND (3)		/GET BYTE OFFSET.
	SNA CLA		/OFFSET=0?
	JMP FILL$	/YES.
	JMS WCHAR	/NO. OUTPUT A NUL.
	JMP PAD$	/ Repeat until word full

	/ Set up zeroing rest of block
FILL$:	TAD BUFPOS	/GET OFFSET.
	AND (1774)	/GET WORD OFFSET.
	CLL RAR
	DCA TMP		/SAVE OFFSET.
	TAD TMP
	TAD (-400) 	/GET COUNT.
	SNA
	JMP WRITE$	/ALREADY AT END OF BLOCK.
	DCA LIMIT	/ Words to go

	STA 		/ Compute address-1 of
	TAD TMP		/ words to be cleared.
	TAD BUFADR
	DCA OUTPTR

	/ Fill rest of block with zeros
LOOP$:	DCA I OUTPTR   / Auto index!
	ISZ LIMIT
	JMP LOOP$

WRITE$:	TAD (1000)	/ Set pointer to "empty"
	DCA BUFPOS
	CALL WBLOCK	/ Write this block
	JMP I FLUSH

	.SBTTL Data buffers & file info
/ File Information Blocks and buffers.  There is one
/ 256 word buffer assigned to each file.  The FINFO
/ macro allocates space for both and links them together.
/ The FILES vector contains pointers to these.
	.DSECT BLOCKS
	FIELD 2
FILE1,	FINFO
FILE2,	FINFO
