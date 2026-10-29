#ifndef COMMON_H
#define COMMON_H

#include <stdio.h>
#include <stdlib.h>

/* V3, V5: elementi massimi di un segmento in shared (5 byte per elemento: 40 KB) */
#define MAX_SEG_SHARED  8192

/* V4: warp per blocco ed elementi massimi del segmento di un warp */
#define WARPS_PER_BLOCK 4
#define MAX_SEG_WARP    64

/* V5: numero di stream (massimo di kernel concorrenti con CC 5.2) */
#define V5_STREAMS 32

static const int N_LIST[] = { 100, 500, 1000, 2000, 5000, 10000, 20000, 50000, 60000, 80000, 100000 };
#define N_LIST_LEN ((int)(sizeof(N_LIST) / sizeof(N_LIST[0])))

/* forma "misti": MISTI_LUNGHI segmenti tra N/32 e N/16, gli altri tra 1 e MISTI_CORTI */
#define MISTI_LUNGHI 8
#define MISTI_CORTI  32
#define MISTI_N_MIN  2000

#define INPUT_FMT "data/input_N%d_%s.txt"

#ifdef __CUDACC__
#include <cuda_runtime.h>

static void HandleError(cudaError_t err, const char *file, int line)
{
    if (err != cudaSuccess) {
        printf("%s in %s at line %d\n", cudaGetErrorString(err), file, line);
        exit(EXIT_FAILURE);
    }
}
#define HANDLE_ERROR(err) (HandleError((err), __FILE__, __LINE__))
#endif

/* linkage C: main.c (gcc) chiama le funzioni definite nei .cu (nvcc, C++) */
#ifdef __cplusplus
extern "C" {
#endif

int  gen_input(int *keys, char *vals, int *P, int N, int max_len, unsigned int seed);
int  gen_input_misti(int *keys, char *vals, int *P, int N, unsigned int seed);
int  write_input(const char *path, const int *keys, const char *vals, const int *P, int N, int K);
int  read_input(const char *path, int **keys, char **vals, int **P, int *N, int *K);

void oddeven_segment(int *keys, char *vals, int start, int end);

/* Stessa firma per tutte le versioni: ordinamento in-place, restituisce i ms del solo
   ordinamento, oppure -1 se la versione non si applica all'input. */
double sort_serial    (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v1_static (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v1_dynamic(int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v1_guided (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v2        (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v3        (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v3_static (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v4        (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v4_shuffle(int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v5        (int *keys, char *vals, const int *P, int N, int K, int threads);
double sort_v5_graph  (int *keys, char *vals, const int *P, int N, int K, int threads);

#ifdef __cplusplus
}
#endif

#endif
