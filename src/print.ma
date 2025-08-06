	.TITLE	PRINT - Output a string.
	.VERSIO	21
/ ++
/
/	PRINT Y2.1
/
/	(c) 1988, 1989, 1990 by Johnny Billquist
/
/	All rights reserved.
/
/	PRINT is a library routine.
/
/	History:
/
/	88/10/30 17:50	BQT	Initial coding.
/	88/12/28 17:30	BQT	Y1.2. Added INPUT.
/	89/01/04 09:05	BQT	Y1.3. Separated IOLIB and STDIO.
/	89/12/01 20:00	BQT	Y1.4. Made functions FSECT.
/	89/12/27 05:00	BQT	Y2.0. Made from IOLIB.
/	90/03/13 02:30	BQT	Y2.1. Modified symbol names.
/
/ --
	.EXTERNAL	PUT
/
	.FSECT	.PRINT
/
/ PRINT outputs a string on TTY, terminated by a NUL.
/
	.ENTRY	$PRINT
/
$PRINT,	0			/For return address.
	CLA
	TAD I	$PRINT		/Get arg1.
	ISZ	$PRINT
	DCA	P$		/Save as pointer.
	TAD I	$PRINT		/Get arg2.
	ISZ	$PRINT
	TAD	(CDF)
	DCA	C$		/Save as data field.
	RDF			/Get return field.
	TAD	(CDF CIF)
	DCA	R$
C$:	HLT			/Change to data field.
	TAD I	P$		/Get char.
	CDF	.FLD		/Change to current field.
	SNA			/NUL?
	JMP	R$		/Yes. String done.
	CIF	PUT		/Output char.
	JMS	PUT
	ISZ	P$		/Bump pointer.
	JMP	C$		/Repeat.
R$:	HLT			/Return field.
	JMP I	$PRINT		/Return.

P$:	0			/Pointer.
/
$
