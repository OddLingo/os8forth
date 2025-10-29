#include <stdio.h>

int main()
{
  int ch;
  while (ch = getchar() )
    {
      ch = ch & 0177;
      if (ch==0) break;
      if (ch==0032) break;
      if (ch==0177) break;
      if (ch != 13)  putchar( ch );
    }
}
