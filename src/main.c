#include <omp.h>
#include "common.h"

#define REPS       5
#define CSV_PATH   "results/risultati.csv"
#define WARMUP_MS  300.0

#define LEN(a) ((int)(sizeof(a) / sizeof((a)[0])))

static const int T_ONE[] = { 1 };
static const int T_CPU[] = { 1, 2, 4, 8 };
static const int T_GPU[] = { 64, 128, 256 };
static const int T_V4[]  = { WARPS_PER_BLOCK * 32 };
static const int T_V5[]  = { V5_STREAMS };

typedef double (*sort_fn)(int *, char *, const int *, int, int, int);

typedef struct {
    const char *name;
    sort_fn     fn;
    const int  *threads;
    int         n_threads;
} Version;

/* S deve restare la prima: e' la base dello speedup */
static const Version VERSIONS[] = {
    { "S",          sort_serial,     T_ONE, LEN(T_ONE) },
    { "V1-static",  sort_v1_static,  T_CPU, LEN(T_CPU) },
    { "V1-dynamic", sort_v1_dynamic, T_CPU, LEN(T_CPU) },
    { "V1-guided",  sort_v1_guided,  T_CPU, LEN(T_CPU) },
    { "V2",         sort_v2,         T_GPU, LEN(T_GPU) },
    { "V3",         sort_v3,         T_GPU, LEN(T_GPU) },
    { "V3-statica", sort_v3_static,  T_GPU, LEN(T_GPU) },
    { "V4",         sort_v4,         T_V4,  LEN(T_V4)  },
    { "V4-shuffle", sort_v4_shuffle, T_V4,  LEN(T_V4)  },
    { "V5",         sort_v5,         T_V5,  LEN(T_V5)  },
    { "V5-graph",   sort_v5_graph,   T_ONE, LEN(T_ONE) },
};

static double median(const double *a, int n)
{
    double s[REPS];
    for (int i = 0; i < n; i++) {
        double x = a[i];
        int j = i;
        while (j > 0 && s[j - 1] > x) {
            s[j] = s[j - 1];
            j--;
        }
        s[j] = x;
    }
    return (n & 1) ? s[n / 2] : 0.5 * (s[n / 2 - 1] + s[n / 2]);
}

static void copy_input(int *dk, char *dv, const int *sk, const char *sv, int N)
{
    for (int i = 0; i < N; i++) {
        dk[i] = sk[i];
        dv[i] = sv[i];
    }
}

/* 1 esecuzione di riscaldamento + REPS misurate, ognuna su una copia dell'input (ordinamento
   in-place). t_ord = tempo restituito dalla versione, t_tot = intera chiamata.
   Restituisce 0 se la versione non si applica all'input. */
static int measure(const Version *v, int threads, int N, int K, const int *P,
                   const int *orig_keys, const char *orig_vals, int *keys, char *vals,
                   double *t_ord, double *t_tot)
{
    double ord[REPS], tot[REPS];
    for (int r = 0; r <= REPS; r++) {
        copy_input(keys, vals, orig_keys, orig_vals, N);
        double t0 = omp_get_wtime();
        double tk = v->fn(keys, vals, P, N, K, threads);
        double tt = (omp_get_wtime() - t0) * 1000.0;
        if (tk < 0.0)
            return 0;
        if (r > 0) {
            ord[r - 1] = tk;
            tot[r - 1] = tt;
        }
    }
    *t_ord = median(ord, REPS);
    *t_tot = median(tot, REPS);
    return 1;
}

/* le prime regioni parallele dopo l'avvio sono lente: V1 lavora per WARMUP_MS prima delle misure */
static void warmup_cpu(int threads)
{
    enum { WN = 20000 };
    int  *k = (int *)malloc(WN * sizeof(int));
    char *v = (char *)malloc(WN * sizeof(char));
    int  *P = (int *)malloc((WN + 1) * sizeof(int));
    if (k == NULL || v == NULL || P == NULL) {
        fprintf(stderr, "memoria insufficiente per il riscaldamento\n");
        exit(EXIT_FAILURE);
    }
    double t0 = omp_get_wtime();
    while ((omp_get_wtime() - t0) * 1000.0 < WARMUP_MS) {
        int K = gen_input(k, v, P, WN, 32, 1);
        sort_v1_static(k, v, P, WN, K, threads);
    }
    free(k);
    free(v);
    free(P);
}

static void run_input(int N, const char *shape, FILE *csv)
{
    char path[256];
    snprintf(path, sizeof(path), INPUT_FMT, N, shape);
    int  *orig_keys, *P, K;
    char *orig_vals;
    if (read_input(path, &orig_keys, &orig_vals, &P, &N, &K) != 0) {
        fprintf(stderr, "impossibile leggere %s: creare gli input con  make dati\n", path);
        exit(EXIT_FAILURE);
    }

    int  *keys = (int *)malloc(N * sizeof(int));
    char *vals = (char *)malloc(N * sizeof(char));
    if (!keys || !vals) {
        fprintf(stderr, "memoria insufficiente per N = %d\n", N);
        exit(EXIT_FAILURE);
    }

    int max_seg = 0;
    for (int i = 0; i < K; i++)
        if (P[i + 1] - P[i] > max_seg)
            max_seg = P[i + 1] - P[i];

    printf("\n%s: N = %d, segmenti %s, K = %d, segmento piu' lungo %d\n",
           path, N, shape, K, max_seg);
    printf("  %-11s %7s %14s %14s %10s %10s\n", "versione", "thread",
           "ordin. [ms]", "totale [ms]", "speedup o.", "speedup t.");

    double s_ord = 0.0, s_tot = 0.0;
    for (int i = 0; i < LEN(VERSIONS); i++) {
        const Version *v = &VERSIONS[i];
        for (int t = 0; t < v->n_threads; t++) {
            int threads = v->threads[t];
            double t_ord, t_tot;

            if (!measure(v, threads, N, K, P, orig_keys, orig_vals, keys, vals, &t_ord, &t_tot)) {
                printf("  %-11s %7d %14s %14s\n", v->name, threads, "n/d", "n/d");
                fprintf(csv, "%s,%d,%s,%d,%d,%d,,,,\n", v->name, N, shape, K, max_seg, threads);
                continue;
            }
            if (i == 0) {
                s_ord = t_ord;
                s_tot = t_tot;
            }
            double sp_ord = t_ord > 0.0 ? s_ord / t_ord : 0.0;
            double sp_tot = t_tot > 0.0 ? s_tot / t_tot : 0.0;

            printf("  %-11s %7d %14.3f %14.3f %10.2f %10.2f\n", v->name, threads,
                   t_ord, t_tot, sp_ord, sp_tot);
            fprintf(csv, "%s,%d,%s,%d,%d,%d,%.6f,%.6f,%.4f,%.4f\n",
                    v->name, N, shape, K, max_seg, threads, t_ord, t_tot, sp_ord, sp_tot);
        }
    }

    free(orig_keys);
    free(orig_vals);
    free(P);
    free(keys);
    free(vals);
}

int main(void)
{
    printf("Odd-Even Transposition Sort segmentato: input da data/, 1 + %d ripetizioni per misura\n",
           REPS);

    warmup_cpu(T_CPU[LEN(T_CPU) - 1]);

    FILE *csv = fopen(CSV_PATH, "w");
    if (csv == NULL) {
        fprintf(stderr, "impossibile aprire %s (la cartella esiste?)\n", CSV_PATH);
        return EXIT_FAILURE;
    }
    fprintf(csv, "versione,N,forma,K,max_seg,thread,"
                 "t_ordinamento_ms,t_totale_ms,speedup_ordinamento,speedup_totale\n");

    for (int i = 0; i < N_LIST_LEN; i++) {
        run_input(N_LIST[i], "piccoli", csv);
        run_input(N_LIST[i], "grandi", csv);
        if (N_LIST[i] >= MISTI_N_MIN)
            run_input(N_LIST[i], "misti", csv);
    }
    fclose(csv);

    printf("\nRisultati in %s\n", CSV_PATH);
    return EXIT_SUCCESS;
}
