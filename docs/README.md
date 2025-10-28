# FORTH for OS/8
This is an interpreter/compiler for the FORTH language that runs under the OS/8 monitor on simulated (or real!) Digital Equipment Corporation PDP-8 computers.  By modern standards, the PDP-8 had extremely limited resources so do not expect a full-featured FORTH with multi-tasking, etc.  However, it can read and write text files.

## Minimum hardware and software
* PDP-8/e or later processor.  The pdp8 simulator in the [OpenSIMH](https://opensimh.org/) package works fine.
* Extended Arithmetic Element (EAE)
* 12 KW memory
* Console TTY
* OS/8 version 3
* MACREL assembler, version 2

## Memory Layout

* Field 0 (locations 00000 to 07777) contains the executable machine code for the FORTH engine, plus OS/8 device handlers.
* Field 1 (locations 10000 to 17777) contains the dictionary and stacks.
* Field 2 (locations 20000 and above) is used for I/O buffers and OS/8 file system interfaces.
* Most of Field 2 and all fields above that are available to the FORTH programmer by way of some special words.

## PDP-8 Idiosyncrasies
* The CELL size is one 12-bit value

* The 'character' words (C@, C!, C,) also operate on 12-bit words

* The Data stack is 128 words and the Return stack is 64 words.  There is no protection against under- or overflow.

* Although it is is enticing to use all 32K words for the dictionary, this would require the use of double word addresses *everywhere* and since the FORTH environment is heavily built out of pointers, this would make the dictionary twice as big just to start, and the runtime engine code would be larger as well.  So the dictionary has to fit in 4096 words although the programmer can access the higher memory fields (see **Custom Words** below.)

* The maximum size of a file on OS/8 is 4096 blocks of 256 words. The standard format for text files packs 3 ASCII characters into two words which makes the maximum file size 1,572,864 characters.  This means that file positions as reported by `FILE-POSITION` and consumed by `REPOSITION-FILE` have to be doublewords.

* Turning on bit 0 of the switch register will cause the names of words to be printed on the console as they are executed.

* At startup the interpreter looks for a text file named `DSK:INIT.FS` and executes the contents if found.

## Dictionary
### Standard words

      ! # #> ' * */ + +! , - . ." / : ; < <# <= <> = > >= @
      [ ['] ] 0< 0<> 0= 0= 0> 1+ 1- 2! 2/ 2@ 2DROP .6" 6"
      ABORT ABORT" ACCEPT AGAIN ALIGNED ALLOT AND AVAIL BASE
      BEGIN BL >BODY BYE C! C, C@ CASE CELL CELL+ [CHAR]
      CHAR CHARS CLOSE-FILE CMOVE CONSTANT COUNT CR CREATE
      CREATE-FILE DECIMAL DEPTH DICT DO DOES> DONE DROP
      ?DUP DUP ELSE EMIT ENDCASE ENDOF EXECUTE EXIT FILL FIND
      FLUSH-FILE FM/MOD FORGET HERE HOLD I IF IMMEDIATE >IN
      INCLUDE-FILE INIT INVERT J KEY LEAVE LOAD +LOOP LOOP
      LSHIFT /MOD MOVE NEGATE >NUMBER OCTAL OF OPEN-FILE
      OR OVER PAD PARSE PICK POSTPONE >R R! R> R@ READ-FILE
      READ-LINE R/O ROLL ROT RSHIFT R/W #S .S S" S>D SOURCE-ID
      SPACE SPACES STATE SWAP SWITCH THEN TIB TYPE TYPE6
      UNTIL VARIABLE WITHIN WORD WORDS WRITE-FILE WRITE-LINE
      X! X@

### Custom words
The following FORTH words are extensions to the FORTH Standard to gain access to unique features of the PDP-8 hardware.

* **X@** ( addr fnum -- u ) *Extended Fetch*, Fetches one word at the specified address in the specified memory field.  For example, `OCTAL 300 2 X@` will put the contents of location `20300` on the stack.  Field numbers must be in the range 0 to 7.

* **X!** ( n addr fnum -- ) *Extended Store*, Stores n at the specified address in the specified field.  Modifying locations in all of field 0 and 1, and the lower half of field 2, is not advised.

* **SWITCH** ( -- u ) puts the PDP-8 front panel switch settings on the stack.

* **6"** Works like `S"` but codes the string in SIXBIT, using half the memory but converting to uppercase.

* **TYPE6** ( addr len -- ) Same as `TYPE` but takes a SIXBIT string.  The *length* is in words, not characters.

* **.6"** Similar to `."` but uses SIXBIT storage.

* **.8** Prints numeric value on stack as unsigned octal in 4 digits regardless of current BASE. Useful for debugging.

## Building
The MACREL/LINK relocatable assembler and linker are used.  A BATCH file `FORTH.BI` is provided that puts everything together.

1. Copy the `FORTH.BI` file to `SYS:`
2. `.SUBMIT SYS:FORTH/T`

This will create `SYS:FORTH.SV` as well as the linker map `FORTH.MP` and various `.LS` files.  The interpreter can then be executed by:

        .R FORTH

## Useful code samples
Due to space constraints, many useful non-core words have not been implemented, but they are easily added if you need them.  Just put the definitions into the `INIT.FS` file.

### Dumping memory
This dumps a range of words in memory field 1, which is the dictionary and stack.  This is useful while debugging.

      : DUMP ( addr len -- )
          BASE @ >R OCTAL
          SWAP DUP ROT + SWAP DO
          I .8 I 1 X@ .8 CR LOOP
          R> BASE ! ;

### Right justified numbers
Print an unsigned value u1 right-justified in u2 spaces.  This is useful for generating tabular reports.

      : U.R ( u1 u2 -- )
        >R 0 <# #S #> DUP R> SWAP - SPACES TYPE ;


