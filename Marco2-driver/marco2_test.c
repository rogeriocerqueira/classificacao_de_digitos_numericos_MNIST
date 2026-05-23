/*
 * marco2_test.c — programa de validação do Marco 2.
 *
 * Cumpre o requisito do enunciado:
 *   "enviar 1 imagem fixa e obter classificação correta repetidamente
 *    (estabilidade)"
 *
 * Carrega pesos, bias, beta e a imagem fixa a partir dos arquivos .mif
 * fornecidos pelo projeto, envia ao coprocessador via o driver, e
 * dispara N inferências verificando que todas devolvem a mesma classe.
 *
 * Uso:
 *   sudo ./marco2_test [-d mif_dir] [-n N] [-e classe_esperada]
 *
 * Saída: linhas de progresso, estatísticas finais e PASS/FAIL.
 */

#define _POSIX_C_SOURCE  200809L  /* CLOCK_MONOTONIC, clock_gettime */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <math.h>
#include <unistd.h>
#include <getopt.h>

#include "elm.h"
#include "elm_mif.h"

#define DEFAULT_MIF_DIR  "."
#define DEFAULT_ITERS    100

static double ts_diff_ms(const struct timespec *a, const struct timespec *b)
{
    return (b->tv_sec  - a->tv_sec ) * 1000.0
         + (b->tv_nsec - a->tv_nsec) / 1.0e6;
}

/* Carrega um .mif Q4.12 esperando uma quantidade específica de entradas */
static int load_q4_12_expect(const char *path, size_t expected,
                             int16_t **out_data)
{
    size_t sz = 0;
    int rc = elm_mif_load_q4_12(path, out_data, &sz);
    if (rc != ELM_MIF_OK) {
        fprintf(stderr, "  ERRO: %s (código %d)\n", path, rc);
        return rc;
    }
    if (sz != expected) {
        fprintf(stderr, "  ERRO: %s tem %zu entradas, esperado %zu\n",
                path, sz, expected);
        free(*out_data); *out_data = NULL;
        return -1;
    }
    printf("  %s: %zu entradas carregadas\n", path, sz);
    return ELM_MIF_OK;
}

static int upload_weights(elm_t *e, const char *dir)
{
    char path[512];
    int16_t *bias = NULL, *beta = NULL, *W = NULL;
    int rc = -1;
    struct timespec t0, t1;

    /* bias */
    snprintf(path, sizeof(path), "%s/mem_bias.mif", dir);
    if (load_q4_12_expect(path, ELM_HIDDEN_NEURONS, &bias) != ELM_MIF_OK)
        goto cleanup;

    printf("  enviando %d biases...\n", ELM_HIDDEN_NEURONS);
    for (size_t i = 0; i < ELM_HIDDEN_NEURONS; i++) {
        rc = elm_store_bias(e, (uint8_t)i, bias[i]);
        if (rc != ELM_OK) {
            fprintf(stderr, "  ERRO: elm_store_bias[%zu] = %d\n", i, rc);
            goto cleanup;
        }
    }

    /* beta */
    snprintf(path, sizeof(path), "%s/mem_beta.mif", dir);
    if (load_q4_12_expect(path, ELM_BETA_SIZE, &beta) != ELM_MIF_OK)
        goto cleanup;

    printf("  enviando %d betas...\n", ELM_BETA_SIZE);
    for (size_t i = 0; i < ELM_BETA_SIZE; i++) {
        rc = elm_store_beta(e, (uint16_t)i, beta[i]);
        if (rc != ELM_OK) {
            fprintf(stderr, "  ERRO: elm_store_beta[%zu] = %d\n", i, rc);
            goto cleanup;
        }
    }

    /* pesos (o grandão) */
    snprintf(path, sizeof(path), "%s/mem_win.mif", dir);
    if (load_q4_12_expect(path, ELM_W_SIZE, &W) != ELM_MIF_OK)
        goto cleanup;

    printf("  enviando %d pesos (pode levar alguns segundos)...\n",
           ELM_W_SIZE);
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (size_t i = 0; i < ELM_W_SIZE; i++) {
        rc = elm_store_weight(e, (uint32_t)i, W[i]);
        if (rc != ELM_OK) {
            fprintf(stderr, "\n  ERRO: elm_store_weight[%zu] = %d\n", i, rc);
            goto cleanup;
        }
        if ((i & 0x1FFFu) == 0) {
            printf("    %zu/%d (%.1f%%)\r", i, ELM_W_SIZE,
                   100.0 * i / ELM_W_SIZE);
            fflush(stdout);
        }
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    printf("    %d/%d (100.0%%)\n", ELM_W_SIZE, ELM_W_SIZE);
    printf("  pesos enviados em %.2f s\n", ts_diff_ms(&t0, &t1) / 1000.0);

    rc = ELM_OK;

cleanup:
    free(bias);
    free(beta);
    free(W);
    return rc;
}

int main(int argc, char **argv)
{
    const char *mif_dir = DEFAULT_MIF_DIR;
    int iters    = DEFAULT_ITERS;
    int expected = -1;

    int opt;
    while ((opt = getopt(argc, argv, "d:n:e:h")) != -1) {
        switch (opt) {
        case 'd': mif_dir  = optarg;        break;
        case 'n': iters    = atoi(optarg);  break;
        case 'e': expected = atoi(optarg);  break;
        case 'h':
        default:
            fprintf(stderr,
              "Uso: %s [-d mif_dir] [-n N_iters] [-e classe_esperada]\n",
              argv[0]);
            return 1;
        }
    }

    if (iters < 1) iters = 1;

    printf("===== Marco 2 — Teste de Estabilidade =====\n");
    printf("  diretório .mif: %s\n", mif_dir);
    printf("  iterações:      %d\n", iters);
    if (expected >= 0) printf("  classe esperada: %d\n", expected);
    printf("\n");

    elm_t e;
    int rc = elm_open(&e);
    if (rc != ELM_OK) {
        fprintf(stderr, "ERRO: elm_open falhou (rc=%d). "
                "Confirme que você é root e que /dev/mem está acessível.\n",
                rc);
        return 2;
    }
    printf("[1/4] Driver aberto. status inicial = 0x%08x\n\n",
           *e.data_out);

    printf("[2/4] Carregando e enviando pesos/bias/beta...\n");
    rc = upload_weights(&e, mif_dir);
    if (rc != ELM_OK) {
        elm_close(&e);
        return 3;
    }
    printf("\n");

    char path[512];
    snprintf(path, sizeof(path), "%s/mem_img.mif", mif_dir);
    uint8_t *img = NULL;
    size_t img_sz = 0;
    rc = elm_mif_load_image(path, &img, &img_sz);
    if (rc != ELM_MIF_OK) {
        fprintf(stderr, "ERRO: %s (rc=%d)\n", path, rc);
        elm_close(&e); return 4;
    }
    if (img_sz != ELM_IMAGE_PIXELS) {
        fprintf(stderr, "ERRO: imagem tem %zu pixels, esperado %d\n",
                img_sz, ELM_IMAGE_PIXELS);
        free(img); elm_close(&e); return 5;
    }
    printf("[3/4] Imagem %s: %zu pixels carregados\n\n", path, img_sz);

    printf("[4/4] Rodando %d inferências...\n", iters);
    uint8_t  first_pred = 0;
    int      unstable   = 0;
    int      errors     = 0;
    double  *latencies  = (double *)malloc((size_t)iters * sizeof(double));
    int      n_valid    = 0;

    for (int i = 0; i < iters; i++) {
        uint8_t pred = 0;
        struct timespec t0, t1;
        clock_gettime(CLOCK_MONOTONIC, &t0);
        rc = elm_classify(&e, img, &pred);
        clock_gettime(CLOCK_MONOTONIC, &t1);

        if (rc != ELM_OK) {
            errors++;
            fprintf(stderr, "  iter %4d: ERRO rc=%d status=0x%08x\n",
                    i, rc, *e.data_out);
            continue;
        }

        latencies[n_valid++] = ts_diff_ms(&t0, &t1);

        if (i == 0) {
            first_pred = pred;
            printf("  iter %4d: pred=%u (latência: %.2f ms) [referência]\n",
                   i, pred, latencies[0]);
        } else if (pred != first_pred) {
            unstable++;
            fprintf(stderr, "  iter %4d: INSTABILIDADE pred=%u (esperava %u)\n",
                    i, pred, first_pred);
        }
    }

    /* Estatísticas */
    double sum = 0;
    for (int i = 0; i < n_valid; i++) sum += latencies[i];
    double mean = n_valid ? sum / n_valid : 0;
    double var = 0;
    for (int i = 0; i < n_valid; i++) {
        double d = latencies[i] - mean;
        var += d * d;
    }
    double stdev = n_valid ? sqrt(var / n_valid) : 0;
    double min = latencies[0], max = latencies[0];
    for (int i = 1; i < n_valid; i++) {
        if (latencies[i] < min) min = latencies[i];
        if (latencies[i] > max) max = latencies[i];
    }

    printf("\n===== Resultado =====\n");
    printf("  iterações executadas: %d\n", iters);
    printf("  com erro de hardware: %d\n", errors);
    printf("  com instabilidade:    %d\n", unstable);
    printf("  latência média:       %.3f ms\n", mean);
    printf("  latência sigma:       %.3f ms\n", stdev);
    printf("  latência min/max:     %.3f / %.3f ms\n", min, max);
    printf("  throughput:           %.1f img/s\n",
           mean > 0 ? 1000.0 / mean : 0);
    printf("  predição:             %u\n", first_pred);

    int pass = (errors == 0) && (unstable == 0);
    if (expected >= 0) {
        if (first_pred == (uint8_t)expected) {
            printf("  classificação:        CORRETA (esperado %d)\n",
                   expected);
        } else {
            printf("  classificação:        INCORRETA "
                   "(predito %u, esperado %d)\n", first_pred, expected);
            pass = 0;
        }
    }

    printf("\n%s\n", pass ? "PASS" : "FAIL");

    free(latencies);
    free(img);
    elm_close(&e);
    return pass ? 0 : 1;
}
