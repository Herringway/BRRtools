module common;
import core.stdc.stdlib;
import core.stdc.stdio;

//#ifndef SKIP_SAFE_MALLOC
void *safe_malloc(const size_t s)
{
	void *p = malloc(s);
	if(!p)
	{
		fprintf(stderr, "Can't allocate enough memory.\n");
		exit(1);
	}
	return p;
}
//#else
//void *safe_malloc(const size_t s);
//#endif

enum PI = 3.14159265;

//#define MAX(a, b) ((a)>(b) ? (a) : (b))

alias pcm_t = short;
alias u8 = ubyte;
alias u16 = ushort;
alias u32 = uint;
