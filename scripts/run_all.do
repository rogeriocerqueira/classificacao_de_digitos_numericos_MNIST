# ============================================================
#  run_all.do — Executa todos os testbenches do projeto ELM
#
#  Estrategia de simulacao das RAMs:
#    ram_stubs.v implementa diretamente as 5 RAMs (sem altsyncram),
#    eliminando warnings de width mismatch e dependencia dos
#    arquivos .v gerados pelo MegaWizard.
#
#  Arquivos .hex necessarios em sim/:
#    W_in_q.hex  — 100352 valores de 16 bits (pesos W_in)
#    b_q.hex     —    128 valores de 16 bits (bias)
#    beta_q.hex  —   1280 valores de 16 bits (pesos beta)
#    png.hex     —    784 valores de 16 bits (imagem Q4.12)
#
#  Troca de imagem antes de rodar:
#    cp 0.hex png.hex   (digito 0)
#    cp 7.hex png.hex   (digito 7)
#    ...
# ============================================================

set RTL ../elm_accel
set SIM  .

# ------------------------------------------------------------
# 1. Biblioteca de trabalho
# ------------------------------------------------------------
vlib work
vmap work work

# ------------------------------------------------------------
# 2. RTL — ordem: folhas antes de quem as instancia
# ------------------------------------------------------------
vlog -sv $RTL/mac.v
vlog -sv $RTL/tanh_lut.v
vlog -sv $RTL/argmax_block.v
vlog -sv $RTL/fsm.v

# Stubs das RAMs (substitui os .qip do Quartus na simulacao)
# ram_image corrigido para 16 bits (Q4.12)
vlog -sv $SIM/ram_stubs.v

vlog -sv $RTL/elm_accel_core.v
vlog -sv $RTL/display_7seg.v
vlog -sv $RTL/elm_accel.v

# ------------------------------------------------------------
# 3. Testbenches
# ------------------------------------------------------------
vlog -sv $SIM/mac_tb.v
vlog -sv $SIM/tanh_lut_tb.v
vlog -sv $SIM/argmax_block_tb.v
vlog -sv $SIM/fsm_tb.v
vlog -sv $SIM/elm_accel_tb.v
vlog -sv $SIM/elm_accel_tb_real.v

# ------------------------------------------------------------
# 4. Execucao (modo batch)
# ------------------------------------------------------------
echo "\n========== mac_tb =========="
vsim -batch -do "run -all; quit" work.mac_tb

echo "\n========== tanh_lut_tb =========="
vsim -batch -do "run -all; quit" work.tanh_lut_tb

echo "\n========== argmax_block_tb =========="
vsim -batch -do "run -all; quit" work.argmax_block_tb

echo "\n========== fsm_tb =========="
vsim -batch -do "run -all; quit" work.fsm_tb

echo "\n========== elm_accel_tb =========="
vsim -batch -do "run -all; quit" work.elm_accel_tb

echo "\n========== elm_accel_tb_real =========="
vsim -batch -do "run -all; quit" work.elm_accel_tb_real

echo "\n===== TODOS OS TESTES CONCLUIDOS ====="
