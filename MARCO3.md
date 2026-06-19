# Marco 3: Aplicação C + Validação

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

## Objetivo

Construir a camada de software que integra o co-processador ELM (Marco 1) e o driver Assembly (Marco 2) em uma aplicação C nativa rodando no HPS (ARM Cortex-A9) da DE1-SoC, com saída de vídeo VGA, entrada por mouse e benchmark sobre o dataset MNIST.

---

## Arquitetura

```
Usuário (terminal / mouse / VGA)
         │
         ▼
      main.c  ──  elm_init_weights()  ──►  libelm.a (Marco 2)
         │                                       │
         ├── modo_arquivo.c                      ▼
         ├── modo_desenho.c            Co-processador ELM (FPGA)
         └── modo_benchmark.c          via Lightweight HPS-to-FPGA Bridge
                   │
              vga.c / mouse.c
         (acesso direto a /dev/mem : PIOs MMIO)
```

Os 7 PIOs criados no Platform Designer conectam o HPS à FPGA:

| PIO | Endereço | Função |
|-----|----------|--------|
| `data_in` | `0xFF200000` | HPS escreve instrução ao co-processador |
| `data_out` | `0xFF200010` | Co-processador retorna resultado + flags |
| `ctrl` | `0xFF200020` | ENABLE / CLR_OP / RESET |
| `vga_addr` | `0xFF200070` | Índice do pixel no framebuffer (0–783) |
| `vga_color` | `0xFF200080` | Cor RRRGGGBB (9 bits) |
| `vga_ctrl` | `0xFF200090` | ENABLE / WRITE_EN / RST |
| `vga_status` | `0xFF2000A0` | DONE do framebuffer |

---

## Modos de Operação

### Modo 1 : Arquivo
Lê uma imagem `.mif` do dataset MNIST, exibe no VGA e classifica.

```bash
sudo ./app --modo arquivo --img ../../Marco2-driver/image_files/imagem_7.mif -e 7
```

### Modo 2 : Desenho com Mouse
Captura eventos do mouse via `/dev/input/event0`. O usuário desenha no canvas 28×28 exibido em escala 10× no monitor (280×280 px centralizado em 640×480).

- **Botão esquerdo** → desenha (traço branco)
- **Botão do meio** → apaga
- **Botão direito** → confirma e classifica

Um cursor em cruz vermelha indica a posição atual.

```bash
sudo ./app --modo desenho
```

### Modo 3 : Benchmark
Lê imagens PNG diretamente via `stb_image`, sem pré-conversão. Testa um dígito por execução com offset configurável para garantir conjuntos sem repetição.

```bash
sudo ./app --modo benchmark \
  --dir ../../Marco2-driver/image_files/test \
  --e 7 --n 100 --offset 0 --log resultado_d7.log
```

Métricas calculadas: acurácia, latência média, desvio padrão (σ), mínima, máxima e throughput (img/s). Resultados salvos em CSV + resumo no `.log`.

---

## Inicialização

Ao iniciar, o `main.c` executa `elm_init_weights()` que carrega os pesos da rede nos BRAMs da FPGA via MMIO:

| Arquivo | Conteúdo | Tamanho |
|---------|----------|---------|
| `mem_win.mif` | W_in (pesos entrada→oculta) | 128 × 784 = 100.352 valores Q4.12 |
| `mem_bias.mif` | bias (neurônios ocultos) | 128 valores Q4.12 |
| `mem_beta.mif` | beta (pesos oculta→saída) | 10 × 128 = 1.280 valores Q4.12 |

Os pesos são carregados **uma única vez** e permanecem nos BRAMs entre inferências. O `elm_reset()` é chamado antes de cada `elm_classify()` para zerar a FSM e os acumuladores sem apagar os pesos.

---

## Compilação e Execução

```bash
# Na placa (DE1-SoC)
cd Marco3-API/files

make              # compila tudo
chmod +x app      # garante permissao de execucao
sudo ./app        # abre menu interativo
```

> O `.sof` deve ser gravado via Quartus Programmer antes de rodar. O FPGA perde a configuração ao desligar.

---

## Estrutura

```
Marco3-API/files/
├── main.c              # Orquestrador: inicializa ELM, VGA, loop de modos
├── modo_arquivo.c      # Modo 1: inferência por arquivo .mif
├── modo_desenho.c      # Modo 2: canvas com mouse + cursor VGA
├── modo_benchmark.c    # Modo 3: benchmark PNG com métricas
├── vga.c / vga.h       # Driver VGA via PIOs MMIO
├── mouse.c / mouse.h   # Driver mouse via /dev/input/event0
├── app.h               # Tipos e constantes compartilhados
├── stb_image.h         # Leitura de PNG (single-header, nothings/stb)
├── stb_image_impl.c    # Compilação única da implementação stb
└── Makefile
```

---

<p align="center">
  <a href="MARCO2.md">← Marco 2</a> &nbsp;|&nbsp; <a href="README.md">Início</a>
</p>