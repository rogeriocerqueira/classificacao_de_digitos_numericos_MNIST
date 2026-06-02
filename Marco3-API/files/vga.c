/*
 * vga.c — implementação do driver VGA do Marco 3.
 *
 * Comunicação via 4 PIOs na lightweight bridge (mesma abordagem
 * do elm_exec.S do Marco 2, mas em C com __sync_synchronize()).
 *
 * Sequência para escrever um pixel (espelha o handshake do elm_exec):
 *   1. Escreve addr e color nos PIOs
 *   2. Barreira de memória
 *   3. Sobe enable + write_en no ctrl PIO
 *   4. Polling do status PIO até DONE=1
 *   5. Abaixa ctrl
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <string.h>
#include "vga.h"

/* ── Tamanho total do mapeamento ──────────────────────── */
#define MMAP_SPAN  0x1000   /* 4 KB — cobre toda a bridge */

/* ── Conversão de cor ─────────────────────────────────── */
uint16_t gray_to_rrrgggbb(uint8_t gray)
{
    /*
     * RRRGGGBB — 9 bits
     * R[8:6] = gray[7:5]  (3 bits mais significativos)
     * G[5:3] = gray[7:5]  (idem — escala de cinza: R=G=B)
     * B[2:0] = gray[7:6]  (2 bits)
     */
    uint16_t r = (gray >> 5) & 0x7;
    uint16_t g = (gray >> 5) & 0x7;
    uint16_t b = (gray >> 6) & 0x3;
    return (r << 6) | (g << 3) | b;
}

/* ── Abertura e inicialização ─────────────────────────── */
int vga_open(vga_t *v)
{
    if (!v) return APP_ERR;

    v->fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (v->fd < 0) {
        perror("vga_open: open /dev/mem");
        return APP_ERR;
    }

    v->mmap_base = mmap(NULL, MMAP_SPAN,
                        PROT_READ | PROT_WRITE, MAP_SHARED,
                        v->fd, VGA_BRIDGE_BASE);
    if (v->mmap_base == MAP_FAILED) {
        perror("vga_open: mmap");
        close(v->fd);
        return APP_ERR;
    }

    /* Aponta cada PIO para o offset correto dentro do mapeamento */
    char *base = (char *)v->mmap_base;
    v->addr   = (volatile uint32_t *)(base + VGA_ADDR_OFF);
    v->color  = (volatile uint32_t *)(base + VGA_COLOR_OFF);
    v->ctrl   = (volatile uint32_t *)(base + VGA_CTRL_OFF);
    v->status = (volatile uint32_t *)(base + VGA_STATUS_OFF);

    /* Garante estado limpo */
    *v->ctrl = 0;
    __sync_synchronize();

    printf("[VGA] aberto. addr=0x%08lX color=0x%08lX ctrl=0x%08lX\n",
           VGA_BRIDGE_BASE + VGA_ADDR_OFF,
           VGA_BRIDGE_BASE + VGA_COLOR_OFF,
           VGA_BRIDGE_BASE + VGA_CTRL_OFF);

    return APP_OK;
}

void vga_close(vga_t *v)
{
    if (!v) return;
    if (v->mmap_base && v->mmap_base != MAP_FAILED)
        munmap(v->mmap_base, MMAP_SPAN);
    if (v->fd >= 0)
        close(v->fd);
}

/* ── Escrita de um pixel ──────────────────────────────── */
void vga_set_pixel(vga_t *v, uint16_t addr, uint16_t color)
{
    /* 1. Escreve endereço e cor */
    *v->addr  = addr  & 0x3FF;   /* 10 bits */
    *v->color = color & 0x1FF;   /*  9 bits */
    __sync_synchronize();        /* equivalente ao dsb sy do Marco 2 */

    /* 2. Sobe enable + write_en */
    *v->ctrl = VGA_CTRL_ENABLE | VGA_CTRL_WRITE_EN;
    __sync_synchronize();

    /* 3. Polling DONE (bit0 do status) */
    while (!(*v->status & 0x1));

    /* 4. Abaixa ctrl */
    *v->ctrl = 0;
    __sync_synchronize();
}

/* ── Exibe imagem MNIST (escala de cinza) ─────────────── */
void vga_draw_image(vga_t *v, const uint8_t img[IMG_PIXELS])
{
    for (int i = 0; i < IMG_PIXELS; i++)
        vga_set_pixel(v, (uint16_t)i, gray_to_rrrgggbb(img[i]));
}

/* ── Exibe canvas do modo desenho ────────────────────── */
void vga_draw_canvas(vga_t *v, const uint8_t canvas[IMG_PIXELS])
{
    for (int i = 0; i < IMG_PIXELS; i++) {
        uint16_t color = canvas[i] ? VGA_WHITE : VGA_BLACK;
        vga_set_pixel(v, (uint16_t)i, color);
    }
}

/* ── Limpa framebuffer ────────────────────────────────── */
void vga_clear(vga_t *v)
{
    for (int i = 0; i < IMG_PIXELS; i++)
        vga_set_pixel(v, (uint16_t)i, VGA_BLACK);
}

/* ── Reset do lsu_controller ──────────────────────────── */
void vga_reset(vga_t *v)
{
    *v->ctrl = VGA_CTRL_RST;
    __sync_synchronize();
    *v->ctrl = 0;
    __sync_synchronize();
    vga_clear(v);
}
