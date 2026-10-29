#!/usr/bin/env python3
# Grafici dal CSV di oddeven:  python3 scripts/grafici.py [CSV] [CARTELLA]   (oppure make grafici)
import csv
import os
import sys

FORME = ["piccoli", "grandi", "misti"]
TITOLI_FORMA = {
    "piccoli": "Segmenti piccoli (lunghezza 1-32)",
    "grandi":  "Segmenti grandi (lunghezza 1-N/16)",
    "misti":   "Misti (8 lunghi N/32-N/16, gli altri 1-32)",
}

BLU, ARANCIO, ACQUA, GIALLO, MAGENTA = "#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4"
GRIGIO, TESTO, TESTO2, GRIGLIA = "#52514e", "#0b0b0b", "#52514e", "#e4e3df"

STILI = {
    "S":          dict(color=GRIGIO,  linestyle="-",  marker="o"),
    "V1-static":  dict(color=BLU,     linestyle="-",  marker="o"),
    "V1-dynamic": dict(color=BLU,     linestyle="--", marker="s"),
    "V1-guided":  dict(color=BLU,     linestyle=":",  marker="^"),
    "V2":         dict(color=ARANCIO, linestyle="-",  marker="D"),
    "V3":         dict(color=ACQUA,   linestyle="-",  marker="o"),
    "V3-statica": dict(color=ACQUA,   linestyle="--", marker="s"),
    "V4":         dict(color=GIALLO,  linestyle="-",  marker="v"),
    "V4-shuffle": dict(color=GIALLO,  linestyle="--", marker="^"),
    "V5":         dict(color=MAGENTA, linestyle="-",  marker="P"),
    "V5-graph":   dict(color=MAGENTA, linestyle="--", marker="X"),
}
ORDINE = list(STILI)
V1 = ["V1-static", "V1-dynamic", "V1-guided"]
CORE_FISICI = 4
GPU = ["V2", "V3", "V4"]
TRATTO_T = {64: dict(linestyle="-", marker="o"), 128: dict(linestyle="--", marker="s"),
            256: dict(linestyle=":", marker="^")}
GRIGIO_CHIARO = "#c9c8c2"
VIOLA = "#6250d6"


def carica(path):
    righe = []
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            if r["t_ordinamento_ms"] == "":
                continue
            righe.append({
                "versione": r["versione"],
                "forma":    r["forma"],
                "N":        int(r["N"]),
                "thread":   int(r["thread"]),
                "t_ord":    float(r["t_ordinamento_ms"]),
                "t_tot":    float(r["t_totale_ms"]),
            })
    return righe


def migliori(righe, campo):
    best = {}
    for r in righe:
        per_n = best.setdefault((r["versione"], r["forma"]), {})
        t = r[campo]
        if r["N"] not in per_n or t < per_n[r["N"]][0]:
            per_n[r["N"]] = (t, r["thread"])
    return best


def tempi(best):
    return {forma: {v: {n: t for n, (t, _) in best[(v, forma)].items()}
                    for v in ORDINE if (v, forma) in best}
            for forma in FORME}


def speedup(best):
    out = {}
    for forma in FORME:
        s = best.get(("S", forma), {})
        out[forma] = {}
        for v in ORDINE:
            if v == "S" or (v, forma) not in best:
                continue
            out[forma][v] = {n: s[n][0] / t
                             for n, (t, _) in best[(v, forma)].items() if n in s and t > 0}
    return out


def stampa_riepilogo(best_ord):
    for forma in FORME:
        s = best_ord.get(("S", forma), {})
        if not s:
            continue
        n_max = max(s)
        print(f"\n{TITOLI_FORMA[forma]}, N = {n_max} (configurazione migliore, solo ordinamento)")
        print(f"  {'versione':<11} {'thread':>6} {'tempo [ms]':>12} {'speedup':>8}")
        for v in ORDINE:
            if (v, forma) not in best_ord:
                continue
            per_n = best_ord[(v, forma)]
            if n_max not in per_n:
                print(f"  {v:<11} {'':>6} {'n/d':>12}")
                continue
            t, thr = per_n[n_max]
            print(f"  {v:<11} {thr:>6} {t:>12.3f} {s[n_max][0] / t:>8.2f}")


def scaling_v1(righe):
    out = {}
    for forma in FORME:
        seriale = {r["N"]: r["t_ord"] for r in righe if r["versione"] == "S" and r["forma"] == forma}
        if not seriale:
            continue
        n_max = max(seriale)
        per_v = {}
        for r in righe:
            if r["versione"] in V1 and r["forma"] == forma and r["N"] == n_max and r["t_ord"] > 0:
                per_v.setdefault(r["versione"], {})[r["thread"]] = seriale[n_max] / r["t_ord"]
        out[forma] = (n_max, per_v)
    return out


def indice(righe):
    return {(r["versione"], r["forma"], r["N"], r["thread"]): r for r in righe}


def n_max_forma(righe, forma):
    return max(r["N"] for r in righe if r["versione"] == "S" and r["forma"] == forma)


def rapporto_per_t(righe, num, den):
    idx = indice(righe)
    out = {}
    for forma in FORME:
        out[forma] = {}
        for (v, f, n, t), r in idx.items():
            if v != num or f != forma or (den, f, n, t) not in idx:
                continue
            d = idx[(den, f, n, t)]["t_ord"]
            if d > 0:
                out[forma].setdefault(t, {})[n] = r["t_ord"] / d
    return out


def tacca(x):
    if x >= 1:
        return f"{x:,.0f}".replace(",", ".")
    return f"{x:g}".replace(".", ",")


def stile_assi(ax, titolo, etichetta_x, etichetta_y):
    ax.set_title(titolo, color=TESTO, fontsize=12)
    ax.set_xlabel(etichetta_x, color=TESTO2)
    ax.set_ylabel(etichetta_y, color=TESTO2)
    ax.grid(True, which="major", color=GRIGLIA, linewidth=0.8)
    ax.tick_params(colors=TESTO2, labelsize=9)
    for lato in ("top", "right"):
        ax.spines[lato].set_visible(False)
    for lato in ("left", "bottom"):
        ax.spines[lato].set_color(GRIGLIA)


def pannelli(plt):
    fig, assi = plt.subplots(1, len(FORME), figsize=(6.3 * len(FORME) + 0.5, 5.4))
    return fig, list(assi)


def chiudi_figura(plt, fig, assi, ordine_legenda, titolo, sottotitolo, nome_file, cartella,
                  sinistra=0.045, colonne=9, basso=0.2):
    voci = {}
    for ax in assi:
        for h, lab in zip(*ax.get_legend_handles_labels()):
            voci.setdefault(lab, h)
    etichette = [lab for lab in ordine_legenda if lab in voci]
    fig.legend([voci[lab] for lab in etichette], etichette, loc="lower center",
               ncol=min(len(etichette), colonne), frameon=False, fontsize=10)
    fig.suptitle(titolo, color=TESTO, fontsize=14, y=0.975)
    fig.text(0.5, 0.915, sottotitolo, ha="center", color=TESTO2, fontsize=9)
    fig.subplots_adjust(left=sinistra, right=0.985, top=0.83, bottom=basso, wspace=0.17)
    percorso = os.path.join(cartella, nome_file)
    fig.savefig(percorso, dpi=150, facecolor="white")
    plt.close(fig)
    print(f"scritto {percorso}")


def figura(plt, ticker, dati, titolo, etichetta_y, nome_file, cartella, riferimento_uno):
    fig, assi = pannelli(plt)
    numero = ticker.FuncFormatter(lambda x, _: tacca(x))

    for ax, forma in zip(assi, FORME):
        for v in ORDINE:
            punti = dati[forma].get(v)
            if not punti:
                continue
            xs = sorted(punti)
            ax.plot(xs, [punti[n] for n in xs], label=v, linewidth=2,
                    markersize=6, markeredgewidth=0, **STILI[v])
        if riferimento_uno:
            ax.axhline(1.0, color=GRIGIO, linewidth=1.2, linestyle=(0, (4, 3)),
                       label="S (seriale) = 1")
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.xaxis.set_major_formatter(numero)
        ax.yaxis.set_major_formatter(numero)
        stile_assi(ax, TITOLI_FORMA[forma], "N (coppie nel vettore X)", etichetta_y)

    chiudi_figura(plt, fig, assi, ORDINE + ["S (seriale) = 1"], titolo,
                  "Per ogni versione: numero di thread migliore tra quelli provati. "
                  "Confrontare le versioni dentro lo stesso pannello.", nome_file, cartella,
                  colonne=6, basso=0.22)


def figura_v1(plt, dati, efficienza, nome_file, cartella):
    fig, assi = pannelli(plt)
    tutti_thread = sorted({t for _, per_v in dati.values() for pv in per_v.values() for t in pv})

    for ax, forma in zip(assi, FORME):
        if forma not in dati:
            continue
        n_max, per_v = dati[forma]
        for v in V1:
            punti = per_v.get(v)
            if not punti:
                continue
            xs = sorted(punti)
            ys = [punti[t] / t if efficienza else punti[t] for t in xs]
            ax.plot(xs, ys, label=v, linewidth=2, markersize=7, markeredgewidth=0, **STILI[v])

        ideale = [1.0] * len(tutti_thread) if efficienza else tutti_thread
        ax.plot(tutti_thread, ideale, color=GRIGIO, linewidth=1.2, linestyle=(0, (4, 3)),
                label="ideale")
        ax.axvline(CORE_FISICI, color="#a9a8a2", linewidth=1.2, linestyle=":")
        ax.text(CORE_FISICI * 1.04, 0.97, f"{CORE_FISICI} core fisici", color=TESTO2, fontsize=9,
                va="top", transform=ax.get_xaxis_transform())

        ax.set_xscale("log", base=2)
        ax.set_xticks(tutti_thread)
        ax.set_xticklabels([str(t) for t in tutti_thread])
        ax.set_ylim(0, 1.15 if efficienza else max(tutti_thread) * 1.08)
        n_testo = f"{n_max:,}".replace(",", ".")
        stile_assi(ax, f"{TITOLI_FORMA[forma]}, N = {n_testo}",
                   "thread OpenMP (num_threads)",
                   "efficienza (speedup / thread)" if efficienza else "speedup (T_S / T_V1)")

    titolo = ("Efficienza di V1 (OpenMP) in funzione dei thread" if efficienza
              else "Strong scaling di V1 (OpenMP): speedup in funzione dei thread")
    chiudi_figura(plt, fig, assi, V1 + ["ideale"], titolo,
                  "Speedup rispetto al seriale S sullo stesso input. CPU: Ryzen 5 1500X, "
                  "4 core fisici x 2 thread (SMT).", nome_file, cartella)


def numero_it(x):
    testo = f"{x:,.1f}" if x < 10 else f"{x:,.0f}"
    return testo.replace(",", "#").replace(".", ",").replace("#", ".")


def figura_trasferimenti(plt, righe, nome_file, cartella):
    idx = indice(righe)
    n_scelti = [2000, 10000, 100000]
    fig, assi = pannelli(plt)
    larghezza = 0.26

    for ax, forma in zip(assi, FORME):
        for gi, n in enumerate(n_scelti):
            for vi, v in enumerate(GPU):
                x = gi + (vi - 1) * (larghezza + 0.03)
                candidati = [r for (vv, f, nn, _), r in idx.items() if vv == v and f == forma and nn == n]
                if not candidati:
                    ax.text(x, 2, "n/d", ha="center", va="bottom", color=TESTO2, fontsize=8)
                    continue
                r = min(candidati, key=lambda c: c["t_tot"])
                kernel = min(r["t_ord"], r["t_tot"])
                quota_k = 100.0 * kernel / r["t_tot"]
                ax.bar(x, quota_k, larghezza, color=STILI[v]["color"], label=f"{v}: kernel")
                ax.bar(x, 100.0 - quota_k, larghezza, bottom=quota_k, color=GRIGIO_CHIARO,
                       edgecolor="white", linewidth=1.5, label="allocazioni + copie")
                ax.text(x, 101.5, f"{numero_it(r['t_tot'])}\nms", ha="center", va="bottom",
                        color=TESTO2, fontsize=7.5)
        ax.set_xticks(range(len(n_scelti)))
        ax.set_xticklabels([f"N = {numero_it(n)}\nV2   V3   V4" for n in n_scelti])
        ax.set_ylim(0, 118)
        ax.set_yticks(range(0, 101, 20))
        ax.set_yticklabels([f"{y}%" for y in range(0, 101, 20)])
        stile_assi(ax, TITOLI_FORMA[forma], "", "quota del tempo totale")
        ax.grid(False, axis="x")

    chiudi_figura(plt, fig, assi, [f"{v}: kernel" for v in GPU] + ["allocazioni + copie"],
                  "GPU: tempo del kernel e tempo di allocazioni e copie",
                  "Per ogni versione e N: T con il tempo totale minimo. Sopra ogni barra il tempo "
                  "totale (cudaMalloc + copie + kernel + cudaFree).", nome_file, cartella)


def figura_thread_per_blocco(plt, righe, nome_file, cartella):
    idx = indice(righe)
    versioni = ["V2", "V3", "V3-statica"]
    fig, assi = pannelli(plt)
    tutti_t = sorted(TRATTO_T)

    for ax, forma in zip(assi, FORME):
        n = n_max_forma(righe, forma)
        for v in versioni:
            punti = {t: idx[(v, forma, n, t)]["t_ord"] for t in tutti_t if (v, forma, n, t) in idx}
            if punti:
                xs = sorted(punti)
                ax.plot(xs, [punti[t] for t in xs], label=v, linewidth=2, markersize=7,
                        markeredgewidth=0, **STILI[v])
        ax.set_xscale("log", base=2)
        ax.set_xticks(tutti_t)
        ax.set_xticklabels([str(t) for t in tutti_t])
        ax.set_ylim(bottom=0)
        stile_assi(ax, f"{TITOLI_FORMA[forma]}, N = {numero_it(n)}",
                   "thread per blocco (T)", "tempo di ordinamento [ms]")

    chiudi_figura(plt, fig, assi, versioni,
                  "GPU: effetto dei thread per blocco",
                  "Segmenti piccoli: pochi thread utili per segmento, conviene T piccolo. "
                  "Segmenti grandi: pochi blocchi, conviene T grande.", nome_file, cartella)


def figura_rapporto(plt, ticker, dati, colore, titolo, sottotitolo, etichetta_y, nome_file, cartella):
    fig, assi = pannelli(plt)
    numero = ticker.FuncFormatter(lambda x, _: tacca(x))
    massimo = max((y for per_t in dati.values() for pts in per_t.values() for y in pts.values()),
                  default=1.0)

    for ax, forma in zip(assi, FORME):
        for t in sorted(dati[forma]):
            punti = dati[forma][t]
            xs = sorted(punti)
            ax.plot(xs, [punti[n] for n in xs], color=colore, linewidth=2, markersize=6,
                    markeredgewidth=0, label=f"T = {t}", **TRATTO_T.get(t, {}))
        ax.axhline(1.0, color=GRIGIO, linewidth=1.2, linestyle=(0, (4, 3)), label="stesso tempo")
        ax.set_xscale("log")
        ax.xaxis.set_major_formatter(numero)
        ax.set_ylim(0, massimo * 1.1)
        stile_assi(ax, TITOLI_FORMA[forma], "N (coppie nel vettore X)", etichetta_y)

    chiudi_figura(plt, fig, assi, [f"T = {t}" for t in sorted(TRATTO_T)] + ["stesso tempo"],
                  titolo, sottotitolo, nome_file, cartella)


def figura_warp(plt, ticker, righe, nome_file, cartella):
    idx = indice(righe)
    forma = "piccoli"
    fig, ax = plt.subplots(1, 1, figsize=(9, 5.6))
    numero = ticker.FuncFormatter(lambda x, _: tacca(x))
    ordine = []

    for v in ["V2", "V3"]:
        for t in sorted(TRATTO_T):
            punti = {n: r["t_ord"] for (vv, f, n, tt), r in idx.items() if vv == v and f == forma and tt == t}
            if punti:
                xs = sorted(punti)
                etichetta = f"{v}, T = {t}"
                ordine.append(etichetta)
                ax.plot(xs, [punti[n] for n in xs], color=STILI[v]["color"], linewidth=2,
                        markersize=5, markeredgewidth=0, label=etichetta, **TRATTO_T[t])
    for v, etichetta in [("V4", "V4 (warp, shared)"), ("V4-shuffle", "V4-shuffle (warp, registri)")]:
        punti = {n: r["t_ord"] for (vv, f, n, _), r in idx.items() if vv == v and f == forma}
        if punti:
            xs = sorted(punti)
            ordine.append(etichetta)
            ax.plot(xs, [punti[n] for n in xs], linewidth=2.5, markersize=7, markeredgewidth=0,
                    label=etichetta, **STILI[v])

    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.xaxis.set_major_formatter(numero)
    ax.yaxis.set_major_formatter(numero)
    stile_assi(ax, TITOLI_FORMA[forma], "N (coppie nel vettore X)", "tempo di ordinamento [ms]")
    chiudi_figura(plt, fig, [ax], ordine, "Warp contro blocco sui segmenti piccoli",
                  "V2 e V3: un blocco di T thread per segmento. V4: un warp per segmento "
                  "(segmento in shared). V4-shuffle: come V4, segmento nei registri.", nome_file, cartella, sinistra=0.1, colonne=3, basso=0.29)


def figura_v5(plt, ticker, best, nome_file, cartella):
    fig, assi = pannelli(plt)
    numero = ticker.FuncFormatter(lambda x, _: tacca(x))
    etichette = {"S": "S (seriale)", "V1": "V1 (schedule e thread migliori)",
                 "V2": "V2 (un lancio)", "V3": "V3 (un lancio)", "V5": "V5 (un kernel per segmento)"}

    for ax, forma in zip(assi, FORME):
        serie = {}
        for v in ["S", "V2", "V3", "V5"]:
            if (v, forma) in best:
                serie[v] = {n: t for n, (t, _) in best[(v, forma)].items()}
        v1 = {}
        for v in V1:
            for n, (t, _) in best.get((v, forma), {}).items():
                v1[n] = min(t, v1.get(n, t))
        if v1:
            serie["V1"] = v1
        for v in ["S", "V1", "V2", "V3", "V5"]:
            punti = serie.get(v)
            if not punti:
                continue
            xs = sorted(punti)
            stile = STILI["V1-static"] if v == "V1" else STILI[v]
            ax.plot(xs, [punti[n] for n in xs], label=etichette[v], linewidth=2.5 if v == "V5" else 2,
                    markersize=7 if v == "V5" else 6, markeredgewidth=0, **stile)
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.xaxis.set_major_formatter(numero)
        ax.yaxis.set_major_formatter(numero)
        stile_assi(ax, TITOLI_FORMA[forma], "N (coppie nel vettore X)", "tempo di ordinamento [ms]")

    chiudi_figura(plt, fig, assi, [etichette[v] for v in ["S", "V1", "V2", "V3", "V5"]],
                  "Un kernel per segmento (V5) contro un solo lancio",
                  "V5: un lancio per segmento su 32 stream (circa 3,6 us a lancio). "
                  "Per ogni versione la configurazione migliore.", nome_file, cartella, colonne=5)


def figura_v5_graph(plt, ticker, best_ord, best_tot, nome_file, cartella):
    fig, assi = pannelli(plt)
    numero = ticker.FuncFormatter(lambda x, _: tacca(x))
    marcatore = {"V5": "P", "V5-graph": "X"}
    colore = {"V5": MAGENTA, "V5-graph": VIOLA}
    nomi = {"V5": "V5 (stream)", "V5-graph": "V5-graph"}
    ordine = []

    for ax, forma in zip(assi, FORME):
        for v in ["V5", "V5-graph"]:
            for best, tratto, quale in [(best_ord, "-", "ordinamento"), (best_tot, "--", "totale")]:
                punti = {n: t for n, (t, _) in best.get((v, forma), {}).items()}
                if not punti:
                    continue
                etichetta = f"{nomi[v]}, {quale}"
                if etichetta not in ordine:
                    ordine.append(etichetta)
                xs = sorted(punti)
                ax.plot(xs, [punti[n] for n in xs], color=colore[v],
                        linestyle=tratto, marker=marcatore[v], linewidth=2, markersize=8,
                        markeredgewidth=0, label=etichetta)
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.xaxis.set_major_formatter(numero)
        ax.yaxis.set_major_formatter(numero)
        stile_assi(ax, TITOLI_FORMA[forma], "N (coppie nel vettore X)", "tempo [ms]")

    chiudi_figura(plt, fig, assi, ordine, "Un kernel per segmento: stream contro CUDA graph",
                  "Linea piena: solo ordinamento (esecuzione dei kernel). Tratteggiata: tempo totale "
                  "(per il grafo comprende costruzione e istanziazione).", nome_file, cartella, colonne=4)


def main():
    csv_path = sys.argv[1] if len(sys.argv) > 1 else "results/risultati.csv"
    cartella = sys.argv[2] if len(sys.argv) > 2 else "results/grafici"

    righe = carica(csv_path)
    if not righe:
        sys.exit(f"nessuna riga valida in {csv_path}: eseguire prima  make run")
    best_ord = migliori(righe, "t_ord")
    best_tot = migliori(righe, "t_tot")
    stampa_riepilogo(best_ord)

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        import matplotlib.ticker as ticker
    except ImportError:
        sys.exit("\nmanca matplotlib: installarlo con  sudo apt install python3-matplotlib")

    os.makedirs(cartella, exist_ok=True)
    figura(plt, ticker, tempi(best_ord),
           "Tempo di ordinamento in funzione di N", "tempo di ordinamento [ms]",
           "01_tempo_ordinamento.png", cartella, riferimento_uno=False)
    figura(plt, ticker, speedup(best_ord),
           "Speedup del solo ordinamento rispetto al seriale", "speedup (T_S / T_versione)",
           "02_speedup_ordinamento.png", cartella, riferimento_uno=True)
    figura(plt, ticker, speedup(best_tot),
           "Speedup del tempo totale (GPU: con allocazioni e copie)", "speedup (T_S / T_versione)",
           "03_speedup_totale.png", cartella, riferimento_uno=True)

    scaling = scaling_v1(righe)
    figura_v1(plt, scaling, False, "04_scaling_V1.png", cartella)
    figura_v1(plt, scaling, True, "05_efficienza_V1.png", cartella)

    figura_trasferimenti(plt, righe, "06_trasferimenti_GPU.png", cartella)
    figura_thread_per_blocco(plt, righe, "07_thread_per_blocco.png", cartella)
    figura_rapporto(plt, ticker, rapporto_per_t(righe, "V2", "V3"), ACQUA,
                    "Memoria globale contro shared: quante volte V2 e' piu' lenta di V3",
                    "Stesso input e stesso T. Sopra 1: la shared (V3) e' piu' veloce.",
                    "T_V2 / T_V3 (solo ordinamento)", "08_globale_vs_shared.png", cartella)
    figura_rapporto(plt, ticker, rapporto_per_t(righe, "V3-statica", "V3"), ACQUA,
                    "Shared statica contro dinamica: quante volte V3-statica e' piu' lenta",
                    "Stesso input e stesso T. Sopra 1: la shared dinamica (V3) e' piu' veloce.",
                    "T_V3-statica / T_V3 (solo ordinamento)",
                    "09_shared_dinamica_vs_statica.png", cartella)
    figura_warp(plt, ticker, righe, "10_warp_vs_blocco.png", cartella)

    figura_v5(plt, ticker, best_ord, "11_lanci_V5.png", cartella)
    figura_v5_graph(plt, ticker, best_ord, best_tot, "12_V5_stream_vs_graph.png", cartella)


if __name__ == "__main__":
    main()
