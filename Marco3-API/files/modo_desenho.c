/*
 * modo_desenho.c — Modo 2: inferência a partir de desenho com mouse.
 *
 * Fluxo:
 *   1. Limpa o VGA e exibe canvas em branco
 *   2. Loop de captura:
 *      - lê eventos do mouse
 *      - botão esquerdo pressionado → pinta pixel no canvas e no VGA
 *      - botão direito → confirma e encerra o loop
 *   3. Envia canvas ao CoProcessor
 *   4. Imprime predição no terminal
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "app.h"
#include "vga.h"
#include "mouse.h"
#include "elm.h"        // em vez de "../../../Marco2-driver/elm.h"


int modo_desenho(elm_t *elm, vga_t *vga, const app_config_t *cfg)
{
    printf("\n╔══════════════════════════════════════╗\n");
    printf("║  Modo 2 — Desenho com Mouse          ║\n");
    printf("╚══════════════════════════════════════╝\n\n");
    printf("Instruções:\n");
    printf("  Botão ESQUERDO → desenha\n");
    printf("  Botão DIREITO  → confirma e classifica\n\n");

    /* ── Canvas em memória ──────────────────────────── */
    uint8_t canvas[IMG_PIXELS];
    memset(canvas, 0, sizeof(canvas));

    /* ── Limpa VGA ──────────────────────────────────── */
    vga_clear(vga);

    /* ── Abre mouse ─────────────────────────────────── */
    mouse_t mouse;
    if (mouse_open(&mouse, MOUSE_DEVICE) != APP_OK) {
        fprintf(stderr, "Erro: não foi possível abrir o mouse.\n");
        fprintf(stderr, "  Verifique /dev/input/event* e permissões.\n");
        return APP_ERR;
    }

    printf("Mouse pronto. Comece a desenhar!\n\n");

    /* ── Loop de captura ────────────────────────────── */
    while (1) {
        mouse_poll(&mouse);

        /* Botão direito → confirma */
        if (mouse.state.btn_right) {
            printf("\nConfirmado! Classificando...\n");
            break;
        }

        /* Botão esquerdo → pinta */
        if (mouse.state.btn_left) {
            int cx = mouse.state.x;
            int cy = mouse.state.y;
            int idx = cy * CANVAS_W + cx;

            if (canvas[idx] == 0) {
                canvas[idx] = 255;

                /* Atualiza VGA em tempo real */
                vga_set_pixel(vga, (uint16_t)idx, VGA_WHITE);

                /* Pinta pixels vizinhos para traço mais grosso */
                int neighbors[4][2] = {{cx-1,cy},{cx+1,cy},{cx,cy-1},{cx,cy+1}};
                for (int n = 0; n < 4; n++) {
                    int nx = neighbors[n][0];
                    int ny = neighbors[n][1];
                    if (nx >= 0 && nx < CANVAS_W && ny >= 0 && ny < CANVAS_H) {
                        int nidx = ny * CANVAS_W + nx;
                        if (canvas[nidx] == 0) {
                            canvas[nidx] = 128;
                            vga_set_pixel(vga, (uint16_t)nidx, VGA_GRAY);
                        }
                    }
                }
            }
        }

        usleep(5000);   /* 5ms — evita busy-wait excessivo */
    }

    mouse_close(&mouse);

    /* ── Envia canvas ao CoProcessor ───────────────── */
    printf("Enviando ao CoProcessor...\n");
    uint8_t pred = 0;
    int rc = elm_classify(elm, canvas, &pred);
    if (rc != ELM_OK) {
        fprintf(stderr, "Erro: elm_classify falhou (rc=%d)\n", rc);
        return APP_ERR;
    }

    /* ── Imprime resultado ──────────────────────────── */
    printf("\n┌─────────────────────────────┐\n");
    printf("│  Predição:  %d               │\n", pred);
    printf("└─────────────────────────────┘\n\n");

    /* ── Pergunta se quer repetir ───────────────────── */
    printf("Deseja desenhar novamente? (s/n): ");
    char resp[4];
    if (fgets(resp, sizeof(resp), stdin) && (resp[0] == 's' || resp[0] == 'S')) {
        return modo_desenho(elm, vga, cfg);
    }

    return APP_OK;
}
