/*
 * modo_desenho.c - Modo 2: inferencia a partir de desenho com mouse.
 *
 * Fluxo:
 *   1. Limpa o VGA e exibe canvas em branco
 *   2. Loop de captura:
 *      - le eventos do mouse
 *      - botao esquerdo  -> desenha pixel no canvas e no VGA
 *      - botao do meio   -> apaga pixel no canvas e no VGA
 *      - botao direito   -> confirma e encerra o loop
 *      - movimento       -> atualiza cursor em cruz no VGA
 *   3. elm_reset + elm_classify
 *   4. Imprime predicao no terminal
 *   5. Pergunta se quer repetir (loop, sem recursao)
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

/* Desenha cursor em cruz na posicao (cx, cy) */
static void cursor_draw(vga_t *vga, const uint8_t canvas[IMG_PIXELS],
                        int cx, int cy)
{
    int pts[5][2] = {
        {cx,   cy},
        {cx-1, cy}, {cx+1, cy},
        {cx,   cy-1}, {cx,   cy+1}
    };
    int i;
    for (i = 0; i < 5; i++) {
        int px = pts[i][0], py = pts[i][1];
        if (px < 0 || px >= CANVAS_W || py < 0 || py >= CANVAS_H) continue;
        int idx = py * CANVAS_W + px;
        if (canvas[idx] == 0)
            vga_set_pixel(vga, (uint16_t)idx, VGA_RED);
    }
}

/* Apaga cursor (restaura cor original do canvas) */
static void cursor_erase(vga_t *vga, const uint8_t canvas[IMG_PIXELS],
                         int cx, int cy)
{
    int pts[5][2] = {
        {cx,   cy},
        {cx-1, cy}, {cx+1, cy},
        {cx,   cy-1}, {cx,   cy+1}
    };
    int i;
    for (i = 0; i < 5; i++) {
        int px = pts[i][0], py = pts[i][1];
        if (px < 0 || px >= CANVAS_W || py < 0 || py >= CANVAS_H) continue;
        int idx = py * CANVAS_W + px;
        uint16_t color = (canvas[idx] != 0) ? VGA_WHITE : VGA_BLACK;
        vga_set_pixel(vga, (uint16_t)idx, color);
    }
}

/* Pinta pixel + vizinhos (traco mais grosso) */
static void paint_pixel(vga_t *vga, uint8_t canvas[IMG_PIXELS],
                        int cx, int cy)
{
    int neighbors[4][2] = {{cx-1,cy},{cx+1,cy},{cx,cy-1},{cx,cy+1}};
    int n;
    if (canvas[cy * CANVAS_W + cx] == 0) {
        canvas[cy * CANVAS_W + cx] = 255;
        vga_set_pixel(vga, (uint16_t)(cy * CANVAS_W + cx), VGA_WHITE);
    }
    for (n = 0; n < 4; n++) {
        int nx = neighbors[n][0], ny = neighbors[n][1];
        if (nx < 0 || nx >= CANVAS_W || ny < 0 || ny >= CANVAS_H) continue;
        int nidx = ny * CANVAS_W + nx;
        if (canvas[nidx] == 0) {
            canvas[nidx] = 255;
            vga_set_pixel(vga, (uint16_t)nidx, VGA_WHITE);
        }
    }
}

/* Apaga pixel + vizinhos */
static void erase_pixel(vga_t *vga, uint8_t canvas[IMG_PIXELS],
                        int cx, int cy)
{
    int pts[5][2] = {
        {cx,   cy},
        {cx-1, cy}, {cx+1, cy},
        {cx,   cy-1}, {cx,   cy+1}
    };
    int i;
    for (i = 0; i < 5; i++) {
        int px = pts[i][0], py = pts[i][1];
        if (px < 0 || px >= CANVAS_W || py < 0 || py >= CANVAS_H) continue;
        int idx = py * CANVAS_W + px;
        canvas[idx] = 0;
        vga_set_pixel(vga, (uint16_t)idx, VGA_BLACK);
    }
}

int modo_desenho(elm_t *elm, vga_t *vga, const app_config_t *cfg)
{
    printf("\n==========================================\n");
    printf("  Modo 2 - Desenho com Mouse\n");
    printf("==========================================\n\n");
    printf("Instrucoes:\n");
    printf("  Botao ESQUERDO -> desenha\n");
    printf("  Botao MEIO     -> apaga\n");
    printf("  Botao DIREITO  -> confirma e classifica\n\n");

    /* Abre mouse uma unica vez */
    mouse_t mouse;
    if (mouse_open(&mouse, MOUSE_DEVICE) != APP_OK) {
        fprintf(stderr, "Erro: nao foi possivel abrir o mouse.\n");
        fprintf(stderr, "  Verifique /dev/input/event* e permissoes.\n");
        return APP_ERR;
    }

    char resp[4];
    do {
        /* Limpa canvas e VGA a cada novo desenho */
        uint8_t canvas[IMG_PIXELS];
        memset(canvas, 0, sizeof(canvas));
        vga_clear(vga);

        printf("Mouse pronto. Comece a desenhar!\n\n");

        /* Posicao inicial do cursor */
        int prev_cx = mouse.state.x;
        int prev_cy = mouse.state.y;
        cursor_draw(vga, canvas, prev_cx, prev_cy);

        /* Loop de captura */
        while (1) {
            mouse_poll(&mouse);

            int cx = mouse.state.x;
            int cy = mouse.state.y;

            if (mouse.state.btn_right) {
                cursor_erase(vga, canvas, prev_cx, prev_cy);
                printf("\nConfirmado! Classificando...\n");
                break;
            }

            if (mouse.state.btn_left) {
                cursor_erase(vga, canvas, prev_cx, prev_cy);
                paint_pixel(vga, canvas, cx, cy);
                cursor_draw(vga, canvas, cx, cy);
                prev_cx = cx;
                prev_cy = cy;
            }
            else if (mouse.state.btn_middle) {
                cursor_erase(vga, canvas, prev_cx, prev_cy);
                erase_pixel(vga, canvas, cx, cy);
                cursor_draw(vga, canvas, cx, cy);
                prev_cx = cx;
                prev_cy = cy;
            }
            else if (cx != prev_cx || cy != prev_cy) {
                cursor_erase(vga, canvas, prev_cx, prev_cy);
                cursor_draw(vga, canvas, cx, cy);
                prev_cx = cx;
                prev_cy = cy;
            }

            usleep(5000);
        }

        /* Reseta FSM antes de classificar */
        elm_reset(elm);

        /* Inferencia */
        uint8_t pred = 0;
        int rc = elm_classify(elm, canvas, &pred);
        if (rc != ELM_OK) {
            fprintf(stderr, "Erro: elm_classify falhou (rc=%d)\n", rc);
            mouse_close(&mouse);
            return APP_ERR;
        }

        /* Resultado */
        printf("\n-------------------------------\n");
        printf("  Predicao:  %d\n", pred);
        printf("-------------------------------\n\n");

        /* Pergunta se quer repetir */
        printf("Deseja desenhar novamente? (s/n): ");
        resp[0] = 'n';
        fgets(resp, sizeof(resp), stdin);

    } while (resp[0] == 's' || resp[0] == 'S');

    mouse_close(&mouse);
    return APP_OK;
}