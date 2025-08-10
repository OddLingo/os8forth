	.TITLE FORTH interpreter for PDP-8
	.SBTTL Page zero

	.NOLIST

	.INCLUDE COMMON.MA

	.LIST

/ These are macros so that bounds checking can be
/ added if required.
	.MACRO PUSH
	JMS PUSHS
	.ENDM
	.MACRO POP
	ISZ SP
	.ENDM

/ All machine code is in Field zero so IF register never
/ changes. The dictionary and all interpreted code and
/ stacks are in Field 1.

/ Field 0:
/   07200-07577 Console I/O handler (large)
/   07600-07777 OS/8 Fixed
/ Field 1:
/   10000-11777 OS/8 User Service Routines
/   12000-17177 Forth dictionary
/   17200-17377 Data stack
/   17400-17577 Return stack
/ Field 2
/   20000-20177 Console input buffer
/   20200-00577 File system input block buffer
/   20600-20777 File system output block buffer

	.XSECT SCAN
	FIELD 0
/// Auto-index registers used for scanning
TEXT1,	0	/ Pointer to dictionary name text.
TEXT2,	0

	.ZSECT COMMON
	FIELD 0
/// Forth machine registers
SP,	0	/ Data stack pointer
RSP,	0	/ Return stack pointer
IP,	0	/ Next instruction pointer
SOURCE,	0	/ Where interpreter reads from

BASE,	12		/ Number conversion base
HERE,	DCTEND		/ Start of free memory
DICT,	XBYE		/ Start of dictionary chain
STATE,	0		/ Compiling

/// Temporary values
TEXT3,	0	/ Non-autoinc pointers
TEXT4,	0
LSTKEY,	0	/ Latest input key
NEWORD,	0	/ Word being built
COUNT,	0	/ Counting up from zero
LIMIT,	0	/ Size of a buffer, up to zero
TOS,	0	/top of stack value
T1,	0
T2,	0
DPTR,	0	/address of current dictionary word
SEEK6,	NAME6	/ Address of sought word
CPTR,	0	/ Address of code pointer
CHAR,	0	/ latest character read
TOGGLE,	0
CURENT,	0	/ Current executing word
PADSPC,	20	/ Distance PAD is above HERE
THISW,	0
WRDLEN,	0
INOFF,	0	/ >IN offset in characters from the
		/ start of the input buffer to the
		/ start of the parse area.
LINLEN,	0	/ # of characters in TIB

/// Shared constants
LENMSK,	17	/ Length mask in dicitonary header
IMMFLG,	4000	/ Flag to execute during compilation
FTHFLG,	2000	/ Flag for interpreted code

/ Stacks are at the top of Field 1.
SBASE,	7200	/ Bottom of data stack
SSIZE,	0177
STTOP,	7577
RBASE,	7400	/ Bottom of return stack
RSIZE,	0177

ASPACE,	40	/ ASCII Space
NEGZRO,	7720	/ Negative ASCII zero
LOMEM,	-200	/ Boundary for field 0 references
MASK6,	0077	/ Sixbit mask
MASK7,	0177	/ TTI parity mask
NAMPAD,	0037	/ Padding for names
WRDPTR,	WRDBUF
TTOPTR,	0	/ Console output buffer
TTLIM,	0
TIBPTR,	TIB	/ Console input buffer
TIBLEN,	0120	/ 80 characters max per line

// Short routines used in many places.
TOSTMP,	0		/ Push AC on the data stack
PUSHS,	0
	DCA TOSTMP
	CLA CMA		/ Minus 1
	TAD SP		/ plus the old SP
	DCA SP		/ is the new SP
	TAD TOSTMP
	DCA I SP
	JMP I PUSHS

// Push AC on the return stack
PUSHRS,	0
	DCA TOSTMP
	CLA CMA		/ Decrement RSP
	TAD RSP
	DCA RSP
	TAD TOSTMP	/ Put value there
	DCA I RSP
	JMP I PUSHRS

/// Lay down a dictionary word from AC
LAYDN,	0
	DCA I HERE
	ISZ HERE
	JMP I LAYDN

	.RSECT ENGINE
	.SBTTL Startup
	.ENABLE SIXBIT

/// Start execution here
	.START .
INIT,	IOF		/ No interrupts
	CLA 
	DCA SOURCE	/ Start in Console mode
	JMS STACKS	/ Init stacks
	KCC		/ Clear device flags
	TCF
	CDF DCTEND	/ Indirect data references to field 1.
	JMS AVAIL	/ Print available memory
	JMS DOT
	JMS MSG
	TEXT \ AVAIL\
	JMS CRLF
	JMS MSG
	TEXT \> \
	JMS FILDEV
	JMS QUIT
	HLT	

BYE,	0		/ Exit to OS/8
	JMS MSG
	TEXT \GOODBYE@\
	JMS CRLF
	.EXIT

// Execute compiled FORTH opcodes until RETURN.
// Any machine-code words are called with JMS but
// FORTH words are handled iteratively with their
// own call stack. Calls to the FORTH word "EXECUTE"
// are also trapped here.
RUN,	0
	CLA
	JMS PUSHRS	/ Fake a zero return address
LOOP$:	CLA
	// IP=0 means stop. CURENT=0 means return
	TAD IP
	SNA
	JMP STOP
	CLA
	TAD I IP	/Fetch next instruction
	SNA
	JMP RET$
	DCA CURENT	/ Save as the "current" word

	ISZ IP		/ Increment IP for next time
	JMS TRACE

	// Set code and data pointers
	TAD CURENT
	IAC		/ Skip over head word
	IAC		/ Skip dictonary backlink
	DCA CPTR	/ Points at code word
	TAD CPTR
	IAC
	DCA DPTR

	// Determine execution type from flag
	TAD I CURENT
	AND FTHFLG
	SZA
	JMP FORTH$	/ Interpreted
	TAD I CPTR
	DCA CPTR
	JMS I CPTR	/ Machine code
	JMP LOOP$

FORTH$:	TAD IP		/ Save old IP for later return
	JMS PUSHRS	/ Go down a level on return stack
	TAD IP		/ Save old IP
	TAD I CPTR	/ Set new IP
	DCA IP
	JMP LOOP$

/ Return from an interpreted word.
RET$:	TAD I RSP	/ Get resume address
	DCA IP
	ISZ RSP		/ Pop return stack
	JMP LOOP$
	JMP LOOP$

ABORT,	0
	DCA IP		/ Force hard stop
	JMP I ABORT

	// Execution token of zero means stop.
STOP,	JMS CRLF
	JMP I RUN


	.SBTTL Main interpreter
PAGE
/// Main interpreter loop
/// Empty the return stack, store zero in SOURCE-ID
// if it is present, make the user input device the
// input source, and enter interpretation state.
// Do not display a message. Repeat the following:
//  * Accept a line from the input source into the
//    input buffer, set >IN to zero, and interpret.
//  * Display the implementation-defined system prompt
//    if in interpretation state, all processing
//    has been completed, and no ambiguous condition
//    exists.
QUIT,	0
	JMS STACKS	/ Initialize stacks
	DCA STATE
	DCA SOURCE	/ Console is input
LINE$:	TAD TIBPTR	/ Read a line
	PUSH
	TAD TIBLEN	/ Max length
	PUSH
	DCA INOFF	/ Zero input offset
	JMS ACCEPT

	TAD I SP
	DCA LINLEN	/ Actual length
	POP

	/ Get the next word but check end of line.
NEXTW$:	TAD INOFF
	CIA
	TAD LINLEN
	SPA
	JMP END$ 	/ Overflowed
	CLA
	JMS BL		/ Push Space delimiter
	JMS WORD	/ Get next word, caddr on stack
	TAD I WRDPTR	/ Get anything?
	SNA
	JMP PREND$  	/ No.

	// Check dictionary first because there are
	// words that start with a digit.
	JMS FIND	/ caddr 0 | xt 1 | xt -1
	TAD I SP
	POP		/ Execution token is at TOS
	SNA		/ Found it?
	JMP NUMCK$	/ Undefined word or it is a number
	CLA
	TAD STATE	/ Compiling or interpreting?
	SZA
	JMP COMP$
	//?? Error if IMMFLG set here
	JMS DOEXEC	/ Execute word on stack now
	JMP NEXTW$

COMP$:	CLA		/ Compile it
	TAD I SP	/ Get address of dict entry
	DCA T1
	TAD I T1	/ Get header word
	SPA
	JMP IMM$	/ It is immediate
	CLA
	POP
	TAD T1		/ Lay down the xt
	JMS LAYDN	/ Add to current definition
	JMP NEXTW$
IMM$:	CLA		/ Execute now
	JMS DOEXEC
	JMP NEXTW$

PREND$:	POP
END$:	CLA
	TAD STATE	/ All done, display prompt.
	SZA
	JMP LINE$
	JMS MSG
	TEXT \ OK\
	JMS CRLF
	JMP LINE$

	// If first char is numeric, use NUMLO to
	// convert it
NUMCK$:	TAD WRDPTR
	IAC
	DCA CHAR
	TAD I CHAR
	DCA CHAR
	JMS SKPNUM	/ Skip if CHAR is numeric
	JMP NUMER$	/ We don't know what it is.
	JMS NUMLO	/ Use low-level number parser
	TAD STATE	/ Compiling or interpreting?
	SNA
	JMP NEXTW$	/ Already on stack

	/ Comple numeric literal now on stack
	JMS LAYLIT
	XLIT
	TAD I SP
	POP
	JMS LAYDN
	JMP NEXTW$

NUMER$:	JMS UNDEF	/ Don't know what
	JMP END$

STACKS,	0		/ Initialize both stacks
	TAD SBASE	/ Set data stack top
	TAD SSIZE
	DCA SP
	TAD RBASE	/ Set return stack top
	TAD RSIZE
	DCA RSP
	DCA I RSP	/ Force zero as top opcode
	JMP I STACKS

TWODIV,	0     / Arithmetic shift right
	TAD I SP
	CLL
	SPA
	CML
	RAR
	DCA I SP
	JMP I TWODIV

MINUS1,	0     / Subtract one
	CLA CMA
	TAD I SP
	DCA I SP
	JMP I MINUS1

INTNOW,	0     / Interpret inside definition
	DCA STATE
	JMP I INTNOW
CMPNOW,	0     / Resume compiling
	ISZ STATE
	JMP I CMPNOW

INVERT,	0
	TAD I SP
	CMA
	DCA I SP
	JMP I INVERT

	.SBTTL Input

	PAGE
	.ENTRY PUT
PUT,	0
	TLS			/Output char.
	TSF			/Wait until ready.
	JMP	.-1
	CLA			/Clear AC.
	JMP I PUT

EMIT,	0		/ Output char on stack
	TAD I SP
	POP
	JMS PUT
	JMP I EMIT

CRLF,	0		/ End output line
	CLA
	TAD (15
	JMS PUT
	TAD (12
	JMS PUT
	JMP I CRLF

	.ENTRY GET
GET,	0			/For return address.
	KSF			/Wait for incoming char.
	JMP	.-1
	KRB			/Read char.
	JMP I	GET		/Return.

KEY,	0		/ Wait for a key ( -- ch )
	JMS GET
	PUSH	/ Put it on the stack
	TAD I SP	/ Type it too
	JMS PUT
	JMP I KEY

	PAGE
// Read a string ( c-addr +n1 -- +n2 )
// Receive a string of at most +n1 characters.
ACCEPT,	0
	TAD I SP	/ Save buffer size
	DCA INLEN$
	POP
	TAD I SP	/ Buffer address
	DCA INBUF$
	POP
	.INPUT
INBUF$:	0		/ buf
INLEN$:	0		/ len
	/ Get length from MQ
	CLA MQA
	PUSH
	JMP I ACCEPT

	.SBTTL Output

// Print an ASCII string ( addr len -- )
TYPE,	0
	TAD I SP	/ Get count as limit
	CIA
	DCA LIMIT
	POP
	CLA CMA
	TAD I SP
	DCA TEXT1
	POP
	//.PRINT	/?? Assume NUL terminator

LOOP$:	TAD I TEXT1	/ Advance and fetch
	JMS PUT	/ Print one char
	ISZ LIMIT	/ Count down
	JMP LOOP$	/ More to go
	JMP I TYPE	/ Done

/// Print a fixed message in sixbit following the call.
/// End with zero, so the text must not contain "@".
MSG,	0
LOOP$:	CDF .		/ We can indirect through MSG
	TAD I MSG	/ Get next 2 chars
	CDF DCTEND
	ISZ MSG		/ Advance over
	SNA
	JMP I MSG	/ Oops, zero so stop
	DCA T1
	TAD T1
	JMS LEFT6
	JMS P1SIX
	TAD T1		/ Do right half
	AND MASK6
	SNA
	JMP I MSG	/ Oops, zero
	JMS P1SIX
	JMP LOOP$

LEFT6,	0    	    	/ Get the left 6 bits
	RTR; RTR; RTR
	AND MASK6
	JMP I LEFT6

P1SIX,	0		/ Print 6b char in AC
	AND MASK6
	JMS TO8
	JMS PUT	/ Print the ASCII
	CLA
	JMP I P1SIX

TO8,	0		/ Convert 6b to 8b
	TAD (-40	/ Add 100 if under 40
	SPA
	TAD (100
	TAD ASPACE
	JMP I TO8

	.SBTTL Comparisons

	PAGE
COMP,	0		/ Subtract for comparison
	TAD I SP
	CIA
	POP
	TAD I SP
	CLL
	JMP I COMP

WITHIN,	0		/ ( v lo hi -- flag )
	TAD I SP
	DCA LIMIT	/ Upper limit
	POP
	TAD I SP
	DCA COUNT	/ Lower limit
	POP
	TAD I SP
	DCA T1		/ Test value
	TAD COUNT	/ Check lower limit
	CIA
	TAD T1
	SPA
	JMP NOTIN$
	CLA
	TAD LIMIT	/ Check upper limit
	CIA
	TAD T1
	SPA
	JMP NOTIN$
	CLA CMA		/ true FLAG IS -1
	SKP
NOTIN$:	CLA		/ Return false flag
	DCA I SP
	JMP I WITHIN

GTRZ,	0		/ True if n > 0
	TAD .-1
	DCA EQL
	TAD I SP
	SPA SNA
	JMP RFALSE
	JMP RTRUE

EQL,	0		/ True if a==b
	JMS COMP
	SZA
	JMP RFALSE
RTRUE,	CLA IAC
FLAG,	DCA I SP
	JMP I EQL
RFALSE,	CLA
	JMP FLAG

NEQL,	0		/True if a != b
	TAD .-1
	DCA EQL
	JMS COMP
	SZA
	JMP RTRUE
	JMP RFALSE

LESS,	0		/ True if a<b
	TAD .-1
	DCA EQL
	JMS COMP
	SMA SNL
	JMP RFALSE
	JMP RTRUE

GTR,	0		/ True if a>b
	TAD .-1
	DCA EQL
	JMS COMP
	SPA SNA
	JMP RFALSE
	JMP RTRUE

GEQL,	0		/ True if a>=b
	TAD .-1
	DCA EQL
	JMS COMP
	SPA SZL
	JMP RFALSE
	JMP RTRUE

LEQL,	0		/ True if a<=b
	TAD .-1
	DCA EQL
	JMS COMP
	SMA SZA
	JMP RFALSE
	JMP RTRUE

EQLZ,	0		/ True if n=0
	TAD .-1
	DCA EQL
	TAD I SP
	SZA
	JMP RFALSE
	JMP RTRUE

	PAGE
NEQZ,	0		/ True if n != 0
	TAD .-1
	DCA EQL
	TAD I SP
	SNA
	JMP RFALSE
	JMP RTRUE

LESSZ,	0		/ True if n < 0
	TAD .-1
	DCA EQL
	TAD I SP
	SMA
	JMP RFALSE
	JMP RTRUE

ANDOP,	0		/ Bitwise AND
	TAD I SP
	POP
	AND I SP
	DCA I SP
	JMP I ANDOP

OROP,	0		/ Bitwise OR by De'Morgan's law
	TAD I SP
	CMA
	DCA T1
	POP
	TAD I SP
	CMA
	AND T1
	CMA
	DCA I SP
	JMP I OROP

PAD,	0		/ Dynamic work area above HERE
	TAD HERE
	TAD PADSPC
	PUSH
	JMP I PAD

DIVMOD,	0		/ Divide with remainder
	TAD I SP
	DCA MODBY$
	POP
	TAD I SP
	MQL DVI
MODBY$:	0
	DCA I SP	/ Remainder is in AC
	MQA
	PUSH	/ Quotient was in MQ
	JMP I DIVMOD

	.SBTTL Literals

// Compile a literal string inline.  This is a simpler
// version of WORD.
   .ENABLE 7BIT
NEGQ,	-""		/ Terminating quote
LITSTR,	0
	TAD HERE
	DCA T1		/ Remember where length goes
	DCA COUNT
	JMS LAYDN	/ Save space for length
LOOP$:	JMS NXTIN
	TAD I SP
	DCA CHAR
	POP
	TAD CHAR	/ Check for terminating quote
	TAD NEGQ
	SNA CLA
	JMP DONE$
	TAD CHAR	/ Not quote so save it
	JMS LAYDN
	ISZ COUNT
	JMP LOOP$	/ Go back for more
DONE$:	TAD COUNT	/ Fixup the length
	DCA I T1
	JMP I LITSTR

XLITS,	0		/ Runtime for string addr+len
	TAD I IP
	DCA COUNT
	ISZ IP
	TAD IP
	PUSH	/ Push address of first char
	TAD COUNT
	PUSH	/ Push length
	JMP I XLITS

GENOP,	0		/ Lay down a literal at runtime
	TAD I IP
	JMS LAYDN
	ISZ IP
	JMP I GENOP

LAYLIT,	0		/ Lay a literal and skip it
	CLA
	CDF .		/ Fetch from instruction space
	TAD I LAYLIT
	CDF DCTEND
	JMS LAYDN
	ISZ LAYLIT
	JMP I LAYLIT

// S" Push address and count of a literal string
SQUOT,	0
	JMS LAYLIT
	XSTR
	JMS LITSTR
	JMP I SQUOT

	PAGE
SKPIP,	0
	TAD IP		/ Skip IP ahead
	TAD COUNT
	DCA IP
	JMP I SKPIP

QUOTS,	0		/ Run time for literal strings ( -- addr len )
	JMS XLITS
	JMS SKPIP	/ Advance IP over the string
	JMP I QUOTS

DQUOT,	0		/ Compile ." as S" and TYPE
	JMS LAYLIT
	XTYPES		/ Op to make addr,len
	JMS LITSTR	/ Put the string inline
	JMS LAYLIT
	XTYPE
	JMP I DQUOT

// ." Print a literal string
RDQUOT,	0
	JMS LAYLIT
	XTYPE	/ Lay down runtime
	JMS LITSTR	/ Lay down the string
	JMP I RDQUOT

HALT,	0
	HLT
	JMP I HALT

DOEXEC,	0		/ ( xt -- )
	TAD I SP	/ Get dictionary header
	POP
	DCA CURENT

	JMS TRACE
	TAD CURENT	/ 
	IAC		/ Skip backlink
	IAC
	DCA CPTR	/ Code address

	TAD CPTR
	IAC
	DCA DPTR	/ Data address

	TAD I CURENT	/ Check execution mode
	AND FTHFLG
	SZA
	JMP FORTH$	/ It is compiled FORTH
	TAD I CPTR
	DCA CPTR
	JMS I CPTR	/ It is machine code
	JMP I DOEXEC

FORTH$:	CLA
	TAD DPTR	/ Set runtime IP to this code
	DCA IP
	JMS RUN
	JMP I DOEXEC

SET10,	0		/ Runtime for DECIMAL
	TAD (12
	DCA BASE
	JMP I SET10

SET8,	0		/ Runtime for OCTAL
	TAD (10
	DCA BASE
	JMP I SET8
	
SYSVAR,	0		/ runtime for System variables
	TAD DPTR
	PUSH
	JMP I SYSVAR

DOCON,	0		/ runtime for CONSTANT
	TAD I DPTR
	PUSH
	JMP I DOCON

GENCON,	0		/ Define a CONSTANT
	JMS CREATE
	TAD I SP	/ Get the value
	POP
	JMS LAYDN
	TAD (DOCON	/ Set CONSTANT action
	DCA I CPTR
	JMP I GENCON

GENVAR,	0		/ Define a VARIABLE
	JMS CREATE
	TAD I SP
	POP
	JMS LAYDN
	TAD (DOVAR	/ SeVARIABLE action
	DCA I CPTR
	JMP I GENVAR

DOVAR,	0
	TAD DPTR	/ Get the value address
	PUSH
	JMP I DOVAR

SYSCON,	0		/ runtime for System constants
	TAD I DPTR	/ Get the value
	DCA T1
	CDF .
	TAD I T1
	CDF DCTEND	/ Field One back on
	PUSH
	JMP I SYSCON

ISLIT,	0     / Push a literal from dictionary
	TAD I DPTR
	PUSH
	JMP I SYSCON

	PAGE

	.SBTTL Convert to Sixbit
	
// These routines are called from a few places to convert
// 7bit ASCII to packed SIXBIT.  These are used in the
// FORTH dictionary and in OS/8 file and device names.

SIXIDE,	0		/ Left/right toggle
SIXLEN,	0		/ Count of output words
SIXCHR,	0
SIXOUT,	0		/ Destination buffer
SIXIN,	0		/ Count of input characters

A6INIT,	0		/ Initialize ASCII/SIXBIT
	DCA SIXOUT	/ Destination
	DCA SIXLEN	/ Word count
	DCA SIXIDE	/ Side toggle
	DCA SIXIN	/ Character count
	JMP I A6INIT

A6ADD,	0		/ Add one character
	DCA SIXCHR
	ISZ SIXIN
	TAD SIXCHR
	TAD (-140	/ Fold lower case
	SPA
	TAD (140
	AND MASK6
	DCA SIXCHR	/ Save as SIXBIT
	TAD SIXIDE	/ Check which side
	SZA
	JMP A6R$	/ Go do 2nd character

// Doing the left side so shift and store
	TAD SIXCHR
	CLL RTL;RTL;RTL	/ Move to left half
	DCA I SIXOUT	/ Save to output
	ISZ SIXLEN
	ISZ SIXIDE	/ Set right flag
	JMP I A6ADD	/ Done with input

A6R$:	CLA
	TAD I SIXOUT	/ Fetch left side
	TAD SIXCHR	/ Merge second code
	DCA I SIXOUT
	DCA SIXIDE	/ Clear side flag
	ISZ SIXOUT	/ Advance to next output word
	JMP I A6ADD

A6DONE,	0		/ Report word count
	TAD SIXLEN
	JMP I A6DONE

A6NAME,	0		/ Pad SIXBIT to a full word
	TAD SIXIDE	/ Odd input needs padding
	SNA
	JMP I A6NAME
	CLA
	TAD NAMPAD	/ Names pad with underscore
	JMS A6ADD
	JMP I A6NAME

A6FILE,	0		/ Pad SIXBIT to 6 characters
	TAD (-6)
A6PAD,	TAD SIXIN
	DCA SIXCHR
PAD0$:	JMS A6ADD
	ISZ SIXCHR
	JMP PAD0$
	JMP I A6FILE

A6EXT,	0		/ Pad SIXBIT to 2 characters
	TAD .-1		/ Borrow A6FILE ending
	DCA A6FILE
	TAD (-2)
	JMP A6PAD

A6DEV,	0		/ Pad SIXBIT to 4 characters
	TAD .-1		/ Borrow A6FILE ending
	DCA A6FILE
	TAD (-4)
	JMP A6PAD

	PAGE
GETCH,	0		/ Get CH
	TAD LIMIT
	SNA
	JMP I GETCH	/ Previously exhausted
	ISZ LIMIT
	JMP OK$
	JMP I GETCH	/ Non-skip return
OK$:	TAD I TEXT1	/ Skip return with ch
	JMS A6ADD
	JMS GETCH
	JMP I GETCH

PUTCH,	0		/ Convert ch limited by T1
	ISZ T1
	JMP OK$
	JMP I PUTCH	/ Nonskip return when full
OK$:	JMS A6ADD	/ Convert + skip return
	ISZ PUTCH
	JMP I PUTCH

// Convert an ASCII string into a SIXBIT
// filename for use by file operations.
CVTFIL,	0
	TAD I SP	/ Length on stack
	CIA
	DCA LIMIT
	POP
	CLA CMA
	TAD I SP	/ Start of string
	DCA TEXT1
	POP
	TAD SEEK6	/ Use the dictionary buffer
	JMS A6INIT
	TAD (-6		/ Output limit
	DCA T1
FLOOP$:	JMS GETCH	/ Copy filename part
	JMP DOT$	/ End of input
	DCA CHAR
	TAD CHAR	/ Is it period?
	TAD (-".)
	SNA
	JMP DOT$	/ Yes, do extension
	TAD (".)
	JMS PUTCH
	JMP FLOOP$
DOT$:	JMS A6FILE
	TAD (-2		/ Now 2 char extension
	DCA T1
XLOOP$:	JMS GETCH	/ Copy extension
	JMP FDONE$	/ End of input
	JMS PUTCH
	JMP XLOOP$
FDONE$:	JMS A6EXT	/ Pad the extension
	JMP I CVTFIL

TOFILE,	0		/ ( addr len buf -- )
	TAD I SP
	JMS A6INIT	/ Set destination
	POP
	TAD I SP
	CIA
	DCA LIMIT	/ Set count
	POP
	CLA CMA
	TAD I SP
	DCA TEXT1	/ Set source-1
	POP
COPY$:	TAD I TEXT1
	JMS A6ADD
	ISZ LIMIT
	JMP COPY$
	JMS A6FILE
	JMP I TOFILE

IGNORE,	0		/ A non-operation
	JMP I IGNORE

// Set up for a far reference.  Address will be
// in T1 and CHANGE is primed to do the CDF.
SETFLD,	0
	TAD I SP	/ Get field number
	AND (7
	CLL RTL; RAL
	TAD (CDF
	DCA CHANGE+1
	POP
	TAD I SP	/ Get address
	DCA T1
	JMP I SETFLD

CHANGE,	0		/ Set programmed data field
	0
	JMP I CHANGE

FFETCH,	0		/ ( addr fld -- n )
	JMS SETFLD
	JMS CHANGE
	TAD I T1	/ Far fetch
	CDF DCTEND
	DCA I SP
	JMP I FFETCH

FSTORE,	0		/ ( n addr fld -- )
	JMS SETFLD
	POP
	TAD I SP	/ The value
	JMS CHANGE
	DCA I T1	/ Far Store
	CDF DCTEND
	POP
	JMP I FSTORE

	PAGE
	.SBTTL Memory

FETCH,	0		/ ( addr -- n )
	TAD I SP	/Get the address
	DCA TOS
	TAD TOS		/ Compare with 0200
	TAD LOMEM
	SPA		/ Do not change field over 0200
	CDF .
	CLA
	TAD I TOS
	CDF DCTEND
	DCA I SP
	JMP I FETCH

STORE,	0		/ ( n addr -- )
	TAD I SP	/GET ADDRESS
	DCA TOS
	POP
	TAD I SP	/GET VALUE
	POP
	DCA T1
	TAD TOS		/ Compare address with 0200
	TAD LOMEM
	SPA		/ Do change field if > 0200
	CDF .
	CLA
	TAD T1
	DCA I TOS
	CDF DCTEND
	JMP I STORE

MOVE,	0		/ ( adr1 adr2 len -- )
	TAD I SP	/ count
	CIA
	DCA LIMIT
	POP
	CLA CMA		/ destination -1
	TAD I SP
	DCA TEXT2
	POP
	CLA CMA		/ source -1
	TAD I SP
	DCA TEXT1
LOOP$:	TAD I TEXT1
	DCA I TEXT2
	ISZ LIMIT
	JMP LOOP$
	JMP I MOVE

	.SBTTL Stack operations

OVER,	0		/ ( a b -- a b a )
	TAD SP
	IAC
	DCA T1
	TAD I T1
	PUSH
	JMP I OVER

PUSHR,	0		/ >R
	TAD I SP
	JMS PUSHRS
	POP
	JMP I PUSHR

POPR,	0		/ R>
	TAD I RSP
	DCA T1
	ISZ RSP
	TAD T1
	PUSH
	JMP I POPR

RFET,	0		/ R@
	TAD I RSP
	PUSH
	JMP I RFET

RSTOR,	0
	TAD I SP
	DCA I RSP
	POP
	JMP I RSTOR

DEPTH,	0		/ Report stack depth
	TAD SP		/ Subtract SP
	CIA
	TAD SBASE	/ from stack top
	TAD SSIZE
	PUSH
	JMP I DEPTH

ROTOP,	0		/ Rotate top 3 stack items
	TAD I SP	/ Fetch top down
	DCA T1
	POP
	TAD I SP
	DCA T2
	POP
	TAD I SP
	DCA TOS
	TAD T2
	DCA I SP
	TAD T1
	PUSH
	TAD TOS
	PUSH	
	JMP I ROTOP

QDUP,	0		/ DUP if non-zero
	TAD I SP
	SNA
	JMP I QDUP
	PUSH
	JMP I QDUP

DUP,	0		/ ( n -- n n )
	TAD I SP
	PUSH
	JMP I DUP

DROP,	0
	POP
	JMP I DROP

DROP2,	0
	POP
	POP
	JMP I DROP2

SWAP,	0		/ ( n1 n2 -- n2 n1 )
	TAD I SP	/ Get n1
	DCA TOS
	TAD SP		/ Look at 2nd stack item
	IAC
	DCA T1		/ Other SP
	TAD I T1	/ Get n2
	DCA I SP	/ Put it at top
	TAD TOS		/ Get what WAS at top
	DCA I T1	/ Put it at second
	JMP I SWAP

	.SBTTL Mathematics

	PAGE
NEGATE,	0		/ Invert a number
	TAD I SP
	CIA
	DCA I SP
	JMP I NEGATE

TIMES,	0		/ (a b -- a*b )
	TAD I SP
	DCA MULT$
	POP
	TAD I SP
	MQL MUY
MULT$:	0
	MQA
	DCA I SP
	JMP I TIMES

DIVIDE,	0		/ ( a b -- a/b )
	TAD I SP
	DCA DIVSR$
	POP
	TAD I SP
	MQL DVI
DIVSR$:	0
	MQA
	DCA I SP
	JMP I DIVIDE

MULDIV,	0		/ ( a b c -- a*b/c )
	TAD I SP
	DCA MD2$
	POP
	TAD I SP
	DCA MD1$
	POP
	TAD I SP
	MQL
	MUY
MD1$:	00
	DVI
MD2$:	00
	CLA MQA
	DCA I SP	
	JMP I MULDIV

ONEP,	0		/ ( n -- n+1 )
	TAD I SP
	IAC
	DCA I SP
	JMP I ONEP

PLUS,	0		/ ( a b -- a+b )
	TAD I SP
	DCA T1
	POP
	TAD T1
	TAD I SP
	DCA I SP
	JMP I PLUS

MINUS,	0		/ ( a b -- a-b )
	TAD I SP
	CIA
	POP
	TAD I SP
	DCA I SP
	JMP I MINUS

TICK,	0
	JMS BL
	JMS WORD
	TAD I WRDPTR
	SNA
	HLT
	JMS FIND
	TAD I SP
	SNA
	HLT
	POP
	JMP I TICK

/ Bitwise left shift   ( a b -- a<b )
LSHIFT,	0
	TAD I SP
	CIA
	DCA LIMIT
	POP
	TAD I SP
LOOP$:	CLL
	RAL
	ISZ LIMIT
	JMP LOOP$
	PUSH
	JMP I LSHIFT

/ Bitwise right shift   ( a b -- a>b )
RSHIFT,	0
	TAD I SP
	CIA
	DCA LIMIT
	POP
	TAD I SP
LOOP$:	CLL
	RAR
	ISZ LIMIT
	JMP LOOP$
	DCA I SP
	JMP I RSHIFT

	.SBTTL Number conversions
	PAGE
DOT,	0		/ Print a numeric value
	TAD I SP	/ Get the value
	DCA T1
	POP
	TAD BASE	/ Modify the divisor
	DCA DIVSR$
	DCA COUNT	/ Count the digits
LOOP$:	CLA
	TAD T1
	MQL
	CLA
	DVI		/ Remainder in AC
DIVSR$:	12
	TAD (60		/ Make it ASCII
	PUSH		/ Push it
	ISZ COUNT	/ Count it
	MQA		/ Get Dividend
	SNA
	JMP GOT$
	DCA T1
	JMP LOOP$	/ More digits
GOT$:	TAD COUNT	/ Done, make count negative
	CIA
	DCA LIMIT
OUT$:	CLA		/ Digits are on the stack in reverse order
	JMS EMIT	/ Get back a digit and print
	ISZ LIMIT
	JMP OUT$	/ Print them all
	JMP I DOT	/ Finished.

	.SBTTL Compiler

	PAGE
/// Allocate space in the dictionary ( n -- )
ALLOT,	0
	TAD I SP
	POP
	TAD HERE
	DCA HERE
	JMP I ALLOT

/// Initialize a new dictionary entry.
CREATE,	0
	TAD HERE
	DCA NEWORD	/ We start building here

	JMS BL		/ Push SPACE as delimiter
	JMS WORD	/ Put ASCII name in WRDBUF
	JMS PAKNAM	/ Convert to SIXBIT

	TAD I SEEK6	/ Sixbit word count
	DCA COUNT
	TAD COUNT
	CIA
	DCA LIMIT

	TAD SEEK6	/ Start after the count
	DCA TEXT1

COPY$:	TAD I TEXT1	/ Lay down the name
	JMS LAYDN
	ISZ LIMIT
	JMP COPY$

	/ HERE is now at the new entry header.
	TAD HERE
	DCA NEWORD

	/ Lay down the name length
	TAD COUNT
	JMS LAYDN

	TAD DICT	/ Link to previous word
	JMS LAYDN
	TAD HERE
	DCA CPTR
	JMS LAYLIT; XCUTE  / Forth runtime for now
	TAD HERE    / Set data area pointer
	DCA DPTR

	TAD NEWORD	/ This is now first word
	DCA DICT
	JMP I CREATE

COMMA,	0		/ Add word to definition
	TAD I SP
	JMS LAYDN
	POP
	JMP I COMMA

/// Define a new word
COLON,	0
	ISZ STATE	/ Enter COMPILING mode
	JMS CREATE	/ Init new entry, set NEWORD
	TAD I NEWORD	/ Set FORTH-type flag
	TAD FTHFLG
	DCA I NEWORD
	JMP I COLON

AVAIL,	0		/ Get available memory
	TAD HERE
	CIA
	TAD RBASE	/ Limit is bottom of R-stack
	PUSH
	JMP I AVAIL

SEMI,	0		/ Finish compilation
	DCA STATE	/ Flag off
	JMS LAYLIT
	0		/ Add a RETURN op
	JMP I SEMI

MAKIMM,	0		/ Make recent word immediate
	TAD I DICT
	TAD IMMFLG
	DCA I DICT
	JMP I MAKIMM
	
BL,	0		/ Push a space
	TAD ASPACE
	PUSH
	JMP I BL

	.SBTTL Parsing input

	PAGE
/// Consume next input character from TIB buffer.
// Use this instead of KEY in most places. ( -- ch )
INPTR,	0
NXTIN,	0
	TAD TIBPTR	/ Starting address
	TAD INOFF	/ Plus offset ( check INOFF > TIDLEN )
	DCA INPTR
	ISZ INOFF	/ Advance over it
	TAD I INPTR
	PUSH	/ Push char on stack
	JMP I NXTIN

// Parse one word up to a delimiter ( char -- caddr )
// Skip leading delimiters. Parse characters delimited
// by char. An ambiguous condition exists if the length
// of the parsed string is greater than the
// implementation-defined length of a counted string.
// c-addr is the address of a transient region
// containing the parsed word as a counted string.
// If the parse area was empty or contained no
// characters other than the delimiter, the resulting
// string has a zero length. A program may replace
// characters within the string.
WORD,	0		/ Parse one word
	TAD I SP
	CIA
	DCA CHAR	/ Save the negative delimiter
	CLA CMA
	TAD WRDPTR	/ Set output pointer -1
	DCA TEXT1
	DCA I TEXT1	/ Stuff zero count
	TAD TEXT1
	DCA I SP	/ WRDBUF is output
	DCA COUNT

LOOP1$:	JMS NXTIN	/ Get next candidate
	TAD I SP
	DCA T1
	POP		/ Dispose of char on stack

	JMS CLASS$
	JMP LOOP1$	/ Skip leading delimiters
	JMP END$	/ Stop at any control code
	JMP SAVE$	/ Save this character

LOOP2$:	JMS NXTIN	/ Get another
	TAD I SP
	DCA T1
	POP
	JMS CLASS$
	JMP END$	/ Stop at delimiter
	JMP END$	/ or any control code
SAVE$:	CLA		/ or save and keep going
	TAD T1
	DCA I TEXT1
	ISZ COUNT
	JMP LOOP2$

END$:	CLA
	TAD COUNT	/ Fix up length
	DCA I WRDPTR
	JMP I WORD

// Classify the character as one of three:
//  1. The sought delimiter
//  2. A control character
//  3. Anything else
CLASS$:	0
	TAD CHAR	/ Is it the delimiter?
	TAD T1
	SNA
	JMP I CLASS$	/ Delimiter first return
	ISZ CLASS$
	CLA
	TAD ASPACE
	CIA
	TAD T1
	SPA
	JMP I CLASS$	/ Control, skip return
	ISZ CLASS$
	JMP I CLASS$	/ Else double skip

// Convert counted string to address and length
// ( caddr -- addr len )
COUNTS,	0
	TAD I SP
	DCA TOS		/ Save the length
	TAD I SP	/ Increment the address
	IAC
	DCA I SP	/ Save it back
	TAD TOS
	PUSH	/ Push the length
	JMP I COUNTS
	PAGE
	.SBTTL Flow control

MARKFU,	0		/ Record a fixup location
	TAD HERE
	PUSH
	JMS LAYLIT
	0
	JMP I MARKFU

GENIF,	0
	JMS LAYLIT
	XJMPF
	JMS MARKFU	/ Fixup to ELSE or THEN
	JMP I GENIF

FIXUP,	0		/ Fixup a previous jump
	TAD I SP	/ Get place needing fixup
	POP
	DCA T1
	TAD T1	/ Compute difference
	CIA
	TAD HERE
	DCA I T1	/ Point it to HERE
	JMP I FIXUP

GENELS,	0		/ Compile ELSE
	JMS LAYLIT
	XJMP
	JMS MARKFU
	JMS SWAP
	JMS FIXUP
	JMP I GENELS

GENTHN,	0		/ Compile THEN that resolves IF
	JMS FIXUP
	JMP I GENTHN

JUMP,	0		/ Adjust IP by a signed constant
	TAD I IP	/ Get adjustment
	TAD IP		/ Add to old IP
	DCA IP		/ Save it
	JMP I JUMP

JUMPT,	0		/ Adjust IP if TOS true
	TAD I SP
	POP
	SZA
	JMP YES$
	ISZ IP		/ False so skip the adjustment
	JMP I JUMPT
YES$:	CLA		/ True so do the adjustment
	TAD I IP	/ Get adjustment
	TAD IP		/ Add to old IP
	DCA IP		/ Save it
	JMP I JUMPT

JUMPF,	0		/ Adjust IP if TOS false
	TAD I SP
	POP
	SNA
	JMP YES$
	ISZ IP		/ True so skip the adjustment
	JMP I JUMPF
YES$:	CLA		/ false so do the adjustment
	TAD I IP	/ Get adjustment
	TAD IP		/ Add to old IP
	DCA IP		/ Save it
	JMP I JUMPF

	.SBTTL Parsing numbers

LITNUM,	0	  / Runtime for a literal number
	TAD I IP
	PUSH
	ISZ IP
	JMP I LITNUM

	// Low-level number parser.  Text already in
	// WRDBUF, result goes on stack.
NUMLO,	0
	TAD I WRDPTR
	CIA
	DCA LIMIT
	TAD WRDPTR
	DCA TEXT1
	DCA TOS		/ Start with zero
LOOP$:	TAD I TEXT1
	DCA CHAR
	JMS SKPNUM	/ Skip if numeric
	JMP DONE$
	TAD CHAR	/ Is numeric, convert to value
	TAD NEGZRO	/ Subtract ASCII "0"
	DCA CHAR
	TAD TOS		/ Shift previous value
	MQL		/ Into MQ
	TAD BASE
	DCA .+2
	MUY
	0		/ Multiplicand
	MQA		/ Get product
	TAD CHAR	/ Add lastest char
	DCA TOS		/ This is latest value
	ISZ LIMIT
	JMP LOOP$	/ Get next digit
DONE$:	TAD TOS
	PUSH	/ All done push final value
	JMP I NUMLO

	PAGE
// >NUMBER ( ud1 c-addr1 u1 -- ud2 c-addr2 u2 )
// ud2 is the unsigned result of converting the
// characters within the string specified by c-addr1 u1
// into digits, using the number in BASE, and adding
// each into ud1 after multiplying ud1 by the number in
// BASE. Conversion continues left-to-right until a
// character that is not convertible, including any "+"
// or "-", is encountered or the string is entirely
// converted. Then c-addr2 is the location of the
// first unconverted character or the first character
// past the end of the string if the string was
// entirely converted. u2 is the number of unconverted
// characters in the string. An ambiguous condition
// exists if ud2 overflows during the conversion.
GETNUM,	0		/ ( dinit caddr len -- dval caddr remain )
	TAD I SP
	DCA COUNT
	TAD COUNT
	CIA
	DCA LIMIT	/ Save limit count
	POP
	CMA
	TAD I SP
	DCA TEXT1	/ Save input pointer
	POP
	POP		/ Ignore high word
	TAD I SP
	DCA TOS		/ Save starting value
LOOP$:	TAD I TEXT1	/ Examine next char
	DCA CHAR
	JMS SKPNUM	/ Skip if numeric
	JMP BADNM$
	TAD CHAR	/ Is numeric so convert to value
	TAD NEGZRO
	DCA CHAR
	TAD TOS		/ Shift previous value
	MQL		/ Into MQ
	TAD BASE
	DCA .+2
	MUY
	00		/ Multiplicand
	MQA		/ Get product
	TAD CHAR	/ Add lastest char
	DCA TOS		/ This is latest value
	ISZ LIMIT
	JMP LOOP$	/ Get next digit
	TAD TOS
	PUSH	/ All done push final value
	CLA
	PUSH	/ Push high word
	TAD TEXT1
	IAC
	PUSH	/ Push last pointer
	TAD COUNT
	TAD LIMIT
	PUSH	/ Push remaining count
	JMP I GETNUM

BADNM$:	JMS UNDEF
	JMS MSG; TEXT \GETNUM FAIL\
	JMP I GETNUM

/ Report undefined word
UNDEF,	0
	JMS MSG
	TEXT \ ?UNDEF '\
	JMS PSEEK
	TAD ("'
	JMS PUT
	JMS CRLF
	JMP I UNDEF

// Print the sought-after word
PSEEK,	0
	TAD WRDPTR
	IAC
	PUSH
	TAD I WRDPTR
	PUSH
	JMS TYPE
	JMP I PSEEK

	PAGE
NEGNIN,	7703

SKPNUM,	0		/ Skip if CHAR is numeric
	TAD NEGZRO
	TAD CHAR
	SPA
	JMP NOT$
	CLA
	TAD NEGNIN
	TAD CHAR
	SMA
	JMP .+2		/ Not numeric, don't skip
	ISZ SKPNUM	/ Is numeric so skip return
NOT$:	CLA
	JMP I SKPNUM
	
LPIDX,	0		/ Value of inner loop variable
	TAD I RSP
	PUSH
	JMP I LPIDX

LPEND,	0
	ISZ RSP
	HLT	//??

SWITCH,	0		/ Read the console switches
	OSR
	PUSH
	JMP I SWITCH

// Print contents of the stack, top down.
DOTS,	0
	JMS DEPTH	/ Calulate how many words
	TAD I SP
	POP
	SPA SNA
	JMP I DOTS	/ Do nothing if empty.
	CIA
	DCA LIMIT$	/ Should be negative count
	TAD SP
	DCA T2
LOOP$:	JMS SPACE
	TAD I T2
	PUSH
	JMS DOT
	ISZ T2
	ISZ LIMIT$
	JMP LOOP$
	JMS CRLF
	JMP I DOTS
LIMIT$:	0

SPACE,	0		/ Type a space
	CLA
	TAD ASPACE
	JMS PUT
	JMP I SPACE

// Print name of current word if SR bit 0 is set.
TRACE,	0
	OSR
	SMA
	JMP I TRACE
	JMS PNAME
	JMS SPACE
	JMP I TRACE

	// Dump the entire dictionary
WORDS,	0
	TAD DICT	/ Start here
	DCA CURENT
	TAD (-72
	DCA THISW
LOOP$:	JMS PNAME	/ Print this name
	TAD COUNT	/ Add word length
	IAC
	TAD THISW
	DCA THISW
	TAD THISW	/ Past column 72?
	SPA
	JMP NEXT$
	TAD (-72	/ Start new line
	DCA THISW
	JMS CRLF
	JMP BUMP$
NEXT$:	JMS SPACE
BUMP$:	ISZ CURENT	/ Find link word
	TAD I CURENT	/ Fetch link
	SNA
	JMP I WORDS	/ Zero means stop
	DCA CURENT
	JMP LOOP$

// Print a counted name in the dictionary.
// Zero is allowed because that is "@". CURENT
// points to the current executing word.
PNAME,	0
	TAD I CURENT
	SNA
	HLT		/ Trying to print missing entry
	AND LENMSK	/ Words in the name are limit
	CIA
	DCA LIMIT
	DCA COUNT
	TAD CURENT	/ Ptr is already one back
	TAD LIMIT
	DCA TEXT3
LOOP$:	TAD I TEXT3	/ Fetch word of two chars
	DCA T1
	TAD T1
	JMS LEFT6	/ Look at left 6 bits
	ISZ COUNT
	JMS P1SIX
	TAD T1		/ Now do right half
	AND MASK6
	TAD (-37	/ But stop at 037
	SNA
	JMP I PNAME
	TAD NAMPAD	/ Correct it
	ISZ COUNT
	JMS P1SIX
	ISZ TEXT3
	ISZ LIMIT	/ Count down
	JMP LOOP$
	JMP I PNAME

	PAGE
// FIND ( caddr -- caddr 0 | xt 1 | xt -1 )
// Find the definition named in the counted string
// at caddr. If the definition is not found, return
// caddr and zero. If the definition is found,
// return its execution token xt. If the definition
// is immediate, also return one (1), otherwise also
// return minus-one (-1). For a given string, the
// values returned by FIND while compiling may differ
// from those returned while not compiling. The
// dictionary stores names in SIXBIT format so
// we convert into NAME6 first.
THIS,	0		/ The entry under consideration
FIND,	0		/ Search dictionary
	JMS PAKNAM	/ Pack the name into SIXBIT
	TAD DICT	/ Start at most recent entry.
	DCA THIS
TRY$:	CLA		/ Try this candidate
	TAD I THIS	/ Compare lengths
	AND LENMSK
	CIA
	TAD I SEEK6
	SZA
	JMP NEXT$	/ Length mismatch
	TAD I SEEK6	/ Get length again
	CIA
	DCA LIMIT	/ Negative words to compare

	TAD SEEK6	/ Point TEXT3 at goal string
	IAC
	DCA TEXT3
	TAD THIS	/ Point TEXT4 at candidate
	TAD LIMIT
	DCA TEXT4

SUB$:	TAD I TEXT3	/ Subtract one from the other
	CIA
	TAD I TEXT4
	SZA
	JMP NEXT$	/ Text mismatch. Skip to next.
	ISZ LIMIT	/ Matches; keep going?
	JMP MORE$	/ Try next pair of chars

	TAD THIS	/ Found goal.  Put it on stack
	PUSH
	TAD I THIS	/ Check IMM flag in sign bit
	SPA
	JMP IMM$
	CLA IAC
FDONE$:	PUSH	/ And the +1 success flag
	JMP I FIND

IMM$:	CLA CMA		/ Return -1 flag for IMMEDIATE
	JMP FDONE$

MORE$:	ISZ TEXT3	/ Advance both pointers
	ISZ TEXT4
	JMP SUB$	/ Compare next words

	// Move THIS to next dictionary entry
NEXT$:	ISZ THIS	/ Advance THIS to link word
	CLA
	TAD I THIS	/ Get the link
	SZA
	JMP FNEXT$	/ Try next candidate
	CLA
	PUSH	/ End of chain, return failure
	JMP I FIND

FNEXT$:	DCA THIS
	JMP TRY$

// Pack counted string at TOS into NAME6 in SIXBIT
PAKNAM,	0
	CLA CMA		/ Minus 1
	TAD I SP	/ Address of counted ASCII
	DCA TEXT1
	POP
	TAD I TEXT1	/ Input count ( 1+ )
	DCA COUNT

	TAD SEEK6	/ Set output area
	IAC
	JMS A6INIT	/ Initialize converter

	TAD COUNT	/ Convert count to limit
	CIA
	DCA LIMIT	/ Negative count of input chars

LOOP6$:	TAD I TEXT1	/ Get ASCII char
	JMS A6ADD	/ Convert it
LEN6$:	ISZ LIMIT
	JMP LOOP6$
	JMS A6NAME	/ Pad with underscore
	TAD SEEK6	/ Fixup 
	DCA TEXT3
	JMS A6DONE	/ Get final word count
	DCA I TEXT3	/ Put it in front
	JMP I PAKNAM

	.SBTTL File operations

	PAGE
FILDEV,	0	/ Get device number in AC
	CLA
	CDF .
	CIF 10
	JMS I (7700)
	12    / INQUIRE request
INFO$:	DEVICE DSK
	0
	HLT
	TAD INFO$+1
	DCA F1FIB+DEVNUM
	TAD F1FIB+DEVNUM	/ Now load handler
	CDF .
	CIF 10
	JMS I (7700)
	1     / FETCH request
ARG1$:	RKSPOT
	HLT
	TAD ARG1$		/ Get entry point
	DCA F1FIB+DEVADR
	CDF DCTEND
	JMP I FILDEV

F1FIB,	.FIB RKSPOT,,RKBUF1
TMPNAM,	FILENAME TEST.TX

	.LIST MEB,ME
FILOPN,	0	/ Open a file named by string
	CDF .
	.IOPEN F1FIB,TMPNAM
	CDF DCTEND
	PUSH
	JMP I FILOPN

FILCLS,	0	/ Open a file named by string
	JMP I FILCLS

FILRD,	0	/ Read a block from the file
	CDF .
	.GET	F1FIB
	JMP I FILRD

FILRDL,	0	/ Read a line from a file
	TAD (TIB-1
	DCA TEXT2
LOOP$:	CDF .
	.ICHAR	F1FIB
	CDF DCTEND
	AND MASK7
	DCA CHAR
	TAD CHAR
	DCA I TEXT2
	TAD (-15
	TAD CHAR
	SNA CLA
	JMP I FILRDL
	JMP LOOP$

// Reserved area for disk device handler in F0.
// OS/8 reeserved area starts at 7600.
	.ASECT RKPARK
	FIELD 0
	.GLOBAL RKSPOT
	*7400
RKSPOT,	0; *.+177

	.DSECT BUFFS
	FIELD 2
RKBUF1,	0; *.+377

	.SBTTL  Built-in word definitions

	.DSECT PREDEF
	FIELD 1
WRDBUF,	ZBLOCK 20	/ Assemble ASCII token here
NAME6,	ZBLOCK 10	/ Sought word here in SIXBIT

/ Dictionary of built-in words.  Each entry is at least
/ 4 words long so 32 fit on a memory page or 1024 in
/ one field. Entries are chained in reverse order.
/ Offset   Contents
/ -N	sixbit word text padded with 037
/ 0	4000 set if immediate
/	2000 set if interpreted action
/	0007 number of words in text
/ 1	Link to previous word, in field 1
/ 2	Address of code in field 0 or interpret if 2000 set.
/ 3	Value (optional)

// We manually pad to an even number of characters with
// underscore.  This is the pattern that FIND will be
// looking for.
	.DISABLE FILL
	.ENABLE SIXBIT
/	.NOLIST
	A=0
// Terminal Buffers 80 chars each
	TEXT "TIB_";   B=.; 2; A; DOVAR
	.GLOBAL TIB
TIB,	*.+120
	TEXT "2/";	A=.; 1; B; TWODIV
	TEXT "1-";	B=.; 1; A; MINUS1
	TEXT "ALIGNED_";A=.; 4; B; IGNORE
	TEXT "CHARS_";	B=.; 3; A; IGNORE
	TEXT "[_";	A=.; 4001; B; INTNOW
	TEXT "]_";	B=.; 1; A; CMPNOW
	TEXT "INVERT";	A=.; 3; B; INVERT
	TEXT "+LOOP_";	B=.; 6003; A; 0
	 / R@ + R! DUP R@ >= JMPT (HERE -) R> 2DROP 
	   XGENOP; XFETR; XGENOP; XPLUS; XGENOP; XRSTOR
	   XGENOP; XDUP;
	   XGENOP; XFETR; XGENOP; XGEQ; XGENOP; XJMPT
	   XHERE; XMINUS; XCOMA
	   XGENOP; XPOPR; XGENOP; X2DROP; 0
	TEXT "LSHIFT";	A=.; 3; B; LSHIFT
	TEXT "RSHIFT";	B=.; 3; A; RSHIFT
	TEXT "OPEN-FILE_"; A=.; 5; B; FILOPN
	TEXT "CLOSE-FILE"; B=.; 5; A; FILCLS
	TEXT "READ-FILE_"; A=.; 5; B; FILRD
	TEXT "READ-LINE_"; B=.; 5; A; FILRDL
	TEXT "R/O_"; A=.; 2; B; ISLIT; 0
	TEXT "R/W_"; B=.; 2; A; ISLIT; 1
	TEXT "X@"; A=.; 1; B; FFETCH
	TEXT "X!"; B=.; 1; A; FSTORE
	TEXT "CONSTANT"; A=.; 4; B; GENCON
	TEXT "VARIABLE"; B=.; 4; A; GENVAR
	TEXT "(CON)_";   A=.; 3; B; DOCON
	TEXT "(VAR)_";   B=.; 3; A; DOVAR
	TEXT "=_";	A=.; 1; B; EQL
	TEXT ">_";	XGTR=.; 1; A; GTR
	TEXT "<_";	A=.; 1; XGTR; LESS
	TEXT ">=";	XGEQ=.; 1; A; GEQL
	TEXT "<=";	XLEQL=.; 1; XGEQ; LEQL
	TEXT "<>";	B=.; 1; XLEQL; NEQL
	TEXT "0=";	A=.; 1; B; EQLZ
	TEXT "0<";	B=.; 1; A; LESSZ
	TEXT "0>";	A=.; 1; B; GTRZ
	TEXT "0=";	B=.; 1; A; EQLZ

	TEXT "IF";	XIF=.; 4001; B; GENIF
	TEXT "ELSE";	XELSE=.; 4002; XIF; GENELS
	TEXT "THEN";	XTHEN=.; 4002; XELSE; GENTHN
	TEXT ">R";	XTOR=.; 1; XTHEN; PUSHR
	TEXT "R>";	XPOPR=.; 1; XTOR; POPR
	TEXT "R@";	XFETR=.; 1; XPOPR; RFET
	TEXT "R!";	XRSTOR=.; 1; XFETR; RSTOR
	TEXT "(JMP)_"; XJMP=.; 3; XRSTOR; JUMP
	TEXT "(JMPT)"; XJMPT=.; 3; XJMP; JUMPT
	TEXT "(JMPF)"; XJMPF=.; 3; XJMPT; JUMPF
	TEXT "AGAIN_"; B=.; 6003; XJMPF; 0
	   XGENOP; XJMP;
	   XHERE; XMINUS; XCOMA; 0
	TEXT "*/"; A=.; 1; B; MULDIV
	TEXT "[']_";	B=.; 4002; A; TICK
	TEXT "BEGIN_";A=.; 6003; B; 0
	   XHERE; 0
	TEXT "UNTIL_"; B=.; 6003; A; 0
	   XGENOP; XJMPF; XHERE; XMINUS; XCOMA; 0
	TEXT "DO"; A=.; 6001; B; 0
	   XGENOP; XTOR;
	   XHERE; 0
	TEXT "LOOP"; B=.; 6002; A; 0
	 / R@ 1+ R! DUP R@ >= JMPT (HERE -) R> 2DROP 
	   XGENOP; XFETR; XGENOP; X1PLUS; XGENOP; XRSTOR
	   XGENOP; XDUP;
	   XGENOP; XFETR; XGENOP; XGEQ; XGENOP; XJMPT
	   XHERE; XMINUS; XCOMA
	   XGENOP; XPOPR; XGENOP; X2DROP; 0
	TEXT "IMMEDIATE_";A=.; 5; B; MAKIMM
	TEXT "'_";	B=.;	1; A; TICK
	TEXT "DEPTH_";	A=.;	3; B; DEPTH
	TEXT ",_";	XCOMA=.; 1; A; COMMA
	TEXT "EMIT";	B=.;	2; XCOMA; EMIT
	TEXT "@_";	A=.; 	1; B; FETCH
	TEXT "C@";	B=.; 	1; A; FETCH
	TEXT "-_";	XMINUS=.; 1; B; MINUS
	TEXT "+_";	XPLUS=.; 1; XMINUS; PLUS
	TEXT "!_";	A=.; 	1; XPLUS; STORE
	TEXT "C!";	B=.; 	1; A; STORE
	TEXT "ABORT_";A=.; 	3; B; ABORT
	TEXT "FIND";	B=.; 	2; A; FIND
	TEXT "SWAP";	XSWAP=.; 2; B; SWAP
	TEXT "KEY_";	B=.; 	2; XSWAP; KEY
	TEXT ";_";	A=.;	4001; B; SEMI
	TEXT "BASE";	B=.; 2; A; SYSVAR; BASE
	TEXT "ACCEPT";A=.; 3; B; ACCEPT
	TEXT "CREATE";A=.; 3; B; CREATE
	TEXT "ALLOT_";B=.; 3; A; ALLOT
	TEXT "AND_";	B=.;	2; A; ANDOP
	TEXT "OR";	A=.;	1; B; OROP
	TEXT "ROT_";	B=.;	2; A; ROTOP
	TEXT "?DUP";	A=.;	2; B; QDUP
	TEXT "PAD_";	B=.;	2; A; PAD
	TEXT "/MOD";	A=.;	2; B; DIVMOD
	TEXT "I_";	B=.; 1; A; LPIDX
	TEXT "DONE";	A=.; 2; B; LPEND
	TEXT "CR";  XCR=.; 1; A; CRLF
	TEXT "TYPE";	XTYPE=.; 2; XCR; TYPE
	TEXT "BL";	B=.; 1; XTYPE; SYSCON; ASPACE
	TEXT "WITHIN";A=.; 3; B; WITHIN
	TEXT "DROP";	XDROP=.; 2; A; DROP
	TEXT "2DROP_"; X2DROP=.; 3; XDROP; DROP2
	TEXT "DECIMAL_"; A=.; 4; X2DROP; SET10
	TEXT "OCTAL_"; B=.; 3; A; SET8
	TEXT "WORDS_";	A=.; 3; B; WORDS
	TEXT "CELL";	B=.; 2; A; IGNORE
	TEXT "CELL+_";	A=.; 3; B; IGNORE
	TEXT "(QS)";	XSTR=.; 2; A; QUOTS / runtime "
	TEXT "(DQS)_";	XTYPES=.; 3; XSTR; RDQUOT / runtime ."
	TEXT "C,";	B=.; 1; XTYPES; COMMA
	TEXT "(GEN)_"; XGENOP=.; 3; B; GENOP
	TEXT "/_";     B=.; 1; XGENOP; DIVIDE
	TEXT ">NUMBER_"; A=.; 4; B; GETNUM
	TEXT "MOVE";	B=.; 2; A; MOVE
	TEXT "CMOVE_";	A=.; 3; B; MOVE
	TEXT "OVER";	B=.; 2; A; OVER
	TEXT "._";	A=.; 1; B; DOT
	TEXT "AVAIL_";	   B=.; 3; A; AVAIL
	TEXT ">IN_";	A=.; 2; B; SYSVAR; INOFF
	TEXT "SWITCH";	B=.; 3; A; SWITCH
	TEXT "NEGATE";	A=.; 3; B; NEGATE
	TEXT \S"\;	B=.; 4001; A; SQUOT
	TEXT \."\;	A=.; 4001; B; DQUOT
	TEXT "SPACE_";	B=.; 3; A; SPACE
	TEXT ".S";	A=.; 1; B; DOTS
	TEXT "STATE_";	B=.; 3; A; SYSVAR; STATE
	TEXT "*_";	A=.; 1; B; TIMES
	TEXT "1+";	X1PLUS=.; 1; A; ONEP
	TEXT "COUNT_";	A=.; 3; X1PLUS; COUNTS
	TEXT ":_";	B=.; 1; A; COLON
	TEXT "DUP_";  	XDUP=.; 2; B; DUP
	TEXT "EXECUTE_"; XCUTE=.; 4; XDUP; DOEXEC
	TEXT "(LIT)_";	 XLIT=.; 3; XCUTE; LITNUM
	TEXT "FILENAME"; XFILE=.; 4; XLIT; TOFILE
	TEXT "HERE";	 XHERE=.; 2; XFILE; SYSCON; HERE
// This must be the last entry.
	TEXT "BYE_";	 XBYE=.; 2; XHERE; BYE
	.LIST
	.GLOBAL DCTEND
DCTEND=.
