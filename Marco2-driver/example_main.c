/*
 * example_main.c — programa mínimo que exercita o driver.
 *
 * NÃO faz inferência de verdade — usa pesos sintéticos (zeros). O
 * propósito é validar que o linkage C↔ASM está correto e que o
 * handshake roda sem travar.
 *
 * Para fazer inferência real, substitua a geração sintética por
 * leitura dos arquivos de pesos fornecidos pelo enunciado.
 */

#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include "elm.h"

static void fill_synthetic_image(uint8_t img[ELM_IMAGE_PIXELS])
{
    int i;
    for (i = 0; i < ELM_IMAGE_PIXELS; i++) {
        img[i] = (uint8_t)(i & 0xFF);
    }
}

int main(int argc, char **argv)
{
    elm_t elm;
    uint8_t img[ELM_IMAGE_PIXELS];
    uint8_t predicted = 0xFF;
    int rc;

    (void)argc; (void)argv;

    printf("== Driver ELM — teste de linkage e handshake ==\n");

    rc = elm_open(&elm);
    if (rc != ELM_OK) {
        fprintf(stderr, "elm_open falhou (rc=%d)\n", rc);
        return 1;
    }
    printf("Driver aberto. data_out inicial = 0x%08x\n", *elm.data_out);

    /* Sanity check: o coprocessador deve estar idle (busy=0) */
    if (*elm.data_out & ELM_ST_BUSY) {
        fprintf(stderr, "AVISO: coprocessador iniciou marcado BUSY.\n");
    }

    fill_synthetic_image(img);

    printf("Carregando imagem sintética (%d pixels)...\n", ELM_IMAGE_PIXELS);
    rc = elm_load_image(&elm, img);
    if (rc) {
        fprintf(stderr, "elm_load_image falhou (rc=%d)\n", rc);
        elm_close(&elm);
        return 2;
    }

  
    printf("Disparando inferência...\n");
    rc = elm_start(&elm, &predicted);
    if (rc) {
        fprintf(stderr, "elm_start falhou (rc=%d). status=0x%08x\n",
                rc, *elm.data_out);
        elm_close(&elm);
        return 3;
    }

    printf("Resultado: %u (status final = 0x%08x)\n",
           predicted, *elm.data_out);

    elm_close(&elm);
    printf("Driver fechado.\n");
    return 0;
}
