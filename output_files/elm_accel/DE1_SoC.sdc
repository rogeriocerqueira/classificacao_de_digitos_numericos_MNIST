# ============================================================
# Timing constraints para DE1-SoC
# ============================================================

# Clock de 50 MHz
create_clock -name clk_50 -period 20.000 [get_ports {clk}]

# Input delays
set_input_delay -clock clk_50 -max 4.000 [get_ports {reset_n}]
set_input_delay -clock clk_50 -max 4.000 [get_ports {start_btn}]

# Output delays
set_output_delay -clock clk_50 -max 4.000 [get_ports {hex3[*]}]
set_output_delay -clock clk_50 -max 4.000 [get_ports {hex2[*]}]
set_output_delay -clock clk_50 -max 4.000 [get_ports {hex1[*]}]
set_output_delay -clock clk_50 -max 4.000 [get_ports {hex0[*]}]
set_output_delay -clock clk_50 -max 4.000 [get_ports {led_ready}]
set_output_delay -clock clk_50 -max 4.000 [get_ports {led_busy}]
set_output_delay -clock clk_50 -max 4.000 [get_ports {led_done}]