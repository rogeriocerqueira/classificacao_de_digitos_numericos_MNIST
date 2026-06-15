# =============================================================
# Makefile - Marco 3 (DE1-SoC ARM nativo)
#
# Uso na placa:
#   make               -> compila tudo
#   make run_arquivo   -> compila + executa modo arquivo (digito 7)
#   make run_desenho   -> compila + executa modo desenho
#   make run_benchmark -> compila + executa benchmark
#   make clean         -> remove objetos e executavel
#   make help          -> lista os alvos
# =============================================================

# Compilador e flags
CC      = gcc
CFLAGS  = -O2 -Wall -Wextra -std=gnu99 \
          -march=armv7-a -mfpu=neon -mfloat-abi=hard
INC     = -I. -I../../Marco2-driver
LDFLAGS = -L../../Marco2-driver -lelm -lm -lrt

# Arquivos
TARGET  = app
SRCS    = main.c vga.c mouse.c \
          modo_arquivo.c modo_desenho.c modo_benchmark.c \
          stb_image_impl.c
OBJS    = $(SRCS:.c=.o)

# Caminhos
IMG_DIR   = ../../Marco2-driver/image_files
IMG_7     = $(IMG_DIR)/imagem_7.mif
PNG_DIR   = ../../Marco2-driver/mif_files/mnist_png/test
DEVMEM   := $(shell which devmem2 2>/dev/null || which devmem 2>/dev/null || echo "devmem2")

# =============================================================
#  ALVOS PRINCIPAIS
# =============================================================

all: check_libelm $(TARGET)
	@echo ""
	@echo "Marco 3 compilado com sucesso!"
	@echo "Execute: make run_arquivo"

$(TARGET): $(OBJS)
	@echo "[LD] Linkando $(TARGET)..."
	$(CC) $(CFLAGS) $(OBJS) $(LDFLAGS) -o $@

# stb_image_impl.c nao precisa de -Wall -Wextra (header externo)
stb_image_impl.o: stb_image_impl.c
	@echo "[CC] Compilando stb_image_impl.c (stb, sem warnings)..."
	$(CC) -O2 -std=gnu99 -march=armv7-a -mfpu=neon -mfloat-abi=hard \
	      $(INC) -c stb_image_impl.c -o stb_image_impl.o

%.o: %.c
	@echo "[CC] Compilando $<..."
	$(CC) $(CFLAGS) $(INC) -c $< -o $@

# =============================================================
#  VERIFICACOES
# =============================================================

check_libelm:
	@if [ ! -f ../../Marco2-driver/libelm.a ]; then \
		echo "[Marco2] libelm.a nao encontrada - compilando Marco 2..."; \
		$(MAKE) -C ../../Marco2-driver libelm.a \
			CFLAGS="-O2 -Wall -Wextra -std=gnu99 -march=armv7-a -mfpu=neon -mfloat-abi=hard"; \
	else \
		echo "[Marco2] libelm.a OK"; \
	fi

check_images:
	@if [ ! -d $(IMG_DIR) ]; then \
		echo "ERRO: $(IMG_DIR) nao encontrado."; \
		exit 1; \
	fi
	@if [ ! -f $(IMG_7) ]; then \
		echo "AVISO: imagem_7.mif nao encontrada em $(IMG_DIR)"; \
	fi

check_png:
	@if [ ! -d $(PNG_DIR) ]; then \
		echo "ERRO: $(PNG_DIR) nao encontrado."; \
		echo "Copie a pasta mnist_png/test/ para a placa."; \
		exit 1; \
	fi
	@echo "[PNG] Diretorio OK: $(PNG_DIR)"

# =============================================================
#  EXECUCAO DOS MODOS
# =============================================================

run_arquivo: all check_images
	@echo ""
	@echo "[Marco3] Executando modo arquivo - digito 7..."
	sudo ./$(TARGET) --modo arquivo \
		--img $(IMG_7) \
		-e 7

IMG    ?= imagem_7.mif
CLASSE ?= 7
run_img: all check_images
	@echo ""
	@echo "[Marco3] Executando modo arquivo - $(IMG)..."
	sudo ./$(TARGET) --modo arquivo \
		--img $(IMG_DIR)/$(IMG) \
		-e $(CLASSE)

run_desenho: all
	@echo ""
	@echo "[Marco3] Executando modo desenho..."
	@echo "  Botao esquerdo -> desenha pixel"
	@echo "  Botao meio     -> apaga pixel"
	@echo "  Botao direito  -> confirma e classifica"
	sudo ./$(TARGET) --modo desenho

# Benchmark PNG (offset configuravel)
# Uso: make run_benchmark
#      make run_benchmark OFFSET=100
#      make run_benchmark OFFSET=200 N=1000
OFFSET ?= 0
N      ?= 1000
run_benchmark: all check_png
	@echo ""
	@echo "[Marco3] Executando benchmark PNG..."
	@echo "  Dir:    $(PNG_DIR)"
	@echo "  N:      $(N) ($(shell echo $$(($(N)/10))) por digito)"
	@echo "  Offset: $(OFFSET)"
	sudo ./$(TARGET) --modo benchmark \
		--dir $(PNG_DIR) \
		--n $(N) \
		--offset $(OFFSET) \
		--log benchmark_$(OFFSET).csv
	@echo ""
	@echo "Log salvo em: benchmark_$(OFFSET).csv"

# =============================================================
#  DIAGNOSTICO
# =============================================================

test_vga:
	@echo "[VGA] Testando PIOs com $(DEVMEM)..."
	@echo "  Escrevendo pixel branco no indice 392 (centro)..."
	sudo $(DEVMEM) 0xFF200070 w 0x188
	sudo $(DEVMEM) 0xFF200080 w 0x1FF
	sudo $(DEVMEM) 0xFF200090 w 0x3
	@echo "  Status DONE:"
	sudo $(DEVMEM) 0xFF2000A0
	sudo $(DEVMEM) 0xFF200090 w 0x0
	@echo "[VGA] Se retornou 0x1 -> hardware OK!"

test_elm:
	@echo "[ELM] Testando CoProcessor..."
	sudo ../../Marco2-driver/elm_test || \
	sudo ../../Marco2-driver/marco2_test

find_mouse:
	@echo "[Mouse] Detectando device..."
	@for i in 0 1 2 3; do \
		dev="/dev/input/event$$i"; \
		if [ -e "$$dev" ]; then \
			echo "  Encontrado: $$dev"; \
		fi; \
	done

list_images:
	@echo "[Imagens .mif] em $(IMG_DIR):"
	@ls $(IMG_DIR)/*.mif 2>/dev/null || echo "  Nenhuma imagem .mif encontrada"
	@echo "[PNGs] contagem por digito em $(PNG_DIR):"
	@for d in 0 1 2 3 4 5 6 7 8 9; do \
		n=$$(ls $(PNG_DIR)/$$d/*.png 2>/dev/null | wc -l); \
		echo "  Digito $$d: $$n PNGs"; \
	done

# =============================================================
#  LIMPEZA
# =============================================================

clean:
	@echo "[Clean] Removendo objetos..."
	rm -f $(OBJS) $(TARGET)
	@echo "[Clean] Pronto."

clean_all: clean
	rm -f benchmark_*.csv

# =============================================================
#  AJUDA
# =============================================================

help:
	@echo ""
	@echo "Marco 3 - Makefile"
	@echo "=================="
	@echo "COMPILACAO"
	@echo "  make              -> compila tudo"
	@echo "  make clean        -> remove objetos"
	@echo ""
	@echo "EXECUCAO"
	@echo "  make run_arquivo  -> modo arquivo (digito 7)"
	@echo "  make run_desenho  -> modo desenho com mouse"
	@echo "  make run_benchmark           -> benchmark offset=0"
	@echo "  make run_benchmark OFFSET=100 -> benchmark offset=100"
	@echo "  make run_benchmark OFFSET=200 N=1000 -> 1000 imgs offset=200"
	@echo ""
	@echo "IMAGEM CUSTOMIZADA"
	@echo "  make run_img IMG=imagem_3.mif CLASSE=3"
	@echo ""
	@echo "DIAGNOSTICO"
	@echo "  make test_vga     -> testa PIOs com devmem2"
	@echo "  make test_elm     -> testa CoProcessor"
	@echo "  make find_mouse   -> detecta device do mouse"
	@echo "  make list_images  -> lista imagens disponiveis"
	@echo ""

.PHONY: all clean clean_all help \
        run_arquivo run_img run_desenho run_benchmark \
        test_vga test_elm find_mouse list_images \
        check_libelm check_images check_png
