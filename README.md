# 🧠 Classificação de Dígitos MNIST em FPGA  Marco 1

![Quartus Version](https://img.shields.io/badge/Quartus%20Prime-21.1%20Lite-blue?style=for-the-badge&logo=intel)
![Language](https://img.shields.io/badge/HDL-Verilog-orange?style=for-the-badge)
![Status](https://img.shields.io/badge/Marco%201-Concluído-brightgreen?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-lightgrey?style=for-the-badge)

> Implementação de um classificador de dígitos numéricos (0–9) utilizando uma rede neural **Extreme Learning Machine (ELM)** em co-processador FPGA, com inferência totalmente executada em hardware descrito em Verilog.

![Diagrama de Arquitetura](gitimage/architecture.png)
<!-- Substitua pela imagem real exportada do draw.io ou Quartus RTL Viewer -->

---

## 📖 Visão Geral

Este projeto implementa um **classificador de dígitos MNIST** em hardware reconfigurável (FPGA), utilizando uma rede neural do tipo **Extreme Learning Machine (ELM)**. Toda a inferência  da leitura da imagem até a predição do dígito ocorre diretamente no chip, sem auxílio de CPU.

### Por que ELM?

A ELM foi escolhida por três razões principais:

- **Estrutura simples**: camada oculta com pesos aleatórios fixos e somente a camada de saída é treinada, o que dispensa retropropagação em hardware
- **Baixa latência**: número reduzido de operações por inferência em comparação a CNNs
- **Adequada para ponto fixo**: operações lineares e função de ativação simples mapeiam bem em Q4.12

### Objetivo do Marco 1

> Construir e validar o núcleo de inferência ELM em FPGA por meio de **simulação funcional** no ModelSim/QuestaSim.

---

## 🏗️ Arquitetura do Sistema

### Fluxo de Inferência

```
┌─────────────┐     ┌──────────┐     ┌────────────┐     ┌──────────┐     ┌──────────────┐
│  Imagem     │     │  Memória │     │  MAC Unit  │     │ Ativação │     │   Argmax     │
│  28×28 px   │────▶│  W_in/β  │────▶│  (Q4.12)   │────▶│ Sigmoid  │────▶│  Saída 0–9  │
│  (784 bytes)│     │  bias    │     │            │     │  (LUT)   │     │              │
└─────────────┘     └──────────┘     └────────────┘     └──────────┘     └──────────────┘
                                            ▲
                                     ┌──────────────┐
                                     │  FSM Control │
                                     │  (elm_fsm)   │
                                     └──────────────┘
```

### Representação Numérica  Ponto Fixo Q4.12

```
 Bit 15   Bit 14–12    Bit 11–0
┌───────┬────────────┬─────────────────────────────┐
│ Sinal │   Inteiro  │        Fração (1/4096)       │
│  (1b) │    (4b)    │           (12b)              │
└───────┴────────────┴─────────────────────────────┘

  Faixa: -8.0 até +7.9997...
  Resolução: ≈ 0.000244
```

> 💡 Para converter um valor real `v` para Q4.12: `int(v * 4096)` em Python.

---

## 🔄 Máquina de Estados (FSM)

### Diagrama de Estados

```
          ┌───────┐
    rst ──▶ IDLE  │◀─────────────────────┐
          └───┬───┘                      │
         start│                          │
          ┌───▼───┐                      │
          │ LOAD  │  Carrega imagem      │
          └───┬───┘  na memória          │
         done │                          │
          ┌───▼──────────┐               │
          │ COMPUTE_     │  MAC para     │
          │ HIDDEN       │  camada oculta│
          └───┬──────────┘               │
         done │                          │
          ┌───▼───────┐                  │
          │ ACTIVATE  │  Piecewise (LUT)   │
          └───┬───────┘                  │
         done │                          │
          ┌───▼──────────┐               │
          │ COMPUTE_     │  Multiplica   │
          │ OUTPUT       │  por β        │
          └───┬──────────┘               │
         done │                          │
          ┌───▼───┐                      │
          │ARGMAX │  Seleciona classe    │
          └───┬───┘  vencedora           │
         done │                          │
          ┌───▼───┐                      │
          │ DONE  │  Resultado pronto ───┘
          └───────┘
```

> 📸 *Veja também o diagrama gerado automaticamente pelo Quartus State Machine Viewer em `docs/fsm_quartus.png`*

### Tabela de Estados

| Estado           | Descrição                                        | Transição          |
|------------------|--------------------------------------------------|--------------------|
| `IDLE`           | Aguarda sinal `start`                            | `start=1` → `LOAD` |
| `LOAD`           | Transfere os 784 pixels para a memória interna   | Contador cheio → `COMPUTE_HIDDEN` |
| `COMPUTE_HIDDEN` | Executa operações MAC: `h = W_in · x + b`        | MAC completo → `ACTIVATE` |
| `ACTIVATE`       | Aplica sigmoid via LUT sobre cada nó oculto      | LUT completa → `COMPUTE_OUTPUT` |
| `COMPUTE_OUTPUT` | Calcula saída: `y = β · h`                       | MAC completo → `ARGMAX` |
| `ARGMAX`         | Encontra índice do maior valor em `y[0..9]`      | Seleção pronta → `DONE` |
| `DONE`           | Mantém resultado; aguarda reset ou novo `start`  | `rst=1` → `IDLE`  |

---

## 📁 Estrutura do Repositório

```bash
.
├── elm_accel/               # Módulos RTL principais
│   ├── datapath.v           # Coordena MAC, memória e ativação
│   ├── mac.v                # Unidade Multiplica-Acumula (Q4.12)
│   ├── fsm.v                # Controlador de estados da inferência
│   └── memory.v             # Armazena imagem, W_in, bias e β
│
├── sim/                     # Arquivos de simulação
│   └── testbench.v          # Testbench com imagens MNIST
│
├── state_management/        # Controle e monitoramento de estado
│
├── memory/                  # Inicialização e dados de memória
│
├── scripts/
│   └── run_simulation.sh    # Script para compilar e simular
│
├── images/                  # Imagens MNIST de teste (.png)
├── docs/                    # Diagramas, prints e documentação
└── README.md
```

### Dependências entre Módulos

```
elm_top (top-level)
├── fsm.v          ──▶ controla sinais de enable/reset
├── datapath.v
│   ├── mac.v      ──▶ operação de produto escalar Q4.12
│   └── memory.v   ──▶ fornece pesos e pixels ao MAC
```

### Descrição dos Módulos

| Arquivo              | Módulo       | Responsabilidade                                      |
|----------------------|--------------|-------------------------------------------------------|
| `elm_accel/mac.v`    | `mac`        | Multiplica dois operandos Q4.12 e acumula resultado   |
| `elm_accel/datapath.v` | `datapath` | Orquestra o fluxo de dados entre MAC e memória        |
| `elm_accel/fsm.v`    | `elm_fsm`    | Gera sinais de controle conforme estado atual         |
| `elm_accel/memory.v` | `memory`     | ROM/RAM para imagem, pesos W_in, bias e β             |
| `sim/testbench.v`    | `tb`         | Aplica estímulos e verifica saída esperada            |

---

## ⚙️ Ambiente e Dependências

| Ferramenta              | Versão utilizada         |
|-------------------------|--------------------------|
| Intel Quartus Prime     | 24.1 Lite                |
| Questa Intel Starter FPGA     | 20.1.1 (integrado)       |
| Python                  | 3.10+                    |
| Biblioteca NumPy        | 1.24+                    |
| Sistema Operacional     | Mint 22.1 (Xia) / Windows 11|
| Placa FPGA alvo         | DE1-Soc (EPCS128) |

> ⚠️ Versões diferentes do Quartus podem apresentar divergências no relatório de timing. Recomenda-se usar a **24.1 Lite** para reprodução fiel dos resultados.

---

## 🚀 Manual de Uso

### Pré-requisitos

- Quartus Prime 24.1 Lite instalado e no PATH
- Questa Intel Start FPGA Edition instalado
- Python 3.10+ com NumPy (`pip install numpy`)

---

### Passo 1  Clonar o repositório

```bash
git clone https://github.com/seu-usuario/mnist-fpga-elm.git
cd mnist-fpga-elm
```

---

### Passo 2  Gerar os pesos da ELM

```bash
cd scripts/
python generate_weights.py
```

> Isso criará os arquivos `.mif` com os pesos `W_in`, `bias` e `β` na pasta `memory/`, prontos para serem carregados nas ROMs do Quartus.

---

### Passo 3  Executar a simulação

```bash
bash run_simulation.sh
```

O script irá:
1. Compilar todos os módulos Verilog com `vlog`
2. Carregar o testbench no ModelSim
3. Executar a simulação e exibir as waveforms

---

### Passo 4  Compilar no Quartus Prime

1. Abra o Quartus Prime Lite Edition 24.1
2. `File` → `Open Project` → selecione `elm_accel/elm_accel.qpf`
3. Compile com `Processing` → `Start Compilation` (ou `Ctrl+L`)
4. Verifique o relatório em `elm_accel/output_files/`

---

### Passo 5  Interpretar as waveforms

Após a simulação, observe no ModelSim:

- **`start`** → pulso que inicia a inferência
- **`state`** → sequência de estados da FSM
- **`result`** → dígito predito (0–9) ao final do ciclo
- **`done`** → sinal alto quando a inferência termina

---

## 📊 Resultados da Simulação

### Waveforms  ModelSim

![Waveform Simulação](docs/sim_waveform.png)
<!-- Substitua pela captura real do ModelSim -->

### Timing por Fase de Inferência

```
Ciclos de clock por fase (estimativa):

LOAD            █████████████████████████  784 ciclos
COMPUTE_HIDDEN  ████████████████████████████████████████████  N×784 ciclos
ACTIVATE        ████  N ciclos
COMPUTE_OUTPUT  ████████  N×10 ciclos
ARGMAX          █  10 ciclos

Total estimado: depende do número de neurônios ocultos N
```

### Acurácia por Dígito

| Dígito | Correto | Total testado | Acurácia |
|--------|---------|---------------|----------|
| 0      |        |              | %       |
| 1      |        |              | %       |
| 2      |        |              | %       |
| 3      |        |              | %       |
| 4      |        |              | %       |
| 5      |        |              | %       |
| 6      |        |              | %       |
| 7      |        |              | %       |
| 8      |        |              | %       |
| 9      |        |              | %       |
| **Total** |     |              | **%**   |

> 📝 *Preencha com os valores reais após executar o testbench completo.*

### Recursos de Hardware (Relatório Quartus)

| Recurso          | Utilizado | Disponível | Uso (%) |
|------------------|-----------|------------|---------|
| LUTs / ALMs      |          | 10.000     | %      |
| Flip-Flops       |          | 20.000     | %      |
| Blocos de RAM    |          | 414 Kbits  | %      |
| Multiplicadores  |          | 23         | %      |
| Fmax             |  MHz     |           |        |

---

## 🖼️ Galeria

### Exemplos de Imagens MNIST Testadas

<!-- Adicione prints das imagens testadas:
![Dígito 3](images/5776.png) ![Dígito 7](images/5783.png) ![Dígito 1](images/5786.png)
-->

### RTL Viewer  Quartus

![RTL Viewer](docs/rtl_viewer.png)
<!-- Exportar via Tools > Netlist Viewers > RTL Viewer -->

### FSM  State Machine Viewer

![FSM Quartus](docs/fsm_quartus.png)
<!-- Exportar via Tools > Netlist Viewers > State Machine Viewer -->

---

## 👥 Equipe

| Nome | Papel | GitHub |
|------|-------|--------|
| Rogério Cerqueira| Arquitetura RTL / Verilog | [@usuario](https://github.com/rogeriocerqueira) |
| Jones Barcellar | Treinamento ELM / Geração de pesos | [@usuario](https://github.com/jonesBdev) |
| Ricardo Vilas Boas | Testbench e validação | [@usuario](https://github.com/RickVB-FSA) |

> 📌 Projeto desenvolvido como trabalho acadêmico  Sistemas Digiatais  Universidade Estadual de Feira de Santana  2026.1

---

## 📚 Referências

- HUANG, G.-B. et al. **Extreme Learning Machine: Theory and Applications**. *Neurocomputing*, v. 70, 2006.
- LECUN, Y. et al. **The MNIST Database of Handwritten Digits**. Disponível em: [yann.lecun.com/exdb/mnist](http://yann.lecun.com/exdb/mnist/)
- Intel. **Quartus Prime Lite Edition  User Guide**. Disponível em: [intel.com/quartus](https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime.html)
- IEEE. **Verilog HDL Standard  IEEE Std 1364-2001**.
- Material de apoio da disciplina  [inserir referência da disciplina]

---

<p align="center">
  Desenvolvido em Verilog · Simulado no Questa Intel Starter FPGA · Sintetizado no Quartus Prime  Lite Edition 24.1
</p>
