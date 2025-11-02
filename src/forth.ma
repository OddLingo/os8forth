	.TITLE FORTH interpreter for PDP-8
	.SBTTL Page zero

	.LIST  MEB

/ These are macros so that bounds checking can be
/ added if required.
	.MACRO PUSH VAL
	.IF NB VAL <TAD VAL
	>
	JMS PUSHS
	.ENDM

	.MACRO RPUSH
	JMS PUSHRS
	.ENDM

	CHKPOP=0
	.MACRO POP DEST
	.IF NB DEST <TAD I SP
	DCA DEST
	>
	.IF NE CHKPOP <CALL POPS>
	.IF EQ CHKPOP <ISZ SP>
	.ENDM

/ Call common routines with this macro, that puts a
/ single indirect word in the $ENGINE ZSECT.  It is
/ important that $ENGINE gets located on Page 0 of
/ Field 0, which it will not if Page 0 is overfilled.
/ Check the LINKER map.
	.MACRO CALL RTN
	JMS I [RTN]
	.ENDM

/ An IOCALL calls a routine in another field.
/ This is used for file operations.
	.MACRO IOCALL RTN
	CIF RTN; JMS RTN
	.ENDM

	.MACRO LAYOP OP
	CALL LAYLIT
	OP
	.ENDM

/ This generates a fatal error message and restarts.
	.MACRO ERROR TYPE
	JMS RECOVR
	.DISABLE FILL
	.ENABLE SIXBIT
	TEXT \TYPE\
	.ENDM

/ Lay down a FORWARD jump, to be resolved later
/ by FIXFWD.
	.MACRO LAYFWD TYPE
	CALL LAYLIT
	.IF NB TYPE <TYPE>
	.IF BL TYPE <XJMP>
	JMS MARKFJ
	.ENDM

/ The Forth engine code is in Field zero so IF register
/ rarely changes. The dictionary and all interpreted
/ code and stacks are in Field 1.  Field 2 has
/ disk I/O routines.

/ Field 0:
/   00000-07177 Interpreter
/   07200-07577 Disk handler
/   07600-07777 OS/8 Fixed
/ Field 1:
/   10000-17177 Forth dictionary
/   17200-17377 Data stack
/   17400-17577 Return stack
/   17600-17777 OS/8 Fixed
/ Field 2
/   20000-21777 I/O library
/   22000-23177 Forth I/I support
/   24400-25000 Filename parser

	.XSECT SCAN
	FIELD 0
/// Auto-index registers used for scanning
TEXT1,	0	/ Pointer to dictionary name text.
TEXT2,	0

	.ZSECT COMMON
	FIELD 0
	.GLOBAL SP
/// Forth machine registers
SP,	0	/ Data stack pointer
RSP,	0	/ Return stack pointer
OSP,	0	/ Opcode stack pointer
IP,	0	/ Next instruction pointer

BASE,	12	/ Number conversion base
SCALE,	^D1000	/ Print scale factor
SCDIGS,	-3	/ Negative digit count
HERE,	DCTEND	/ Start of free memory
DICT,	XBYE	/ Start of dictionary chain
STATE,	0	/ Compiling
INJECT,	0	/ Forced execution token
SRCID,	0	/ Where interpreter reads from
STOPAT,	7777	/ HLT when IP matches

/// Temporary values
TEXT3,	0	/ Non-autoinc pointers
TEXT4,	0
NEWORD,	0	/ Word being built
COUNT,	0	/ Counting up from zero
LIMIT,	0	/ Counting up TO zero
HIGH,	0	/ Hi order word of value
LOW,	0	/ Low order word of value
T1,	0
T2,	0
DPTR,	0	/ address of current dictionary word
CPTR,	0	/ Address of code pointer
CHAR,	0	/ latest character read
CURENT,	0	/ Current executing word
PADSPC,	^D20	/ Distance PAD is above HERE
THISW,	0
INOFF,	0	/ >IN offset in characters from the
		/ start of the input buffer to the
		/ start of the parse area.
LINLEN,	0	/ # of characters in TIB

/// Shared constants
    	.ENABLE 7BIT
NEGQ,	-""	/ Terminating quote
LENMSK,	17	/ Length mask in dictonary header
IMMFLG,	4000	/ Flag to execute during compilation
FTHFLG,	2000	/ Flag for interpreted code
NEGNIN,	-"9		/ Digit 9
NEGMIN,	-"-		/ Minus sign

/ Stacks are at the top of Field 1.
SBASE,	7200	/ Bottom of data stack
RBASE,	7400	/ Bottom of return stack
OBASE,	7500	/ Bottom of opcode stack
SSIZE,	0177	/ Data stack gets a full page
RSIZE,	0077	/ R- and O- stacks are smaller

ASPACE,	40	/ ASCII Space
AZERO,	60	/ ASCII Zero
NEGZRO,	7720	/ Negative ASCII zero
LOMEM,	-200	/ Boundary for field 0 references
MASK6,	0077	/ Sixbit mask
MASK7,	0177	/ ASCII parity mask
NAMPAD,	0037	/ Padding for names
WRDPTR,	WRDBUF
SEEK6,	NAME6	/ Address of sought word
TIBPTR,	TIB	/ Console input buffer
TIBLEN,	^D80	/ 80 characters max per line

// Short routines used in many places.
// Push AC on the data stack
PUSHS,	0
	DCA PUSHRS
	STA		/ Minus 1
	TAD SP		/ plus the old SP
	DCA SP		/ is the new SP
	TAD PUSHRS
	DCA I SP
	JMP I PUSHS

// Push AC on the return stack
PUSHRS,	0
	DCA PUSHS
	STA		/ Decrement RSP
	TAD RSP
	DCA RSP
	TAD PUSHS	/ Put value there
	DCA I RSP
	JMP I PUSHRS

// Lay down a dictionary word from AC, like COMMA
LAYDN,	0
	DCA I HERE
	ISZ HERE
	JMP I LAYDN

// The ENGINE section in Field 0 contains the
// PDP-8 code that implements the "Forth machine".
// It is usually invisible to the Forth programmer.
	.RSECT ENGINE
	.SBTTL Startup
	.ENABLE SIXBIT


/// Start execution here
	.START .
INIT,	IOF		/ No interrupts
	CLA 
	JMS RESET	/ Init everything
	KCC		/ Clear device flags
	TCF
	CDF SYMBOL	/ Indirect references to F1
	PUSH (XINIT)	/ Run INIT word
	JMS DOEXEC
RESUME,	JMS QUIT	/ Start interpreter
	HLT	

BYE,	0		/ Exit to OS/8
	JMS MSG
	TEXT \GOODBYE@\
	CALL CRLF
	CDF CIF
	JMP 7600

// Execute compiled FORTH opcodes until an EXIT.
// Any machine-code words are called with JMS but
// FORTH words are handled iteratively with their
// own call stack. Calls to "EXECUTE" are handled
// specially to avoid recursion in the PDP-8 code.
RUN,	0
	CLA
	RPUSH	/ Fake a zero return address
NEXT$:	CLA
	TAD INJECT	/ Is there a pending EXECUTE?
	SNA
	JMP NOINJ$	/ No
	DCA CURENT	/ Yes, make it next
	DCA INJECT	/ and clear flag
	TAD (XCUTE)
	CIA
	TAD CURENT	/ But was it XCUTE?
	SZA CLA
	JMP RUNIT$	/ No, just go
	POP INJECT	/ Yes, do its work here
	JMP NEXT$

NOINJ$:	CLA
	TAD IP		/ IP=0 means stop
	SNA CLA		/ Else fall to GETOP
	JMP I RUN

GETOP$:	TAD IP		/ Check breakpoint
	TAD STOPAT
	SNA CLA
	HLT
	TAD I IP	/ Fetch next instruction
	SNA
	JMP RET$	/ Zero opcode means return
	DCA CURENT	/ Save as the "current" word

	ISZ IP		/ Increment IP for next time
RUNIT$:	JMS TRACE

	// Set code and data pointers
	TAD CURENT
	JMS PUSHOS	/ Remember what it is
	TAD CURENT
	IAC		/ Skip flag word
	IAC		/ Skip dictonary link
	DCA CPTR	/ Addr of code word
	TAD CPTR
	IAC
	DCA DPTR	/ Addr of parameter area

	// Determine execution type from flag.
	TAD I CURENT
	AND FTHFLG
	SZA CLA
	JMP FORTH$	/ Interpreted

	/ Execite a machine-code word.  These never
	/ recurse and always return right away, though
	/ they can change the state of the engine.
	TAD I CPTR
	DCA CPTR
	JMS I CPTR	/ Run the code
	ISZ OSP
	JMP NEXT$	/ DOES> returns here

/ Start a new interpretered word, saving the
/ current context so it can be resumed.
FORTH$:	TAD IP	/ Save old IP for later return
		/ Note: it might be zero
	RPUSH	/ Go down a level on R-stack
	TAD I CPTR	/ Set new IP
	DCA IP
	JMP NEXT$

/ Return from an interpreted word.  A zero
/ opcode has been encountered by RUN.
RET$:	TAD I RSP	/ Get resume address
	DCA IP		/ Next op is there.
	ISZ RSP		/ Pop return stack
	ISZ OSP		/ And op stack
	JMP NEXT$

// EXECUTE ( xt -- ) Make the RUN engine do word
// on the stack.
DOEXEC,	0
	POP INJECT	/ force current
	TAD IP		/ is RUN already going?
	SNA CLA
	JMS RUN		/ No, do it now
	JMP I DOEXEC

// ABORT stops execution and clears stacks.
ABORT,	0
	JMS RESET
	JMS PUSHOS	/ Make OSP coorect
	JMP I ABORT

// Push AC on opcode stack
PUSHOS,	0
	DCA ABORT
	STA		/ Decrement OSP
	TAD OSP
	DCA OSP
	TAD ABORT	/ Put value there
	DCA I OSP
 	JMP I PUSHOS

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
LLOOP$:	PUSH TIBPTR	/ Read a line
	PUSH TIBLEN	/ Max length
	DCA INOFF	/ Zero input offset
	JMS ACCEPT
	TAD I SP	/ Actual input length
	POP
	SNA
	JMP LLOOP$	/ Nothing, get another.
	DCA LINLEN	/ Save it.

	/ Get the next word but check end of line.
WLOOP$:	TAD INOFF
	CIA
	TAD LINLEN
	SPA CLA
	JMP END$ 	/ Overflowed
	CALL BL		/ Push Space delimiter
	CALL WORD	/ Get next word, caddr on stack
	TAD I WRDPTR	/ Get anything?
	SNA CLA
	JMP PREND$  	/ No.

	// Check dictionary first because there are
	// words that start with a digit.
	CALL FIND	/ caddr 0 | xt 1 | xt -1
	TAD I SP
	POP		/ Execution token is at TOS
	SNA CLA		/ Found it?
	JMP NUMCK$	/ Undefined word or number
	TAD STATE	/ Compiling or interpreting?
	SZA CLA
	JMP COMP$
	//?? Error if IMMFLG set here
	/ Set up runtime to execute word we found.
	JMS DOEXEC	/ Execute word on stack now
	JMP WLOOP$	/ Get another word
	// We are in Compiling Mode so we either lay
	// down the opcode or, if flagged IMMEDIATE,
	// execute it.
COMP$:	TAD I SP	/ Get address of dict entry
	DCA T1
	TAD I T1	/ Get header word
	SPA CLA
	JMP IMM$	/ It is immediate
	POP
	TAD T1		/ Lay down the xt
	JMS LAYDN	/ Add to current definition
	JMP WLOOP$	/ Get another word

IMM$:	JMS DOEXEC	/ Execute now
	JMP WLOOP$

PREND$:	POP		/ Don't need WORD flag
END$:	CLA
	TAD STATE	/ All done, compiling?
	SZA CLA
	JMP LLOOP$	/ Yes, get another line
	TAD SRCID	/ Reading a file?
	SZA CLA
	JMP LLOOP$	/ Yes, get another line
	JMS MSG		/ No, say "OK".
	TEXT \ OK\
	CALL CRLF
	JMP LLOOP$	/ Get another line

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
	JMP WLOOP$	/ Already on stack

	/ Comple numeric literal now on stack
	LAYOP XLIT
	TAD I SP
	POP
	JMS LAYDN
	JMP WLOOP$

NUMER$:	JMS UNDEF	/ Don't know what
	JMP END$

// Initialize all engine state and stacks.
RESET,	0
	TAD SBASE	/ Set data stack top
	TAD SSIZE
	DCA SP
	TAD RBASE	/ Set return stack top
	TAD RSIZE
	DCA RSP
	TAD OBASE	/ Set opcode stack top
	TAD RSIZE
	DCA OSP
	DCA I RSP	/ Force zero as top opcode
	DCA I OSP
	DCA IP		/ Nothing is running
	DCA STATE	/ Not compiling
	DCA INJECT	/ No pending EXECUTE
	DCA SRCID	/ Reading from console
	JMP I RESET

// /2 Arithmetic shift right
TWODIV,	0
	TAD I SP
	CLL
	SPA
	CML
	RAR
	DCA I SP
	JMP I TWODIV

// LITERAL (C n -- ) Create a literal at compile time
GENLIT,	0
	LAYOP XLIT	/ Literal at runtime
	TAD I SP
	POP
	JMS LAYDN
	JMP I GENLIT

// 2*	( n -- 2n )  Shift left one bit
TIMES2,	0
	TAD I SP
	CLL RAL
	DCA I SP
	JMP I TIMES2

	PAGE
MINUS1,	0     / 1- Subtract one
	STA
	TAD I SP
	DCA I SP
	JMP I MINUS1

INTNOW,	0     / [ Interpret inside definition
	DCA STATE
	JMP I INTNOW

CMPNOW,	0     / ] Resume compiling
	ISZ STATE
	JMP I CMPNOW

INVERT,	0
	TAD I SP
	CMA
	DCA I SP
	JMP I INVERT

	.SBTTL Input

	.ENTRY PUT
PUT,	0
	TLS		/Output char.
	TSF		/Wait until ready.
	JMP	.-1
	CLA		/Clear AC.
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

// Get one character from the console.  The .INPUT
// library also uses this.
	.ENTRY GET
GET,	0			/For return address.
	KSF			/Wait for incoming char.
	JMP .-1
	KRB			/Read char.
	JMP I GET		/Return.

KEY,	0		/ Wait for a key ( -- ch )
	JMS GET
	PUSH	/ Put it on the stack
	TAD I SP	/ Type it too
	JMS PUT
	JMP I KEY

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
	BSW		/ Move to left half
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

// 2! ( hi lo addr -- )
STORE2,	0
	STA
	TAD I SP
	DCA TEXT2
	POP
	TAD I SP
	DCA I TEXT2
	POP
	TAD I SP
	DCA I TEXT2
	POP
	JMP I STORE2

// 2@ ( addr -- hi lo )
FETCH2,	0
	STA
	TAD I SP
	DCA TEXT1
	POP
	TAD I TEXT1
	PUSH
	TAD I TEXT2
	PUSH
	CALL SWAP
	JMP I FETCH2

	PAGE
// Read a string ( c-addr +n1 -- +n2 )
// Receive a string of at most +n1 characters.
	.EXTERNAL	$INPUT
ACCEPT,	0
	TAD SRCID	/ Non-zero src means a file
	SZA
	JMP FILE$
	/ From console.  Use library routine.
	TAD I SP	/ Save buffer size
	DCA INLEN$
	POP
	TAD I SP	/ Put it here
	DCA INBUF$
	POP
	JMS $INPUT
INBUF$:	0		/ buf
INLEN$:	0		/ len
	/ Get length from MQ
	CLA MQA
	PUSH
	JMP I ACCEPT

	/ Reading from a file instead
FILE$:	PUSH		/ File id on stack
	/ Stack: addr len id
	JMS FILRDL	/ Read a line
	/ Stack: iot flag len
	TAD I SP	/ Check status. Zero is OK
	POP
	SZA CLA
	JMP EOF$
	POP		/ Do not need flag
	JMP I ACCEPT

EOF$:	POP	/ Do not need flag
	POP   	/ Do not need length
	TAD SRCID	/ Close input file
	PUSH
	JMS FILCLS
	POP		/ Ignore status
	CLA
	DCA SRCID	/ Back to console
	PUSH 		/ Look like an empty line
	JMP I ACCEPT

	.SBTTL Output

// Print an ASCII string ( addr len -- )
TYPE,	0
	TAD I SP	/ Get count as limit
	CIA
	DCA LIMIT
	POP
	STA
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
	CDF SYMBOL
	ISZ MSG		/ Advance over
	SNA
	JMP I MSG	/ Oops, zero so stop
	DCA CHAR
	TAD CHAR
	BSW
	JMS P1SIX
	TAD CHAR	/ Do right half
	AND MASK6
	SNA
	JMP I MSG	/ Oops, zero
	JMS P1SIX
	JMP LOOP$

P2SIX,	0		/ Print one word of SIXBIT
	TAD CHAR
	BSW
	JMS P1SIX
	TAD CHAR	/ Do right half
	AND MASK6
	SNA
	JMP I P2SIX	/ Oops, zero
	JMS P1SIX
	JMP I P2SIX

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

// X@ Extended fetch ( addr fld -- n )
FFETCH,	0
	JMS SETFLD
	JMS CHANGE
	TAD I T1	/ Far fetch
	CDF SYMBOL		/ Back to dictionary
	DCA I SP
	JMP I FFETCH

// X! Extended store ( n addr fld -- )
FSTORE,	0
	JMS SETFLD
	POP
	TAD I SP	/ The value
	JMS CHANGE
	DCA I T1	/ Far Store
	CDF SYMBOL		/ Back to dictionary
	POP
	JMP I FSTORE

	.SBTTL Comparisons
	PAGE
// ( a b -- a )  Difference in AC
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
	STA		/ true FLAG IS -1
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

// PAD ( -- addr ) Address of a dynamic work area
PAD,	0
	TAD HERE
	TAD PADSPC
	PUSH
	JMP I PAD

	PAGE
MOD,	0
	JMS DIVMOD
	POP
	JMP I MOD

DIVMOD,	0		/ Divide with remainder
	TAD I SP
	DCA MODBY$
	POP
	TAD I SP
	CLL
	MQL DVI
MODBY$:	0
	SZL
	JMP DOVER
	DCA I SP	/ Remainder is in AC
	MQA
	PUSH	/ Quotient was in MQ
	JMP I DIVMOD
DOVER,	ERROR OV

	.SBTTL Literals

// Compile a literal string inline.  This is a simpler
// version of WORD.
   .ENABLE 7BIT
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

// S" Push address and count of a literal string
SQUOT,	0
	LAYOP XSTR
	JMS LITSTR
	JMP I SQUOT

// EXIT a zero opcode means return from word.
GENEX,	0
	JMS LAYDN
	JMP I GENEX

// S>D Convert to double integer
TODBL,	0
	TAD I SP	/ Test sign
	SPA CLA
	JMP NEG$	/ Negative
	PUSH		/ Positive, append zero
	JMP I TODBL
NEG$:	CLA CMA		/ Append -1
	JMP .-3

// MAX ( a b -- n )  Whichever is greater
MAX,	0
	TAD I SP	/ Set B aside
	DCA HIGH
	JMS COMP	/ Subtract B from A
	SMA CLA
	JMP I MAX	/ A was greater
	TAD HIGH	/ B was greater
	DCA I SP
	JMP I MAX

// MIN ( a b -- n )  Whichever is less
MIN,	0
	TAD I SP	/ Set B aside
	DCA HIGH
	JMS COMP	/ Subtract B from A
	SPA CLA
	JMP I MIN	/ A was less
	TAD HIGH	/ B was less
	DCA I SP
	JMP I MIN

// Generate non-counting loop structures.
// WHILE ( f -- )  Jump to BEGIN if nonzero
WHILE,	0
	LAYOP XJMPT
	JMS GENBK
	JMP I WHILE

// Generate the relative address for a jump
// back to location on the compile-time stack.
GENBK,	0
	TAD HERE	/ Where are we now?
	CIA
	TAD I SP	/ Subtract goal
	POP
	JMS LAYDN	/ Lay the difference
	JMP I GENBK

// UNTIL ( n -- )  Jump to BEGIN if zero
UNTIL,	0
	LAYOP XJMPF
	JMS GENBK
	JMP I UNTIL

// BEGIN ( -- n ) Mark top of loop
BEGIN,	0
	TAD HERE
	PUSH
	JMP I BEGIN

// AGAIN ( n -- ) Jump to BEGIN 
AGAIN,	0
	LAYOP XJMP
	JMS GENBK
	JMP I AGAIN

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
	LAYOP XSTR
	JMS LITSTR	/ Put the string inline
	LAYOP XTYPE
	JMP I DQUOT

// ." Print a literal string
RDQUOT,	0
	LAYOP XTYPE	/ Lay down runtime
	JMS LITSTR	/ Lay down the string
	JMP I RDQUOT

HALT,	0
	HLT
	JMP I HALT

SET10,	0		/ Runtime for DECIMAL
	TAD (12
	DCA BASE
	TAD (^D1000
	DCA SCALE
	JMP I SET10

SET8,	0		/ Runtime for OCTAL
	TAD (10
	DCA BASE
	TAD (1000
	DCA SCALE
	JMP I SET8
	
SYSVAR,	0		/ runtime for System variables
	TAD I DPTR
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
	JMS LAYDN	/ Space for the value
	TAD (DOVAR	/ Set action
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
	CDF SYMBOL	/ Field One back on
	PUSH
	JMP I SYSCON

ISLIT,	0     / Push a literal from dictionary
	TAD I DPTR
	PUSH
	JMP I SYSCON

	.SBTTL Memory

// @ Simple fetch ( addr -- n )
FETCH,	0
	TAD I SP	/Get the address
	DCA LOW
	TAD LOW		/ Compare with 0200
	TAD LOMEM
	SPA		/ Do not change field over 0200
	CDF .
	CLA
	TAD I LOW
	CDF SYMBOL
	DCA I SP
	JMP I FETCH

// ! Simple store ( n addr -- )
STORE,	0
	TAD I SP	/GET ADDRESS
	DCA LOW
	POP
	TAD I SP	/GET VALUE
	POP
	DCA T1
	TAD LOW		/ Compare address with 0200
	TAD LOMEM
	SPA		/ Do change field if > 0200
	CDF .
	CLA
	TAD T1
	DCA I LOW
	CDF SYMBOL
	JMP I STORE

// D= ( d1 d2 -- f )	Compare double
DEQL,	0     / d1l d1h d2l d2h
	CALL ROT    / d1L d2L d2H d1H
	JMS EQL	    / d1L d2L f
	TAD I SP
	POP	    / d1L d2L
	SNA CLA
	JMP F1$		/ Highs Not equal
	JMS EQL	/ flag
	JMP I DEQL
F1$:	POP   / d1L
	DCA I SP	/ flag
	JMP I DEQL

	PAGE
MOVE,	0		/ ( adr1 adr2 len -- )
	TAD I SP	/ count
	CIA
	DCA LIMIT
	POP
	STA		/ destination -1
	TAD I SP
	DCA TEXT2
	POP
	STA		/ source -1
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
	RPUSH
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

// ROT ( a b c -- b c a )
ROT,	0
	TAD I SP	/ Fetch top down
	DCA T1		/ c
	POP
	TAD I SP
	DCA T2		/ b
	POP
	TAD I SP
	DCA LOW		/ a
	TAD T2
	DCA I SP
	TAD T1
	PUSH
	TAD LOW
	PUSH	
	JMP I ROT

// -ROT ( a b c -- c a b )
MROT,	0
	TAD I SP	/ Fetch top down
	DCA T1		/ c
	POP
	TAD I SP
	DCA T2		/ b
	POP
	TAD I SP
	DCA LOW		/ a
	TAD T1
	DCA I SP
	TAD LOW
	PUSH
	TAD T2
	PUSH	
	JMP I MROT

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
	TAD I SP	/ Get n2
	DCA DROP2	/ Save it
	TAD SP		/ Point at n1
	IAC
	DCA DROP
	TAD I DROP	/ Get n1
	DCA I SP	/ Put it at top
	TAD DROP2	/ Get what WAS at top
	DCA I DROP	/ Put it at second
	JMP I SWAP

	.SBTTL Mathematics

// NEGATE 2s complement
NEGATE,	0
	TAD I SP
	CIA
	DCA I SP
	JMP I NEGATE

// * Single precision multiply
TIMES,	0		/ (a b -- a*b )
	TAD I SP
	DCA MULT$
	POP
	TAD I SP
	MQL MUY
MULT$:	0
	CLA MQA		/ Get low 12b
	DCA I SP
	JMP I TIMES

	PAGE
// UM* Unsigned multiply with double result
// ( u1 u2 -- ud )
UMULT, 0
	TAD I SP
	DCA MULT$
	POP
	TAD I SP
	MQL MUY
MULT$:	0
	DCA HIGH	/ High order part
	MQA
	DCA I SP	/ Low order part
	TAD HIGH
	PUSH		/ Low order part
	JMP I UMULT

// M* Signed multiply with double result
// ( n1 n2 -- d )
MSTAR, 0
	TAD I SP	/ n2 after MUY
	DCA MULT$
	POP
	TAD I SP	/ n1 to MQ
	MQL MUY
MULT$:	0
	DCA HIGH	/ Set hi 12b aside
	MQA
	DCA I SP	/ lo 12b on stack
	TAD HIGH	/ then hi 12b
	PUSH
	JMP I MSTAR

// Unsigned 12-bit divide ( a b -- a/b )
UDIV,	0
	TAD I SP
	DCA DIVSR$
	POP
	TAD I SP
	CLL
	MQL DVI
DIVSR$:	0
	CLA MQA
	DCA I SP
	JMP I UDIV

// Signed 12-bit divide ( a b -- a/b )
SDIV,	0
	TAD I SP
	DCA DIVSR$
	POP
	TAD I SP
	CLL
	MQL DVI
DIVSR$:	0
	CLA MQA
	DCA I SP
	JMP I SDIV

// Multiply then divide with 24-bit intermediary.
// M*
MULDIV,	0		/ ( a b c -- a*b/c )
	CALL MROT	/ c a b
	JMS MSTAR	/ c abd
	CALL ROT	/ abd c
	JMS FMMOD	/ a*b/c
	CALL SWAP
	POP
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

// ' gets xt of following word, or zero if
// no such word exists.
TICK,	0
	CALL BL
	CALL WORD
	TAD I WRDPTR
	SNA CLA
	JMP NOPE$
	CALL FIND
	POP
	JMP I TICK
NOPE$:	PUSH
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

// Simple integer division.
DIV,	0
	JMS DIVMOD	/ Use /MOD
	CALL SWAP	/ Throw away remainder
	POP
	JMP I DIV
	
	PAGE
// D* ( d n -- d ) Multiple double by single
DMULT,	0
	JMS DUP		/ dlo dhi n n
	CALL MROT	/ dlo n dhi n
	JMS MSTAR	/ dlo n plo phi
	POP 		/ dlo n plo
	CALL MROT	/ plo dlo n
	JMS MSTAR	/ plo plo phi
	CALL ROT		/ plo phi plo
	JMS PLUS	/ plo phi
	JMP I DMULT

	.SBTTL Number conversions
// U8. ( n -- ) Print unsigned value
UDOT,	0		/ Print a numeric value
	JMS UNUM
	JMS TYPE
	JMP I UDOT

// Convert an unsigned value to text
UNUM,	0
 	PUSH		/ Double unsigned
	JMS FOINIT	/ Use Formatted conversion
	JMS FONUM	/ Output all digits
	JMS FODONE
	JMP I UNUM

// D. ( d -- ) Print double value
DDOT,	0
	TAD DDOT	/ Borrow code
	DCA DOT
	JMS TUCK	/ Remember the sign
	JMS DABS
	JMP DOTGO

// DABS Double absolute value
DABS,	0
	TAD I SP
	SPA CLA
	JMS DNEG	/ Complement
	JMP I DABS

// TUCK ( n1 n2 -- n2 n1 n2 )
TUCK,	0
	JMS DUP
	CALL MROT
	JMP I TUCK

// . ( nn - )) Print signed value.
DOT,	0
	JMS DUP		/ Remember the sign
	JMS ABS
	JMS TODBL
DOTGO,	JMS FOINIT	/ Init formatting
	JMS FONUM
	CALL ROT	/ Get the signed value back
	JMS SIGN	/ Emit minus sign
	JMS FODONE
	JMS TYPE
	JMP I DOT

// ABS Single word absolute value ( n -- n )
ABS,	0
	TAD I SP
	SMA CLA
	JMP I ABS
	TAD I SP
	CIA
	DCA I SP
	JMP I ABS

.SBTTL Compiler

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

	CALL BL		/ Push SPACE as delimiter
	CALL WORD	/ Put ASCII name in WRDBUF
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

	TAD HERE	/ CPTR to where code goes
	DCA CPTR
	LAYOP MYADR	/ Default push self
	TAD HERE    	/ Set data area pointer
	DCA DPTR

	TAD NEWORD	/ This is now first word
	DCA DICT	/ in the dictionary.
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
	TAD HERE	/ Data IS the code
	DCA I CPTR
	JMP I COLON

// SOURCE ( -- addr len )	Get input descriptor
SOURCE,	0
	PUSH TIBPTR
	PUSH LINLEN
	JMP I SOURCE

	PAGE
AVAIL,	0		/ Get available memory
	TAD HERE
	CIA
	TAD RBASE	/ Limit is bottom of R-stack
	PUSH
	JMP I AVAIL

SEMI,	0		/ Finish compilation
	DCA STATE	/ Flag off
	CALL LAYLIT
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

FIXBAC,	0   / Fixup a backwards jump
	TAD HERE
	CIA
	TAD I SP
	DCA I HERE
	JMP I FIXBAC

	.SBTTL Parsing input

/// Consume next input character from TIB buffer.
// Use this instead of KEY in most places. ( -- ch )
INPTR,	0
NXTIN,	0
	TAD TIBPTR	/ Starting address
	TAD INOFF	/ Plus offset ?? check INOFF > TIDLEN
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
WORD,	0
	TAD I SP
	CIA
	DCA CHAR	/ Save the negative delimiter
	STA
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

	JMS CLASS
	JMP LOOP1$	/ Skip leading delimiters
	JMP END$	/ Stop at any control code
	JMP SAVE$	/ Save this character

LOOP2$:	JMS NXTIN	/ Get another
	TAD I SP
	DCA T1
	POP
	JMS CLASS
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
CLASS,	0
	TAD CHAR	/ Is it the delimiter?
	TAD T1
	SNA CLA
	JMP I CLASS	/ Delimiter first return
	ISZ CLASS
	TAD ASPACE
	CIA
	TAD T1
	SPA CLA
	JMP I CLASS	/ Control, skip return
	ISZ CLASS
	JMP I CLASS	/ Else double skip

// Convert counted string to address and length
// ( caddr -- addr len )
COUNTS,	0
	TAD I SP
	DCA LOW		/ Save the length
	TAD I SP	/ Increment the address
	IAC
	DCA I SP	/ Save it back
	TAD LOW
	PUSH	/ Push the length
	JMP I COUNTS

// POSTPONE compiles IMMEDIATE words so that they
// do not run at compile time.
PSTPON,	0
	CALL BL		/ Lookup next word
	CALL WORD
	CALL FIND	/ S: xt 1
	TAD I SP
	POP
	SNA CLA		/ Found it?
	JMP POP$  	/ No, lose caddr
	TAD I SP
	JMS LAYDN
POP$:	POP
	JMP I PSTPON

	.SBTTL Flow control

/ Mark a FOWARD jump location on the stack,
/ be be fixed up by FIXFWD later.
MARKFJ,	0
	TAD HERE
	PUSH
	JMS LAYDN
	JMP I MARKFJ

GENIF,	0
	LAYFWD XJMPF	/ Fixup to ELSE or THEN
	JMP I GENIF

/ Fix up a FORWARD jump. The jump offset on the
/ stack is set to point to HERE.
FIXFWD,	0
	TAD I SP	/ Get place needing fixup
	POP
	SNA
	JMP I FIXFWD	/ No fixup there
	DCA T1
	TAD T1	/ Compute difference
	CIA
	TAD HERE
	DCA I T1	/ Point it to HERE
	JMP I FIXFWD

	PAGE
GENELS,	0		/ Compile ELSE
	LAYFWD
	CALL SWAP
	JMS FIXFWD
	JMP I GENELS

GENTHN,	0		/ Compile THEN that resolves IF
	JMS FIXFWD
	JMP I GENTHN

JUMP,	0		/ Adjust IP by a signed constant
	TAD I IP	/ Get adjustment
	TAD IP		/ Add to old IP
	DCA IP		/ Save it
	JMP I JUMP

JUMPT,	0		/ Adjust IP if TOS true
	TAD I SP
	POP
	SZA CLA
	JMP YES$
	ISZ IP		/ False so skip the adjustment
	JMP I JUMPT
YES$:	/ True so do the adjustment
	TAD I IP	/ Get adjustment
	TAD IP		/ Add to old IP
	DCA IP		/ Save it
	JMP I JUMPT

JUMPF,	0		/ Adjust IP if TOS false
	TAD I SP
	POP
	SNA CLA
	JMP YES$	/ False, adjust the IP
	ISZ IP		/ True so skip the adjustment
	JMP I JUMPF
YES$:	TAD I IP	/ Get adjustment
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
// WRDBUF, result goes on stack.  D* is used
// to build a 24-bit value that might turn out
// to be just 12 bits.
ISNEG,	0
ISDBL,	0
NUMLO,	0
	DCA ISNEG	/ Clear negative flag
	DCA ISDBL
	TAD I WRDPTR	/ Get char count
	CIA
	DCA LIMIT
	TAD WRDPTR	/ First char
	DCA TEXT1
	PUSH		/ Initial value zero
	PUSH		/ 0 0
LOOP$:	TAD I TEXT1
	DCA CHAR
	JMS SKPNUM	/ Skip if numeric
	JMP SETD$	/ Mark as double
	TAD CHAR	/ Check for hyphen
	TAD NEGMIN
	SNA CLA
	JMP SETM$	/ Yes, set flag
	/ Shift previous value by base
	PUSH BASE
	JMS DMULT	/ val = val * base
	TAD CHAR	/ Get digit value by
	TAD NEGZRO	/ subtracting ASCII "0"
	PUSH		/ on stack
	PUSH		/ high zero
	JMS DPLUS	/ Add new digit to value
NEXT$:	ISZ LIMIT	/ Count characters
	JMP LOOP$	/ Get next digit
	JMP DONE$

	/ Setting flags for later
SETM$:	ISZ ISNEG	/ Set negative flag
	JMP NEXT$
SETD$:	ISZ ISDBL
	JMP NEXT$

	/ Now apply flags
DONE$:	TAD ISNEG	/ Was there a minus sign?
	SZA CLA
	JMS DNEG	/ Yes, negate
	TAD ISDBL	/ Was it double?
	SNA CLA
	POP	/ No, lose high order part
	JMP I NUMLO

// FM/MOD ( d n -- rem quo ) Divide double
// number yielding remainder and quotient.
FMMOD,	0
	TAD I SP
	POP	
	DCA DIVBY$
	TAD I SP	/ High order to AC
	POP
	DCA T1
	TAD I SP	/ Low order in MQ
	POP
	MQL
	TAD T1
	CLL
	DVI
DIVBY$:	0
	SZL
	JMP DOVER	/ Divide overflow?
	PUSH		/ Remainder
	CLA MQA
	PUSH		/ Quotient
	JMP I FMMOD

// SIGN ( n -- ) Put minus sign in formatted
// output if value is negative.
SIGN,	0
	TAD I SP	/ Get value
	POP
	SMA CLA		/ Is it negative?
	JMP I SIGN	/ No
	TAD ("-)	/ Yes, put minus sign.
	JMS FOOUT
	JMP I SIGN

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
	DCA LOW		/ Save starting value
LOOP$:	TAD I TEXT1	/ Examine next char
	DCA CHAR
	JMS SKPNUM	/ Skip if numeric
	JMP BADNM$
	TAD CHAR	/ Is numeric so convert to value
	TAD NEGZRO
	DCA CHAR
	TAD LOW		/ Shift previous value
	MQL		/ Into MQ
	TAD BASE
	DCA .+2
	MUY
	00		/ Multiplicand
	CLA MQA		/ Get product
	TAD CHAR	/ Add lastest char
	DCA LOW		/ This is latest value
	ISZ LIMIT
	JMP LOOP$	/ Get next digit
	TAD LOW
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

BADNM$:	ERROR NF

/ Report undefined word
UNDEF,	0
	JMS PSEEK
	ERROR UD

// Print the sought-after word
PSEEK,	0
	TAD WRDPTR
	IAC
	PUSH
	TAD I WRDPTR
	PUSH
	JMS TYPE
	JMP I PSEEK

LPIDX,	0		/ Value of inner loop variable
	TAD I RSP
	PUSH
	JMP I LPIDX

LPJDX,	0     / Value of outer loop variable
	TAD RSP
	IAC
	DCA T1
	TAD I T1
	PUSH
	JMP I LPJDX

GENDO,	0
	LAYOP XTOR
	RPUSH	/ Zero the LEAVE chain
	TAD HERE	/ Remember top of loop
	PUSH		/ for later fixup
	JMP I GENDO

// +LOOP Generate the bottom of a modified LOOP
GPLOOP,	0
	TAD GPLOOP	/ Steal return address
	DCA GLOOP
	LAYOP XLPPBO	/ Lay down alternate head
	JMP GBOT	/ The rest is like LOOP

// Compile LOOP - Generate the bottom of a DO-LOOP.
// This lays down the runtime (LP) operation,
// resolves any LEAVEs, then lays down the Loop Exit
// (LX) operation.
GLOOP,	0
	LAYOP XLPBOT
GBOT,	TAD HERE	/ Compute jump distance
	CIA
	TAD I SP
	POP
	JMS LAYDN	/ Set jump back offset
	TAD I RSP	/ Fixup LEAVEs
	DCA T1
FIXLP$:	TAD T1		/ Addr of place to fix
	SNA
	JMP LAYFX$	/ No more
	DCA T2		/ Save next in chain
	TAD I T2
	DCA T2
	TAD T1		/ Distance to jump
	CIA
	TAD HERE
	DCA I T1	/ Adjust the jump
	TAD T2
	DCA T1
	JMP FIXLP$	/ Check another
	/ Fixed up LEAVEs will jump here.
LAYFX$:	LAYOP XLPXIT
/	POP
	ISZ RSP		/ Don't need LEAVE chain
	JMP I GLOOP

BOTLPP,	0     / Bottom of +LOOP
	TAD BOTLPP     / Steal code in BOTLP
	DCA BOTLP
	TAD I SP
	POP
	JMP SETI

	PAGE
// Processing at the bottom of a loop.
// R@ 1+ R! DUP R@ >= JMPT (HERE -) R> 2DROP 
BOTLP,	0
	TAD I RSP	/ Increment loop variable
	IAC
SETI,	DCA I RSP
	TAD I RSP	/ Check against limit
	CIA
	TAD I SP
	SZA SMA CLA
	JMP BACK$	/ Not yet
	ISZ IP		/ Skip the address
	JMP I BOTLP	/ LPXIT will clean up
BACK$:	TAD I IP	/ Jump to top of loop
	TAD IP
	DCA IP
	JMP I BOTLP

// Cleanup at the exit of a LOOP for any reason.
// Pop loop index from Rstack and limit value
// from data stack.
LPXIT,	0
	ISZ RSP
	POP
	JMP I LPXIT

// Skip if CHAR is numeric
SKPNUM,	0
	TAD NEGMIN	/ = "-"
	TAD CHAR
	SNA CLA
	JMP NUM$
	TAD NEGZRO	/ >= "0"
	TAD CHAR
	SPA CLA
	JMP NOT$
	TAD CHAR
	TAD NEGNIN	/ <= "9"
	SMA SZA
	JMP .+2		/ Not numeric, don't skip
NUM$:	ISZ SKPNUM	/ Is numeric so skip return
NOT$:	CLA
	JMP I SKPNUM
	
SWITCH,	0		/ Read the console switches
	LAS
	PUSH
	JMP I SWITCH

// Print contents of the stack, bottom to top.
DOTS,	0
	JMS DEPTH	/ Calulate how many words
	TAD I SP
	POP
	SPA SNA
	JMP I DOTS	/ Do nothing if empty.
	CIA
	DCA LIMIT$	/ Should be negative count
	STA
	TAD SBASE	/ Start at bottom
	TAD SSIZE
	DCA SP$
LOOP$:	JMS SPACE
	TAD I SP$
	PUSH
	JMS DOT
	STA
	TAD SP$
	DCA SP$
	ISZ LIMIT$
	JMP LOOP$
	CALL CRLF
	JMP I DOTS
SP$:	0     / Private stack scanner
LIMIT$:	0

SPACE,	0		/ Type a space
	CLA
	TAD ASPACE
	JMS PUT
	JMP I SPACE

// Print name of current word if SR bit 0 is set.
TRACE,	0
	LAS		/ Load switches
	SMA CLA		/ b0 set?
	JMP I TRACE	/ No
	JMS PNAME	/ Yes, print name
	PUSH SP		/ Print stack
	CALL DOT8
	JMS SPACE	/ Print space
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
	CALL CRLF
	JMP BUMP$
NEXT$:	JMS SPACE
BUMP$:	ISZ CURENT	/ Find link word
	TAD I CURENT	/ Fetch link
	SNA
	JMP I WORDS	/ Zero means stop
	DCA CURENT
	JMP LOOP$

	PAGE
// Print a counted name in the dictionary.
// Zero is allowed because that is "@". CURENT
// points to the current executing word.
PNAME,	0
	TAD I CURENT
	SNA
	JMP MISS$
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
	BSW		/ Look at left 6 bits
	ISZ COUNT
	CALL P1SIX
	TAD T1		/ Now do right half
	AND MASK6
	TAD (-37	/ But stop at 037
	SNA
	JMP I PNAME
	TAD NAMPAD	/ Correct it
	ISZ COUNT
	CALL P1SIX
	ISZ TEXT3
	ISZ LIMIT	/ Count down
	JMP LOOP$
	JMP I PNAME
MISS$:	ERROR ME	/ Trying to print missing entry
	JMP I PNAME

// Add a character to the front of the PAD output
// area, working down.  This is for formatted numbers.
FOPTR,	0
FOLEN,	0
FOOUT,	0
	DCA FODONE	/ Temp save char to output
	CLA CMA		/ Decrement output pointer
	TAD FOPTR
	DCA FOPTR
	TAD FODONE	/ Put new char there
	DCA I FOPTR
	ISZ FOLEN	/ Increment used length
	JMP I FOOUT

// <# Initialize formatted output.  The string
// is built right to left so we use 16 words
// starting at PAD.  Double value D1 is on the stack.
FOINIT,	0
	DCA HIGH
	TAD I SP	/ Scaling required?
	SNA CLA
	JMP ALLOC$
	/ Pre-scale the value by 1000
	PUSH SCALE
	JMS FMMOD	/ rem quo
	TAD I SP	/ quo is part over 1000
	DCA HIGH	/ Save it for later
	DCA I SP	/ Zero old high part
	/ Stack is now D1 MOD SCALE and HIGH
	/ contains D1 / SCALE.
	/ Allocate buffer above PAD.
ALLOC$:	JMS PAD
	TAD I SP
	TAD (20
	DCA FOPTR	/ Set top end
	POP
	DCA FOLEN	/ Zero length
	JMP I FOINIT

// #> Put PAD & COUNT on stack
FODONE,	0
	POP		/ Delete value
	POP
	PUSH FOPTR	/ Start of formatted str
	PUSH FOLEN	/ Length
	JMP I FODONE

// # ( d1 -- d2 ) Format one digit of number.
// Each call divides the double value by the BASE
// and uses the remainder to make the digit.
FODIG,	0
	PUSH BASE	/ Use current base
	JMS FMMOD	/ rem quo
	CALL SWAP	/ quo rem
	TAD I SP	/ Recover remainder
	POP
	TAD AZERO	/ Convert to ASCII
	JMS FOOUT	/ Add to buffer
	JMS TODBL	/ Quotient still double
	JMP I FODIG

// #S ( d -- d ) Format all digits of a number
// Keep calling FODIG until only zero is left.
// This has to be done in two parts to prevent
// divide overflow on large numbers.
FONUM,	0
	/ Loop printing the D1 MOD SCALE part
	/ that was created by FOINIT.  This has
	/ to be done SCALE/BASE times if HIGH
	/ part is non-zero.
	TAD HIGH	/ Is there a high part?
	SNA CLA
	JMP LOOP2$	/ No, jump ahead
	TAD SCDIGS	/ Get -# low digits
	DCA LIMIT
LOOP1$:	JMS FODIG	/ Do one digit
	ISZ LIMIT
	JMP LOOP1$

	/ Set up printing the D1 / SCALE part
	/ AFTER the low-order part.
	POP 		/ Make room for part 2
	POP
	TAD HIGH	/ Get the scaled out part
	PUSH		/ Make it dbl on the stack
	JMS TODBL
	/ Loop printing the second part
LOOP2$:	JMS FODIG	/ rem quo
	CALL SWAP	/ quo rem
	TAD I SP	/ Is the residue zero?
	SNA CLA
	JMP I FONUM	/ Yes, stop
	CALL SWAP
	JMP LOOP2$	/ No, do it again

// HOLD Add character to formatted output
HOLD,	0
	TAD I SP
	JMS FOOUT
	POP
	JMP I HOLD

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

IMM$:	STA		/ Return -1 flag for IMMEDIATE
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
	STA		/ Minus 1
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

// OPEN-FILE ( c-addr u fam -- fileid ior )
// Open the file named in the character string
// c-addr u, with file access method indicated by fam.
// The meaning of fam is implementation defined.
// If the file is successfully opened, ior is zero,
// fileid is its identifier, and the file has been
// positioned to the start of the file.  Otherwise,
// ior is the implementation-defined I/O result code
// and fileid is undefined.

	.EXTERNAL SETFID,FHOPEN,FHCLOS,FHRDL
FILOPN,	0
	POP	/?? Ignore mode for now
	IOCALL FHOPEN	/ Call OS8 interface
	JMP I FILOPN

SETSTR,	0	/ Describe a counted string
	TAD I SP	/ Length into MQ
	MQL
	POP
	TAD I SP	/ Address into AC
	POP
	JMP I SETSTR

// CREATE-FILE ( addr len mode -- id status )
	.EXTERNAL FHCRE
FILCRE,	0
	IOCALL FHCRE	/ OS8 interface
	JMP I FILCRE

// CLOSE-FILE ( id -- status )
FILCLS,	0
	IOCALL FHCLOS
	JMP I FILCLS

// FLUSH-FILE ( id -- status )
	.EXTERNAL FHFLUS
FILFLU,	0
	TAD I SP
	IOCALL FHFLUS
	DCA I IP
	JMP I FILFLU

// READ-FILE ( c-addr u1 fileid -- u2 ior )
// Read u1 consecutive characters to c-addr from the
// current position of the file identified by fileid.
// If u1 characters are read without an exception, ior
// is zero and u2 is equal to u1.
// If the end of the file is reached before u1 characters
// are read, ior is zero and u2 is the number of characters
// actually read.
FILRD,	0	/ Read a block from the file
	CDF .
	JMP I FILRD

	PAGE
/ READ-LINE ( c-addr u1 fileid -- u2 flag ior )
/ Read the next line from the file specified by fileid
/ into memory at the address c-addr. At most u1 characters
/ are read. Up to two implementation-defined line-
/ terminating characters may be read into memory at the end
/ of the line, but are not included in the count u2.
/ The line buffer provided by c-addr should be at least
/ u1+2 characters long.  If the operation succeeded,
/ flag is true and ior is zero. If a line terminator
/ was received before u1 characters were read, then u2
/ is the number of characters, not including the line
/ terminator, actually read (0 <= u2 <= u1). When
/ u1 = u2 the line terminator has yet to be reached.
/ At EOF ior=-1, flag=0, u2=0
FILRDL,	0
	IOCALL FHRDL	/ Read one line
	JMP I FILRDL

FILWR,	0   / Write a block
	JMP I FILWR

// WRITE-LINE ( addr len id -- st )
	.EXTERNAL FHWRL
FILWRL,	0
	IOCALL FHWRL
	JMP I FILWRL

// INCLUDE-FILE ( id -- )
// Change SOURCE-ID.  The real work is in ACCEPT.
FILINC,	0
	TAD I SP
	DCA SRCID
	POP
	JMP I FILINC

// Parse a string up to a specified delimiter,
// putting the address and length on the stack.
// This is quite different from WORD.
PARSE,	0
	TAD I SP
	CIA
	DCA CHAR	/ Save the negative delimiter
	TAD TIBPTR
	TAD INOFF
	DCA I SP	/ This is the output address
	DCA COUNT	/ Zero count

LOOP$:	JMS NXTIN	/ Look at next character
	TAD I SP
	DCA T1
	POP
	JMS CLASS
	JMP END$	/ Stop at delimiter
	JMP END$	/ or any control code
SAVE$:	ISZ COUNT	/ or keep going
	CLA
	JMP LOOP$

END$:	CLA
	TAD COUNT	/ Fix up length
	PUSH
	JMP I PARSE

// Conditional abort with message
// IF ." abc" TYPE ABORT THEN
ABTQ,	0	/ ABORT"
	JMS GENIF
	JMS DQUOT
	LAYOP XABORT
	JMS FIXFWD
	JMP I ABTQ

// CHAR: Parse a character and push it
PSHCH,	0
	CALL BL
	CALL WORD
	POP
	TAD WRDBUF+1
	PUSH
	JMP I PSHCH

// [CHAR]: Push a character during compile
CPSHCH,	0
	CALL BL
	CALL WORD
	POP
	LAYOP XLIT
	TAD WRDBUF+1
	JMS LAYDN
	JMP I CPSHCH

// DOES> add runtime action to a CREATEd item.
// This runs as a defining word is being compiled.
DOES,	0
	TAD I NEWORD	/ Set Forth runtime flag
	TAD (FTHFLG)
	DCA I NEWORD
	LAYOP XDOES	/ Make new word call part 2
	JMS LAYDN	/ then return
	LAYOP XPAR	/ Push paramater address
	JMP I DOES

// >BODY push address of some word's parameter
// area on the stack.  It is 3 words after the
// flag word.
TOBODY,	0
	TAD I SP
	IAC; IAC; IAC
	DCA I SP
	JMP I TOBODY

// Push address of running word's parameter
// area on the stack.  This runs as a CREATEd
// word's runtime is executing.
PARADR,	0
	TAD OSP		/ Look who called us
	IAC
	DCA T1
	TAD I T1	/ Get opcode
	PUSH
	JMS TOBODY
	JMP I PARADR

	PAGE
MYADR,	0
	TAD OSP		/ Look who called us
	DCA T1
	TAD I T1	/ Get opcode
	PUSH
	JMS TOBODY
	JMP I MYADR

// Runtime for DOES>.  Sets CODE pointer for a new word.
// Will leave the body address of the word being
// defined on the stack. This runs as a defining word
// is executing.
DODOES,	0
	/ The IP is pointing at the RETURN op.  One
	/ after that is the runtime.
	TAD IP
	IAC
	DCA T2		/ This will be new code ptr
	TAD NEWORD	/ Find code ptr of word being
	IAC; IAC	/ defined.
	DCA T1
	TAD T2		/ Point it at DOES> clause
	DCA I T1

	TAD I NEWORD	/ Set FORTH-type flag
	TAD FTHFLG
	DCA I NEWORD
	JMP I DODOES

// +! ( n addr -- )
PSTORE,	0
	POP T1		/ Stash address
	TAD I T1	/ Get old value
	TAD I SP	/ Add increment
	DCA I T1	/ Store it back
	POP	
	JMP I PSTORE

// FILL ( addr n char -- )
FILL,	0
	TAD I SP
	DCA CHAR	/ Fill with this
	POP
	TAD I SP
	CIA
	DCA LIMIT	/ How many
	POP
	STA
	TAD I SP
	DCA TEXT2	/ Where
	POP
	TAD LIMIT	/ Do nothing if n=0
	SNA CLA
	JMP I FILL
	TAD CHAR
LOOP$:	DCA I TEXT2	/ Write n words
	ISZ LIMIT
	JMP LOOP$
	JMP I FILL

// PICK ( a b c n -- a b c a )
PICK,	0
	TAD I SP
	POP
	TAD SP
	DCA T1
	TAD I T1
	PUSH
	JMP I PICK

// ROLL ( a b c d 2 -- a c d b )
ROLL,	0
	TAD I SP	/ Number to shift
	DCA COUNT
	JMS PICK	/ a b c d b'
	TAD SP		/ Pointing at b'
	TAD COUNT	/ Pointing at c
	DCA T1
	TAD COUNT
	IAC
	CIA
	DCA GENCAS	/ Borrow temp -2
SHUFL$:	TAD I T1	/ Get c
	ISZ T1
	DCA I T1	/ Store at old b
	TAD T1
	TAD (-2)	/ Back two to get d
	DCA T1
	ISZ GENCAS
	JMP SHUFL$	/ Repeat n times
	POP 		/ a c d b b Lose extra 'b'
	JMP I ROLL

// CASE ( val -- ) The first OF clause does not need
// to resolve a JUMP, so we put a zero on the stack.
GENCAS,	0
	PUSH		/ Zero fixup marker
	JMP I GENCAS

// Compile time OF ( ref val -- ref ) Resolve
// previous FALSE jump, if any, and make next test.
GENOF,	0
	LAYFWD XOF	/ Lay compare-and-jump op
	JMP I GENOF

// Runtime for OF.  Execute the test and jump around
// the body if false.
DOOF,	0
	JMS COMP	/ Compare top two
	SNA CLA
	JMP NOJ$
	JMS JUMP
	JMP I DOOF
NOJ$:	ISZ IP
	JMP I DOOF

// ENDOF Create JUMP from TRUE branch to ENDCASE,
// then resolve previous FALSE branch.
GENEOF,	0
	CALL SWAP	/ Bring TRUE jump to top
	JMS FIXFWD	/ Chain previous to this
	LAYFWD		/ Make this TRUE jump
	CALL SWAP	/ Go back for OF-FALSE
	JMS FIXFWD	/ Make it jump here
	JMP I GENEOF

// ENDCASE.  The last failed OF jumps here.
GENEC,	0
	JMS FIXFWD
	LAYOP XDROP
	JMP I GENEC

SPACES,	0
	TAD I SP
	POP
	CIA
	DCA LIMIT
LOOP$:	JMS SPACE
	ISZ LIMIT
	JMP LOOP$
	JMP I SPACES

	PAGE
FORGET,	0
	CALL BL		/ Push Space delimiter
	CALL WORD	/ Get next word, caddr on stack
	TAD I WRDPTR	/ Get anything?
	SNA
	JMP I FORGET	/ No
	CALL FIND	/ caddr 0 | xt 1 | xt -1
	TAD I SP
	POP		/ Execution token is at TOS
	SNA CLA
	JMP I FORGET	/ Not found
	TAD I SP	/ Get token of word to forget
	POP
	DCA T1
	TAD I T1	/ Head length
	AND LENMSK
	CIA		/ Back over the name
	TAD T1
	DCA HERE	/ Set freespace start
	TAD T1
	IAC		/ Address of Link word
	DCA T1
	TAD I T1	/ Get previous
	DCA DICT	/ Make precediing word the top.
	JMP I FORGET

// Compile a literal SIXBIT string inline.
QUOT6,	0
	LAYOP XSTR
	TAD HERE
	DCA T1		/ Remember where length goes
	JMS LAYDN	/ Save space for length
	TAD HERE
	JMS A6INIT	/ Init SIXBIT packing
LOOP$:	JMS NXTIN
	TAD I SP
	DCA CHAR
	POP
	TAD CHAR	/ Check for terminating quote
	TAD NEGQ
	SNA CLA
	JMP DONE$
	TAD CHAR	/ Not quote so pack it
	JMS A6ADD
	ISZ COUNT
	JMP LOOP$	/ Go back for more
DONE$:	JMS A6DONE	/ Fixup the length
	DCA I T1
	TAD I T1	/ Also adjust HERE
	TAD HERE
	DCA HERE
	JMP I QUOT6

// .6" Type the following SIXBIT string
DQUOT6,	0
	JMS QUOT6
	LAYOP XTYP6
	JMP I DQUOT6

// .6 Type a sixbit string
TYPE6,	0
	TAD I SP	/ Get word count
	POP
	CIA
	DCA LIMIT
	TAD I SP	/ Get start address
	POP
	DCA T1
LOOP$:	TAD I T1
	SNA
	JMP I TYPE6
	BSW		/ Print left half
	CALL P1SIX
	TAD I T1	/ Do right half
	AND MASK6
	SNA
	JMP I TYPE6	/ Stop at zero
	CALL P1SIX
	ISZ T1
	ISZ LIMIT
	JMP LOOP$
	JMP I TYPE6

// Report an error and restart.
RECOVR,	0
	JMS RESET	/ Put world in known state
	JMS MSG		/ Announce error
	.ENABLE SIXBIT,FILL
	TEXT "?ERROR "
	CDF .
	TAD I RECOVR	/ 2-char code
	CDF SYMBOL
	DCA CHAR
	CALL P2SIX
	CALL CRLF
	JMP RESUME

// LEAVE becomes an unconditional jump that is
// part of a chain of jumps to the end of a loop.
// These get fixed up in GLOOP.
GENLV,	0
	LAYOP XJMP
	TAD HERE
	DCA T1		/ Place to be fixed
	TAD I RSP	/ Find the chain
	JMS LAYDN
	TAD T1
	DCA I RSP	/ Link LEAVE chain
	JMP I GENLV

	PAGE
// D+ ( d1 d2 -- d3 )  Add two 24-bit values
//??? Not carrying from low to high words.
DPLUS,	0
	POP HIGH
	POP LOW
	CALL SWAP	/ d1H d1L
	CLA CLL
	TAD I SP	/ Add low half
	TAD LOW
	DCA I SP
	CALL SWAP
	SZL CLA
	IAC		/ Carry a one
	TAD I SP	/ Add high half
	TAD HIGH
	DCA I SP
	JMP I DPLUS

// M+ ( d n -- d )  Add 12 bits to 24 bits
MPLUS,	0
	JMS TODBL	/ Extend to double
	JMS DPLUS
	JMP I MPLUS

// DNEGATE ( d -- d )  Double negate
DNEG,	0
	JMS INVERT
	CALL SWAP
	JMS NEGATE
	CALL SWAP
	JMP I DNEG

// Ignore rest of line
CMTL,	0
	TAD LINLEN	/ Skip input offset to end
	DCA INOFF
	JMP I CMTL

// Parenthesized comment.  Skip to right paren.
CMTP,	0
	PUSH ("))
	CALL PARSE
	POP
	POP
	JMP I CMTP

// .( Immediate form of ."
CMSG,	0
	PUSH (")
	CALL PARSE	/ addr len
	JMS TYPE
	JMP I CMSG

// U.R ( u1 u2 -- ) Print u1 right-justified in u2
// spaces.
UDOTR,	0
	POP CMSG	/ Save width
	JMS UNUM
	TAD I SP	/ Calc padding width
	CIA
	TAD CMSG
	PUSH
	JMS SPACES	/ Emit padding
	JMS TYPE	/ Emit digits
	JMP I UDOTR

// 2DUP ( d - d d )
DUP2,	0
	JMS OVER
	JMS OVER
	JMP I DUP2

// 2OVER ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )
OVER2,	0
	PUSH (3
	JMS PICK
	PUSH (3
	JMS PICK
	JMP I OVER2

SWAP2,	0
	JMS ROT
	JMS PUSHR
	JMS ROT
	JMS POPR
	JMP I SWAP2

// .6 Print two sixbit characters
DOT6,	0
	JMP I DOT6

// .8 Print value as 4 octal digits
DOT8,	0
	POP T1
	TAD (-4)	/Loop four times.
	DCA LIMIT
LOOP$:	TAD T1		/Get number.
	RTL;RAL		/Shift one digit left
	DCA T1		/and save.
	TAD T1
	RAL	/Shift last bit of high digit into low.
	AND (7)		/Mask out low digit.
	TAD AZERO	/ASCIIfy.
	CALL PUT	/Output number.
	ISZ LIMIT	/Bump digit count.
	JMP LOOP$	/Repeat.
	JMP I DOT8	/Return.

// 2>R ( a b -- )  Two words to Rstack
RTWO,	0
	CALL SWAP
	TAD I SP
	POP
	RPUSH
	TAD I SP
	POP
	RPUSH
	JMP I RTWO

LAYLIT,	0		/ Lay a literal and skip it
	CLA
	CDF .		/ Fetch from instruction space
	TAD I LAYLIT
	CDF SYMBOL
	JMS LAYDN
	ISZ LAYLIT
	JMP I LAYLIT

.IF NE CHKPOP <POPS, 0
	ISZ SP
	DCA SPOP$
	TAD SP
	TAD (-7400)
	SMA CLA
	HLT
	TAD SPOP$
	JMP I POPS
SPOP$:	0>

	PAGE
// FILE-POSITION ( id -- ud ior ) Return file position
// in characters.
	.EXTERNAL FHPOS
FILPOS,	0
	IOCALL FHPOS	/ Get position
POS$:	HLT   		/ Error
	/ Double posotion is now on stack
	CLA
	PUSH		/ flag
	JMP I FILPOS

.SBTTL  Built-in word definitions

// The SYMBOL section in Field 1 contains the Forth
// "address space" as seen by a Forth programmer.
// The dictionary, stacks, and Terminal Input
// Buffer are all here.
	.DSECT SYMBOL
	FIELD 1
WRDBUF,	ZBLOCK ^D16	/ Assemble ASCII token here
NAME6,	ZBLOCK ^D8	/ Sought word here in SIXBIT
ZERO,	0	/ For faking a return
	.GLOBAL TIB
TIB=.
	*.+^D80	/ Terminal Input Buffer

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
TEXT "FILE-POSITION_"; B=.; 7; A; FILPOS
TEXT "STOPAT";	A=.; 3; B; SYSVAR; STOPAT
TEXT ".8";	B=.; 1; A; DOT8
TEXT "0<";	A=.; 1; B; LESSZ
TEXT ".6";	B=.; 1; A; DOT6
TEXT "2>R_";	A=.; 2; B; RTWO
TEXT "2*";	B=.; 1; A; TIMES2
TEXT "2SWAP_";	A=.; 3; B; SWAP2
TEXT "2OVER_";	B=.; 3; A; OVER2
TEXT "2DUP";	A=.; 2; B; DUP2
TEXT "U.R_";	B=.; 2;	A; UDOTR
TEXT "LITERAL_";A=.; 4004; B; GENLIT
TEXT "MOD_";	B=.;	2; A; MOD
TEXT "MAX_";	A=.; 2; B; MAX
TEXT "MIN_";	B=.; 2; A; MIN
TEXT "D=";	A=.; 1; B; DEQL
TEXT "/_";	B=.; 1; A; DIV
TEXT ".(";	A=.; 4001; B; CMSG
TEXT "(_";	B=.; 4001; A; CMTP
TEXT "\_";	A=.; 1; B; CMTL
TEXT "DNEGATE_";B=.; 4; A; DNEG
TEXT "TUCK";	A=.; 2; B; TUCK
TEXT "DABS";	B=.; 2; A; DABS
TEXT "D+";	A=.; 1; B; DPLUS
TEXT "D.";	B=.; 1; A; DDOT
TEXT "M+";	A=.; 1; B; MPLUS
TEXT "M*";	B=.; 1; A; MSTAR
TEXT "D*";	A=.; 1; B; DMULT
TEXT "-ROT";	B=.; 2; A; MROT
TEXT "UM*_";	A=.; 2; B; UMULT 
TEXT "ABS_";	B=.; 2; A; ABS
TEXT "U.";	A=.; 1; B; UDOT
TEXT "SIGN";	B=.; 2; A; SIGN
TEXT "#S";	A=.; 1; B; FONUM
TEXT "FM/MOD";	B=.; 3; A; FMMOD
TEXT "HOLD";	A=.; 2; B; HOLD
TEXT "S>D_";	B=.; 2; A; TODBL
TEXT "<#";	A=.; 1; B; FOINIT
TEXT "#>";	B=.; 1; A; FODONE
TEXT "#_";	A=.; 1; B; FODIG
TEXT "LEAVE_";	B=.; 4003; A; GENLV 
TEXT "(L+)";	XLPPBO=.; 2; B; BOTLPP
TEXT "(LX)";	XLPXIT=.; 2; XLPPBO; LPXIT
TEXT "(LP)";	XLPBOT=.; 2; XLPXIT; BOTLP
TEXT "J_";	A=.; 1; B; LPJDX
TEXT "EXIT"; B=.; 4002; A; GENEX
TEXT \.6"_\; DQ6=.; 4002; B; DQUOT6
TEXT "FORGET"; B=.; 3; DQ6; FORGET
TEXT "INIT"; XINIT=.; 2002; B; .+1
	.ENABLE ASCII
	  XSTR; 7; TEXT "INIT.FS"; XLOAD; 0
	.ENABLE SIXBIT
TEXT "LOAD";	XLOAD=.; 2002; XINIT; .+1
	  XLIT; 0; XOPEN; XJMPF; ^D10
	  XSTR; 3; TEXT "NOINIT"; XTYP6
	  XDROP; XJMP; 2; XINCL; 0
TEXT "SPACES";	B=.; 3; XLOAD; SPACES
TEXT "DICT";	A=.; 2; B; SYSCON; DICT
TEXT "(OF)";	XOF=.; 2; A; DOOF
TEXT "ENDCASE_";A=.; 4004; XOF; GENEC
TEXT "ENDOF_";	B=.; 4003; A; GENEOF
TEXT "CASE";	A=.; 4002; B; GENCAS
TEXT "OF";	B=.; 4001; A; GENOF
TEXT "PICK";	A=.; 2; B; PICK
TEXT "ROLL";	B=.; 2; A; ROLL
TEXT "(PAR";	XPAR=.; 2; B; PARADR
TEXT ">BODY_";	XBODY=.; 3; XPAR; TOBODY
TEXT "FILL";	A=.; 2; XBODY; FILL
TEXT "0<>_";	B=.; 2; A; NEQZ
TEXT "+!";	A=.; 1; B; PSTORE
TEXT "WORD";	B=.; 2; A; WORD
TEXT "(DS)";	XDOES=.; 2; B; DODOES
TEXT "DOES>_";	B=.; 4003; XDOES; DOES
TEXT "CHAR";	A=.; 2; B; PSHCH
TEXT "[CHAR]";	B=.; 4003; A; CPSHCH
TEXT \ABORT"\; A=.; 4003; B; ABTQ
TEXT "PARSE_";	B=.; 3; A; PARSE
TEXT "POSTPONE";A=.; 4004; B; PSTPON
TEXT "2@";	B=.; 1; A; FETCH2
TEXT "2!";	A=.; 1; B; STORE2
TEXT "SOURCE-ID_"; B=.; 5; A; SYSCON; SRCID
TEXT "INCLUDE-FILE"; XINCL=.; 6; B; FILINC
TEXT "FLUSH-FILE"; B=.; 5; XINCL; FILFLU 
TEXT "CREATE-FILE_"; A=.; 6; B; FILCRE 
TEXT "SOURCE"; B=.; 3; A; SOURCE
TEXT "2/";	A=.; 1; B; TWODIV
TEXT "1-";	B=.; 1; A; MINUS1
TEXT "ALIGNED_";A=.; 4; B; IGNORE
TEXT "CHARS_";	B=.; 3; A; IGNORE
TEXT "[_";	A=.; 4001; B; INTNOW
TEXT "]_";	B=.; 1; A; CMPNOW
TEXT "INVERT";	A=.; 3; B; INVERT
TEXT "+LOOP_";	B=.; 4003; A; GPLOOP
TEXT "LSHIFT";	A=.; 3; B; LSHIFT
TEXT "RSHIFT";	B=.; 3; A; RSHIFT
TEXT "OPEN-FILE_"; XOPEN=.; 5; B; FILOPN
TEXT "CLOSE-FILE"; XCLOSE=.; 5; XOPEN; FILCLS
TEXT "READ-FILE_"; A=.; 5; XCLOSE; FILRD
TEXT "READ-LINE_"; B=.; 5; A; FILRDL
TEXT "WRITE-FILE"; A=.; 5; B; FILWR
TEXT "WRITE-LINE"; B=.; 5; A; FILWRL
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
TEXT "AGAIN_"; B=.; 4003; XJMPF; AGAIN
TEXT "*/"; A=.; 1; B; MULDIV
TEXT "[']_";	B=.; 4002; A; TICK
TEXT "BEGIN_";A=.; 4003; B; BEGIN
TEXT "UNTIL_"; B=.; 4003; A; UNTIL
TEXT "DO"; A=.; 4001; B; GENDO
TEXT "LOOP"; B=.; 4002; A; GLOOP
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
TEXT "ABORT_";	XABORT=.; 3; B; ABORT
TEXT "FIND";	B=.; 	2; XABORT; FIND
TEXT "SWAP";	XSWAP=.; 2; B; SWAP
TEXT "KEY_";	B=.; 	2; XSWAP; KEY
TEXT ";_";	A=.;	4001; B; SEMI
TEXT "BASE";	B=.; 2; A; SYSVAR; BASE
TEXT "ACCEPT";  A=.; 3; B; ACCEPT
TEXT "CREATE";	B=.; 3; A; CREATE
TEXT "ALLOT_";	A=.; 3; B; ALLOT
TEXT "AND_";	B=.;	2; A; ANDOP
TEXT "OR";	A=.;	1; B; OROP
TEXT "ROT_";	B=.;	2; A; ROT
TEXT "?DUP";	A=.;	2; B; QDUP
TEXT "PAD_";	B=.;	2; A; PAD
TEXT "/MOD";	A=.;	2; B; DIVMOD
TEXT "I_";	B=.; 1; A; LPIDX
TEXT "WHILE_";	A=.; 4003; B; WHILE
TEXT "CR";	XCR=.; 1; A; CRLF
TEXT "TYPE";	XTYPE=.; 2; XCR; TYPE
TEXT "BL";	B=.; 1; XTYPE; SYSCON; ASPACE
TEXT "WITHIN";A=.; 3; B; WITHIN
TEXT "DROP";	XDROP=.; 2; A; DROP
TEXT "2DROP_"; X2DROP=.; 3; XDROP; DROP2
TEXT "DECIMAL_"; A=.; 4; X2DROP; SET10
TEXT "OCTAL_";	 B=.; 3; A; SET8
TEXT "WORDS_";	A=.; 3; B; WORDS
TEXT "CELL";	B=.; 2; A; IGNORE
TEXT "CELL+_";	A=.; 3; B; IGNORE
TEXT "(QS)";	XSTR=.; 2; A; QUOTS / runtime "
TEXT "(DQS)_";	XTYPES=.; 3; XSTR; RDQUOT / runtime ."
TEXT "C,";	B=.; 1; XTYPES; COMMA
TEXT "(GEN)_"; XGENOP=.; 3; B; GENOP
TEXT "UM/MOD"; B=.; 3; XGENOP; UDIV
TEXT ">NUMBER_"; A=.; 4; B; GETNUM
TEXT "MOVE";	B=.; 2; A; MOVE
TEXT "CMOVE_";	A=.; 3; B; MOVE
TEXT "OVER";	B=.; 2; A; OVER
TEXT "._";	A=.; 1; B; DOT
TEXT "AVAIL_";	B=.; 3; A; AVAIL
TEXT ">IN_";	A=.; 2; B; SYSVAR; INOFF
TEXT "SWITCH";	B=.; 3; A; SWITCH
TEXT "NEGATE";	A=.; 3; B; NEGATE
TEXT \6"\;	B=.; 4001; A; QUOT6
TEXT "TYPE6_";	XTYP6=.; 3; B; TYPE6
TEXT \S"\;	B=.; 4001; XTYP6; SQUOT
TEXT \."\;	A=.; 4001; B; DQUOT
TEXT "SPACE_";	B=.; 3; A; SPACE
TEXT ".S";	A=.; 1; B; DOTS
TEXT "STATE_";	B=.; 3; A; SYSVAR; STATE
TEXT "*_";	A=.; 1; B; TIMES
TEXT "1+";	X1PLUS=.; 1; A; ONEP
TEXT "COUNT_";	A=.; 3; X1PLUS; COUNTS
TEXT ":_";	B=.; 1; A; COLON
TEXT "DUP_";  	XDUP=.; 2; B; DUP
TEXT "EXECUTE_";XCUTE=.; 4; XDUP; DOEXEC
TEXT "(LIT)_";	XLIT=.; 3; XCUTE; LITNUM
TEXT "HERE";	XHERE=.; 2; XLIT; SYSCON; HERE
// This must be the last entry.
TEXT "BYE_";	XBYE=.; 2; XHERE; BYE
	.LIST
	.GLOBAL DCTEND
DCTEND=.
