	.TITLE	PUT - Put one char on TTY.
	.VERSIO	20
/ ++
/
/	PUT Y2.0
/
/	(c) 1989 by Johnny Billquist
/
/	All rights reserved.
/
/	PUT is a library for standard IO.
/
/	History:
/
/	89/01/04 09:05	BQT	Y1.0. Separated code from IOLIB.
/	89/12/01 20:00	BQT	Y1.1. Made functions into FSECT.
/	89/12/27 05:00	BQT	Y2.0. Made from STDIO.
/
/ --
/
	.FSECT	PUT
/
/ Put outputs one char on TTY.
/
	0			/Return address.
	TLS			/Output char.
	TSF			/Wait until ready.
	JMP	.-1
	CLA			/Clear AC.
	RDF			/Get return field.
	TAD	(CDF CIF)
	DCA	.+1
	HLT			/Do return change.
	JMP I	PUT		/Return.
/
$
