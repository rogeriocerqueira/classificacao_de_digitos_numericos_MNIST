# Marco 2 — Driver Linux Assembly

<p align="center">
  <a href="MARCO1.md">
    <img src="https://img.shields.io/badge/Marco%201-gray?style=for-the-badge"/>
    <img src="https://img.shields.io/badge/Co--Processador-1565C0?style=for-the-badge&logo=intel"/>
  </a>
  &nbsp;
  <a href="README.md">
    <img src="https://img.shields.io/badge/← Voltar-README-gray?style=for-the-badge"/>
  </a>
  &nbsp;
  <a href="MARCO3.md">
    <img src="https://img.shields.io/badge/Marco%203-gray?style=for-the-badge"/>
    <img src="https://img.shields.io/badge/API%20C-2E7D32?style=for-the-badge&logo=c"/>
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Assembly-ARM%20Cortex--A9-red?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/C-Driver%20Linux-blue?style=for-the-badge"/>
  <img src="https://img.shields.io/badge/Marco%202-Concluído-brightgreen?style=for-the-badge"/>
</p>

---

## Sumário

1. [Descrição](#descrição)
2. [O Chip Cyclone V — HPS e FPGA](#o-chip-cyclone-v--hps-e-fpga)
3. [Arquitetura do Sistema](#arquitetura-do-sistema)
4. [Os 3 PIOs — Ponte HPS↔FPGA](#os-3-pios--ponte-hpsfpga)
5. [Conjunto de Instruções (ISA)](#conjunto-de-instruções-isa)
6. [Estrutura do Repositório](#estrutura-do-repositório)
7. [Driver Assembly — elm_exec.S](#driver-assembly--elm_execs)
8. [Driver C — elm.c](#driver-c--elmc)
9. [Parser de Arquivos .mif — elm_mif.c](#parser-de-arquivos-mif--elm_mifc)
10. [Programa de Teste — marco2_test.c](#programa-de-teste--marco2_testc)
11. [Integração com o Marco 1](#integração-com-o-marco-1)
12. [Fluxo Completo de uma Inferência](#fluxo-completo-de-uma-inferência)
13. [Softwares Utilizados](#softwares-utilizados)
14. [Compilação na Placa](#compilação-na-placa)
15. [Teste na Placa](#teste-na-placa)
16. [Análise dos Resultados](#análise-dos-resultados)

---

## Descrição

O Marco 2 implementa o **driver Linux** que conecta o processador ARM (HPS) ao co-processador ELM sintetizado na FPGA, permitindo classificar dígitos manuscritos MNIST em tempo real.

> ⚙️ **Co-processador utilizado:** Este driver foi desenvolvido e validado para operar com o co-processador ELM disponível em:
> **[https://github.com/DestinyWolf/Problema_SD_2026_1](https://github.com/DestinyWolf/Problema_SD_2026_1)**
> O bitstream gerado (`soc_system.sof`) já integra esse co-processador — basta gravá-lo na FPGA antes de executar o driver.

A comunicação é feita via **Memory-Mapped I/O (MMIO)** através da lightweight HPS-to-FPGA bridge do Cyclone V. O núcleo da implementação é o arquivo `elm_exec.S`, escrito inteiramente em **Assembly ARM Cortex-A9**, que implementa 9 funções responsáveis por 100% do acesso ao hardware.

---

## O Chip Cyclone V — HPS e FPGA

A DE1-SoC usa um chip Cyclone V que contém dois mundos dentro do mesmo encapsulamento:

```
┌─────────────────────────────────────────────────────────┐
│                    Chip Cyclone V                        │
│                                                          │
│  ┌───────────────────┐          ┌─────────────────────┐  │
│  │        HPS        │          │        FPGA         │  │
│  │  ARM Cortex-A9    │          │  CoProcessor ELM    │  │
│  │  Linux rodando    │◄────────►│  (rede neural em    │  │
│  │  Driver ASM       │  bridge  │   hardware)         │  │
│  │                   │          │  BRAM com pesos     │  │
│  └───────────────────┘          └─────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**HPS — Hard Processor System:**
- ARM Cortex-A9 dual-core 925 MHz
- RAM DDR3 1 GB
- Linux rodando nativamente
- Executa o driver (`elm_exec.S`, `elm.c`)

**FPGA — Lógica Reconfigurável:**
- CoProcessor ELM sintetizado em Verilog
- Pesos W_in, bias e beta gravados na BRAM via arquivos `.mif`
- 3 PIOs conectados à bridge para comunicação com o HPS
- Configurada pelo bitstream `soc_system.sof`

---

## Arquitetura do Sistema

```
┌──────────────────────────────────────────────────────────────┐
│                        DE1-SoC                               │
│                                                              │
│   ┌──────────────┐   Lightweight    ┌──────────────────────┐ │
│   │   HPS ARM    │   Bridge         │        FPGA          │ │
│   │  Cortex-A9   │  0xFF200000      │                      │ │
│   │              │                  │  ┌────────────────┐  │ │
│   │  elm_mif.c   │──── 0xFF200040 ─►│  │   data_in PIO  │  │ │
│   │  (lê .mif)   │                  │  └───────┬────────┘  │ │
│   │              │                  │          │           | │
│   │  elm.c       │◄─── 0xFF200050 ──│  ┌───────▼────────┐  │ │
│   │  (API C)     │                  │  │  CoProcessor   │  │ │
│   │              │──── 0xFF200060 ─►│  │     ELM        │  │ │
│   │  elm_exec.S  │                  │  └───────┬────────┘  │ │
│   │  (Assembly)  │                  │          │           │ │
│   │              │◄─── 0xFF200050 ──│  ┌───────▼────────┐  │ │
│   └──────────────┘                  │  │  data_out PIO  │  │ │
│                                     │  └────────────────┘  │ │
│                                     │  ┌────────────────┐  │ │
│                                     │  │   ctrl PIO     │  │ │
│                                     │  └────────────────┘  │ │
│                                     └──────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Os 3 PIOs — Ponte HPS↔FPGA

Três PIOs foram configurados no **Platform Designer (Qsys)** e conectados ao `hps_0.h2f_lw_axi_master`:

| PIO       | Largura | Direção    | Endereço físico | Função |
|-----------|---------|------------|-----------------|--------|
| `data_in` | 32 bits | HPS → FPGA | `0xFF200040`    | HPS envia instrução ao CoProcessor |
| `data_out`| 32 bits | FPGA → HPS | `0xFF200050`    | CoProcessor retorna status e resultado |
| `ctrl`    | 3 bits  | HPS → FPGA | `0xFF200060`    | `bit0`=Enable · `bit1`=ClrOp · `bit2`=Reset |

**Cálculo dos endereços:**
```
0xFF200000  (bridge base — fixo no Cyclone V)
+     0x40  (offset do PIO — definido no Platform Designer)
──────────
0xFF200040  (endereço físico do data_in)
```

**Bits do registrador `data_out`:**

| Bits    | Campo   | Descrição                 |
|---------|---------|---------------------------|
| `[3:0]` | `DIGIT` | Dígito predito (0–9)      |
| `[4]`   | `DONE`  | Inferência concluída      |
| `[5]`   | `BUSY`  | CoProcessor ocupado       |
| `[6]`   | `ERROR` | Erro durante operação     |

> A direção é **do ponto de vista do HPS**: `data_in` é Output porque o HPS *escreve* para a FPGA; `data_out` é Input porque o HPS *lê* da FPGA.

---

## Conjunto de Instruções (ISA)

O co-processador possui 6 instruções implementadas pelo driver. Cada instrução é uma palavra de 32 bits enviada pelo PIO `data_in`:

| Instrução             | OPCode | Função Assembly       | Layout dos 32 bits                      |
|-----------------------|--------|-----------------------|-----------------------------------------|
| `Store Image`         | `000`  | `enc_store_img()`     | `[zeros][pixel 8b][addr 10b][000]`      |
| `Store Weights Addr`  | `001`  | `enc_store_w_addr()`  | `[zeros][addr 17b][001]`                |
| `Store Weights Value` | `010`  | `enc_store_w_value()` | `[zeros][value 16b][010]`               |
| `Store Bias`          | `011`  | `enc_store_bias()`    | `[zeros][value 16b][addr 7b][011]`      |
| `Store Beta`          | `100`  | `enc_store_beta()`    | `[zeros][value 16b][addr 11b][100]`     |
| `Start`               | `101`  | `enc_start()`         | `[zeros][101]`                          |

> `Store Weights Addr` e `Store Weights Value` são sempre enviadas em par — o endereço primeiro (`ELM_NO_WAIT`) e o valor na sequência (`ELM_WAIT_DONE`), pois `STORE_W_ADDR` não seta o sinal `DONE`.

---

## Estrutura do Repositório

```bash
Marco2-driver/
├── elm_exec.S          # Assembly ARM — 9 funções, 100% do acesso ao hardware
├── elm.c               # API C — inicialização, mmap e chamadas ao Assembly
├── elm.h               # Interface pública do driver
├── elm_platform.h      # _Static_assert verificam endereços em compilação
├── elm_proto.h         # Opcodes, shifts, máscaras — compartilhado C e Assembly
├── hps_0.h             # Endereços dos PIOs (gerado com base no Quartus 24.1)
├── elm_mif.c           # Parser de arquivos .mif do filesystem
├── elm_mif.h           # Interface do parser
├── example_main.c      # Programa de teste simples (elm_test)
├── marco2_test.c       # Programa de validação completa
├── build.sh            # Script de compilação nativa na placa
└── mif_files/
    ├── mem_win.mif     # Pesos W_in (100.352 valores em Q4.12)
    ├── mem_bias.mif    # Bias (128 valores em Q4.12)
    ├── mem_beta.mif    # Beta (1.280 valores em Q4.12)
    └── mem_img.mif     # Imagem a classificar (784 pixels)
```

---

## Driver Assembly — elm_exec.S

O arquivo `elm_exec.S` implementa **9 funções em Assembly ARM Cortex-A9** responsáveis por 100% do acesso ao hardware.

### As 9 funções

| Função              | Descrição                                            |
|---------------------|------------------------------------------------------|
| `elm_exec`          | Handshake completo com o CoProcessor via 3 PIOs      |
| `elm_reset`         | Reseta o CoProcessor via ctrl PIO                    |
| `elm_clear_error`   | Limpa flag de erro via ctrl PIO                      |
| `enc_store_img`     | Codifica instrução STORE_IMAGE (opcode 000)          |
| `enc_store_w_addr`  | Codifica instrução STORE_WEIGHTS_ADDR (opcode 001)   |
| `enc_store_w_value` | Codifica instrução STORE_WEIGHTS_VALUE (opcode 010)  |
| `enc_store_bias`    | Codifica instrução STORE_BIAS (opcode 011)           |
| `enc_store_beta`    | Codifica instrução STORE_BETA (opcode 100)           |
| `enc_start`         | Codifica instrução START (opcode 101)                |

### Sequência do elm_exec (8 passos por instrução)

```asm
1. Espera BUSY cair        ← polling data_out bit5
2. Limpa erro residual     ← ctrl = CLR_OP se ERROR=1
3. Escreve instrução       ← str r1, [r4]  (data_in)
4. dsb sy                 │ ← barreira de memória CRÍTICA
5. Sobe enable             ← str ENABLE, [r5]  (ctrl)
6. Polling DONE/ERROR      ← ldr r3, [r6]  (data_out)
7. Abaixa enable           ← str 0, [r5]  (ctrl)
8. Espera BUSY cair        ← handshake completo
```

## Driver C — elm.c

O `elm.c` cuida apenas do que não precisa de controle de baixo nível:

| Função                    | Descrição                                                  |
|---------------------------|------------------------------------------------------------|
| `elm_open()`              | Abre `/dev/mem`, faz `mmap` da bridge, chama `elm_reset`   |
| `elm_close()`             | Libera `mmap` e fecha `/dev/mem`                           |
| `elm_store_image_pixel()` | Valida parâmetros e chama `elm_exec(enc_store_img(...))`   |
| `elm_store_weight()`      | Envia par STORE_W_ADDR + STORE_W_VALUE                     |
| `elm_store_bias()`        | Valida e chama `elm_exec(enc_store_bias(...))`             |
| `elm_store_beta()`        | Valida e chama `elm_exec(enc_store_beta(...))`             |
| `elm_classify()`          | Chama `elm_load_image()` + `elm_start()`                   |

Todas as funções de hardware são declaradas como `extern` — implementadas em `elm_exec.S`:

```c
extern int      elm_exec(elm_t *e, uint32_t instr, int wait_done);
extern void     elm_reset(elm_t *e);
extern void     elm_clear_error(elm_t *e);
extern uint32_t enc_store_img(uint16_t addr, uint8_t pixel);
extern uint32_t enc_store_w_addr(uint32_t addr);
extern uint32_t enc_store_w_value(int16_t value);
extern uint32_t enc_store_bias(uint8_t addr, int16_t value);
extern uint32_t enc_store_beta(uint16_t addr, int16_t value);
extern uint32_t enc_start(void);
```

---

## Parser de Arquivos .mif — elm_mif.c

O `elm_mif.c` lê os arquivos `.mif` do filesystem (cartão SD da placa) e converte para arrays na RAM do ARM:

```c
// Lê imagem (784 pixels, 8 bits cada)
elm_mif_load_image("mif_files/mem_img.mif", &img, &img_sz);

// Lê pesos em Q4.12 (signed 16 bits)
elm_mif_load_q4_12("mif_files/mem_win.mif", &W, &sz);
```

**Estratégia do parser:**
1. `fopen` + `fread` — lê o arquivo inteiro para a RAM
2. `strip_comments` — remove comentários `--linha` e `%...%`
3. `find_field` — extrai DEPTH, WIDTH, DATA_RADIX do header
4. `apply_stmt` — processa cada `addr : valor;` do bloco CONTENT

---

## Programa de Teste — marco2_test.c

Cumpre o requisito do enunciado: enviar 1 imagem fixa e obter classificação correta repetidamente.

```bash
sudo ./marco2_test [-d mif_dir] [-n N_iters] [-e classe_esperada]
```

**Sequência de execução:**

```
[1/4] Abre o driver (elm_open)
[2/4] Carrega e envia pesos/bias/beta via driver
[3/4] Carrega imagem do filesystem (elm_mif_load_image)
[4/4] Roda N inferências:
      - mede latência com clock_gettime (CLOCK_MONOTONIC)
      - verifica estabilidade (pred == first_pred)
      - detecta erros de hardware (rc != ELM_OK)
      Imprime PASS ou FAIL
```

## Integração com o Marco 1

O projeto Quartus `elm_hps_project/soc_system.qpf` integra:

| Componente           | Origem           | Função                                          |
|----------------------|------------------|-------------------------------------------------|
| `soc_system.qsys`    | Platform Designer| HPS + 3 PIOs conectados ao lw_axi_master        |
| `ghrd_top.v`         | Marco 2          | Top-level que instancia soc_system + CoProcessor|
| `CoProcessor.v`      | Marco 1          | Rede neural ELM em hardware                     |
| `aux_files/*.v`      | Marco 1          | MAC, reg_bank, tanh PWL Q4.12, display          |
| `inference_unit/*.v` | Marco 1          | first_layer, second_layer, argmax iterativo     |
| `memory_files/*.mif` | Marco 1          | Pesos W_in, bias e beta na BRAM                 |

### Resultado da compilação Quartus

```
Flow Status:     Successful
Logic (ALMs):    3,347 / 32,070  (10%)
Total registers: 4,574
Block memory:    2,162,976 / 4,065,280  (53%)  ← pesos .mif na BRAM
DSP Blocks:      10 / 87  (11%)
0 errors, 762 warnings
```

> O aumento de 7%→10% em ALMs e 13%→53% em BRAM confirma que o CoProcessor foi integrado com sucesso.

---

## Fluxo Completo de uma Inferência

```
Filesystem (cartão SD)
└── mif_files/mem_img.mif
         │
         │ elm_mif.c: fopen + fread + parse
         ▼
RAM do ARM (DDR3)
└── uint8_t img[784]
         │
         │ elm.c: elm_classify() → elm_load_image()
         │        itera 784 vezes
         ▼
elm_exec.S: enc_store_img(addr, pixel)
            → instrução de 32 bits
            str r1, [r4]    ← escreve em data_in
            dsb sy          ← barreira de memória
            str ENABLE, [r5]← sobe enable em ctrl
            polling [r6]    ← espera DONE em data_out
         │
         │ Lightweight Bridge (0xFF200000)
         ▼
PIO data_in (0xFF200040)
         │ repete 784 vezes
         ▼
CoProcessor ELM (FPGA)
├── W_in × pixels + bias → tanh PWL Q4.12
└── beta × hidden → argmax
         │
         ▼
PIO data_out (0xFF200050)
└── bits[3:0] = dígito predito
    bit[4]    = DONE
         │
         │ elm_exec.S: ldr r3, [r6]
         ▼
RAM do ARM
└── uint8_t pred = 7
         │
         ▼
Terminal SSH + HEX0 + LEDR[0]
└── "predição: 7   PASS"
```

---

## Softwares Utilizados

| Software                         | Versão         | Finalidade                                        |
|----------------------------------|----------------|---------------------------------------------------|
| Intel Quartus Prime Lite Edition | 24.1std.0.1077 | Integração HPS↔FPGA via Platform Designer (Qsys) |
| GCC (nativo ARM)                 | armv7-a        | Compilação nativa na placa (C + Assembly)         |
| GNU Make / build.sh              | —              | Automação do build                                |
| minicom / PuTTY / SSH            | —              | Acesso à DE1-SoC                                  |
| Python 3                         | 3.10+          | Geração e validação dos arquivos .mif             |
| Git                              | —              | Controle de versão                                |

---

## Compilação na Placa

Os binários compilados no host x86 não rodam na placa por incompatibilidade de glibc. Compile nativamente usando o `build.sh`:

```bash
# Transferir os fontes
scp elm.c elm.h elm_exec.S elm_mif.c elm_mif.h \
    elm_platform.h elm_proto.h hps_0.h \
    example_main.c marco2_test.c build.sh \
    aluno@<IP>:/home/aluno/TEC499/TP01/G0X/Marco2-driver/

# Compilar na placa
ssh aluno@<IP>
cd ~/TEC499/TP01/G0X/Marco2-driver
chmod +x build.sh
./build.sh
```

**Ou passo a passo manualmente:**

```bash
# Objetos
gcc -O2 -Wall -Wextra -std=gnu99 -march=armv7-a \
    -mfpu=neon -mfloat-abi=hard -I. -c elm.c -o elm.o

gcc -march=armv7-a -mfpu=neon -mfloat-abi=hard -I. \
    -c elm_exec.S -o elm_exec.o

gcc -O2 -Wall -Wextra -std=gnu99 -march=armv7-a \
    -mfpu=neon -mfloat-abi=hard -I. -c elm_mif.c -o elm_mif.o

# Biblioteca estática
ar rcs libelm.a elm.o elm_exec.o elm_mif.o

# Executável de teste simples
gcc -O2 -std=gnu99 -march=armv7-a -mfpu=neon -mfloat-abi=hard \
    -I. -c example_main.c -o example_main.o
gcc -O2 -std=gnu99 -march=armv7-a -mfpu=neon -mfloat-abi=hard \
    -o elm_test example_main.o -L. -lelm -lm

# Executável de validação completa
gcc -O2 -Wall -Wextra -std=gnu99 -march=armv7-a \
    -mfpu=neon -mfloat-abi=hard -I. -c marco2_test.c -o marco2_test.o
gcc -O2 -std=gnu99 -march=armv7-a -mfpu=neon -mfloat-abi=hard \
    -o marco2_test marco2_test.o -L. -lelm -lm -lrt
```

---
### 1. Gravar o bitstream

```
Quartus → Tools → Programmer
→ elm_hps_project/output_files/soc_system.sof
→ Start → aguarda 100% (Successful)
```

### 2. Transferir os mif_files

```bash
ssh aluno@<IP> "mkdir -p ~/TEC499/TP01/G0X/Marco2-driver/mif_files"
scp mif_files/* aluno@<IP>:~/TEC499/TP01/G0X/Marco2-driver/mif_files/

# Opcional — todas as imagens para testar múltiplos dígitos
scp ../Marco1-coprocessador/image_files/imagem_*.mif \
    aluno@<IP>:~/TEC499/TP01/G0X/Marco2-driver/mif_files/
```

### 3. Teste simples

```bash
sudo ./elm_test
```

Saída esperada:
```
Driver aberto. data_out inicial = 0x00000000
Resultado: 0 (status final = 0x00000010)   ← DONE=1 ✓
```

> `elm_test` usa imagem sintética (pixels zerados) — o status `0x00000010` confirma DONE=1, hardware funcionando.

### 4. Teste completo de estabilidade

```bash
sudo ./marco2_test -d ./mif_files -n 10 -e 7
```

Saída esperada:
```
===== Marco 2 — Teste de Estabilidade =====
[1/4] Driver aberto. status inicial = 0x00000000
[2/4] Carregando e enviando pesos/bias/beta...
[3/4] Imagem mem_img.mif: 784 pixels carregados
[4/4] Rodando 10 inferências...
  iter    0: pred=7 (latência: X.XX ms) [referência]

===== Resultado =====
  predição:             7
  classificação:        CORRETA (esperado 7)
  instabilidade:        0
  erro de hardware:     0
PASS
```

### 5. Testar outros dígitos

```bash
cp mif_files/imagem_4.mif mif_files/mem_img.mif
sudo ./marco2_test -d ./mif_files -n 5 -e 4

cp mif_files/imagem_0.mif mif_files/mem_img.mif
sudo ./marco2_test -d ./mif_files -n 5 -e 0
```

## Análise dos Resultados


| Métrica               | Valor                  |
|-----------------------|------------------------|
| Resultado final       | **PASS**               |
| Dígito classificado   | **7** (CORRETA)        |
| Iterações executadas  | 10                     |
| Erro de hardware      | 0                      |
| Instabilidade         | 0                      |
| Latência média        | ~3,5 ms                |
| Throughput            | **285,6 img/s**        |
