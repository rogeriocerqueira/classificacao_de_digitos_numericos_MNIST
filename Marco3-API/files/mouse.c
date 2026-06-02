/*
 * mouse.c — leitura do mouse via /dev/input/event*.
 *
 * O kernel Linux entrega eventos struct input_event com:
 *   type  = EV_REL → movimento relativo
 *   code  = REL_X ou REL_Y
 *   value = delta de pixels
 *
 *   type  = EV_KEY → botão
 *   code  = BTN_LEFT ou BTN_RIGHT
 *   value = 1 (press) ou 0 (release)
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <linux/input.h>
#include "mouse.h"
#include "vga.h"    /* VGA_SCREEN_W, VGA_SCREEN_H, VGA_IMG_OFF_* */

/* ── Posição VGA acumulada (0..639 / 0..479) ──────────── */
static int cur_vga_x = VGA_SCREEN_W / 2;
static int cur_vga_y = VGA_SCREEN_H / 2;

/* ── Abertura ─────────────────────────────────────────── */
int mouse_open(mouse_t *m, const char *device)
{
    if (!m || !device) return APP_ERR;

    m->fd = open(device, O_RDONLY | O_NONBLOCK);
    if (m->fd < 0) {
        perror("mouse_open: open");
        fprintf(stderr, "  Tente: ls /dev/input/event*\n");
        return APP_ERR;
    }

    memset(&m->state, 0, sizeof(m->state));
    m->state.x = CANVAS_W / 2;
    m->state.y = CANVAS_H / 2;

    printf("[Mouse] aberto: %s\n", device);
    return APP_OK;
}

void mouse_close(mouse_t *m)
{
    if (m && m->fd >= 0) close(m->fd);
}

/* ── Clamp helper ─────────────────────────────────────── */
static int clamp(int v, int lo, int hi)
{
    return v < lo ? lo : (v > hi ? hi : v);
}

/* ── Polling não-bloqueante ───────────────────────────── */
int mouse_poll(mouse_t *m)
{
    struct input_event ev;
    int count = 0;

    while (read(m->fd, &ev, sizeof(ev)) == sizeof(ev)) {
        if (ev.type == EV_REL) {
            if (ev.code == REL_X) {
                cur_vga_x = clamp(cur_vga_x + ev.value, 0, VGA_SCREEN_W - 1);
            }
            else if (ev.code == REL_Y) {
                cur_vga_y = clamp(cur_vga_y + ev.value, 0, VGA_SCREEN_H - 1);
            }
            /* Converte posição VGA → canvas 28×28 */
            mouse_canvas_xy(cur_vga_x, cur_vga_y,
                            &m->state.x, &m->state.y);
        }
        else if (ev.type == EV_KEY) {
            if (ev.code == BTN_LEFT)
                m->state.btn_left  = ev.value;
            else if (ev.code == BTN_RIGHT)
                m->state.btn_right = ev.value;
        }
        count++;
    }
    return count;
}

/* ── Aguarda clique do botão esquerdo ─────────────────── */
void mouse_wait_click(mouse_t *m)
{
    struct input_event ev;
    int released = 1;

    /* Lê de forma bloqueante temporariamente */
    int flags = fcntl(m->fd, F_GETFL, 0);
    fcntl(m->fd, F_SETFL, flags & ~O_NONBLOCK);

    while (1) {
        if (read(m->fd, &ev, sizeof(ev)) != sizeof(ev)) break;

        if (ev.type == EV_KEY && ev.code == BTN_LEFT) {
            if (ev.value == 1 && released) {
                /* Clique registrado — atualiza posição */
                mouse_canvas_xy(cur_vga_x, cur_vga_y,
                                &m->state.x, &m->state.y);
                m->state.btn_left = 1;
                break;
            }
            released = (ev.value == 0);
        }
        /* Atualiza posição mesmo enquanto espera */
        if (ev.type == EV_REL) {
            if (ev.code == REL_X)
                cur_vga_x = clamp(cur_vga_x + ev.value, 0, VGA_SCREEN_W-1);
            if (ev.code == REL_Y)
                cur_vga_y = clamp(cur_vga_y + ev.value, 0, VGA_SCREEN_H-1);
        }
    }

    /* Restaura não-bloqueante */
    fcntl(m->fd, F_SETFL, flags);
}

/* ── Conversão VGA → canvas ───────────────────────────── */
void mouse_canvas_xy(int vga_x, int vga_y, int *cx, int *cy)
{
    /*
     * A imagem 28×28 está centrada em 640×480:
     *   x: [VGA_IMG_OFF_X .. VGA_IMG_OFF_X+28)
     *   y: [VGA_IMG_OFF_Y .. VGA_IMG_OFF_Y+28)
     *
     * Fora da região → clamp para a borda do canvas.
     */
    int px = vga_x - VGA_IMG_OFF_X;
    int py = vga_y - VGA_IMG_OFF_Y;
    *cx = clamp(px, 0, CANVAS_W - 1);
    *cy = clamp(py, 0, CANVAS_H - 1);
}
