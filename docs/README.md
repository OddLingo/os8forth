# FORTH for OS/8
This is an interpreter/compiler for the FORTH language that runs under the OS/8 monitor on simulated (or real!) Digital Equipment Corporation PDP-8 computers.

## Minimum hardware and software
* Extended Arithmetic Element (EAE)
* 12 KW memory
* Console TTY
* OS/8 version 3
* MACREL assembler, version 2

## Memory Layout
* Field 0 (locations 00000 to 07777) contains all of the executable machine code, including OS/8 device handlers.
* Field 1 (locations 10000 to 17777) contains the dictionary and both stacks.
* Field 2 (locations 20000 and above) is used for I/O buffers.
* Most of Field 2 and any memory above that is available to the FORTH programmer by way of some special words.

## FORTH issues
* The CELL size is one 12-bit value
* The 'character' words (C@, C!, C,) also operate on words
* The Data and Return stacks have 128 words each.  There is no protection against under- or overflow.

### Custom words
The following FORTH words are extensions to the FORTH Standard to gain access to unique features of the PDP-8 hardware.

* **X@** ( addr fnum -- n ) *Extended Fetch*, Fetches one word at the specified address in the specified memory field.  For example, `200 2 X@` will put the contents of location `20200` on the stack.  Field numbers must be in the range 0 to 7.
* **X!** ( n addr fnum -- ) *Extended Store*, Stores n at the specified address in the specified field.  Modifying locations in fields 0 and 1 is not advised.

## Building
The MACREL/LINK relocatable assembler and linker are used.

       MAC FORTH.RB,FORTH.LS<FORTH.MA/Q/S/X=120
       LINK FORTH.SV,FORTH.MP<FORTH.RB/K=3/9
