/* V5: CUDA, un kernel da un blocco per segmento, distribuiti a giro su V5_STREAMS stream */
#include "common.h"

__global__ void kernel_v5(int *keys, char *vals, int start, int n)
{
    extern __shared__ int smem[];
    int  *sk = smem;
    char *sv = (char *)(smem + n);          /* shared dinamica: n chiavi, poi n valori */
    __shared__ int changed;

    for (int t = threadIdx.x; t < n; t += blockDim.x) {
        sk[t] = keys[start + t];
        sv[t] = vals[start + t];
    }
    __syncthreads();

    int quiet = 0;
    for (int phase = 0; phase < n && quiet < 2; phase++) {
        if (threadIdx.x == 0)
            changed = 0;
        __syncthreads();                        /* reset visibile prima degli scambi */

        for (int j = (phase & 1) + 2 * threadIdx.x; j + 1 < n; j += 2 * blockDim.x) {
            if (sk[j] > sk[j + 1]) {             /* > stretto per mantenere la stabilita' */
                int  tk = sk[j];  sk[j] = sk[j + 1];  sk[j + 1] = tk;
                char tv = sv[j];  sv[j] = sv[j + 1];  sv[j + 1] = tv;
                changed = 1;
            }
        }
        __syncthreads();                        /* fine fase: scambi visibili a tutti */

        quiet = changed ? 0 : quiet + 1;        /* stesso valore per tutti: uscita uniforme */
        __syncthreads();                        /* tutti hanno letto changed prima del reset */
    }

    for (int t = threadIdx.x; t < n; t += blockDim.x) {
        keys[start + t] = sk[t];
        vals[start + t] = sv[t];
    }
}

double sort_v5(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)threads;
    if (K == 0)
        return 0.0;

    int max_seg = 0;
    for (int i = 0; i < K; i++)
        if (P[i + 1] - P[i] > max_seg)
            max_seg = P[i + 1] - P[i];
    if (max_seg > MAX_SEG_SHARED) {
        fprintf(stderr, "V5: segmento di %d elementi, oltre il limite di %d: non eseguita\n",
                max_seg, MAX_SEG_SHARED);
        return -1.0;
    }

    int  *d_keys;
    char *d_vals;
    HANDLE_ERROR(cudaMalloc((void **)&d_keys, N * sizeof(int)));
    HANDLE_ERROR(cudaMalloc((void **)&d_vals, N * sizeof(char)));
    HANDLE_ERROR(cudaMemcpy(d_keys, keys, N * sizeof(int), cudaMemcpyHostToDevice));
    HANDLE_ERROR(cudaMemcpy(d_vals, vals, N * sizeof(char), cudaMemcpyHostToDevice));

    cudaStream_t streams[V5_STREAMS];
    for (int s = 0; s < V5_STREAMS; s++)
        HANDLE_ERROR(cudaStreamCreate(&streams[s]));

    cudaEvent_t ev_start, ev_stop;
    HANDLE_ERROR(cudaEventCreate(&ev_start));
    HANDLE_ERROR(cudaEventCreate(&ev_stop));

    HANDLE_ERROR(cudaEventRecord(ev_start, 0));
    for (int i = 0; i < K; i++) {
        int start = P[i], n = P[i + 1] - start;
        if (n < 2)
            continue;
        int T = ((n / 2 + 31) / 32) * 32;       /* n/2 coppie, arrotondate a warp interi */
        if (T > 1024)
            T = 1024;
        int bytes = n * (int)(sizeof(int) + sizeof(char));
        kernel_v5<<<1, T, bytes, streams[i % V5_STREAMS]>>>(d_keys, d_vals, start, n);
    }
    HANDLE_ERROR(cudaGetLastError());
    HANDLE_ERROR(cudaEventRecord(ev_stop, 0));
    HANDLE_ERROR(cudaEventSynchronize(ev_stop));
    HANDLE_ERROR(cudaDeviceSynchronize());

    float ms = 0.0f;
    HANDLE_ERROR(cudaEventElapsedTime(&ms, ev_start, ev_stop));

    HANDLE_ERROR(cudaMemcpy(keys, d_keys, N * sizeof(int), cudaMemcpyDeviceToHost));
    HANDLE_ERROR(cudaMemcpy(vals, d_vals, N * sizeof(char), cudaMemcpyDeviceToHost));

    HANDLE_ERROR(cudaEventDestroy(ev_start));
    HANDLE_ERROR(cudaEventDestroy(ev_stop));
    for (int s = 0; s < V5_STREAMS; s++)
        HANDLE_ERROR(cudaStreamDestroy(streams[s]));
    HANDLE_ERROR(cudaFree(d_keys));
    HANDLE_ERROR(cudaFree(d_vals));

    return (double)ms;
}
