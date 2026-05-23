# Makefile para o driver ELM (Marco 2)
#
# Build nativo na HPS (Linaro/Ubuntu rodando no DE1-SoC):
#     make
#
# Cross-compile a partir de um host x86:
#     make CROSS_COMPILE=arm-linux-gnueabihf-
#
# Para inspecionar o assembly gerado a partir do C:
#     make elm.s
#
# Para limpar:
#     make clean

CROSS_COMPILE ?=
CC      = $(CROSS_COMPILE)gcc
AR      = $(CROSS_COMPILE)ar

# Flags comuns a C e ASM (.S é pré-processado pelo gcc).
COMMON_FLAGS = -march=armv7-a -mfpu=neon -mfloat-abi=hard
CFLAGS  = -O2 -Wall -Wextra -std=c11 $(COMMON_FLAGS) -I.
ASFLAGS = $(COMMON_FLAGS) -I.

LIB_OBJS  = elm.o elm_exec.o elm_mif.o
LIB       = libelm.a

APP_OBJS  = example_main.o
APP       = elm_test

TEST_OBJS = marco2_test.o
TEST      = marco2_test

.PHONY: all clean

all: $(LIB) $(APP) $(TEST)

$(LIB): $(LIB_OBJS)
	$(AR) rcs $@ $^

$(APP): $(APP_OBJS) $(LIB)
	$(CC) $(CFLAGS) -o $@ $(APP_OBJS) -L. -lelm -lm

$(TEST): $(TEST_OBJS) $(LIB)
	$(CC) $(CFLAGS) -o $@ $(TEST_OBJS) -L. -lelm -lm

# Regras de compilação
%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.S
	$(CC) $(ASFLAGS) -c $< -o $@

# Dependências de cabeçalhos
elm.o:          elm.c elm.h elm_proto.h elm_platform.h hps_0.h
elm_exec.o:     elm_exec.S elm_proto.h
elm_mif.o:      elm_mif.c elm_mif.h
example_main.o: example_main.c elm.h elm_proto.h
marco2_test.o:  marco2_test.c elm.h elm_mif.h elm_proto.h

clean:
	rm -f $(LIB_OBJS) $(APP_OBJS) $(TEST_OBJS) $(LIB) $(APP) $(TEST) *.s
