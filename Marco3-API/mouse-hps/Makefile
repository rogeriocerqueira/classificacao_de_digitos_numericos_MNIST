# ==============================================================================
# Makefile — mouse_hps
#
# Suporta dois modos de compilação:
#
#   make              Compilação nativa (direto na DE1-SoC ou em qualquer Linux)
#   make cross        Cross-compilação no host para ARM (DE1-SoC)
#   make clean        Remove binários gerados
#   make help         Exibe esta ajuda
#
# Cross-compilação requer o toolchain arm-linux-gnueabihf instalado no host:
#   Ubuntu/Debian: sudo apt install gcc-arm-linux-gnueabihf
# ==============================================================================

# ------------------------------------------------------------------------------
# Alvo padrão
# ------------------------------------------------------------------------------
.DEFAULT_GOAL := native

# ------------------------------------------------------------------------------
# Fonte e binários
# ------------------------------------------------------------------------------
SRC     := mouse_hps.c
BIN     := mouse_hps
BIN_ARM := mouse_hps_arm

# ------------------------------------------------------------------------------
# Compilador nativo
# ------------------------------------------------------------------------------
CC_NATIVE  := gcc

# ------------------------------------------------------------------------------
# Cross-compilador (ARM Cortex-A9, hard-float, Linux)
# ------------------------------------------------------------------------------
CC_CROSS   := arm-linux-gnueabihf-gcc

# ------------------------------------------------------------------------------
# Flags comuns
#
#   -Wall -Wextra     Habilita warnings importantes durante o desenvolvimento
#   -O2               Otimização balanceada (velocidade sem comprometer debug)
#   -lm               Linka libm (necessário para sqrtf)
# ------------------------------------------------------------------------------
CFLAGS_COMMON := -Wall -Wextra -O2
LIBS          := -lm

# ------------------------------------------------------------------------------
# Flags específicas para ARM (Cortex-A9 da DE1-SoC)
#
#   -march=armv7-a        Arquitetura ARMv7-A (Cortex-A9)
#   -mfpu=neon-vfpv3      Habilita FPU NEON/VFPv3 presente no Cortex-A9
#   -mfloat-abi=hard      ABI hard-float: parâmetros float em registradores FPU
#                         (compatível com o Linux da DE1-SoC)
# ------------------------------------------------------------------------------
CFLAGS_ARM := -march=armv7-a -mfpu=neon-vfpv3 -mfloat-abi=hard

# ==============================================================================
# ALVOS
# ==============================================================================

# ------------------------------------------------------------------------------
# native — compila para a arquitetura atual da máquina
# Usar quando: compilando diretamente na DE1-SoC, ou testando no PC Linux
# ------------------------------------------------------------------------------
.PHONY: native
native: $(SRC)
	@echo "[native] Compilando $(SRC) → $(BIN)"
	$(CC_NATIVE) $(CFLAGS_COMMON) -o $(BIN) $(SRC) $(LIBS)
	@echo "[native] OK: ./$(BIN)"

# ------------------------------------------------------------------------------
# cross — cross-compila no host para ARM (DE1-SoC)
# Usar quando: desenvolvendo no PC e enviando o binário para a placa via scp
# ------------------------------------------------------------------------------
.PHONY: cross
cross: $(SRC)
	@echo "[cross] Compilando $(SRC) → $(BIN_ARM)  (target: ARM Cortex-A9)"
	$(CC_CROSS) $(CFLAGS_COMMON) $(CFLAGS_ARM) -o $(BIN_ARM) $(SRC) $(LIBS)
	@echo "[cross] OK: ./$(BIN_ARM)"
	@echo "[cross] Para enviar à placa:"
	@echo "        scp $(BIN_ARM) root@<ip-da-placa>:~/"

# ------------------------------------------------------------------------------
# all — compila ambos os alvos
# ------------------------------------------------------------------------------
.PHONY: all
all: native cross

# ------------------------------------------------------------------------------
# clean — remove binários gerados
# ------------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo "[clean] Removendo binários..."
	rm -f $(BIN) $(BIN_ARM)
	@echo "[clean] OK"

# ------------------------------------------------------------------------------
# help — exibe resumo dos alvos disponíveis
# ------------------------------------------------------------------------------
.PHONY: help
help:
	@echo ""
	@echo "mouse_hps — Makefile"
	@echo "────────────────────────────────────────────────────"
	@echo "  make              Compilação nativa ($(CC_NATIVE))"
	@echo "  make cross        Cross-compilação ARM ($(CC_CROSS))"
	@echo "  make all          Compila ambos os alvos"
	@echo "  make clean        Remove binários gerados"
	@echo "  make help         Exibe esta mensagem"
	@echo ""
	@echo "  Binário nativo : $(BIN)"
	@echo "  Binário ARM    : $(BIN_ARM)"
	@echo ""
	@echo "  Flags ARM: $(CFLAGS_ARM)"
	@echo ""
