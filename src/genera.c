/* Crea gli input in data/: un file per N e forma (piccoli, grandi, misti) */
#include "common.h"

#define SEED      42
#define SMALL_LEN 32

int main(void)
{
    char path[256];

    for (int i = 0; i < N_LIST_LEN; i++) {
        int N = N_LIST[i];

        int  *keys = (int *)malloc(N * sizeof(int));
        char *vals = (char *)malloc(N * sizeof(char));
        int  *P    = (int *)malloc((N + 1) * sizeof(int));
        if (keys == NULL || vals == NULL || P == NULL) {
            fprintf(stderr, "memoria insufficiente per N = %d\n", N);
            return EXIT_FAILURE;
        }

        for (int large = 0; large <= 1; large++) {
            int max_len = large ? N / 16 : SMALL_LEN;
            const char *shape = large ? "grandi" : "piccoli";

            int K = gen_input(keys, vals, P, N, max_len, SEED);
            snprintf(path, sizeof(path), INPUT_FMT, N, shape);
            if (write_input(path, keys, vals, P, N, K) != 0) {
                fprintf(stderr, "impossibile scrivere %s (la cartella data/ esiste?)\n", path);
                return EXIT_FAILURE;
            }
            printf("%-32s N = %6d  K = %5d  max_len = %5d\n", path, N, K, max_len);
        }

        if (N >= MISTI_N_MIN) {
            int K = gen_input_misti(keys, vals, P, N, SEED);
            snprintf(path, sizeof(path), INPUT_FMT, N, "misti");
            if (write_input(path, keys, vals, P, N, K) != 0) {
                fprintf(stderr, "impossibile scrivere %s (la cartella data/ esiste?)\n", path);
                return EXIT_FAILURE;
            }
            printf("%-32s N = %6d  K = %5d  %d lunghi tra %d e %d\n", path, N, K,
                   MISTI_LUNGHI, N / 32, N / 16);
        }

        free(keys);
        free(vals);
        free(P);
    }
    return EXIT_SUCCESS;
}
