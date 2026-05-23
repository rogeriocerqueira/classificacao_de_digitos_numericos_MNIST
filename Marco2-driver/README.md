# Driver ELM — Marco 2

Driver userspace para o coprocessador ELM via `/dev/mem`, com as rotinas
críticas (handshake MMIO) escritas em Assembly ARMv7-A conforme exigido
pelo enunciado.

## Estrutura

```
elm_proto.h     constantes do protocolo (opcodes, máscaras de bit, layout
                de instrução, dimensões da rede, offsets dos campos do
                struct). Compartilhado entre C e Assembly.

elm_platform.h  cola entre o driver e o ambiente Qsys gerado. Inclui o
                hps_0.h e define a base da lwh2f bridge. ÚNICO arquivo
                que conhece o hardware específico — se o Qsys mudar,
                edite só aqui.

elm.h           API pública. Aplicações incluem só este header.

elm.c           implementação em C: mmap, encoding de instruções, API
                de alto nível (elm_load_weights, elm_classify, ...).

elm_exec.S      ROTINA CRÍTICA em Assembly ARM. Faz o handshake MMIO
                completo de uma instrução com o coprocessador.

example_main.c  programa mínimo demonstrando o uso.

Makefile        build nativo na HPS ou cross-compile.
```

## Divisão de trabalho C ↔ Assembly

| Camada                   | Linguagem | Onde      |
|--------------------------|-----------|-----------|
| `open` / `mmap`          | C         | `elm.c`   |
| Encoding de instruções   | C         | `elm.c`   |
| **Handshake MMIO**       | **ASM**   | `elm_exec.S` |
| **Polling de flags**     | **ASM**   | `elm_exec.S` |
| **Barreiras de memória** | **ASM**   | `elm_exec.S` |
| API de alto nível        | C         | `elm.c`   |

A única função ASM (`elm_exec`) é chamada por toda operação que toque o
coprocessador. Quando o app faz `elm_load_weights()`, o C orquestra
200.704 chamadas à `elm_exec`, e cada uma delas executa o handshake
bit-a-bit em Assembly.

## Pré-requisitos

1. **Arquivo `hps_0.h`** gerado pelo Qsys, no mesmo diretório. Deve definir,
   para cada PIO, macros com o prefixo do nome do componente:
   - `DATA_IN_BASE`, `DATA_IN_DATA_WIDTH`, `DATA_IN_HAS_OUT`
   - `DATA_OUT_BASE`, `DATA_OUT_DATA_WIDTH`, `DATA_OUT_HAS_IN`
   - `CTRL_BASE`, `CTRL_DATA_WIDTH`, `CTRL_HAS_OUT`

   O `elm_platform.h` faz `_Static_assert` sobre essas larguras e direções,
   então um Qsys mal configurado falha em tempo de compilação, não em
   runtime.

2. **GCC para ARMv7-A** (Cortex-A9). Build nativo na HPS funciona
   diretamente; cross-compile requer toolchain `arm-linux-gnueabihf-`.

## Compilação

Nativo na HPS:
```sh
make
```

Cross-compile:
```sh
make CROSS_COMPILE=arm-linux-gnueabihf-
```

Sobrescrever a base da bridge (se necessário):
```sh
make CFLAGS_EXTRA=-DELM_BRIDGE_BASE=0xFF200000
```

## Uso

```c
#include "elm.h"

elm_t e;
uint8_t pred;

if (elm_open(&e) != ELM_OK) { /* erro */ }

elm_load_weights(&e, W);     /* int16_t W[128][784] em Q4.12 */
elm_load_biases (&e, b);
elm_load_betas  (&e, beta);  /* int16_t beta[10][128] (formato matemático) */

elm_classify(&e, img, &pred);

elm_close(&e);
```

## Gotchas conhecidos

- **`STORE_W_ADDR` não seta DONE.** A `elm_exec` aceita um parâmetro
  `wait_done` justamente para essa exceção. A API de alto nível
  (`elm_store_weight`) já trata isso internamente.

- **Sem auto-incremento de endereço.** Cada peso exige 2 instruções
  (W_ADDR + W_VALUE). 100.352 pesos viram ~200K transações. Os pesos
  só precisam ser carregados uma vez por sessão, então faça isso no
  início e reuse para múltiplas inferências.

- **Carregamento de pesos é lento.** No nosso teste informal, ~100 ms
  para os 100K pesos via bridge não-cacheada. Tolerável para inferências
  esporádicas; para benchmark sério no Marco 3, considerar precarga.

- **`elm_exec` não tem timeout.** Se o coprocessador travar (firmware
  com bug), o polling em ASM trava também. Para produção, adicionar um
  contador de iterações máximas. Para Marco 2, mantemos simples.

## Verificação rápida do binário

Para garantir que a `elm_exec` está realmente em Assembly e não foi
inlined pelo C, inspecione com objdump:

```sh
arm-linux-gnueabihf-objdump -d libelm.a | sed -n '/<elm_exec>:/,/^$/p'
```

Você deve ver `push {r4, r5, r6, lr}` no entry point e `dsb sy` em
vários lugares — sinal de que o ASM está ativo, não substituído.
