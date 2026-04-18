# ============================================================
#  run_all.do — Executa todos os testbenches do projeto ELM
#
#  Correção: adicionado ram_stubs.v com implementações diretas
#  das RAMs geradas pelo MegaWizard (ram_w_in, ram_image,
#  ram_bias, ram_beta, ram_h) — necessário pois o Questa não
#  processa automaticamente os arquivos .qip do Quartus.
#
#  Pré-requisito: arquivos .hex na pasta sim/
#    ln -sf ../files/W_in_q.hex .
#    ln -sf ../files/b_q.hex    .
#    ln -sf ../files/beta_q.hex .
#    ln -sf ../files/png.hex    .
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

# Stubs das RAMs (substitui os .qip do Quartus na simulação)
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

# ------------------------------------------------------------
# 4. Execução (modo batch)
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

echo "\n===== TODOS OS TESTES CONCLUÍDOS ====="
