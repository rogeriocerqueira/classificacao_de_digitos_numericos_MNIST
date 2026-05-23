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

---

## Sumário

1. [Objetivo](#objetivo)
2. [Co-processador de Referência](#co-processador-de-referência)
3. [Levantamento de Requisitos](#levantamento-de-requisitos)
4. [Mapa de Registradores MMIO](#mapa-de-registradores-mmio)
5. [ISA do Co-processador](#isa-do-co-processador)
6. [Arquitetura do Driver](#arquitetura-do-driver)
7. [API do Driver](#api-do-driver)
8. [Softwares Utilizados](#softwares-utilizados)
9. [Instalação e Configuração do Ambiente](#instalação-e-configuração-do-ambiente)
10. [Execução dos Testes](#execução-dos-testes)
11. [Análise dos Resultados](#análise-dos-resultados)

---

## Objetivo

> Integrar o co-processador ELM ao HPS (ARM Cortex-A9) da DE1-SoC e controlar a inferência via **MMIO (Memory-Mapped I/O)**, com um driver escrito em **Assembly ARM** expondo uma API consistente para aplicações em espaço de usuário.

---

## Co-processador de Referência

O co-processador utilizado neste marco é o desenvolvido no repositório:

> 🔗 **[DestinyWolf/Problema_SD_2026_1](https://github.com/DestinyWolf/Problema_SD_2026_1/tree/master)**

Este IP implementa o mesmo núcleo ELM descrito no [Marco 1](MARCO1.md), com a adição do mapeamento de registradores acessíveis via **Lightweight HPS-to-FPGA Bridge** da DE1-SoC. A integração entre o IP Verilog e o HPS foi realizada no **Platform Designer (Qsys)** do Quartus Prime 24.1 Lite, expondo os registradores de controle em um endereço base fixo no espaço de memória do ARM.

---

## Levantamento de Requisitos

O driver deve permitir que a aplicação em C:

- Inicialize o hardware e mapeie os registradores MMIO
- Envie a imagem (784 bytes) ao co-processador
- Envie os pesos (`W_in`, `b`, `β`) ao co-processador
- Inicie a inferência
- Aguarde a finalização via polling sobre o registrador `STATUS`
- Leia o dígito predito (0–9) e métricas de tempo
- Libere os recursos mapeados ao encerrar

**Restrições:**

- Rotinas críticas de MMIO em **Assembly ARMv7**
- API coerente via userspace (`/dev/mem`)
- Teste mínimo: classificar uma imagem fixa repetidamente sem falhas de consistência

---

## Mapa de Registradores MMIO

Endereço base do IP na Lightweight Bridge: `0xFF200000` (configurável via Platform Designer).

| Offset | Nome          | Acesso | Descrição                                                                       |
|--------|---------------|--------|---------------------------------------------------------------------------------|
| `0x00` | `CTRL`        | W      | Bit 0: `START` — inicia inferência; Bit 1: `RESET`                              |
| `0x04` | `STATUS`      | R      | Bits [1:0]: `00`=IDLE, `01`=BUSY, `10`=DONE, `11`=ERROR; Bits [5:2]: dígito predito |
| `0x08` | `IMG_ADDR`    | W      | Endereço base do bloco de pixels (784 × 16-bit Q4.12)                          |
| `0x0C` | `WEIGHT_ADDR` | W      | Endereço base dos pesos `W_in` (128 × 784 × 16-bit)                            |
| `0x10` | `BIAS_ADDR`   | W      | Endereço base do bias `b` (128 × 16-bit)                                        |
| `0x14` | `BETA_ADDR`   | W      | Endereço base de β (10 × 128 × 16-bit)                                          |
| `0x18` | `CYCLES`      | R      | Contador de ciclos da última inferência                                         |
| `0x1C` | `RESULT`      | R      | Dígito predito isolado em bits [3:0]                                            |

---

## ISA do Co-processador

| Instrução       | Operação                                                        |
|-----------------|-----------------------------------------------------------------|
| `STORE_IMG`     | Armazena os 784 pixels (Q4.12) na RAM interna de imagem        |
| `STORE_WEIGHTS` | Armazena a matriz `W_in` (128 × 784) na RAM de pesos           |
| `STORE_BIAS`    | Armazena o vetor `b` (128) na RAM de bias                      |
| `START`         | Dispara a FSM de inferência                                     |
| `STATUS`        | Retorna estado (`BUSY`/`DONE`/`ERROR`) e o dígito predito [0–9]|

---

## Arquitetura do Driver

O driver é organizado em três camadas:

```
┌─────────────────────────────┐
│   Aplicação C (Marco 3)     │  ← digit_classify.c
├─────────────────────────────┤
│   API Pública (elm_driver.h)│  ← protótipos em C
├─────────────────────────────┤
│   Rotinas Assembly ARMv7    │  ← elm_driver.s (MMIO direto)
├─────────────────────────────┤
│   /dev/mem  ·  mmap()       │  ← acesso ao espaço físico
├─────────────────────────────┤
│   Lightweight HPS-FPGA Br.  │  ← 0xFF200000
│   Co-processador ELM (FPGA) │
└─────────────────────────────┘
```

O arquivo `elm_driver.s` contém as rotinas críticas em Assembly ARMv7:

- **`elm_mmio_write`** — escreve 32 bits em um registrador MMIO
- **`elm_mmio_read`** — lê 32 bits de um registrador MMIO
- **`elm_send_image`** — loop de transferência dos 784 pixels via MMIO
- **`elm_poll_status`** — polling com timeout sobre o registrador `STATUS`
- **`elm_read_result`** — lê e retorna o campo de dígito predito

---

## API do Driver

Cabeçalho: `driver/elm_driver.h`

```c
/**
 * Inicializa o driver: abre /dev/mem e faz mmap() da região MMIO.
 * Retorna 0 em sucesso, -1 em erro (errno definido).
 */
int elm_init(void);

/**
 * Libera o mmap e fecha o descritor de /dev/mem.
 */
void elm_close(void);

/**
 * Transfere os 784 pixels (Q4.12, uint16_t) para o co-processador.
 * Retorna 0 em sucesso.
 */
int elm_send_image(const uint16_t *img);

/**
 * Transfere os pesos W_in (128×784 uint16_t) para o co-processador.
 */
int elm_send_weights(const uint16_t *w_in);

/**
 * Transfere o vetor de bias b (128 uint16_t) para o co-processador.
 */
int elm_send_bias(const uint16_t *bias);

/**
 * Transfere os pesos de saída beta (10×128 uint16_t) para o co-processador.
 */
int elm_send_beta(const uint16_t *beta);

/**
 * Dispara a inferência (escreve START no registrador CTRL).
 */
int elm_start(void);

/**
 * Aguarda a conclusão por polling (timeout em ms).
 * Retorna 0 (DONE), 1 (BUSY após timeout), -1 (ERROR).
 */
int elm_wait(int timeout_ms);

/**
 * Lê o dígito predito (0–9) do registrador RESULT.
 * Chamar após elm_wait() retornar 0.
 */
int elm_read_digit(void);

/**
 * Lê o contador de ciclos da última inferência.
 */
uint32_t elm_read_cycles(void);
```

**Fluxo de uso:**

```c
elm_init();
elm_send_weights(w_in);
elm_send_bias(b);
elm_send_beta(beta);
elm_send_image(img);
elm_start();
if (elm_wait(5000) == 0) {
    printf("Dígito: %d\n", elm_read_digit());
}
elm_close();
```

---

## Softwares Utilizados

| Software                         | Versão         | Finalidade                                        |
|----------------------------------|----------------|---------------------------------------------------|
| Intel Quartus Prime Lite Edition | 24.1std.0.1077 | Integração HPS↔FPGA via Platform Designer (Qsys) |
| arm-linux-gnueabihf-gcc          | 12.x           | Cross-compilação do driver e da aplicação de teste|
| arm-linux-gnueabihf-as           | 2.40+          | Montagem dos módulos Assembly ARMv7               |
| GNU Make                         | 4.3+           | Automação do build                                |
| Python 3                         | 3.10+          | Conversão PNG → Q4.12 para testes                 |
| minicom / PuTTY                  | —              | Acesso serial à DE1-SoC                           |
| Git                              | —              | Controle de versão                                |

---

## Instalação e Configuração do Ambiente

#### 1. Instalar a toolchain ARM no host (Linux)

```bash
sudo apt update
sudo apt install gcc-arm-linux-gnueabihf binutils-arm-linux-gnueabihf
```

Verificar instalação:

```bash
arm-linux-gnueabihf-gcc --version
arm-linux-gnueabihf-as --version
```

#### 2. Clonar o repositório do co-processador de referência

```bash
git clone https://github.com/DestinyWolf/Problema_SD_2026_1.git
cd Problema_SD_2026_1
```

Seguir as instruções do repositório para gerar o `.sof` com a integração HPS↔FPGA via Platform Designer e gravá-lo na DE1-SoC.

#### 3. Compilar o driver e o teste mínimo

```bash
cd driver/
make
```

Gera:
- `elm_driver.o` — módulo objeto Assembly ARMv7
- `test_driver` — binário ARM para teste de estabilidade

#### 4. Transferir para a DE1-SoC

```bash
scp test_driver root@<ip-da-placa>:/home/root/
```

#### 5. Programar a FPGA e executar

```bash
# Carregar o bitstream
quartus_pgm -m jtag -o "p;output_files/elm_top.sof"

# Rodar o teste de estabilidade
./test_driver --image img_4.hex --repeat 100
```

---

## Execução dos Testes

#### Teste de estabilidade (requisito mínimo do Marco 2)

```bash
./test_driver --image img_4.hex --repeat 100
```

Saída esperada:

```
[ELM Driver] Inicializando MMIO @ 0xFF200000 ... OK
[ELM Driver] Enviando pesos W_in  ... OK
[ELM Driver] Enviando bias b      ... OK
[ELM Driver] Enviando pesos beta  ... OK

Inferência   1/100 → dígito=4  ciclos=102166  OK
Inferência   2/100 → dígito=4  ciclos=102166  OK
...
Inferência 100/100 → dígito=4  ciclos=102166  OK

RESULTADO: 100/100 corretos — ESTABILIDADE CONFIRMADA
```

#### Script de automação

```bash
cd driver/
bash scripts/run_stability_test.sh
```

O script executa o teste, salva o log em `logs/stability_<timestamp>.txt` e imprime um resumo.

---

## Análise dos Resultados

*(A ser preenchida após execução dos testes na placa física.)*

**Pontos a analisar:**

- Latência de transferência MMIO (imagem + pesos) vs. tempo de inferência no co-processador
- Estabilidade: variação de ciclos entre inferências consecutivas
- Overhead do polling em relação ao tempo total de processamento
- Comparação entre latência medida pelo registrador `CYCLES` e pelo `clock_gettime()` no ARM

---

<p align="center">
  <a href="MARCO1.md">← Marco 1</a> &nbsp;|&nbsp; <a href="README.md">Início</a> &nbsp;|&nbsp; <a href="MARCO3.md">Marco 3 →</a>
</p>
