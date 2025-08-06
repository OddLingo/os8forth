	.TITLE	PUTAC - Output AC as fout octal digits.
	.VERSIO	20
/ ++
/
/	PUTAC Y2.0
/
/	(c) 1989 by Johnny Billquist
/
/	All rights reserved.
/
/	PUTAC is a library for standard IO.
/
/	History:
/
/	89/01/04 09:05	BQT	Y1.0. Separated code from IOLIB.
/	89/12/01 20:00	BQT	Y1.1. Made functions into FSECT.
/	89/12/27 05:00	BQT	Y2.0. Made from STDIO.
/
/ --
/
	.EXTERNAL	PUT
	.FSECT	PUTAC
/
/ PUTAC outputs AC as four octal numbers on TTY.
/
	0			/Return address.
	DCA	NUM$		/Save number.
	RDF			/Get return field.
	TAD	(CDF CIF)
	DCA	R$
	CDF	.FLD		/Change to current field.
	TAD	(-4)		/Loop four times.
	DCA	LC$
1$:	TAD	NUM$		/Get number.
	RTL;RAL			/Shift one digit left
	DCA	NUM$		/and save.
	TAD	NUM$
	RAL			/Shift last bit of high digit into low.
	AND	(7)		/Mask out low digit.
	TAD	(60)		/ASCIIfy.
	JMS	PUT		/Output number.
	ISZ	LC$		/Bump digit count.
	JMP	1$		/Repeat.
R$:	HLT			/Done. Change to return field.
	JMP I	PUTAC		/Return.

NUM$:	0			/Number to output.
LC$:	0			/Digit count.
/
$
