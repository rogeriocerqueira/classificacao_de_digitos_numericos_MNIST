/*
 * vga.h — interface do driver VGA para o Marco 3.
 *
 * O vga_driver da FPGA opera em pixel-streaming:
 *   a cada ciclo ele expõe (next_x, next_y) e espera color_in.
 *
 * O framebuffer é um lsu_controller com MEM_SIZE=784, DATA_WIDTH=9.
 * O HPS escreve via 4 PIOs mapeados na lightweight bridge:
 *
 *   vga_addr   → 0xFF200070  (10 bits — índice 0..783)
 *   vga_color  → 0xFF200080  ( 9 bits — RRRGGGBB)
 *   vga_ctrl   → 0xFF200090  ( 3 bits — bit0=enable, bit1=write_en, bit2=rst)
 *   vga_status → 0xFF2000A0  ( 1 bit  — DONE do lsu_controller)
 *
 * A imagem 28×28 é exibida centralizada em 640×480.
 * O restante da tela é preto (lógica in_region no ghrd_top.v).
 */
#ifndef VGA_H
#define VGA_H

#include <stdint.h>
#include "app.h"

/* ── Endereços físicos dos PIOs VGA ────────────────────── */
#define VGA_BRIDGE_BASE   0xFF200000UL
#define VGA_ADDR_OFF      0x70
#define VGA_COLOR_OFF     0x80
#define VGA_CTRL_OFF      0x90
#define VGA_STATUS_OFF    0xA0
#define VGA_SPAN          0xB0    /* cobre todos os PIOs VGA */

/* ── Bits do ctrl PIO ───────────────────────────────────── */
#define VGA_CTRL_ENABLE   (1 << 0)
#define VGA_CTRL_WRITE_EN (1 << 1)
#define VGA_CTRL_RST      (1 << 2)

/* ── Resolução da tela e posição da imagem ─────────────── */
#define VGA_SCREEN_W   640
#define VGA_SCREEN_H   480
#define VGA_IMG_OFF_X  180   /* (640-280)/2 — escala 10x */
#define VGA_IMG_OFF_Y  100   /* (480-280)/2 — escala 10x */
#define VGA_IMG_SCALE  10   /* cada pixel do canvas = 10x10 na tela */

/* ── Struct do driver VGA ───────────────────────────────── */
typedef struct {
    volatile uint32_t *addr;    /* &vga_addr PIO   (0xFF200070) */
    volatile uint32_t *color;   /* &vga_color PIO  (0xFF200080) */
    volatile uint32_t *ctrl;    /* &vga_ctrl PIO   (0xFF200090) */
    volatile uint32_t *status;  /* &vga_status PIO (0xFF2000A0) */
    void              *mmap_base;
    int                fd;
} vga_t;

/* ── Paleta de cores RRRGGGBB (9 bits) ─────────────────── */
#define VGA_BLACK   0x000   /* 000 000 00 */
#define VGA_WHITE   0x1FF   /* 111 111 11 */
#define VGA_RED     0x1C0   /* 111 000 00 */
#define VGA_GREEN   0x038   /* 000 111 00 */
#define VGA_BLUE    0x003   /* 000 000 11 */
#define VGA_GRAY    0x092   /* 010 010 01 */

/* ── API pública ────────────────────────────────────────── */

/*
 * vga_open() — abre /dev/mem e mapeia os PIOs VGA.
 * Retorna APP_OK ou APP_ERR.
 */
int vga_open(vga_t *v);

/*
 * vga_close() — libera mmap e fecha /dev/mem.
 */
void vga_close(vga_t *v);

/*
 * vga_reset() — reseta o lsu_controller do framebuffer.
 * Limpa todos os 784 pixels para preto.
 */
void vga_reset(vga_t *v);

/*
 * vga_set_pixel() — escreve um pixel no framebuffer.
 *   addr  : índice linear 0..783  (y*28 + x)
 *   color : 9 bits RRRGGGBB
 * Aguarda DONE do lsu_controller antes de retornar.
 */
void vga_set_pixel(vga_t *v, uint16_t addr, uint16_t color);

/*
 * vga_draw_image() — exibe img[784] no framebuffer.
 * Converte escala de cinza (0–255) → RRRGGGBB.
 */
void vga_draw_image(vga_t *v, const uint8_t img[IMG_PIXELS]);

/*
 * vga_draw_canvas() — exibe canvas 28×28 (pixels 0/255).
 * Usado no modo desenho.
 */
void vga_draw_canvas(vga_t *v, const uint8_t canvas[IMG_PIXELS]);

/*
 * vga_clear() — apaga toda a imagem (pixels → preto).
 */
void vga_clear(vga_t *v);

/*
 * gray_to_rrrgggbb() — converte valor 0–255 para 9 bits RRRGGGBB.
 */
uint16_t gray_to_rrrgggbb(uint8_t gray);

#endif /* VGA_H */
