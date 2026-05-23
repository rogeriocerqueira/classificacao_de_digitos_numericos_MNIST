# Marco 1 — Co-processador ELM

<p align="center">
  <a href="README.md">
    <img src="https://img.shields.io/badge/← Voltar-README-gray?style=for-the-badge"/>
  </a>
  &nbsp;
  <a href="MARCO2.md">
    <img src="https://img.shields.io/badge/Marco%202-gray?style=for-the-badge"/>
    <img src="https://img.shields.io/badge/Driver%20Assembly-E65100?style=for-the-badge&logo=linux"/>
  </a>
</p>

---

## Co-processador de Referência

O co-processador ELM utilizado neste projeto é o desenvolvido pelo monitor da disciplina:

> 🔗 **[DestinyWolf/Problema_SD_2026_1](https://github.com/DestinyWolf/Problema_SD_2026_1/tree/master)**

O IP implementa a inferência de uma rede ELM (Extreme Learning Machine) em Verilog, com:

- FSM de controle sequencial
- Datapath MAC em ponto fixo Q4.12
- Ativação tanh aproximada via LUT
- Argmax final para predição do dígito (0–9)
- Registradores mapeados em memória acessíveis via Lightweight HPS-to-FPGA Bridge

A integração com o HPS da DE1-SoC foi realizada via **Platform Designer (Qsys)**, expondo os registradores de controle no endereço base `0xFF200000`. O driver do Marco 2 foi desenvolvido sobre essa ISA.

---

## Contexto

Paralelamente, a equipe desenvolveu uma versão própria do co-processador (`elm_accel/`), que não atingiu o comportamento esperado durante a simulação. Optou-se pelo co-processador de referência para garantir a integridade da integração HPS↔FPGA e permitir o foco no desenvolvimento do driver.

---

<p align="center">
  <a href="README.md">← Início</a> &nbsp;|&nbsp; <a href="MARCO2.md">Marco 2 →</a>
</p>
