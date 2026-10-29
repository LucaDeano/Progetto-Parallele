/* V2: CUDA, un blocco per segmento, memoria globale */
#include "common.h"

__global__ void kernel_v2(int *keys, char *vals, const int *P)
{
    __shared__ int changed;

    int start = P[blockIdx.x], end = P[blockIdx.x + 1];
    int n = end - start, quiet = 0;

    for (int phase = 0; phase < n && quiet < 2; phase++) {
        if (threadIdx.x == 0)
            changed = 0;
        __syncthreads();                        /* > stretto per mantenere la stabilita' */

        for (int j = start + (phase & 1) + 2 * threadIdx.x; j + 1 < end; j += 2 * blockDim.x) {
            if (keys[j] > keys[j + 1]) {         /* > stretto: stabilita' */
                int  tk = keys[j];  keys[j] = keys[j + 1];  keys[j + 1] = tk;
                char tv = vals[j];  vals[j] = vals[j + 1];  vals[j + 1] = tv;
                changed = 1;
            }
        }
        __syncthreads();                        /* fine fase: scambi visibili a tutti */

        quiet = changed ? 0 : quiet + 1;        /* stesso valore per tutti: uscita uniforme */
        __syncthreads();                        /* tutti hanno letto changed prima del reset */
    }
}

double sort_v2(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    if (threads < 32 || threads > 1024 || (threads & 31) != 0) {
        fprintf(stderr, "sort_v2: thread per blocco non validi (%d)\n", threads);
        exit(EXIT_FAILURE);
    }
    if (K == 0)
        return 0.0;

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
    kernel_v2<<<K, threads>>>(d_keys, d_vals, d_P);
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
