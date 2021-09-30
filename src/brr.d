import core.stdc.stdio;
import core.stdc.math;
import common;


// Global variables
u8[9] BRR;
pcm_t p1, p2;

void print_note_info(const uint loopsize, const uint samplerate)
{
	static immutable char[3][12] notes = ["C ", "C#", "D ", "Eb", "E ", "F ", "F#", "G ", "G#", "A ", "Bb", "B "];

	if(loopsize < 45)
	{
		double frequency = cast(double)samplerate / cast(double)(16*loopsize);
		double note = 12.0 * log2(frequency / 440.0) - 3.0;
		int octave = 5;
		// Makes sure the note is in the [-0.5 .. 11.5[ range
		while(note < -0.5)
		{
			note += 12.0;
			octave -= 1;
		}
		while(note >= 11.5)
		{
			note -= 12.0;
			octave += 1;
		}
		double inote = round(note);
		int cents = cast(int)((note - inote) * 100.0);

		printf(" (probable note : %s%d %+d cents)\n", notes[cast(int)inote].ptr, octave, cents);
	}
	else
		printf("\n");
}

void print_loop_info(uint loopcount, pcm_t[] oldp1, pcm_t[] oldp2)
{
	if(loopcount > 1)
	{
		if((oldp1[0]==oldp1[1]) && (oldp2[0]==oldp2[1]))
			printf("Looping is stable.\n");
		else
		{
			printf("Looping is unstable, ");
			int i, j=0;
			for (i=0; i<loopcount-1; ++i)
			{
				for (j=i+1; j<loopcount; ++j)
				{
					if (oldp1[i]==oldp1[j]&&oldp2[i]==oldp2[j]) break;
				}
				if (j<loopcount) break;
			}
			if (i<loopcount-1)
				printf("samples repeat from loop %d to loop %d.\n", j, i);
			else
				printf("try a larger number of loops to figure the length until the sample repeats.\n");
		}
	}
}

void generate_wave_file(FILE *outwav, uint samplerate, pcm_t *buffer, size_t k)
{
	struct Wave
	{
		char[4] chunk_ID;				// Should be 'RIFF'
		u32 chunk_size;
		char[4] wave_str;				// Should be 'WAVE'
		char[4] sc1_id;					// Should be 'fmt '
		u32 sc1size;					// Should be at least 16
		u16 audio_format;				// Should be 1 for PCM
		u16 chans;						// 1 for mono, 2 for stereo, etc...
		u32 sample_rate;
		u32 byte_rate;
		u16 block_align;
		u16 bits_per_sample;
		char[4] sc2_id;
		u32 sc2size;
	}
	Wave hdr =
	{
		chunk_ID: "RIFF",
		chunk_size: cast(uint)(32*k + 36),
		wave_str: "WAVE",
		sc1_id: "fmt ",
		sc1size: 16,				//Size of header
		audio_format: 1,			//PCM format, no compression
		chans: 1,					//Mono
		sample_rate: samplerate,	//Sample rate
		byte_rate: 2*samplerate,	//Byte rate
		block_align: 2,			//BlockAlign
		bits_per_sample: 16,		//16-bit samples
		sc2_id: "data",
		sc2size: cast(uint)(32*k)
	};
	fwrite(&hdr, 1, hdr.sizeof, outwav);	// Write header
	fwrite(buffer, 2, 16*k, outwav); 		//write samplebuffer to file
}

int get_brr_prediction(u8 filter, pcm_t p1, pcm_t p2)
{
	int p;
	switch(filter)  						//Different formulas for 4 filters
	{
		case 0:
			return 0;

		case 1:
			p = p1;
			p -= p1 >> 4;
			return p;

		case 2:
			p = p1 << 1;
			p += (-(p1 + (p1 << 1))) >> 5;
			p -= p2;
			p += p2 >> 4;
			return p;

		case 3:
			p = p1 << 1;
			p += (-(p1 + (p1 << 2) + (p1 << 3))) >> 6;
			p -= p2;
			p += (p2 + (p2 << 1)) >> 4;
			return p;

		default:
			return 0;
	}
}

static void decodeSample (char s, u8 shift_am, u8 filter)
{
	int a;
	if(shift_am <= 0x0c)			//Valid shift count
		a = ((s < 8 ? s : s-16) << shift_am) >> 1;
	else
		a = s < 8 ? 2048 : -2048;		//Max values

	a += get_brr_prediction(filter, p1, p2);

	if(a > 0x7fff) a = 0x7fff;
	else if(a < -0x8000) a = -0x8000;
	if(a >	0x3fff) a -= 0x8000;
	else if(a < -0x4000) a += 0x8000;

	p2 = p1;
	p1 = cast(short)a;
}

void decodeBRR(pcm_t *out_) 			//Decode a block of BRR bytes into array pointed by arg.
{
	u8 filter = (BRR[0] & 0x0c)>>2;
	u8 shift_amount = (BRR[0]>>4) & 0x0F;					//Read filter & shift amount

	for(int i=0; i<8; ++i)  									//Loop for each byte
	{
		decodeSample(BRR[i+1]>>4, shift_amount, filter);		//Decode high nybble
		*(out_++) = cast(short)(2*p1);
		decodeSample(BRR[i+1]&0x0f, shift_amount, filter);		//Decode low nybble
		*(out_++) = cast(short)(2*p1);
	}
}

void apply_gauss_filter(pcm_t *buffer, size_t length)
{
	int prev = (372  + 1304) * buffer[0] + 372 * buffer[1];		// First sample
	for(int i=1; i < length-1; ++i)
	{
		int k0 = 372 * (buffer[i-1] + buffer[i+1]);
		int k = 1304 * buffer[i];
		buffer[i-1] = cast(short)(prev/2048);
		prev = k0 + k;
	}
	int last = 372 * buffer[length-2] + (1304 + 372) * buffer[length-1];
	buffer[length-2] = cast(short)(prev/2048);
	buffer[length-1] = cast(short)(last/2048);
}
