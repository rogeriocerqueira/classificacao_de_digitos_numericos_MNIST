# Classificação de Dígitos MNIST em FPGA — Marco 1

## Visão Geral

Este projeto implementa um **classificador de dígitos numéricos (0–9)** utilizando um **co-processador em FPGA**, desenvolvido em Verilog.  

A solução é baseada em uma rede neural do tipo **Extreme Learning Machine (ELM)**, com inferência totalmente executada em hardware.

**Objetivo do Marco 1:**  
Construir e validar o núcleo de inferência (ELM) em FPGA por meio de simulação.

##  Requisitos do Problema

- Entrada: imagem 28×28 pixels (784 bytes, escala de cinza)
- Saída: dígito previsto (0–9)
- Arquitetura:
  - Datapath com unidade MAC (Multiplica-Acumula)
  - Máquina de Estados (FSM)
  - Função de ativação (LUT ou aproximação linear)
  - Operação de Argmax
- Representação numérica:
  - Ponto fixo **Q4.12**
- Memória:
  - Armazenamento de imagem, pesos (W_in), bias (b) e β

## Organização do Projeto

```bash
.
├── rtl/
│   ├── elm_accel.v
│   ├── mac.v
│   ├── fsm.v
│   └── memory.v
├── tb/
│   └── testbench.v
├── scripts/
│   └── run_simulation.sh
├── images/
├── docs/
└── README.md
