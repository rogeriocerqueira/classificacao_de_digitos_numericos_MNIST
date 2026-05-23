/*
 * elm_proto.h — constantes do protocolo do coprocessador ELM.
 *
 * Este arquivo é incluído tanto pelo código C quanto pela rotina Assembly
 * (elm_exec.S). Por isso evita typedefs, sufixos como 'u' em literais e
 * qualquer construção exclusivamente C. As partes específicas de C ficam
 * protegidas por #ifndef __ASSEMBLER__.
 *
 * Todas as constantes aqui derivam do IP do coprocessador (CoProcessor.v),
 * não do sistema Qsys. Logo, mudam apenas se o RTL mudar.
 */

#ifndef ELM_PROTO_H
#define ELM_PROTO_H

/* ============================================================
 * Bits do barramento de sinais (ctrl PIO, 3 bits)
 * ============================================================
 *   bit 0 — Enable        : valida a instrução em data_in
 *   bit 1 — Clear Op      : limpa flag de erro do coprocessador
 *   bit 2 — Reset         : reseta o coprocessador inteiro
 */
#define ELM_SIG_ENABLE   (1 << 0)
#define ELM_SIG_CLR_OP   (1 << 1)
#define ELM_SIG_RESET    (1 << 2)

/* ============================================================
 * Layout do data_out PIO (32 bits, leitura)
 * ============================================================
 *   bits [3:0] — dígito predito (válido após DONE)
 *   bit    4   — DONE  (operação concluída)
 *   bit    5   — BUSY  (operação em andamento)
 *   bit    6   — ERROR (operação anterior inválida)
 *   bits [31:7]— reservado, sempre zero
 */
#define ELM_ST_RESULT_MASK   0x0F
#define ELM_ST_DONE          (1 << 4)
#define ELM_ST_BUSY          (1 << 5)
#define ELM_ST_ERROR         (1 << 6)

/* ============================================================
 * Op codes (3 bits, posicionados nos LSBs da palavra de 32 bits)
 * ============================================================ */
#define ELM_OP_STORE_IMG       0
#define ELM_OP_STORE_W_ADDR    1
#define ELM_OP_STORE_W_VALUE   2
#define ELM_OP_STORE_BIAS      3
#define ELM_OP_STORE_BETA      4
#define ELM_OP_START           5
/* opcodes 6 (STATUS) e 7 (NOP) existem no decoder mas não são úteis aqui */

/* ============================================================
 * Layout dos campos dentro da palavra de instrução (32 bits)
 * ============================================================
 * Estes shifts/máscaras vêm direto das atribuições do ST_DECODE
 * no CoProcessor.v. O OP code sempre fica nos LSBs [2:0].
 */
#define ELM_OPCODE_SHIFT       0

#define ELM_IMG_ADDR_SHIFT     3
#define ELM_IMG_ADDR_MASK      0x3FF       /* 10 bits */
#define ELM_IMG_DATA_SHIFT     13
#define ELM_IMG_DATA_MASK      0xFF        /*  8 bits */

#define ELM_W_ADDR_SHIFT       3
#define ELM_W_ADDR_MASK        0x1FFFF     /* 17 bits */
#define ELM_W_DATA_SHIFT       3
#define ELM_W_DATA_MASK        0xFFFF      /* 16 bits */

#define ELM_BIAS_ADDR_SHIFT    3
#define ELM_BIAS_ADDR_MASK     0x7F        /*  7 bits */
#define ELM_BIAS_DATA_SHIFT    10
#define ELM_BIAS_DATA_MASK     0xFFFF      /* 16 bits */

#define ELM_BETA_ADDR_SHIFT    3
#define ELM_BETA_ADDR_MASK     0x7FF       /* 11 bits */
#define ELM_BETA_DATA_SHIFT    14
#define ELM_BETA_DATA_MASK     0xFFFF      /* 16 bits */

/* ============================================================
 * Dimensões da rede ELM implementada no IP
 * ============================================================
 * Estas dimensões estão fixadas em hardware (geradores de endereço
 * em first_layer.v e second_layer.v). Mudar exige refazer o RTL.
 */
#define ELM_IMAGE_PIXELS      784
#define ELM_HIDDEN_NEURONS    128
#define ELM_OUTPUT_NEURONS    10
#define ELM_W_SIZE            (ELM_HIDDEN_NEURONS * ELM_IMAGE_PIXELS)   /* 100352 */
#define ELM_BETA_SIZE         (ELM_HIDDEN_NEURONS * ELM_OUTPUT_NEURONS) /* 1280   */

/* ============================================================
 * Q4.12: 1 bit sinal + 3 bits inteiros + 12 bits fracionários
 * ============================================================ */
#define ELM_Q4_12_SHIFT       12

#ifndef __ASSEMBLER__
#define ELM_Q4_12_SCALE       4096.0f   /* 2^12 */
#endif

/* ============================================================
 * Offsets dos campos no struct elm_t (usados pela rotina ASM)
 * ============================================================
 * Estes valores são contratuais entre elm.h e elm_exec.S. Mudar
 * a ordem dos campos no struct sem atualizar estes #defines E o
 * ASM correspondente quebra silenciosamente o driver. Há um
 * _Static_assert em elm.c que verifica essa correspondência.
 */
#define ELM_OFF_DATA_IN       0
#define ELM_OFF_CTRL          4
#define ELM_OFF_DATA_OUT      8

#endif /* ELM_PROTO_H */
