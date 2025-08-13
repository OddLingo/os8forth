	.TITLE	FPARSE - Filename parser.
	.VERSION 22
	.ENABLE	7BIT
/ ++
/	FPARSE Y2.1
/
/	(c) 1989, 1991 by Johnny Billquist
/
/	History:
/
/ 89/01/04 16:00 BQT X1.0. Split from STRLIB.
/ 89/12/27 05:00 BQT Y2.0. Made from PRSLIB.
/ 91/05/09 16:10 BQT Y2.1. Removed default device.
/ 25/08/10 15:41 PAD V2.2. Adapt for FORTH
/ --
	.ZSECT PRSCOM
	FIELD 2
	.GLOBAL SBDEV, SBFILE
T0,	0			/Tmp
T1,	0			/Tmp
T2,	0			/Tmp.
SRC,	0			/Source pointer.
DEST,	0			/Destination address.
COUNT,	0			/Loop count.
TL,	0
OFFSET,	0
TEMP,	ZBLOCK	14		/Tmp storage for filename.
SBDEV,	DEVICE DSK
SBFILE,	FILENAME INIT.FH	/ Parsed filename

	.RSECT	.FPARSE
	FIELD 2
/
/ FUNCTION: PARSE AN ASCII FILENAME INTO SIXBIT.
/
/ USAGE:
/ Source address in AC.  SIXBIT output to SBDEV,SBFILE.
	.ENTRY	$FPARSE
$FPARSE,0
	DCA	SRC		/Save as source pointer.
	TAD (SBDEV)
	DCA	DEST		/Save as dest. address.

	/ Zero out the temporary storage.
	TAD	(TEMP)		/Get pointer to tmp storage.
	DCA	T2		/Save it.
	TAD	(-14)		/Set loop to 14.
	DCA	COUNT
1$:	DCA I	T2		/Clear tmp storage.
	ISZ	T2		/Bump pointer.
	ISZ	COUNT		/Bump count.
	JMP	1$		/Repeat.

	JMS	GETDEV		/Get device values.
	JMP	NODEV		/No device found.
	TAD	(TEMP)		/Found. Set destination to tmp.
	DCA	T1
	JMS	COPY		/Copy device T0->T1
	TAD	(-6)		/Total length is 6.
	DCA	TL
	TAD	(TEMP)		/Offset to start.
	DCA	OFFSET

DONAME,	JMS	GETNAM		/Get file name.
	JMP	EXT$		/No filename found. Pack result.
	TAD	(TEMP+4)	/Found. Set destination to tmp.
	DCA	T1
	JMS	COPY		/Copy filename T0->T1

EXT$:	JMS	GETEXT		/Get extension.
	JMP	PACK$		/Not found. Pack result.
	TAD	(TEMP+12)	/Found. Set destination to tmp.
	DCA	T1
	JMS	COPY		/Copy extension T0->T1

// Pack TEMP to DEST
PACK$:	CLA
	TAD	OFFSET		/Time to pack... Set source to tmp.
	DCA	T2
	TAD	TL		/Set count to 6 words.
	DCA	COUNT
LOOP$:	TAD I	T2		/Get char.
	ISZ	T2		/Bump source pointer.
	AND	(77)		/Make SIXBIT.
	BSW			/High char.
	DCA	T1		/Save it temporarily.
	TAD I	T2		/Get next char.
	ISZ	T2		/Bump source pointer.
	AND	(77)		/Make SIXBIT.
	TAD	T1		/Combine with first char.
	DCA I	DEST		/Save word.
	ISZ	DEST		/Bump destination pointer.
	ISZ	COUNT		/Bump count.
	JMP	LOOP$		/Repeat.
	JMP I	$FPARSE		/Return.

GETEXT,	0			/Get extension.
	TAD	SRC		/Get source pointer.
	DCA	T0		/Save it in tmp.
	JMS	GETCHR		/Get char.
	SNA CLA			/Was it NUL?
	JMP I	GETEXT		/Yes. No extension.
	ISZ	SRC		/No. Bump source pointer.
	JMS	LOOK		/Search for NUL.
	TAD	(-1)		/Decr. length of string.
	SNA			/Empty string?
	JMP I	GETEXT		/Yes. No extension.
	TAD	(2)		/Limit length to 2.
	SPA
	CLA
	TAD	(-2)
	DCA	COUNT		/Save as loop count.
	TAD	SRC		/Get source pointer.
	DCA	T0		/Save as from tmp.
	ISZ	GETEXT		/Bump return.
	JMP I	GETEXT		/Return.

	PAGE

// Copy from T0 to T1
COPY,	0			/Copy routine.
1$:	JMS	GETCHR		/Get char.
	TAD	(-140)		/Convert to uppercase...
	SMA
	TAD	(-40)
	TAD	(140)
	DCA I	T1		/Save it.
	ISZ	T1		/Bump pointer.
	ISZ	COUNT		/Bump count.
	JMP	1$		/Repeat.
	JMP I	COPY		/Return.

GETCHR,	0
	TAD I	T0		/Get char.
	ISZ	T0		/Bump pointer.
	JMP I	GETCHR		/Return.

GETDEV,	0			/Get device.
	TAD	(":)		/Search for device separator.
	JMS	LOOK
	TAD	(-1)		/Decr. string length.
	SNA			/Only ":" found?
	ISZ	SRC		/Yes. Skip it. Use default device.
	SNA SPA			/Separator found and length>0?
	JMP I	GETDEV		/No. Dev not found. Return.
	TAD	(-4)		/Limit length to 4.
	SMA
	CLA
	TAD	(4)
	CIA
	DCA	COUNT		/Save as loop count.
	TAD	SRC		/Get source pointer.
	DCA	T1		/Save it tmp.
	TAD	T0		/Get ptr to filename.
	DCA	SRC		/Save it as new source pointer.
	TAD	T1		/Get old source pointer.
	DCA	T0		/Save for copy.
	ISZ	GETDEV		/Bump return.
	JMP I	GETDEV		/Return.

NODEV,	CLA
	TAD	(-4)		/No device found. Copy only filename at end.
	DCA	TL
	TAD	(TEMP+4)
	DCA	OFFSET
	IAC RAL CLL
	TAD	DEST
	DCA	DEST
	JMP	DONAME

LOOK,	0			/Search for char or EOS.
	CIA			/Make compare out of char.
	DCA	T1		/Save compare.
	TAD	SRC		/Get source pointer.
	DCA	T0		/Save as tmp pointer.
	DCA	COUNT		/Clear count.
1$:	ISZ	COUNT		/Bump count.
	JMS	GETCHR		/Get char.
	SNA			/EOS?
	JMP	2$		/Yes.
	TAD	T1		/Compare.
	SZA CLA			/Equals?
	JMP	1$		/No. Repeat.
	TAD	COUNT		/Yes. Get count.
	JMP I	LOOK		/Return.
2$:	TAD	COUNT		/EOS. Get count.
	CIA			/Negate.
	JMP I	LOOK		/And return.

GETNAM,	0			/Get file name.
	TAD	(".)		/Look out for extension separator.
	JMS	LOOK
	SMA			/If positive, make negative.
	CIA
	IAC			/Decr. length by one.
	SNA			/Zero length?
	JMP I	GETNAM		/Yes. Return. No filename.
	TAD	(6)		/Limit length to 6.
	SPA
	CLA
	TAD	(-6)
	DCA	COUNT		/Save as loop count.
	TAD	SRC		/Get source pointer.
	DCA	T1		/Save tmp.
	CMA			/Get extension separator pointer.
	TAD	T0
	DCA	SRC		/Save as new source pointer.
	TAD	T1		/Get old source pointer.
	DCA	T0		/Save as from pointer for copy.
	ISZ	GETNAM		/Bump return.
	JMP I	GETNAM		/Return.
