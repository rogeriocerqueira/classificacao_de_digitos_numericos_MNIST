/*
 * modo_desenho.c — Modo 2: inferência a partir de desenho com mouse.
 *
 * Fluxo:
 *   1. Limpa o VGA e exibe canvas em branco
 *   2. Loop de captura:
 *      - lê eventos do mouse
 *      - botão esquerdo  → desenha pixel no canvas e no VGA
 *      - botão do meio   → apaga pixel no canvas e no VGA
 *      - botão direito   → confirma e encerra o loop
 *      - movimento       → atualiza cursor em cruz no VGA
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
#include "elm.h"

/* ── Desenha cursor em cruz 3×3 na posição (cx, cy) ──── */
static void cursor_draw(vga_t *vga, const uint8_t canvas[IMG_PIXELS],
                        int cx, int cy)
{
    /* Os 5 pixels da cruz: centro + 4 vizinhos ortogonais */
    int pts[5][2] = {
        {cx,   cy},
        {cx-1, cy}, {cx+1, cy},
        {cx,   cy-1}, {cx,   cy+1}
    };
    for (int i = 0; i < 5; i++) {
        int px = pts[i][0], py = pts[i][1];
        if (px < 0 || px >= CANVAS_W || py < 0 || py >= CANVAS_H) continue;
        int idx = py * CANVAS_W + px;
        /* Só sobrepõe pixels pretos — não estraga o desenho */
        if (canvas[idx] == 0)
            vga_set_pixel(vga, (uint16_t)idx, VGA_RED);
    }
}

/* ── Apaga cursor (restaura cor original do canvas) ───── */
static void cursor_erase(vga_t *vga, const uint8_t canvas[IMG_PIXELS],
                         int cx, int cy)
{
    int pts[5][2] = {
        {cx,   cy},
        {cx-1, cy}, {cx+1, cy},
        {cx,   cy-1}, {cx,   cy+1}
    };
    for (int i = 0; i < 5; i++) {
        int px = pts[i][0], py = pts[i][1];
        if (px < 0 || px >= CANVAS_W || py < 0 || py >= CANVAS_H) continue;
        int idx = py * CANVAS_W + px;
        /* Restaura a cor original do pixel: branco se pintado, preto se vazio */
        uint16_t color = (canvas[idx] != 0) ? VGA_WHITE : VGA_BLACK;
        vga_set_pixel(vga, (uint16_t)idx, color);
    }
}

/* ── Pinta pixel + vizinhos (traço mais grosso) ──────── */
static void paint_pixel(vga_t *vga, uint8_t canvas[IMG_PIXELS],
                        int cx, int cy)
{
    if (canvas[cy * CANVAS_W + cx] == 0) {
        canvas[cy * CANVAS_W + cx] = 255;
        vga_set_pixel(vga, (uint16_t)(cy * CANVAS_W + cx), VGA_WHITE);
    }
    int neighbors[4][2] = {{cx-1,cy},{cx+1,cy},{cx,cy-1},{cx,cy+1}};
    for (int n = 0; n < 4; n++) {
        int nx = neighbors[n][0], ny = neighbors[n][1];
        if (nx < 0 || nx >= CANVAS_W || ny < 0 || ny >= CANVAS_H) continue;
        int nidx = ny * CANVAS_W + nx;
        if (canvas[nidx] == 0) {
            canvas[nidx] = 255;
            vga_set_pixel(vga, (uint16_t)nidx, VGA_WHITE);
        }
    }
}

/* ── Apaga pixel + vizinhos ──────────────────────────── */
static void erase_pixel(vga_t *vga, uint8_t canvas[IMG_PIXELS],
                        int cx, int cy)
{
    int pts[5][2] = {
        {cx,   cy},
        {cx-1, cy}, {cx+1, cy},
        {cx,   cy-1}, {cx,   cy+1}
    };
    for (int i = 0; i < 5; i++) {
        int px = pts[i][0], py = pts[i][1];
        if (px < 0 || px >= CANVAS_W || py < 0 || py >= CANVAS_H) continue;
        int idx = py * CANVAS_W + px;
        canvas[idx] = 0;
        vga_set_pixel(vga, (uint16_t)idx, VGA_BLACK);
    }
}

/* ── Modo desenho principal ──────────────────────────── */
int modo_desenho(elm_t *elm, vga_t *vga, const app_config_t *cfg)
{
    printf("\n╔══════════════════════════════════════╗\n");
    printf("║  Modo 2 — Desenho com Mouse          ║\n");
    printf("╚══════════════════════════════════════╝\n\n");
    printf("Instruções:\n");
    printf("  Botão ESQUERDO → desenha\n");
    printf("  Botão MEIO     → apaga\n");
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

    /* ── Posição anterior do cursor ─────────────────── */
    int prev_cx = mouse.state.x;
    int prev_cy = mouse.state.y;
    cursor_draw(vga, canvas, prev_cx, prev_cy);

    /* ── Loop de captura ────────────────────────────── */
    while (1) {
        mouse_poll(&mouse);

        int cx = mouse.state.x;
        int cy = mouse.state.y;

        /* Botão direito → confirma */
        if (mouse.state.btn_right) {
            cursor_erase(vga, canvas, prev_cx, prev_cy);
            printf("\nConfirmado! Classificando...\n");
            break;
        }

        /* Botão esquerdo → desenha */
        if (mouse.state.btn_left) {
            cursor_erase(vga, canvas, prev_cx, prev_cy);
            paint_pixel(vga, canvas, cx, cy);
            cursor_draw(vga, canvas, cx, cy);
            prev_cx = cx;
            prev_cy = cy;
        }
        /* Botão do meio → apaga */
        else if (mouse.state.btn_middle) {
            cursor_erase(vga, canvas, prev_cx, prev_cy);
            erase_pixel(vga, canvas, cx, cy);
            cursor_draw(vga, canvas, cx, cy);
            prev_cx = cx;
            prev_cy = cy;
        }
        /* Movimento sem botão → só move cursor */
        else if (cx != prev_cx || cy != prev_cy) {
            cursor_erase(vga, canvas, prev_cx, prev_cy);
            cursor_draw(vga, canvas, cx, cy);
            prev_cx = cx;
            prev_cy = cy;
        }

        usleep(5000);   /* 5ms — evita busy-wait excessivo */
    }

    mouse_close(&mouse);

    /* ── Envia canvas ao CoProcessor ───────────────── */
    /* Reseta FSM/acumuladores antes de classificar
     * (nao afeta os BRAMs de pesos, ja carregados em elm_init_weights) */
    elm_reset(elm);

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