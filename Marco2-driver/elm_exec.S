/*
 * elm_exec.S — rotina CRÍTICA do driver ELM (ARM v7-A, Cortex-A9).
 *
 * Implementa o handshake completo de UMA instrução com o coprocessador
 * via os três PIOs (data_in, ctrl, data_out). Esta é a peça que o
 * Marco 2 do enunciado exige em Assembly.
 *
 * Convenção AAPCS:
 *   r0 = elm_t *e
 *        - offset ELM_OFF_DATA_IN  -> ponteiro para data_in PIO
 *        - offset ELM_OFF_CTRL     -> ponteiro para ctrl PIO
 *        - offset ELM_OFF_DATA_OUT -> ponteiro para data_out PIO
 *   r1 = uint32_t instr      (palavra de 32 bits já codificada em C)
 *   r2 = int wait_done       (1 = polling DONE; 0 = só pequeno delay)
 *
 *   Retorna em r0:
 *      0 = sucesso
 *     -1 = flag ERROR subiu durante a operação
 *
 * Sequência:
 *   1. espera busy cair (idle)
 *   2. se há erro residual, limpa antes de prosseguir
 *   3. escreve a instrução em data_in
 *   4. dispara enable em ctrl
 *   5. se wait_done: polling de DONE/ERROR
 *      se !wait_done: pequeno spin (STORE_W_ADDR não seta DONE)
 *   6. abaixa enable
 *   7. espera busy cair (handshake completo)
 *
 * Por que DSB sy? A lwh2f bridge é mapeada como memória Device, então
 * stores não são especulativos, mas dois stores consecutivos podem
 * ser observados em ordem diferente pela FPGA se cruzarem um buffer
 * de write merging. DSB força conclusão antes de prosseguir. Em
 * Cortex-A9 com Device-nGnRnE a barreira é quase um nop, mas garante
 * portabilidade e correção formal.
 */

#include "elm_proto.h"

    .syntax unified
    .arch   armv7-a
    .cpu    cortex-a9
    .text

    .global elm_exec
    .type   elm_exec, %function
    .align  2
elm_exec:
    push    {r4, r5, r6, lr}        @ callee-saved; pilha alinhada em 16

    /* Carrega os três ponteiros para registradores callee-saved.
     * Os offsets vêm de elm_proto.h via #include. */
    ldr     r4, [r0, #ELM_OFF_DATA_IN]    @ r4 = &data_in
    ldr     r5, [r0, #ELM_OFF_CTRL]       @ r5 = &ctrl
    ldr     r6, [r0, #ELM_OFF_DATA_OUT]   @ r6 = &data_out

    /* ----- 1. espera busy cair ----- */
.Lwait_idle:
    ldr     r3, [r6]
    tst     r3, #ELM_ST_BUSY
    bne     .Lwait_idle

    /* ----- 2. limpa erro residual, se houver ----- */
    tst     r3, #ELM_ST_ERROR
    beq     .Lwrite_instr
    mov     r3, #ELM_SIG_CLR_OP
    str     r3, [r5]
    mov     r3, #0
    str     r3, [r5]
    dsb     sy

.Lwrite_instr:
    /* ----- 3. escreve a instrução em data_in ----- */
    str     r1, [r4]
    dsb     sy                      @ data_in tem que ser visto ANTES do enable

    /* ----- 4. sobe enable ----- */
    mov     r3, #ELM_SIG_ENABLE
    str     r3, [r5]
    dsb     sy

    /* ----- 5. polling ou delay curto ----- */
    cmp     r2, #0
    beq     .Lshort_delay

.Lpoll_done:
    ldr     r3, [r6]
    tst     r3, #ELM_ST_ERROR
    bne     .Lhw_error
    tst     r3, #ELM_ST_DONE
    beq     .Lpoll_done
    b       .Llower_enable

.Lshort_delay:
    /* STORE_W_ADDR completa em ~1 ciclo de FPGA (20 ns). Os próprios
     * STR através da bridge já gastam muito mais que isso, então
     * basta um pequeno spin para ser pedante. */
    mov     r3, #16
.Ldelay_loop:
    subs    r3, r3, #1
    bne     .Ldelay_loop

.Llower_enable:
    /* ----- 6. abaixa enable ----- */
    mov     r3, #0
    str     r3, [r5]
    dsb     sy

    /* ----- 7. espera busy cair (libera para a próxima instrução) ----- */
.Lwait_not_busy:
    ldr     r3, [r6]
    tst     r3, #ELM_ST_BUSY
    bne     .Lwait_not_busy

    mov     r0, #0                  @ return 0 (sucesso)
    pop     {r4, r5, r6, pc}

.Lhw_error:
    /* Cleanup: abaixa enable, limpa flag ERROR, retorna -1. */
    mov     r3, #0
    str     r3, [r5]
    dsb     sy
    mov     r3, #ELM_SIG_CLR_OP
    str     r3, [r5]
    mov     r3, #0
    str     r3, [r5]
    dsb     sy
    mvn     r0, #0                  @ r0 = 0xFFFFFFFF = -1
    pop     {r4, r5, r6, pc}

    .size   elm_exec, .-elm_exec

/* Marca a stack como não-executável (boa prática ELF moderna) */
    .section .note.GNU-stack, "", %progbits
    .end
