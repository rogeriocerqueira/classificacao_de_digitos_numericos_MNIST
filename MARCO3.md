# Marco 3: Aplicação C + Validação Completa

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
  <a href="README.md">
    <img src="https://img.shields.io/badge/← Voltar-README-gray?style=for-the-badge"/>
  </a>
</p>

---

> ⏳ **Status: Pendente** — a ser desenvolvido após a conclusão do Marco 2.

---

## Objetivo

Entregar o sistema completo e mensurável: uma aplicação em C com interface de linha de comando capaz de classificar imagens individualmente ou em lote, coletando métricas de acurácia e desempenho.

---

## Entregas Previstas

- Aplicação `digit_classify` em C com CLI
- Classificação individual de imagens PNG 28×28
- Modo benchmark sobre dataset com cálculo de:
  - Acurácia (%)
  - Latência média e desvio padrão
  - Throughput (imagens/segundo)
- Exportação de log em CSV
- Relatório final (5–10 páginas) com arquitetura completa, resultados e análise de gargalos

---

## Interface Planejada

```bash
# Classificar uma imagem
./digit_classify --input img_0001.png

# Rodar benchmark sobre dataset
./digit_classify --dataset test_list.txt --benchmark 1000
```

---

## Estrutura Planejada

```bash
app/
├── digit_classify.c   # Aplicação principal com CLI
├── png_loader.c       # Leitura e conversão de PNG → Q4.12
├── benchmark.c        # Modo dataset e coleta de métricas
├── csv_logger.c       # Exportação de resultados
└── Makefile
```

---

<p align="center">
  <a href="MARCO2.md">← Marco 2</a> &nbsp;|&nbsp; <a href="README.md">Início</a>
</p>
