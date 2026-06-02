/*
 * modo_benchmark.c — Modo 3: validação e benchmark de N imagens.
 *
 * Fluxo:
 *   1. Para cada dígito 0–9 carrega imagem_X.mif do diretório
 *   2. Roda N/10 inferências por dígito (ou N imagens no total)
 *   3. Mede latência individual com clock_gettime
 *   4. Computa: acurácia, latência média, desvio padrão, throughput
 *   5. Exibe cada imagem no VGA durante a inferência
 *   6. Salva log CSV
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "app.h"
#include "vga.h"
#include "../Marco2-driver/elm.h"
#include "../Marco2-driver/elm_mif.h"

/* ── Helper: diferença de tempo em ms ─────────────────── */
static double ts_diff_ms(const struct timespec *a, const struct timespec *b)
{
    return (b->tv_sec  - a->tv_sec ) * 1000.0
         + (b->tv_nsec - a->tv_nsec) / 1.0e6;
}

/* ── Estatísticas ──────────────────────────────────────── */
static void calc_stats(double *lat, int n,
                       double *media, double *stdev,
                       double *vmin,  double *vmax)
{
    double soma = 0;
    *vmin = lat[0]; *vmax = lat[0];
    for (int i = 0; i < n; i++) {
        soma += lat[i];
        if (lat[i] < *vmin) *vmin = lat[i];
        if (lat[i] > *vmax) *vmax = lat[i];
    }
    *media = soma / n;
    double var = 0;
    for (int i = 0; i < n; i++) {
        double d = lat[i] - *media;
        var += d * d;
    }
    *stdev = sqrt(var / n);
}

int modo_benchmark(elm_t *elm, vga_t *vga, const app_config_t *cfg)
{
    printf("\n╔══════════════════════════════════════╗\n");
    printf("║  Modo 3 — Benchmark / Validação      ║\n");
    printf("╚══════════════════════════════════════╝\n\n");
    printf("  Diretório: %s\n", cfg->mif_dir);
    printf("  Imagens:   %d\n", cfg->n_imagens);
    printf("  Log:       %s\n\n", cfg->log_path);

    /* ── Aloca arrays de resultado ──────────────────── */
    double  *latencias = malloc(cfg->n_imagens * sizeof(double));
    int     *corretos  = malloc(cfg->n_imagens * sizeof(int));
    uint8_t *preds     = malloc(cfg->n_imagens * sizeof(uint8_t));
    if (!latencias || !corretos || !preds) {
        fprintf(stderr, "Erro: malloc falhou\n");
        return APP_ERR;
    }

    /* ── Abre CSV ────────────────────────────────────── */
    FILE *csv = fopen(cfg->log_path, "w");
    if (!csv) {
        perror("fopen log");
        free(latencias); free(corretos); free(preds);
        return APP_ERR;
    }
    fprintf(csv, "indice,arquivo,esperado,predito,correto,latencia_ms\n");

    /* ── Loop principal ──────────────────────────────── */
    int n_validos = 0;
    int n_acertos = 0;

    for (int i = 0; i < cfg->n_imagens; i++) {
        /* Determina qual dígito esperado (cicla 0–9) */
        int esperado = i % 10;
        char path[512];
        snprintf(path, sizeof(path), "%s/imagem_%d.mif",
                 cfg->mif_dir, esperado);

        /* Carrega imagem */
        uint8_t *img = NULL;
        size_t   sz  = 0;
        int rc = elm_mif_load_image(path, &img, &sz);
        if (rc != ELM_MIF_OK || sz != IMG_PIXELS) {
            fprintf(stderr, "  [%3d] Erro ao carregar %s — pulando\n",
                    i, path);
            if (img) free(img);
            continue;
        }

        /* Exibe no VGA */
        vga_draw_image(vga, img);

        /* Inferência com medição de latência */
        struct timespec t0, t1;
        uint8_t pred = 0;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        rc = elm_classify(elm, img, &pred);
        clock_gettime(CLOCK_MONOTONIC, &t1);

        if (rc != ELM_OK) {
            fprintf(stderr, "  [%3d] elm_classify falhou\n", i);
            free(img);
            continue;
        }

        double lat = ts_diff_ms(&t0, &t1);
        int correto = (pred == (uint8_t)esperado);

        latencias[n_validos] = lat;
        corretos[n_validos]  = correto;
        preds[n_validos]     = pred;
        if (correto) n_acertos++;
        n_validos++;

        /* Grava no CSV */
        fprintf(csv, "%d,%s,%d,%d,%d,%.4f\n",
                i, path, esperado, pred, correto, lat);

        /* Feedback no terminal */
        printf("  [%3d] esperado=%d pred=%d %s  %.2f ms\n",
               i, esperado, pred,
               correto ? "✓" : "✗", lat);

        free(img);
    }

    fclose(csv);

    if (n_validos == 0) {
        fprintf(stderr, "Nenhuma imagem válida processada.\n");
        free(latencias); free(corretos); free(preds);
        return APP_ERR;
    }

    /* ── Calcula estatísticas ────────────────────────── */
    double media, stdev, vmin, vmax;
    calc_stats(latencias, n_validos, &media, &stdev, &vmin, &vmax);

    double acuracia   = 100.0 * n_acertos / n_validos;
    double throughput = 1000.0 / media;

    /* ── Imprime relatório ───────────────────────────── */
    printf("\n╔══════════════════════════════════════════╗\n");
    printf("║  Resultado do Benchmark                  ║\n");
    printf("╠══════════════════════════════════════════╣\n");
    printf("║  Imagens processadas: %-6d             ║\n", n_validos);
    printf("║  Acertos:             %-6d             ║\n", n_acertos);
    printf("║  Acurácia:            %6.2f%%            ║\n", acuracia);
    printf("╠══════════════════════════════════════════╣\n");
    printf("║  Latência média:      %7.3f ms          ║\n", media);
    printf("║  Desvio padrão:       %7.3f ms          ║\n", stdev);
    printf("║  Mínima:              %7.3f ms          ║\n", vmin);
    printf("║  Máxima:              %7.3f ms          ║\n", vmax);
    printf("║  Throughput:          %7.1f img/s       ║\n", throughput);
    printf("╠══════════════════════════════════════════╣\n");
    printf("║  Log salvo em: %-26s║\n", cfg->log_path);
    printf("╚══════════════════════════════════════════╝\n\n");

    free(latencias); free(corretos); free(preds);
    return APP_OK;
}
