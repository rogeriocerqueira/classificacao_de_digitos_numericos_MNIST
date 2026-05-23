/*
 * elm.c — implementação do driver ELM (parte C).
 *
 * Esta parte cuida de:
 *   - abrir /dev/mem e fazer o mmap da lwh2f bridge
 *   - converter os macros do hps_0.h em ponteiros virtuais
 *   - codificar instruções (shifts/máscaras de bits)
 *   - oferecer API de alto nível (load_image, load_weights, ...)
 *
 * A parte CRÍTICA — o handshake MMIO bit-a-bit — está em elm_exec.S,
 * conforme exigido pelo Marco 2 do enunciado.
 */

#include "elm.h"
#include "elm_proto.h"
#include "elm_platform.h"

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>

/* ------------------------------------------------------------
 * Verificação de contrato com elm_exec.S
 * ------------------------------------------------------------
 * Se alguém reordenar os campos do struct, o linker liga, mas o
 * ASM lê o ponteiro errado. _Static_assert dispara erro de
 * compilação antes disso virar bug em runtime.
 */
_Static_assert(offsetof(elm_t, data_in)  == ELM_OFF_DATA_IN,
               "data_in deve estar no offset ELM_OFF_DATA_IN");
_Static_assert(offsetof(elm_t, ctrl)     == ELM_OFF_CTRL,
               "ctrl deve estar no offset ELM_OFF_CTRL");
_Static_assert(offsetof(elm_t, data_out) == ELM_OFF_DATA_OUT,
               "data_out deve estar no offset ELM_OFF_DATA_OUT");

/* ------------------------------------------------------------
 * Rotina crítica em Assembly (definida em elm_exec.S)
 * ------------------------------------------------------------
 * Faz: espera idle → escreve instrução → sobe enable → polling
 * → abaixa enable → espera busy cair. Retorna 0 ou -1.
 *
 * Parâmetro wait_done deve ser 0 para STORE_W_ADDR (não seta DONE)
 * e 1 para todas as outras instruções.
 */
extern int elm_exec(elm_t *e, uint32_t instr, int wait_done);

#define ELM_WAIT_DONE   1
#define ELM_NO_WAIT     0

/* ============================================================
 * Encoders de instrução
 * ============================================================
 * Todos seguem o layout descoberto no ST_DECODE do CoProcessor.v:
 * OP code nos 3 LSBs, seguido pelo campo de endereço, seguido pelo
 * campo de dado. Os shifts/máscaras estão centralizados em
 * elm_proto.h justamente para não terem variante mágica aqui.
 */

static inline uint32_t enc_store_img(uint16_t addr, uint8_t pixel)
{
    return  ((uint32_t)ELM_OP_STORE_IMG  << ELM_OPCODE_SHIFT)
          | (((uint32_t)addr  & ELM_IMG_ADDR_MASK) << ELM_IMG_ADDR_SHIFT)
          | (((uint32_t)pixel & ELM_IMG_DATA_MASK) << ELM_IMG_DATA_SHIFT);
}

static inline uint32_t enc_store_w_addr(uint32_t addr)
{
    return  ((uint32_t)ELM_OP_STORE_W_ADDR << ELM_OPCODE_SHIFT)
          | ((addr & ELM_W_ADDR_MASK) << ELM_W_ADDR_SHIFT);
}

static inline uint32_t enc_store_w_value(int16_t value)
{
    return  ((uint32_t)ELM_OP_STORE_W_VALUE << ELM_OPCODE_SHIFT)
          | (((uint32_t)(uint16_t)value & ELM_W_DATA_MASK) << ELM_W_DATA_SHIFT);
}

static inline uint32_t enc_store_bias(uint8_t addr, int16_t value)
{
    return  ((uint32_t)ELM_OP_STORE_BIAS << ELM_OPCODE_SHIFT)
          | (((uint32_t)addr & ELM_BIAS_ADDR_MASK) << ELM_BIAS_ADDR_SHIFT)
          | (((uint32_t)(uint16_t)value & ELM_BIAS_DATA_MASK) << ELM_BIAS_DATA_SHIFT);
}

static inline uint32_t enc_store_beta(uint16_t addr, int16_t value)
{
    return  ((uint32_t)ELM_OP_STORE_BETA << ELM_OPCODE_SHIFT)
          | (((uint32_t)addr & ELM_BETA_ADDR_MASK) << ELM_BETA_ADDR_SHIFT)
          | (((uint32_t)(uint16_t)value & ELM_BETA_DATA_MASK) << ELM_BETA_DATA_SHIFT);
}

static inline uint32_t enc_start(void)
{
    return (uint32_t)ELM_OP_START << ELM_OPCODE_SHIFT;
}

/* ============================================================
 * Setup / teardown
 * ============================================================ */

int elm_open(elm_t *e)
{
    if (!e) return ELM_E_NULL_PTR;
    memset(e, 0, sizeof(*e));
    e->fd = -1;

    e->fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (e->fd < 0)
        return ELM_E_OPEN_MEM;

    e->bridge_span = ELM_BRIDGE_SPAN;
    e->bridge = mmap(NULL,
                     e->bridge_span,
                     PROT_READ | PROT_WRITE,
                     MAP_SHARED,
                     e->fd,
                     ELM_BRIDGE_BASE);
    if (e->bridge == MAP_FAILED) {
        close(e->fd);
        e->fd = -1;
        return ELM_E_MMAP;
    }

    /* Os endereços vêm direto do hps_0.h via elm_platform.h.
     * Nenhum offset hardcoded neste arquivo. */
    e->data_in  = (volatile uint32_t *)((char *)e->bridge + DATA_IN_BASE);
    e->ctrl     = (volatile uint32_t *)((char *)e->bridge + CTRL_BASE);
    e->data_out = (volatile uint32_t *)((char *)e->bridge + DATA_OUT_BASE);

    elm_reset(e);
    return ELM_OK;
}

void elm_close(elm_t *e)
{
    if (!e) return;
    if (e->bridge && e->bridge != MAP_FAILED) {
        munmap(e->bridge, e->bridge_span);
    }
    if (e->fd >= 0) {
        close(e->fd);
    }
    memset(e, 0, sizeof(*e));
    e->fd = -1;
}

void elm_reset(elm_t *e)
{
    if (!e || !e->ctrl) return;
    /* Pulsa o reset, depois limpa qualquer erro residual */
    *e->ctrl = ELM_SIG_RESET;
    *e->ctrl = 0;
    *e->ctrl = ELM_SIG_CLR_OP;
    *e->ctrl = 0;
}

void elm_clear_error(elm_t *e)
{
    if (!e || !e->ctrl) return;
    *e->ctrl = ELM_SIG_CLR_OP;
    *e->ctrl = 0;
}

/* ============================================================
 * Conversão Q4.12
 * ============================================================ */

int16_t elm_float_to_q4_12(float v)
{
    float s = v * ELM_Q4_12_SCALE;
    if (s >  32767.0f) s =  32767.0f;
    if (s < -32768.0f) s = -32768.0f;
    return (int16_t)(s >= 0.0f ? s + 0.5f : s - 0.5f);
}

float elm_q4_12_to_float(int16_t v)
{
    return (float)v / ELM_Q4_12_SCALE;
}

/* ============================================================
 * Operações unitárias
 * ============================================================ */

int elm_store_image_pixel(elm_t *e, uint16_t addr, uint8_t pixel)
{
    if (!e) return ELM_E_NULL_PTR;
    if (addr >= ELM_IMAGE_PIXELS) return ELM_E_BAD_RANGE;
    return elm_exec(e, enc_store_img(addr, pixel), ELM_WAIT_DONE);
}

int elm_store_weight(elm_t *e, uint32_t addr, int16_t value)
{
    int rc;
    if (!e) return ELM_E_NULL_PTR;
    if (addr >= ELM_W_SIZE) return ELM_E_BAD_RANGE;

    /* STORE_WEIGHTS_VALUE não tem auto-incremento — precisa do par */
    rc = elm_exec(e, enc_store_w_addr(addr), ELM_NO_WAIT);
    if (rc) return rc;
    return elm_exec(e, enc_store_w_value(value), ELM_WAIT_DONE);
}

int elm_store_bias(elm_t *e, uint8_t addr, int16_t value)
{
    if (!e) return ELM_E_NULL_PTR;
    if (addr >= ELM_HIDDEN_NEURONS) return ELM_E_BAD_RANGE;
    return elm_exec(e, enc_store_bias(addr, value), ELM_WAIT_DONE);
}

int elm_store_beta(elm_t *e, uint16_t addr, int16_t value)
{
    if (!e) return ELM_E_NULL_PTR;
    if (addr >= ELM_BETA_SIZE) return ELM_E_BAD_RANGE;
    return elm_exec(e, enc_store_beta(addr, value), ELM_WAIT_DONE);
}

int elm_start(elm_t *e, uint8_t *predicted_digit)
{
    int rc;
    if (!e) return ELM_E_NULL_PTR;
    rc = elm_exec(e, enc_start(), ELM_WAIT_DONE);
    if (rc) return rc;
    if (predicted_digit) {
        *predicted_digit = (uint8_t)(*e->data_out & ELM_ST_RESULT_MASK);
    }
    return ELM_OK;
}

/* ============================================================
 * Operações em lote
 * ============================================================ */

int elm_load_image(elm_t *e, const uint8_t img[ELM_IMAGE_PIXELS])
{
    int p, rc;
    if (!e || !img) return ELM_E_NULL_PTR;
    for (p = 0; p < ELM_IMAGE_PIXELS; p++) {
        rc = elm_exec(e, enc_store_img((uint16_t)p, img[p]), ELM_WAIT_DONE);
        if (rc) return rc;
    }
    return ELM_OK;
}

int elm_load_weights(elm_t *e,
                     const int16_t W[ELM_HIDDEN_NEURONS][ELM_IMAGE_PIXELS])
{
    int n, p, rc;
    uint32_t base;

    if (!e || !W) return ELM_E_NULL_PTR;

    /* Layout do mem_win: addr = n*784 + p (neurônio-row-major).
     * Vide gerador de addr_win em first_layer.v. */
    for (n = 0; n < ELM_HIDDEN_NEURONS; n++) {
        base = (uint32_t)n * ELM_IMAGE_PIXELS;
        for (p = 0; p < ELM_IMAGE_PIXELS; p++) {
            rc = elm_exec(e, enc_store_w_addr(base + (uint32_t)p), ELM_NO_WAIT);
            if (rc) return rc;
            rc = elm_exec(e, enc_store_w_value(W[n][p]), ELM_WAIT_DONE);
            if (rc) return rc;
        }
    }
    return ELM_OK;
}

int elm_load_biases(elm_t *e, const int16_t b[ELM_HIDDEN_NEURONS])
{
    int n, rc;
    if (!e || !b) return ELM_E_NULL_PTR;
    for (n = 0; n < ELM_HIDDEN_NEURONS; n++) {
        rc = elm_exec(e, enc_store_bias((uint8_t)n, b[n]), ELM_WAIT_DONE);
        if (rc) return rc;
    }
    return ELM_OK;
}

int elm_load_betas(elm_t *e,
                   const int16_t beta[ELM_OUTPUT_NEURONS][ELM_HIDDEN_NEURONS])
{
    int h, o, rc;
    uint16_t addr;

    if (!e || !beta) return ELM_E_NULL_PTR;

    /* Layout do mem_beta: addr = h*10 + o (hidden-row-major).
     * Vide gerador de addr_beta em second_layer.v.
     *
     * O parâmetro chega como beta[o][h] (formato matemático y=β·h),
     * então transpomos na hora de enviar. */
    for (h = 0; h < ELM_HIDDEN_NEURONS; h++) {
        for (o = 0; o < ELM_OUTPUT_NEURONS; o++) {
            addr = (uint16_t)(h * ELM_OUTPUT_NEURONS + o);
            rc = elm_exec(e, enc_store_beta(addr, beta[o][h]), ELM_WAIT_DONE);
            if (rc) return rc;
        }
    }
    return ELM_OK;
}

int elm_classify(elm_t *e,
                 const uint8_t img[ELM_IMAGE_PIXELS],
                 uint8_t *predicted_digit)
{
    int rc;
    if (!e || !img) return ELM_E_NULL_PTR;

    rc = elm_load_image(e, img);
    if (rc) return rc;
    return elm_start(e, predicted_digit);
}
