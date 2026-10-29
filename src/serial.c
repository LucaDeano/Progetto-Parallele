/* S: Odd-Even Transposition Sort seriale, un segmento dopo l'altro */
#include <omp.h>
#include "common.h"

void oddeven_segment(int *keys, char *vals, int start, int end)
{
    int n = end - start, quiet = 0;

    for (int phase = 0; phase < n && quiet < 2; phase++) {
        int swapped = 0;

        for (int j = start + (phase & 1); j + 1 < end; j += 2) {
            if (keys[j] > keys[j + 1]) {        /* > stretto: stabilita' */
                int  tk = keys[j];  keys[j] = keys[j + 1];  keys[j + 1] = tk;
                char tv = vals[j];  vals[j] = vals[j + 1];  vals[j + 1] = tv;
                swapped = 1;
            }
        }

        quiet = swapped ? 0 : quiet + 1;        /* early-exit dopo 2 fasi senza scambi */
    }
}

double sort_serial(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)N;
    (void)threads;

    double t0 = omp_get_wtime();
    for (int i = 0; i < K; i++)
        oddeven_segment(keys, vals, P[i], P[i + 1]);
    double t1 = omp_get_wtime();

    return (t1 - t0) * 1000.0;
}
