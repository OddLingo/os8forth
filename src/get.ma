	.TITLE	GET - Get a character.
	.VERSIO	20
/ ++
/
/	GET Y2.0
/
/	(c) 1989 by Johnny Billquist
/
/	All rights reserved.
/
/	GET is a library for standard IO.
/
/	History:
/
/	89/01/04 09:05	BQT	Y1.0. Separated code from IOLIB.
/	89/12/01 20:00	BQT	Y1.1. Made functions into FSECT.
/	89/12/27 05:00	BQT	Y2.0. Made from STDIO.
/
/ --
/
	.FSECT	GET
/
/ GET reads one char from TTY and returns with it in AC.
/
	0			/For return address.
	CLA			/Get return field.
	RDF
	TAD	(CDF CIF)
	DCA	R$
	KSF			/Wait for incoming char.
	JMP	.-1
	KRB			/Read char.
R$:	HLT			/Return to field.
	JMP I	GET		/Return.
/
$
