/* V4: CUDA, un warp per segmento (shared + __syncwarp) */
#include "common.h"

__global__ void kernel_v4(int *keys, char *vals, const int *P, int K)
{
    __shared__ int  sk[WARPS_PER_BLOCK][MAX_SEG_WARP];
    __shared__ char sv[WARPS_PER_BLOCK][MAX_SEG_WARP];
    __shared__ int  changed[WARPS_PER_BLOCK];

    int lane = threadIdx.x & 31;
    int warp = threadIdx.x >> 5;
    int seg  = blockIdx.x * WARPS_PER_BLOCK + warp;     /* un warp per segmento */

    if (seg >= K)
        return;

    int start = P[seg], n = P[seg + 1] - start;
    int  *wk = sk[warp];                         /* riga di shared di questo warp */
    char *wv = sv[warp];

    for (int t = lane; t < n; t += 32) {
        wk[t] = keys[start + t];
        wv[t] = vals[start + t];
    }
    __syncwarp();

    int quiet = 0;
    for (int phase = 0; phase < n && quiet < 2; phase++) {
        if (lane == 0)
            changed[warp] = 0;
        __syncwarp();

        for (int j = (phase & 1) + 2 * lane; j + 1 < n; j += 64) {
            if (wk[j] > wk[j + 1]) {             /* > stretto per mantenere la stabilita' */
                int  tk = wk[j];  wk[j] = wk[j + 1];  wk[j + 1] = tk;
                char tv = wv[j];  wv[j] = wv[j + 1];  wv[j + 1] = tv;
                changed[warp] = 1;
            }
        }
        __syncwarp();

        quiet = changed[warp] ? 0 : quiet + 1;
        __syncwarp();
    }

    for (int t = lane; t < n; t += 32) {
        keys[start + t] = wk[t];
        vals[start + t] = wv[t];
    }
}

double sort_v4(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)threads;
    if (K == 0)
        return 0.0;

    int max_seg = 0;
    for (int i = 0; i < K; i++)
        if (P[i + 1] - P[i] > max_seg)
            max_seg = P[i + 1] - P[i];
    if (max_seg > MAX_SEG_WARP) {
        fprintf(stderr, "V4: segmento di %d elementi, oltre il limite di %d: non eseguita\n",
                max_seg, MAX_SEG_WARP);
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

    int blocks = (K + WARPS_PER_BLOCK - 1) / WARPS_PER_BLOCK;
    HANDLE_ERROR(cudaEventRecord(ev_start, 0));
    kernel_v4<<<blocks, WARPS_PER_BLOCK * 32>>>(d_keys, d_vals, d_P, K);
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
