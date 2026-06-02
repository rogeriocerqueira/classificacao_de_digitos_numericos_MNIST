#!/bin/sh
#
# build.sh — compila o Marco 3 nativamente na placa DE1-SoC.
#
# Depende do Marco 2 em ../Marco2-driver/ (ou ajuste MARCO2_DIR).
#
# Uso:
#   chmod +x build.sh
#   ./build.sh

set -e

MARCO2_DIR="../Marco2-driver"
FLAGS="-O2 -Wall -Wextra -std=gnu99 -march=armv7-a -mfpu=neon -mfloat-abi=hard"
INC="-I. -I${MARCO2_DIR}"

echo "=== [Marco 3] Compilando ==="

# ── Objetos do Marco 2 (reutiliza a libelm.a se já existir) ──
if [ ! -f "${MARCO2_DIR}/libelm.a" ]; then
    echo "  Compilando Marco 2..."
    (cd ${MARCO2_DIR} && ./build.sh)
fi

# ── Objetos do Marco 3 ────────────────────────────────────────
echo "  vga.c..."
gcc $FLAGS $INC -c vga.c -o vga.o

echo "  mouse.c..."
gcc $FLAGS $INC -c mouse.c -o mouse.o

echo "  modo_arquivo.c..."
gcc $FLAGS $INC -c modo_arquivo.c -o modo_arquivo.o

echo "  modo_desenho.c..."
gcc $FLAGS $INC -c modo_desenho.c -o modo_desenho.o

echo "  modo_benchmark.c..."
gcc $FLAGS $INC -c modo_benchmark.c -o modo_benchmark.o

echo "  main.c..."
gcc $FLAGS $INC -c main.c -o main.o

# ── Linka tudo ───────────────────────────────────────────────
echo "  Linkando..."
gcc $FLAGS \
    main.o vga.o mouse.o \
    modo_arquivo.o modo_desenho.o modo_benchmark.o \
    -L${MARCO2_DIR} -lelm -lm -lrt \
    -o app

echo ""
echo "=== Pronto! ==="
echo ""
echo "  sudo ./app --modo arquivo  --img ../Marco2-driver/mif_files/imagem_7.mif -e 7"
echo "  sudo ./app --modo desenho"
echo "  sudo ./app --modo benchmark --dir ../Marco2-driver/mif_files --n 100 --log resultado.csv"
