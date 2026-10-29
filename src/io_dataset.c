#include "common.h"

#define KEY_RANGE 1000

/* X casuale; P con segmenti lunghi a caso tra 1 e max_len, l'ultimo chiude su N. Restituisce K. */
int gen_input(int *keys, char *vals, int *P, int N, int max_len, unsigned int seed)
{
    srand(seed);

    for (int i = 0; i < N; i++) {
        keys[i] = rand() % KEY_RANGE;
        vals[i] = (char)('a' + rand() % 26);
    }

    int K = 0;
    P[0] = 0;
    while (P[K] < N) {
        int len = 1 + rand() % max_len;
        if (len > N - P[K])
            len = N - P[K];
        P[K + 1] = P[K] + len;
        K++;
    }
    return K;
}

/* Stessa X di gen_input; P con MISTI_LUNGHI segmenti lunghi e il resto corti, in ordine casuale.
   Le lunghezze si scrivono in P[1..K], si mescolano e poi si sommano in posizione. */
int gen_input_misti(int *keys, char *vals, int *P, int N, unsigned int seed)
{
    srand(seed);

    for (int i = 0; i < N; i++) {
        keys[i] = rand() % KEY_RANGE;
        vals[i] = (char)('a' + rand() % 26);
    }

    int K = 0, used = 0;
    int min_l = N / 32, max_l = N / 16;
    for (int i = 0; i < MISTI_LUNGHI; i++) {
        int len = min_l + rand() % (max_l - min_l + 1);
        P[++K] = len;
        used += len;
    }

    while (used < N) {
        int len = 1 + rand() % MISTI_CORTI;
        if (len > N - used)
            len = N - used;
        P[++K] = len;
        used += len;
    }

    for (int i = K; i > 1; i--) {               /* Fisher-Yates */
        int j = 1 + rand() % i;
        int t = P[i]; P[i] = P[j]; P[j] = t;
    }

    P[0] = 0;
    for (int i = 1; i <= K; i++)                /* da lunghezze a inizi dei segmenti */
        P[i] += P[i - 1];
    return K;
}

/* Formato: riga 1 "N K", riga 2 P[0..K], poi una riga "chiave valore" per coppia */
int write_input(const char *path, const int *keys, const char *vals, const int *P, int N, int K)
{
    FILE *f = fopen(path, "w");
    if (f == NULL)
        return -1;

    fprintf(f, "%d %d\n", N, K);
    for (int i = 0; i <= K; i++)
        fprintf(f, i < K ? "%d " : "%d\n", P[i]);
    for (int i = 0; i < N; i++)
        fprintf(f, "%d %c\n", keys[i], vals[i]);

    return fclose(f) == 0 ? 0 : -1;
}

/* Alloca keys, vals e P (li libera il chiamante) */
int read_input(const char *path, int **keys, char **vals, int **P, int *N, int *K)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return -1;
    if (fscanf(f, "%d %d", N, K) != 2 || *N < 1 || *K < 1) {
        fclose(f);
        return -1;
    }

    *keys = (int *)malloc(*N * sizeof(int));
    *vals = (char *)malloc(*N * sizeof(char));
    *P    = (int *)malloc((*K + 1) * sizeof(int));
    int ok = *keys != NULL && *vals != NULL && *P != NULL;

    for (int i = 0; ok && i <= *K; i++)
        ok = fscanf(f, "%d", &(*P)[i]) == 1;
    for (int i = 0; ok && i < *N; i++)
        ok = fscanf(f, "%d %c", &(*keys)[i], &(*vals)[i]) == 2;
    fclose(f);

    if (!ok) {
        free(*keys);
        free(*vals);
        free(*P);
        return -1;
    }
    return 0;
}
