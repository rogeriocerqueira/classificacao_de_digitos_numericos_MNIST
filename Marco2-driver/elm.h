/*
 * elm.h — API pública do driver do coprocessador ELM.
 *
 * Este header pode ser incluído por qualquer aplicação. Não expõe
 * detalhes do hps_0.h nem do protocolo bit-a-bit — só a interface.
 */

#ifndef ELM_H
#define ELM_H

#include <stdint.h>
#include <stddef.h>

#include "elm_proto.h"  /* expõe as dimensões da rede (úteis para o caller) */

/* ============================================================
 * Códigos de retorno
 * ============================================================ */
typedef enum {
    ELM_OK            =  0,
    ELM_E_OPEN_MEM    = -1,   /* falha em open("/dev/mem") */
    ELM_E_MMAP        = -2,   /* falha no mmap da bridge */
    ELM_E_HW_ERROR    = -3,   /* o coprocessador subiu a flag ERROR */
    ELM_E_BAD_RANGE   = -4,   /* endereço fora dos limites (cheque cliente) */
    ELM_E_NULL_PTR    = -5,   /* argumento nulo onde não pode */
} elm_status_t;

/* ============================================================
 * Handle do dispositivo
 * ============================================================
 *
 * IMPORTANTE: a ordem dos três primeiros campos (data_in, ctrl,
 * data_out) é parte do contrato com elm_exec.S, que acessa estes
 * ponteiros pelos offsets ELM_OFF_DATA_IN/CTRL/DATA_OUT definidos
 * em elm_proto.h. Não reordene sem atualizar o ASM.
 */
typedef struct {
    volatile uint32_t *data_in;    /* offset ELM_OFF_DATA_IN  (0) */
    volatile uint32_t *ctrl;       /* offset ELM_OFF_CTRL     (4) */
    volatile uint32_t *data_out;   /* offset ELM_OFF_DATA_OUT (8) */
    /* campos abaixo são privados; ASM ignora */
    int    fd;
    void  *bridge;
    size_t bridge_span;
} elm_t;

/* ============================================================
 * Ciclo de vida
 * ============================================================ */
int  elm_open(elm_t *e);
void elm_close(elm_t *e);
void elm_reset(elm_t *e);
void elm_clear_error(elm_t *e);

/* ============================================================
 * Conversão Q4.12 <-> float
 * ============================================================ */
int16_t elm_float_to_q4_12(float v);
float   elm_q4_12_to_float(int16_t v);

/* ============================================================
 * Operações unitárias (uma instrução por chamada)
 * ============================================================
 * Todas retornam ELM_OK ou um código de erro negativo.
 */
int elm_store_image_pixel(elm_t *e, uint16_t addr, uint8_t  pixel);
int elm_store_weight     (elm_t *e, uint32_t addr, int16_t  value_q4_12);
int elm_store_bias       (elm_t *e, uint8_t  addr, int16_t  value_q4_12);
int elm_store_beta       (elm_t *e, uint16_t addr, int16_t  value_q4_12);

/* Dispara START e devolve em *predicted_digit o resultado [0..9]. */
int elm_start(elm_t *e, uint8_t *predicted_digit);

/* ============================================================
 * Operações em lote (alto nível)
 * ============================================================
 *
 * elm_load_weights espera W[n][p] = peso do pixel p para o neurônio n
 * (row-major neurônio-pixel, o que casa com o gerador de endereço do
 * first_layer.v).
 *
 * elm_load_betas espera beta[o][h] = peso do oculto h para a saída o,
 * que é o formato matemático natural y = β · h, e faz a transposição
 * para o layout hidden-major que o second_layer.v espera.
 */
int elm_load_image  (elm_t *e, const uint8_t  img[ELM_IMAGE_PIXELS]);
int elm_load_weights(elm_t *e, const int16_t  W[ELM_HIDDEN_NEURONS][ELM_IMAGE_PIXELS]);
int elm_load_biases (elm_t *e, const int16_t  b[ELM_HIDDEN_NEURONS]);
int elm_load_betas  (elm_t *e, const int16_t  beta[ELM_OUTPUT_NEURONS][ELM_HIDDEN_NEURONS]);

/* Atalho: carrega a imagem, dispara START, devolve a predição. */
int elm_classify(elm_t *e,
                 const uint8_t img[ELM_IMAGE_PIXELS],
                 uint8_t *predicted_digit);

#endif /* ELM_H */
