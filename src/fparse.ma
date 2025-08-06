	.TITLE	FPARSE - Filename parser.
	.VERSION 21
	.ENABLE	7BIT
/ ++
/	FPARSE Y2.1
/
/	(c) 1989, 1991 by Johnny Billquist
/
/	History:
/
/	89/01/04 16:00	BQT	X1.0. Split from STRLIB.
/	89/12/27 05:00	BQT	Y2.0. Made from PRSLIB.
/	91/05/09 16:10	BQT	Y2.1. Removed default device.
/
/ --
	.RSECT	.FPARSE
/
/ FUNCTION: PARSE AN ASCII FILENAME INTO SIXBIT.
/
/ USAGE:
/	JMS	FPARSE
/	SRCSTR				SOURCE STRING POINTER.
/	DSTADR				DESTINATION ADDRESS.
/
	.ENTRY	$FPARSE
$FPARSE,
	0			/For return address.
	CLA
	TAD I	$FPARSE		/Get arg1.
	ISZ	$FPARSE
	DCA	SP		/Save as source pointer.
	TAD I	$FPARSE		/Get arg2.
	ISZ	$FPARSE
	DCA	DA		/Save as dest. address.
	RDF			/Get return field.
	TAD	(CDF CIF)
	DCA	R
	RDF			/Get data field.
	TAD	(CDF)
	DCA	C2
	CDF	.		/Change to current field.
	TAD	C2
	DCA	C1

	TAD	(ST)		/Get pointer to tmp storage.
	DCA	T2		/Save it.
	TAD	(-14)		/Set loop to 14.
	DCA	LC
1$:	DCA I	T2		/Clear tmp storage.
	ISZ	T2		/Bump pointer.
	ISZ	LC		/Bump count.
	JMP	1$		/Repeat.

	JMS	GDEV		/Get device values.
	JMP	NODEV		/No device found.
	TAD	(ST)		/Found. Set destination to tmp.
	DCA	T1
	JMS	COPY		/Copy device.
	TAD	(-6)		/Total length is 6.
	DCA	TL
	TAD	(ST)		/Offset to start.
	DCA	OFF

NAM,	JMS	GNAM		/Get file name.
	JMP	EXT$		/No filename found. Pack result.
	TAD	(ST+4)		/Found. Set destination to tmp.
	DCA	T1
	JMS	COPY		/Copy filename.

EXT$:	JMS	GEXT		/Get extension.
	JMP	PACK$		/Not found. Pack result.
	TAD	(ST+12)		/Found. Set destination to tmp.
	DCA	T1
	JMS	COPY		/Copy.

PACK$:	CLA
	TAD	OFF		/Time to pack... Set source to tmp.
	DCA	T2
	TAD	TL		/Set count to 6 words.
	DCA	LC
LOOP,	TAD I	T2		/Get char.
	ISZ	T2		/Bump pointer.
	AND	(77)		/Make SIXBIT.
	BSW			/High char.
	DCA	T1		/Save it temporarily.
	TAD I	T2		/Get next char.
	ISZ	T2		/Bump pointer.
	AND	(77)		/Make SIXBIT.
	TAD	T1		/Combine with 1:st char.
C2,	HLT			/Change to data field.
	DCA I	DA		/Save word.
	ISZ	DA		/Bump pointer.
	CDF	.		/Change to current field.
	ISZ	LC		/Bump count.
	JMP	LOOP		/Repeat.
R,	HLT			/Return field.
	JMP I	$FPARSE		/Return.
/
GEXT,	0			/Get extension.
	TAD	SP		/Get source pointer.
	DCA	T0		/Save it in tmp.
	JMS	GCHR		/Get char.
	SNA CLA			/Was it NUL?
	JMP I	GEXT		/Yes. No extension.
	ISZ	SP		/No. Bump source pointer.
	JMS	LOOK		/Search for NUL.
	TAD	(-1)		/Decr. length of string.
	SNA			/Empty string?
	JMP I	GEXT		/Yes. No extension.
	TAD	(2)		/Limit length to 2.
	SPA
	CLA
	TAD	(-2)
	DCA	LC		/Save as loop count.
	TAD	SP		/Get source pointer.
	DCA	T0		/Save as from tmp.
	ISZ	GEXT		/Bump return.
	JMP I	GEXT		/Return.
/
T2,	0			/Tmp.
SP,	0			/Source pointer.
DA,	0			/Destination address.
LC,	0			/Loop count.
TL,	0
OFF,	0
ST,	ZBLOCK	14		/Tmp storage for filename.
/
	PAGE
/
COPY,	0			/Copy routine.
1$:	JMS	GCHR		/Get char.
	TAD	(-140)		/Convert to uppercase...
	SMA
	TAD	(-40)
	TAD	(140)
	DCA I	T1		/Save it.
	ISZ	T1		/Bump pointer.
	ISZ	LC		/Bump count.
	JMP	1$		/Repeat.
	JMP I	COPY		/Return.

GCHR,	0			/Get char.
C1,	HLT			/Change to data field.
	TAD I	T0		/Get char.
	ISZ	T0		/Bump pointer.
	CDF	.FLD		/Change to current field.
	JMP I	GCHR		/Return.

GDEV,	0			/Get device.
	TAD	(":)		/Search for device separator.
	JMS	LOOK
	TAD	(-1)		/Decr. string length.
	SNA			/Only ":" found?
	ISZ	SP		/Yes. Skip it. Use default device.
	SNA SPA			/Separator found and length>0?
	JMP I	GDEV		/No. Dev not found. Return.
	TAD	(-4)		/Limit length to 4.
	SMA
	CLA
	TAD	(4)
	CIA
	DCA	LC		/Save as loop count.
	TAD	SP		/Get source pointer.
	DCA	T1		/Save it tmp.
	TAD	T0		/Get ptr to filename.
	DCA	SP		/Save it as new source pointer.
	TAD	T1		/Get old source pointer.
	DCA	T0		/Save for copy.
	ISZ	GDEV		/Bump return.
	JMP I	GDEV		/Return.

NODEV,	CLA
	TAD	(-4)		/No device found. Copy only filename at end.
	DCA	TL
	TAD	(ST+4)
	DCA	OFF
	IAC RAL CLL
	TAD	DA
	DCA	DA
	JMP	NAM

LOOK,	0			/Search for char or EOS.
	CIA			/Make compare out of char.
	DCA	T1		/Save compare.
	TAD	SP		/Get source pointer.
	DCA	T0		/Save as tmp pointer.
	DCA	LC		/Clear count.
1$:	ISZ	LC		/Bump count.
	JMS	GCHR		/Get char.
	SNA			/EOS?
	JMP	2$		/Yes.
	TAD	T1		/Compare.
	SZA CLA			/Equals?
	JMP	1$		/No. Repeat.
	TAD	LC		/Yes. Get count.
	JMP I	LOOK		/Return.
2$:	TAD	LC		/EOS. Get count.
	CIA			/Negate.
	JMP I	LOOK		/And return.

GNAM,	0			/Get file name.
	TAD	(".)		/Look out for extension separator.
	JMS	LOOK
	SMA			/If positive, make negative.
	CIA
	IAC			/Decr. length by one.
	SNA			/Zero length?
	JMP I	GNAM		/Yes. Return. No filename.
	TAD	(6)		/Limit length to 6.
	SPA
	CLA
	TAD	(-6)
	DCA	LC		/Save as loop count.
	TAD	SP		/Get source pointer.
	DCA	T1		/Save tmp.
	CMA			/Get extension separator pointer.
	TAD	T0
	DCA	SP		/Save as new source pointer.
	TAD	T1		/Get old source pointer.
	DCA	T0		/Save as from pointer for copy.
	ISZ	GNAM		/Bump return.
	JMP I	GNAM		/Return.

T0,	0			/Tmp
T1,	0			/Tmp

