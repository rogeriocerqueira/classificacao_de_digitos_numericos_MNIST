# =============================================================
# Makefile — Marco 3 (DE1-SoC ARM nativo)
#
# Uso na placa:
#   make              → compila tudo
#   make run_arquivo  → compila + executa modo arquivo (dígito 7)
#   make run_desenho  → compila + executa modo desenho
#   make run_benchmark→ compila + executa benchmark
#   make clean        → remove objetos e executável
#   make help         → lista os alvos
# =============================================================

# ── Compilador e flags ────────────────────────────────────────
CC      = gcc
CFLAGS  = -O2 -Wall -Wextra -std=gnu99 \
          -march=armv7-a -mfpu=neon -mfloat-abi=hard
INC     = -I. -I../../Marco2-driver
LDFLAGS = -L../../Marco2-driver -lelm -lm -lrt

# ── Arquivos ──────────────────────────────────────────────────
TARGET  = app
SRCS    = main.c vga.c mouse.c \
          modo_arquivo.c modo_desenho.c modo_benchmark.c
OBJS    = $(SRCS:.c=.o)

# ── Caminhos das imagens ──────────────────────────────────────
IMG_DIR = ../../Marco2-driver/image_files
IMG_7   = $(IMG_DIR)/imagem_7.mif

# =============================================================
#  ALVOS PRINCIPAIS
# =============================================================

## Compila a aplicação
all: check_libelm $(TARGET)
	@echo ""
	@echo "╔══════════════════════════════════════════╗"
	@echo "║  Marco 3 compilado com sucesso!          ║"
	@echo "║  Execute: make run_arquivo               ║"
	@echo "╚══════════════════════════════════════════╝"

$(TARGET): $(OBJS)
	@echo "[LD] Linkando $(TARGET)..."
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) -o $@

%.o: %.c
	@echo "[CC] Compilando $<..."
	$(CC) $(CFLAGS) $(INC) -c $< -o $@

# =============================================================
#  VERIFICAÇÕES
# =============================================================

## Verifica se libelm.a existe, e recompila se necessário
check_libelm:
	@if [ ! -f ../../Marco2-driver/libelm.a ]; then \
		echo "[Marco2] libelm.a não encontrada — compilando Marco 2..."; \
		$(MAKE) -C ../../Marco2-driver libelm.a; \
	else \
		echo "[Marco2] libelm.a OK"; \
	fi

## Verifica se o diretório de imagens existe
check_images:
	@if [ ! -d $(IMG_DIR) ]; then \
		echo "ERRO: $(IMG_DIR) não encontrado."; \
		echo "Copie as imagens .mif para essa pasta."; \
		exit 1; \
	fi
	@if [ ! -f $(IMG_7) ]; then \
		echo "AVISO: imagem_7.mif não encontrada em $(IMG_DIR)"; \
	fi

# =============================================================
#  EXECUÇÃO DOS MODOS
# =============================================================

## Modo 1 — Arquivo (padrão: dígito 7)
run_arquivo: all check_images
	@echo ""
	@echo "[Marco3] Executando modo arquivo — dígito 7..."
	@echo ""
	sudo ./$(TARGET) --modo arquivo \
		--img $(IMG_7) \
		-e 7

## Modo 1 — Arquivo com dígito customizado
## Uso: make run_img IMG=imagem_3.mif CLASSE=3
IMG    ?= imagem_7.mif
CLASSE ?= 7
run_img: all check_images
	@echo ""
	@echo "[Marco3] Executando modo arquivo — $(IMG)..."
	sudo ./$(TARGET) --modo arquivo \
		--img $(IMG_DIR)/$(IMG) \
		-e $(CLASSE)

## Modo 2 — Desenho com mouse
run_desenho: all
	@echo ""
	@echo "[Marco3] Executando modo desenho..."
	@echo "  Botão esquerdo → desenha pixel"
	@echo "  Botão direito  → confirma e classifica"
	@echo ""
	sudo ./$(TARGET) --modo desenho

## Modo 3 — Benchmark
run_benchmark: all check_images
	@echo ""
	@echo "[Marco3] Executando benchmark (100 imagens)..."
	sudo ./$(TARGET) --modo benchmark \
		--dir $(IMG_DIR) \
		--n 100 \
		--log benchmark.csv
	@echo ""
	@echo "Log salvo em: benchmark.csv"

# =============================================================
#  DIAGNÓSTICO
# =============================================================

## Testa hardware VGA com devmem
test_vga:
	@echo "[VGA] Testando PIOs com devmem..."
	@echo "  Escrevendo pixel branco no índice 392 (centro)..."
	busybox devmem 0xFF200070 32 0x188
	busybox devmem 0xFF200080 32 0x1FF
	busybox devmem 0xFF200090 32 0x3
	@echo -n "  Status DONE: "
	busybox devmem 0xFF2000A0 32
	busybox devmem 0xFF200090 32 0x0
	@echo "[VGA] Se retornou 0x1 → hardware OK!"

## Testa Marco 2 (ELM CoProcessor)
test_elm:
	@echo "[ELM] Testando CoProcessor..."
	sudo ../../Marco2-driver/elm_test || \
	sudo ../../Marco2-driver/marco2_test

## Detecta o device do mouse
find_mouse:
	@echo "[Mouse] Detectando device..."
	@for i in 0 1 2 3; do \
		dev="/dev/input/event$$i"; \
		if [ -e "$$dev" ]; then \
			echo "  Encontrado: $$dev"; \
		fi; \
	done
	@echo "  Rode: sudo ../mouse-hps/mouse_hps para confirmar"

## Mostra todas as imagens disponíveis
list_images:
	@echo "[Imagens] Disponíveis em $(IMG_DIR):"
	@ls $(IMG_DIR)/*.mif 2>/dev/null || echo "  Nenhuma imagem .mif encontrada"

# =============================================================
#  LIMPEZA
# =============================================================

## Remove objetos e executável
clean:
	@echo "[Clean] Removendo objetos..."
	rm -f $(OBJS) $(TARGET)
	@echo "[Clean] Pronto."

## Remove também o CSV do benchmark
clean_all: clean
	rm -f benchmark.csv

# =============================================================
#  AJUDA
# =============================================================

help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════╗"
	@echo "║  Marco 3 — Makefile                             ║"
	@echo "╠══════════════════════════════════════════════════╣"
	@echo "║  COMPILAÇÃO                                      ║"
	@echo "║    make              → compila tudo              ║"
	@echo "║    make clean        → remove objetos            ║"
	@echo "║                                                  ║"
	@echo "║  EXECUÇÃO                                        ║"
	@echo "║    make run_arquivo  → modo arquivo (dígito 7)   ║"
	@echo "║    make run_desenho  → modo desenho com mouse    ║"
	@echo "║    make run_benchmark→ benchmark 100 imagens     ║"
	@echo "║                                                  ║"
	@echo "║  IMAGEM CUSTOMIZADA                              ║"
	@echo "║    make run_img IMG=imagem_3.mif CLASSE=3        ║"
	@echo "║                                                  ║"
	@echo "║  DIAGNÓSTICO                                     ║"
	@echo "║    make test_vga     → testa PIOs com devmem     ║"
	@echo "║    make test_elm     → testa CoProcessor         ║"
	@echo "║    make find_mouse   → detecta device do mouse   ║"
	@echo "║    make list_images  → lista imagens disponíveis ║"
	@echo "╚══════════════════════════════════════════════════╝"
	@echo ""

.PHONY: all clean clean_all help \
        run_arquivo run_img run_desenho run_benchmark \
        test_vga test_elm find_mouse list_images \
        check_libelm check_images
