 * modo_arquivo.c — Modo 1: inferência a partir de arquivo .mif.
 *
 * Fluxo:
 *   1. Lê imagem do arquivo .mif (elm_mif_load_image)
 *   2. Exibe a imagem no VGA (vga_draw_image)
 *   3. Envia ao CoProcessor via driver Marco 2 (elm_classify)
 *   4. Imprime resultado no terminal
 *   5. Exibe dígito predito no VGA (texto simples)
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "app.h"
#include "vga.h"
#include "elm.h"        // em vez de "../../../Marco2-driver/elm.h"
#include "elm_mif.h"    // em vez de "../../../Marco2-driver/elm_mif.h"

int modo_arquivo(elm_t *elm, vga_t *vga, const app_config_t *cfg)
{
    printf("\n╔══════════════════════════════════════╗\n");
    printf("║  Modo 1 — Inferência por Arquivo     ║\n");
    printf("╚══════════════════════════════════════╝\n\n");

    /* ── 1. Carrega imagem do .mif ──────────────────── */
    uint8_t *img  = NULL;
    size_t   img_sz = 0;

    int rc = elm_mif_load_image(cfg->img_path, &img, &img_sz);
    if (rc != ELM_MIF_OK) {
        fprintf(stderr, "Erro: não foi possível ler %s (rc=%d)\n",
                cfg->img_path, rc);
        return APP_ERR;
    }
    if (img_sz != IMG_PIXELS) {
        fprintf(stderr, "Erro: imagem tem %zu pixels, esperado %d\n",
                img_sz, IMG_PIXELS);
        free(img);
        return APP_ERR;
    }
    printf("Imagem carregada: %s (%zu pixels)\n", cfg->img_path, img_sz);

    /* ── 2. Exibe no VGA ────────────────────────────── */
    printf("Exibindo no VGA...\n");
    vga_draw_image(vga, img);

    /* ── 3. Envia ao CoProcessor ────────────────────── */
    printf("Enviando ao CoProcessor...\n");
    uint8_t pred = 0;
    rc = elm_classify(elm, img, &pred);
    if (rc != ELM_OK) {
        fprintf(stderr, "Erro: elm_classify falhou (rc=%d)\n", rc);
        free(img);
        return APP_ERR;
    }

    /* ── 4. Imprime resultado ───────────────────────── */
    printf("\n┌─────────────────────────────┐\n");
    printf("│  Predição:  %d               │\n", pred);
    if (cfg->classe_esp >= 0) {
        int correto = (pred == (uint8_t)cfg->classe_esp);
        printf("│  Esperado:  %d               │\n", cfg->classe_esp);
        printf("│  %s                    │\n", correto ? "✓ CORRETO" : "✗ INCORRETO");
    }
    printf("└─────────────────────────────┘\n\n");

    free(img);
    return APP_OK;
}
