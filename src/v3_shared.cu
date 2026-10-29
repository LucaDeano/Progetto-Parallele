/* V3: CUDA, un blocco per segmento, shared memory (dinamica e statica) */
#include "common.h"

__device__ void sort_segment_shared(int *keys, char *vals, int start, int n,
                                    int *sk, char *sv, int *changed)
{
    for (int t = threadIdx.x; t < n; t += blockDim.x) {
        sk[t] = keys[start + t];
        sv[t] = vals[start + t];
    }
    __syncthreads();

    int quiet = 0;
    for (int phase = 0; phase < n && quiet < 2; phase++) {
        if (threadIdx.x == 0)
            *changed = 0;
        __syncthreads();                        /* reset visibile prima degli scambi */

        for (int j = (phase & 1) + 2 * threadIdx.x; j + 1 < n; j += 2 * blockDim.x) {
            if (sk[j] > sk[j + 1]) {             /* > stretto per mantenere la stabilita' */
                int  tk = sk[j];  sk[j] = sk[j + 1];  sk[j + 1] = tk;
                char tv = sv[j];  sv[j] = sv[j + 1];  sv[j + 1] = tv;
                *changed = 1;
            }
        }
        __syncthreads();                        /* fine fase: scambi visibili a tutti */

        quiet = *changed ? 0 : quiet + 1;       /* stesso valore per tutti: uscita uniforme */
        __syncthreads();                        /* tutti hanno letto changed prima del reset */
    }

    for (int t = threadIdx.x; t < n; t += blockDim.x) {
        keys[start + t] = sk[t];
        vals[start + t] = sv[t];
    }
}

__global__ void kernel_v3_dynamic(int *keys, char *vals, const int *P, int max_seg)
{
    extern __shared__ int smem[];
    int  *sk = smem;
    char *sv = (char *)(smem + max_seg);    /* shared dinamica: max_seg chiavi, poi max_seg valori */
    __shared__ int changed;

    int start = P[blockIdx.x], n = P[blockIdx.x + 1] - start;
    sort_segment_shared(keys, vals, start, n, sk, sv, &changed);
}

__global__ void kernel_v3_static(int *keys, char *vals, const int *P)
{
    __shared__ int  sk[MAX_SEG_SHARED];
    __shared__ char sv[MAX_SEG_SHARED];
    __shared__ int  changed;

    int start = P[blockIdx.x], n = P[blockIdx.x + 1] - start;
    sort_segment_shared(keys, vals, start, n, sk, sv, &changed);
}

static double run_v3(int *keys, char *vals, const int *P, int N, int K, int threads,
                     int use_static)
{
    if (threads < 32 || threads > 1024 || (threads & 31) != 0) {
        fprintf(stderr, "sort_v3: thread per blocco non validi (%d)\n", threads);
        exit(EXIT_FAILURE);
    }
    if (K == 0)
        return 0.0;

    int max_seg = 0;
    for (int i = 0; i < K; i++)
        if (P[i + 1] - P[i] > max_seg)
            max_seg = P[i + 1] - P[i];
    if (max_seg > MAX_SEG_SHARED) {
        fprintf(stderr, "V3: segmento di %d elementi, oltre il limite di %d: non eseguita\n",
                max_seg, MAX_SEG_SHARED);
        return -1.0;
    }

    int  *d_keys, *d_P;
    char *d_vals;
    HANDLE_ERROR(cudaMalloc((void **)&d_keys, N * sizeof(int)));
    HANDLE_ERROR(cudaMalloc((void **)&d_vals, N * sizeof(char)));
    HANDLE_ERROR(cudaMalloc((void **)&d_P, (K + 1) * sizeof(int)));

    HANDLE_ERROR(cudaMemcpy(d_keys, keys, N * sizeof(int), cudaMemcpyHostToDevice));
    HANDLE_ERROR(cudaMemcpy(d_vals, vals, N * sizeof(char), cudaMemcpyHostToDevice));
    HANDLE_ERROR(cudaMemcpy(d_P, P, (K + 1) * sizeof(int), cudaMemcpyHostToDevice));

    cudaEvent_t ev_start, ev_stop;
    HANDLE_ERROR(cudaEventCreate(&ev_start));
    HANDLE_ERROR(cudaEventCreate(&ev_stop));

    HANDLE_ERROR(cudaEventRecord(ev_start, 0));
    if (use_static) {
        kernel_v3_static<<<K, threads>>>(d_keys, d_vals, d_P);
    } else {
        int bytes = max_seg * (int)(sizeof(int) + sizeof(char));
        kernel_v3_dynamic<<<K, threads, bytes>>>(d_keys, d_vals, d_P, max_seg);
    }
    HANDLE_ERROR(cudaEventRecord(ev_stop, 0));
    HANDLE_ERROR(cudaEventSynchronize(ev_stop));
    HANDLE_ERROR(cudaDeviceSynchronize());

    float ms = 0.0f;
    HANDLE_ERROR(cudaEventElapsedTime(&ms, ev_start, ev_stop));

    HANDLE_ERROR(cudaMemcpy(keys, d_keys, N * sizeof(int), cudaMemcpyDeviceToHost));
    HANDLE_ERROR(cudaMemcpy(vals, d_vals, N * sizeof(char), cudaMemcpyDeviceToHost));

    HANDLE_ERROR(cudaEventDestroy(ev_start));
    HANDLE_ERROR(cudaEventDestroy(ev_stop));
    HANDLE_ERROR(cudaFree(d_keys));
    HANDLE_ERROR(cudaFree(d_vals));
    HANDLE_ERROR(cudaFree(d_P));

    return (double)ms;
}

double sort_v3(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    return run_v3(keys, vals, P, N, K, threads, 0);
}

double sort_v3_static(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    return run_v3(keys, vals, P, N, K, threads, 1);
}
