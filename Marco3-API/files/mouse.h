/*
 * mouse.h — interface de leitura do mouse via /dev/input/event*.
 *
 * Usa a API de eventos do Linux (linux/input.h).
 * O mouse gera eventos REL_X, REL_Y, BTN_LEFT, BTN_RIGHT e BTN_MIDDLE.
 *
 * No modo desenho, a posição do mouse é convertida para
 * coordenadas do canvas 28×28 (mapeado na tela VGA 640×480).
 */
#ifndef MOUSE_H
#define MOUSE_H

#include <stdint.h>
#include "app.h"

/* ── Dispositivo padrão ─────────────────────────────────── */
#define MOUSE_DEVICE  "/dev/input/event0"

/* ── Limites do canvas ──────────────────────────────────── */
#define CANVAS_W   IMG_W   /* 28 */
#define CANVAS_H   IMG_H   /* 28 */

/* ── Evento processado do mouse ─────────────────────────── */
typedef struct {
    int x;           /* posição atual X (0 a CANVAS_W-1)      */
    int y;           /* posição atual Y (0 a CANVAS_H-1)      */
    int btn_left;    /* 1 = botão esquerdo pressionado (desenha) */
    int btn_right;   /* 1 = botão direito (confirma)           */
    int btn_middle;  /* 1 = botão do meio (apaga)              */
} mouse_state_t;

/* ── Struct do driver de mouse ──────────────────────────── */
typedef struct {
    int           fd;
    mouse_state_t state;
} mouse_t;

/*
 * mouse_open() — abre o dispositivo de entrada.
 * device: caminho ex. "/dev/input/event0"
 * Retorna APP_OK ou APP_ERR.
 */
int mouse_open(mouse_t *m, const char *device);

/*
 * mouse_close() — fecha o descritor.
 */
void mouse_close(mouse_t *m);

/*
 * mouse_poll() — lê eventos pendentes e atualiza m->state.
 * Não bloqueia — retorna imediatamente se não há eventos.
 * Retorna número de eventos processados.
 */
int mouse_poll(mouse_t *m);

/*
 * mouse_wait_click() — bloqueia até botão esquerdo ser clicado.
 * Atualiza m->state com posição do clique.
 */
void mouse_wait_click(mouse_t *m);

/*
 * mouse_canvas_xy() — converte posição VGA para canvas 28×28.
 * vga_x, vga_y: coordenadas em 640×480
 * cx, cy: saída em coordenadas 0..27
 */
void mouse_canvas_xy(int vga_x, int vga_y, int *cx, int *cy);

#endif /* MOUSE_H */
