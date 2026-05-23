/*
 * elm_platform.h — cola entre o driver e o ambiente Qsys gerado.
 *
 * Aqui é o ÚNICO ponto do código que conhece:
 *   - o arquivo hps_0.h gerado pelo Qsys
 *   - a base física da lwh2f bridge no Cyclone V
 *
 * Se você mover o projeto para outra placa SoC, mover os PIOs no
 * Qsys ou trocar o nome dos componentes, edite SÓ este arquivo.
 *
 * Os macros que esperamos de hps_0.h (gerados automaticamente pelo
 * Qsys com prefixo = nome do PIO em maiúsculas) são:
 *
 *   DATA_IN_BASE, DATA_IN_DATA_WIDTH, DATA_IN_HAS_OUT, DATA_IN_SPAN
 *   DATA_OUT_BASE, DATA_OUT_DATA_WIDTH, DATA_OUT_HAS_IN, DATA_OUT_SPAN
 *   CTRL_BASE, CTRL_DATA_WIDTH, CTRL_HAS_OUT, CTRL_SPAN
 */

#ifndef ELM_PLATFORM_H
#define ELM_PLATFORM_H

#include "hps_0.h"

/* ============================================================
 * Base física da lightweight HPS-to-FPGA bridge
 * ============================================================
 * 0xFF200000 é constante do chip Cyclone V (não muda entre projetos
 * Qsys). Algumas versões da geração de cabeçalhos Altera definem isto
 * como ALT_LWFPGASLVS_OFST em socal/hps.h; respeitamos se existir.
 * Permite override via -DELM_BRIDGE_BASE=0x... na linha de comando.
 */
#ifndef ELM_BRIDGE_BASE
  #ifdef ALT_LWFPGASLVS_OFST
    #define ELM_BRIDGE_BASE   ALT_LWFPGASLVS_OFST
  #else
    #define ELM_BRIDGE_BASE   0xFF200000UL
  #endif
#endif

/* Tamanho do mapeamento. A lwh2f bridge cobre 2 MB no Cyclone V, mas
 * para acessar os PIOs basta uma página (4 KB) ou um pouco mais. 64 KB
 * deixa folga para futuras adições sem precisar refazer o mmap. */
#ifndef ELM_BRIDGE_SPAN
  #define ELM_BRIDGE_SPAN     0x00010000UL
#endif

/* ============================================================
 * Verificações de sanidade contra o hps_0.h gerado
 * ============================================================
 * Se o Qsys for refeito com larguras ou direções diferentes, a
 * compilação falha aqui — bem melhor do que um bug silencioso em
 * runtime. _Static_assert é C11 (suportado pelo GCC há anos).
 */
#ifndef __ASSEMBLER__

_Static_assert(DATA_IN_DATA_WIDTH  == 32,
               "PIO 'data_in' precisa ter 32 bits — confira o Qsys");
_Static_assert(DATA_OUT_DATA_WIDTH == 32,
               "PIO 'data_out' precisa ter 32 bits — confira o Qsys");
_Static_assert(CTRL_DATA_WIDTH     ==  3,
               "PIO 'ctrl' precisa ter 3 bits — confira o Qsys");

_Static_assert(DATA_IN_HAS_OUT  == 1,
               "PIO 'data_in' precisa ser de SAIDA (HPS -> FPGA)");
_Static_assert(DATA_OUT_HAS_IN  == 1,
               "PIO 'data_out' precisa ser de ENTRADA (FPGA -> HPS)");
_Static_assert(CTRL_HAS_OUT     == 1,
               "PIO 'ctrl' precisa ser de SAIDA (HPS -> FPGA)");

/* Se os offsets dos PIOs ultrapassarem o span mapeado, falha logo. */
_Static_assert(DATA_IN_BASE  < ELM_BRIDGE_SPAN, "data_in fora do mmap");
_Static_assert(DATA_OUT_BASE < ELM_BRIDGE_SPAN, "data_out fora do mmap");
_Static_assert(CTRL_BASE     < ELM_BRIDGE_SPAN, "ctrl fora do mmap");

#endif /* !__ASSEMBLER__ */

#endif /* ELM_PLATFORM_H */
