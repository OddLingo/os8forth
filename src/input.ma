	.TITLE	INPUT - Input a string.
	.VERSIO	21
/ ++
/
/	INPUT Y2.1
/
/	(c) 1988, 1989, 1990 by Johnny Billquist
/
/	All rights reserved.
/
/	INPUT is a library routine.
/
/	History:
/
/	88/10/30 17:50	BQT	Initial coding.
/	88/12/28 17:30	BQT	Y1.2. Added INPUT.
/	89/01/04 09:05	BQT	Y1.3. Separated IOLIB and STDIO.
/	89/12/01 20:00	BQT	Y1.4. Made functions FSECT.
/	89/12/27 05:00	BQT	Y2.0. Made from IOLIB.
/	90/03/13 02:00	BQT	Y2.1. Added ^U.
/
/ --
	.EXTERNAL	GET,PUT
/
	.FSECT	.INPUT
/
/ INPUT reads a string, terminated by a CR, and puts in at arg1.
/ Arg2 tell maximum length of string. Padded by a NUL in memory.
/
	.ENTRY	$INPUT
/
$INPUT,	0			/For return address.
	CLA			/Get arg1.
	TAD I	$INPUT
	ISZ	$INPUT
	DCA	P$		/Save as pointer.
	TAD I	$INPUT		/Get arg2.
	ISZ	$INPUT
	DCA	ML$		/Save as max length.
	DCA	CL$		/Clear current length.
	RDF			/Get return field.
	TAD	(CDF CIF)
	DCA	R$
	RDF			/Get data field.
	TAD	(CDF)
	DCA	C$
	CDF	.FLD		/Change to current field.
MAIN$:	CIF	GET		/Get character.
	JMS	GET
	AND	(177)		/Mask away high bit.
	DCA	T$		/Save char.
	TAD	T$
	TAD	(-40)		/Check if control char.
	SPA
	JMP	CTRL$		/It was.
	TAD	(40-177)	/Check if rub out.
	SNA
	JMP	RUB$		/It was.
	TAD	(177)		/Normalize.
	CLA CMA			/Decrement max length.
	TAD	ML$
	SPA			/Have we exceeded max length?
	JMP	MAIN$		/Yes.
	DCA	ML$		/No, save new max length.
	TAD	T$		/Save char in buffer.
	JMS	DEP$
	TAD	T$		/Echo char on TTY.
	CIF	PUT
	JMS	PUT
	ISZ	P$		/Bump pointer.
	ISZ	CL$		/Increment current length.
	JMP	MAIN$		/Repeat.

RUB$:	JMS	R2$
	JMP	MAIN$		/Repeat.

CTRL$:	TAD	(40-15)		/Control. Check if CR.
	SNA
	JMP	CR$		/It was.
	TAD	(15-33)		/ESC?
	SNA
	JMP	ESC$
	IAC			/^Z
	SNA
	JMP	NOPE$
	TAD	(32-3)		/^C
	SNA
	JMP	NOPE$
	TAD	(3-25		/^U
	SNA
	JMP	CU$
	JMP	MAIN$		/Was not. Repeat.

ESC$:	TAD	("$)		/Echo $.
	SKP
CR$:	TAD	(15)		/Echo CR.
	CIF	PUT
	JMS	PUT
NOPE$:	JMS	DEP$		/CR. Pad buffer with NUL.
	TAD	CL$		/Get current length.
	MQL
	CLA
	TAD	T$		/Char.
R$:	HLT			/Return field.
	JMP I	$INPUT		/Return.

DEP$:	0			/Deposit char in buffer routine.
C$:	HLT			/Change to data field.
	DCA I	P$		/Save char.
	CDF	.FLD		/Change to current field.
	JMP I	DEP$		/Return.

CU$:	JMS	R2$
	TAD	CL$
	SZA CLA
	JMP	CU$
	JMP	MAIN$

T$:	0			/Tmp storage.
P$:	0			/Pointer.
ML$:	0			/Max length.
CL$:	0			/Current length.
/
R2$:	0
	CMA			/Rub out. Decrement current length.
	TAD	CL$
	SPA			/Not any char in buffer?
	JMP I	R2$		/Nope. Return.
	DCA	CL$		/Yep. Save new current length.
	TAD	(10		/BS
	CIF	PUT
	JMS	PUT
	TAD	(40		/SP
	CIF	PUT
	JMS	PUT
	TAD	(10		/BS
	CIF	PUT
	JMS	PUT
	CMA			/Decrement pointer.
	TAD	P$
	DCA	P$
	ISZ	ML$		/Increment max length.
	JMP I	R2$
