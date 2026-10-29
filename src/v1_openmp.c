/* V1: OpenMP, parallel for sui segmenti, tre schedule */
#include <omp.h>
#include "common.h"

double sort_v1_static(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)N;
    double t0 = omp_get_wtime();

    #pragma omp parallel for schedule(static) num_threads(threads)
    for (int i = 0; i < K; i++)
        oddeven_segment(keys, vals, P[i], P[i + 1]);

    double t1 = omp_get_wtime();
    return (t1 - t0) * 1000.0;
}

double sort_v1_dynamic(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)N;
    double t0 = omp_get_wtime();

    #pragma omp parallel for schedule(dynamic) num_threads(threads)
    for (int i = 0; i < K; i++)
        oddeven_segment(keys, vals, P[i], P[i + 1]);

    double t1 = omp_get_wtime();
    return (t1 - t0) * 1000.0;
}

double sort_v1_guided(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)N;
    double t0 = omp_get_wtime();

    #pragma omp parallel for schedule(guided) num_threads(threads)
    for (int i = 0; i < K; i++)
        oddeven_segment(keys, vals, P[i], P[i + 1]);

    double t1 = omp_get_wtime();
    return (t1 - t0) * 1000.0;
}
