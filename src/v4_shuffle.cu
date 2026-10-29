/* V4-shuffle: CUDA, un warp per segmento, segmento nei registri (shuffle) */
#include <climits>
#include "common.h"

__global__ void kernel_v4_shuffle(int *keys, char *vals, const int *P, int K)
{
    int lane = threadIdx.x & 31;
    int warp = threadIdx.x >> 5;
    int seg  = blockIdx.x * WARPS_PER_BLOCK + warp;
    if (seg >= K)
        return;

    int start = P[seg], n = P[seg + 1] - start;
    int i0 = 2 * lane, i1 = 2 * lane + 1;          /* la lane tiene gli elementi 2l e 2l+1 */

    /* oltre n: riempitivi INT_MAX, che con il > stretto restano in fondo */
    int k0 = (i0 < n) ? keys[start + i0] : INT_MAX;
    int k1 = (i1 < n) ? keys[start + i1] : INT_MAX;
    int v0 = (i0 < n) ? vals[start + i0] : 0;
    int v1 = (i1 < n) ? vals[start + i1] : 0;

    int quiet = 0;
    for (int phase = 0; phase < n && quiet < 2; phase++) {
        int scambio = 0;
        if ((phase & 1) == 0) {
            /* fase pari: coppia (2l, 2l+1) all'interno della lane l */
            if (k0 > k1) {                      /* > stretto per mantenere la stabilita' */
                int tk = k0; k0 = k1; k1 = tk;
                int tv = v0; v0 = v1; v1 = tv;
                scambio = 1;
            }
        } else {
            /* fase dispari: coppia (2l+1, 2l+2) a cavallo tra la lane l e la l+1 */
            int k_dopo  = __shfl_down_sync(0xffffffff, k0, 1);
            int v_dopo  = __shfl_down_sync(0xffffffff, v0, 1);
            int k_prima = __shfl_up_sync(0xffffffff, k1, 1);
            int v_prima = __shfl_up_sync(0xffffffff, v1, 1);

            if (lane < 31 && k1 > k_dopo) {
                k1 = k_dopo;
                v1 = v_dopo;
                scambio = 1;
            }
            if (lane > 0 && k_prima > k0) {
                k0 = k_prima;
                v0 = v_prima;
            }
        }
        quiet = __any_sync(0xffffffff, scambio) ? 0 : quiet + 1;
    }

    if (i0 < n) {
        keys[start + i0] = k0;
        vals[start + i0] = (char)v0;
    }
    if (i1 < n) {
        keys[start + i1] = k1;
        vals[start + i1] = (char)v1;
    }
}

double sort_v4_shuffle(int *keys, char *vals, const int *P, int N, int K, int threads)
{
    (void)threads;
    if (K == 0)
        return 0.0;

    int max_seg = 0;
    for (int i = 0; i < K; i++)
        if (P[i + 1] - P[i] > max_seg)
            max_seg = P[i + 1] - P[i];
    if (max_seg > MAX_SEG_WARP) {
        fprintf(stderr, "V4-shuffle: segmento di %d elementi, oltre il limite di %d: non eseguita\n",
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
    kernel_v4_shuffle<<<blocks, WARPS_PER_BLOCK * 32>>>(d_keys, d_vals, d_P, K);
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
