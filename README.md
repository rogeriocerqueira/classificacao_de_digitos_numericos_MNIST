# Classificação de Dígitos MNIST em FPGA
Co-processador ELM · Driver Assembly · Aplicação C

<p align="center">
  <a href="MARCO1.md">
    <img src="https://img.shields.io/badge/Marco%201-gray?style=for-the-badge"/>
    <img src="https://img.shields.io/badge/Co--Processador-1565C0?style=for-the-badge&logo=intel"/>
  </a>
  &nbsp;
  <a href="MARCO2.md">
    <img src="https://img.shields.io/badge/Marco%202-gray?style=for-the-badge"/>
    <img src="https://img.shields.io/badge/Driver%20Assembly-E65100?style=for-the-badge&logo=linux"/>
  </a>
  &nbsp;
  <a href="MARCO3.md">
    <img src="https://img.shields.io/badge/Marco%203-gray?style=for-the-badge"/>
    <img src="https://img.shields.io/badge/API%20C-2E7D32?style=for-the-badge&logo=c"/>
  </a>
</p>

---

## Sobre o Projeto

Classificador de dígitos MNIST embarcado em um SoC heterogêneo (ARM + FPGA), desenvolvido na disciplina **TEC 499 — Sistemas Digitais** da Universidade Estadual de Feira de Santana (2026.1).

O sistema é construído em três marcos progressivos:

| Marco | Entrega | Status |
|-------|---------|--------|
| [Marco 1 →](MARCO1.md) | Co-processador ELM em Verilog + simulação funcional | ✅ Concluído |
| [Marco 2 →](MARCO2.md) | Driver Linux em Assembly ARM + integração MMIO | 🔄 Em progresso |
| [Marco 3 →](MARCO3.md) | Aplicação C + benchmark + relatório final | ⏳ Pendente |

---

## Arquitetura Geral

```
┌──────────────────────────────────────────┐
│              Aplicação C                 │  Marco 3
├──────────────────────────────────────────┤
│         Driver Assembly ARMv7            │  Marco 2
│           (/dev/mem · MMIO)              │
├──────────────────────────────────────────┤
│     Co-processador ELM (FPGA Verilog)    │  Marco 1
│  Input(784) → Hidden(128) → Output(10)  │
└──────────────────────────────────────────┘
         DE1-SoC · Cyclone V · ARM Cortex-A9
```

---

## Equipe

| Nome               | Papel                              | GitHub |
|--------------------|------------------------------------|--------|
| Rogério Cerqueira  | Arquitetura RTL / Verilog / Driver | [@rogeriocerqueira](https://github.com/rogeriocerqueira) |
| Jones Barcellar    | Treinamento ELM / Geração de pesos | [@jonesBdev](https://github.com/jonesBdev) |
| Ricardo Vilas Boas | Testbench e validação              | [@RickVB-FSA](https://github.com/RickVB-FSA) |

> Projeto acadêmico — TEC 499 Sistemas Digitais · UEFS · 2026.1

---

## Referências

- HUANG, G.-B. et al. **Extreme Learning Machine: Theory and Applications**. *Neurocomputing*, v. 70, 2006.
- LECUN, Y. et al. **The MNIST Database of Handwritten Digits**. [yann.lecun.com/exdb/mnist](http://yann.lecun.com/exdb/mnist/)
- Intel. **Quartus Prime Lite Edition User Guide**. [intel.com/quartus](https://www.intel.com/content/www/us/en/products/details/fpga/development-tools/quartus-prime.html)
- Terasic. **DE1-SoC User Manual**. [terasic.com](https://www.terasic.com.tw/cgi-bin/page/archive.pl?Language=English&CategoryNo=167&No=836)
- ARM. **ARM Architecture Reference Manual ARMv7-A and ARMv7-R edition**. ARM DDI 0406C.
- IEEE. **Verilog HDL Standard — IEEE Std 1364-2001**.
- DestinyWolf. **Problema_SD_2026_1**. [github.com/DestinyWolf/Problema_SD_2026_1](https://github.com/DestinyWolf/Problema_SD_2026_1/tree/master)
