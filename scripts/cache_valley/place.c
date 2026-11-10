/* place.c: where the allocator puts two equal blocks, for block sizes on both sides of 2 MiB and 4 MiB.
 * Two consecutive posix_memalign(16, S) calls per size; prints the distance b - a and its remainder mod 16 KiB.
 * On macOS 27.0.1 (Apple M5): contiguous at 1 MiB, the second block about 6 MiB below the first at 1.94-2.0 MiB,
 * 4 MiB + 16 KiB apart from 2 MiB + 16 B to 3 000 000 B, exactly 4 MiB apart at 4 181 760 B and 4 MiB, 8 MiB + 16 KiB
 * apart from 4 MiB + 16 B to 8 000 000 B (results/cache_valley_placement_2026-11-03.txt, section 1). The field arrays
 * of openEMS are 12 B per cell each, so 2-4 MiB is about 0.175-0.35 M cells.
 *   cc -O2 place.c -o place && ./place
 */
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

int main(void)
{
	const size_t sizes[] = {1u<<20, 2031360, 2075760, 2097152, 2097168, 2120640, 3000000, 4181760,
	                        4194304, 4194320, 4245360, 4704000, 8000000};
	for (unsigned i = 0; i < sizeof sizes / sizeof *sizes; i++) {
		void *a, *b;
		if (posix_memalign(&a, 16, sizes[i]) || posix_memalign(&b, 16, sizes[i]))
			return 1;
		const long d = (long)((intptr_t)b - (intptr_t)a);
		printf("S=%9zu  a mod 16K=%5ld  b-a=%10ld  (b-a) mod 16K=%5ld  (b-a)-S=%ld\n", sizes[i],
		       (long)((uintptr_t)a % 16384), d, ((d % 16384) + 16384) % 16384, d - (long)sizes[i]);
	}
	return 0;
}
