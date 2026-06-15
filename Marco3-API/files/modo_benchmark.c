/*
 * modo_benchmark.c - Modo 3: validacao e benchmark de N imagens PNG.
 *
 * Le PNGs diretamente da pasta test/ usando stb_image.
 * Estrutura esperada:
 *   <mif_dir>/<digito>/<arquivo>.png
 *   ex: ../../Marco2-driver/mif_files/mnist_png/test/7/1234.png
 *
 * Usa --offset para selecionar fatias diferentes sem repeticao:
 *   --offset 0   -> primeiras 100 imagens de cada digito
 *   --offset 100 -> proximas 100 imagens de cada digito
 *
 * Fluxo:
 *   1. Lista os PNGs de cada digito em ordem alfabetica
 *   2. Seleciona n_por_digito arquivos a partir do offset
 *   3. Carrega cada PNG com stb_image (grayscale 28x28)
 *   4. Envia ao CoProcessor com elm_reset antes de cada inferencia
 *   5. Calcula acuracia global + por digito + latencia
 *   6. Salva log CSV
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <dirent.h>
#include "app.h"
#include "vga.h"
#include "elm.h"
#include "stb_image.h"

#define MAX_POR_DIGITO 1100

static double ts_diff_ms(const struct timespec *a, const struct timespec *b)
{
    return (b->tv_sec  - a->tv_sec ) * 1000.0
         + (b->tv_nsec - a->tv_nsec) / 1.0e6;
}

static void calc_stats(double *lat, int n,
                       double *media, double *stdev,
                       double *vmin,  double *vmax)
{
    int i;
    double soma = 0;
    *vmin = lat[0]; *vmax = lat[0];
    for (i = 0; i < n; i++) {
        soma += lat[i];
        if (lat[i] < *vmin) *vmin = lat[i];
        if (lat[i] > *vmax) *vmax = lat[i];
    }
    *media = soma / n;
    double var = 0;
    for (i = 0; i < n; i++) {
        double d = lat[i] - *media;
        var += d * d;
    }
    *stdev = sqrt(var / n);
}

static int cmp_str(const void *a, const void *b)
{
    return strcmp(*(const char **)a, *(const char **)b);
}

static int listar_pngs(const char *dir, char **lista, int max)
{
    DIR *dp = opendir(dir);
    if (!dp) return 0;
    int n = 0;
    struct dirent *entry;
    while ((entry = readdir(dp)) != NULL && n < max) {
        const char *nome = entry->d_name;
        int len = strlen(nome);
        if (len > 4 && strcmp(nome + len - 4, ".png") == 0) {
            lista[n] = malloc(strlen(dir) + 1 + len + 1);
            if (!lista[n]) break;
            sprintf(lista[n], "%s/%s", dir, nome);
            n++;
        }
    }
    closedir(dp);
    qsort(lista, n, sizeof(char *), cmp_str);
    return n;
}

static int carregar_png(const char *path, uint8_t img[IMG_PIXELS])
{
    int w, h, ch;
    unsigned char *data = stbi_load(path, &w, &h, &ch, 1);
    if (!data) {
        fprintf(stderr, "  stbi_load falhou: %s\n", path);
        return APP_ERR;
    }
    if (w == 28 && h == 28) {
        memcpy(img, data, IMG_PIXELS);
    } else {
        int x, y;
        for (y = 0; y < 28; y++)
            for (x = 0; x < 28; x++) {
                int sx = x * w / 28;
                int sy = y * h / 28;
                img[y * 28 + x] = data[sy * w + sx];
            }
    }
    stbi_image_free(data);
    return APP_OK;
}

int modo_benchmark(elm_t *elm, vga_t *vga, const app_config_t *cfg)
{
    printf("\n==========================================\n");
    printf("  Modo 3 - Benchmark / Validacao (PNG)\n");
    printf("==========================================\n\n");

    int n_por_digito = cfg->n_imagens / 10;
    if (n_por_digito < 1) n_por_digito = 1;
    int offset    = cfg->offset;
    int total_max = n_por_digito * 10;

    printf("  Diretorio: %s\n", cfg->mif_dir);
    printf("  Imagens:   %d (%d por digito)\n", total_max, n_por_digito);
    printf("  Offset:    %d (indices %d a %d)\n",
           offset, offset, offset + n_por_digito - 1);
    printf("  Log:       %s\n\n", cfg->log_path);

    double  *latencias = malloc(total_max * sizeof(double));
    int     *corretos  = malloc(total_max * sizeof(int));
    uint8_t *preds     = malloc(total_max * sizeof(uint8_t));
    if (!latencias || !corretos || !preds) {
        fprintf(stderr, "Erro: malloc falhou\n");
        free(latencias); free(corretos); free(preds);
        return APP_ERR;
    }

    FILE *csv = fopen(cfg->log_path, "w");
    if (!csv) {
        perror("fopen log");
        free(latencias); free(corretos); free(preds);
        return APP_ERR;
    }
    fprintf(csv, "indice,arquivo,esperado,predito,correto,latencia_ms\n");

    int acertos_dig[10] = {0};
    int total_dig[10]   = {0};
    int n_validos = 0;
    int n_acertos = 0;
    int d, i;

    char **lista = malloc(MAX_POR_DIGITO * sizeof(char *));
    if (!lista) {
        fprintf(stderr, "Erro: malloc lista falhou\n");
        fclose(csv);
        free(latencias); free(corretos); free(preds);
        return APP_ERR;
    }

    for (d = 0; d < 10; d++) {
        char dir_digito[512];
        snprintf(dir_digito, sizeof(dir_digito), "%s/%d", cfg->mif_dir, d);

        int n_pngs = listar_pngs(dir_digito, lista, MAX_POR_DIGITO);
        if (n_pngs == 0) {
            fprintf(stderr, "  Digito %d: nenhum PNG em %s\n", d, dir_digito);
            continue;
        }

        if (offset >= n_pngs) {
            fprintf(stderr, "  Digito %d: offset %d >= total %d - pulando\n",
                    d, offset, n_pngs);
            for (i = 0; i < n_pngs; i++) free(lista[i]);
            continue;
        }

        int fim = offset + n_por_digito;
        if (fim > n_pngs) fim = n_pngs;

        printf("  Digito %d: %d PNGs, usando [%d..%d]\n",
               d, n_pngs, offset, fim - 1);

        for (i = offset; i < fim; i++) {
            uint8_t img[IMG_PIXELS];
            if (carregar_png(lista[i], img) != APP_OK) continue;

            vga_draw_image(vga, img);
            elm_reset(elm);

            struct timespec t0, t1;
            uint8_t pred = 0;
            clock_gettime(CLOCK_MONOTONIC, &t0);
            int rc = elm_classify(elm, img, &pred);
            clock_gettime(CLOCK_MONOTONIC, &t1);

            if (rc != ELM_OK) {
                fprintf(stderr, "  [d=%d i=%d] elm_classify falhou\n", d, i);
                continue;
            }

            double lat = ts_diff_ms(&t0, &t1);
            int correto = (pred == (uint8_t)d);

            latencias[n_validos] = lat;
            corretos[n_validos]  = correto;
            preds[n_validos]     = pred;

            if (correto) { n_acertos++; acertos_dig[d]++; }
            total_dig[d]++;
            n_validos++;

            fprintf(csv, "%d,%s,%d,%d,%d,%.4f\n",
                    n_validos - 1, lista[i], d, pred, correto, lat);

            printf("  [%d|%03d] esp=%d pred=%d %s  %.2f ms\n",
                   d, i, d, pred, correto ? "OK" : "X", lat);
        }

        for (i = 0; i < n_pngs; i++) free(lista[i]);
    }

    free(lista);
    fclose(csv);

    if (n_validos == 0) {
        fprintf(stderr, "Nenhuma imagem valida processada.\n");
        free(latencias); free(corretos); free(preds);
        return APP_ERR;
    }

    double media, stdev, vmin, vmax;
    calc_stats(latencias, n_validos, &media, &stdev, &vmin, &vmax);
    double acuracia_global = 100.0 * n_acertos / n_validos;
    double throughput      = 1000.0 / media;

    printf("\n==========================================\n");
    printf("  Acuracia por Digito\n");
    printf("==========================================\n");
    printf("  Digito | Acertos | Total | Acuracia\n");
    printf("  -------+---------+-------+---------\n");
    for (d = 0; d < 10; d++) {
        double acc = total_dig[d] > 0
                     ? 100.0 * acertos_dig[d] / total_dig[d] : 0.0;
        printf("    %d    |   %4d  |  %4d |  %6.2f%%\n",
               d, acertos_dig[d], total_dig[d], acc);
    }
    printf("==========================================\n");
    printf("  Resultado Global\n");
    printf("==========================================\n");
    printf("  Imagens processadas: %d\n", n_validos);
    printf("  Acertos:             %d\n", n_acertos);
    printf("  Acuracia global:     %.2f%%\n", acuracia_global);
    printf("------------------------------------------\n");
    printf("  Latencia media:      %.3f ms\n", media);
    printf("  Desvio padrao:       %.3f ms\n", stdev);
    printf("  Minima:              %.3f ms\n", vmin);
    printf("  Maxima:              %.3f ms\n", vmax);
    printf("  Throughput:          %.1f img/s\n", throughput);
    printf("------------------------------------------\n");
    printf("  Log salvo em: %s\n", cfg->log_path);
    printf("==========================================\n\n");

    free(latencias); free(corretos); free(preds);
    return APP_OK;
}
