# FORTH for OS/8
This is an interpreter/compiler for the FORTH language that runs under the OS/8 monitor on simulated (or real!) Digital Equipment Corporation PDP-8 computers.  By modern standards, the PDP-8 had extremely limited resources so do not expect a full-featured FORTH with multi-tasking, etc.  However, it can read and write text files.

## Minimum hardware and software
* PDP-8/e or later processor
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

* The Data and Return stacks have 128 words each.  There is no protection against under- or overflow.

* Although it is is enticing to use all 32K words for the dictionary, this would require the use of double word addresses *everywhere* and since the FORTH environment is heavily built out of pointers, this would make the dictionary twice as big just to start, and the runtime engine code would be larger as well.  So the dictionary has to fit in 4096 words although the programmer can access the higher memory fields (see **Custom Words** below.)

* The maximum size of a file on OS/8 is 4096 blocks of 256 words. The standard format for text files packs 3 ASCII characters into two words which makes the maximum file size 1,572,864 characters.  This means that file positions as reported by FILE-POSITION and consumed by REPOSITION-FILE have to be doublewords.

* Turning on bit 0 of the switch register will cause the names of words to be printed on the console as they are executed.

* At startup the interpreter looks for a text file named **INIT.FS** and executes the contents if found.

### Custom words
The following FORTH words are extensions to the FORTH Standard to gain access to unique features of the PDP-8 hardware.

* **X@** ( addr fnum -- n ) *Extended Fetch*, Fetches one word at the specified address in the specified memory field.  For example, `OCTAL 300 2 X@` will put the contents of location `20300` on the stack.  Field numbers must be in the range 0 to 7.

* **X!** ( n addr fnum -- ) *Extended Store*, Stores n at the specified address in the specified field.  Modifying locations in all of field 0 and 1, and the lower half of field 2, is not advised.

* **SWITCH** ( -- n ) puts the PDP-8 switch settings on the stack.

* **6"** Works like `S"` but codes the string in SIXBIT, using half the memory but converting to uppercase.

* **TYPE6** ( addr len -- ) Same as `TYPE` but takes a SIXBIT string.  The *length* is in words, not characters.

* **.6"** Similar to `."` but uses SIXBIT storage. 

## Building
The MACREL/LINK relocatable assembler and linker are used.  A BATCH file FORTH.BI is provided that puts everything together.
