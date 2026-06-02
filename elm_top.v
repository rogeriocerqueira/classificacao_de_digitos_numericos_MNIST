module elm_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,
    output wire [14:0] HPS_DDR3_ADDR,
    output wire [2:0]  HPS_DDR3_BA,
    output wire        HPS_DDR3_CAS_N,
    output wire        HPS_DDR3_CKE,
    output wire        HPS_DDR3_CK_N,
    output wire        HPS_DDR3_CK_P,
    output wire        HPS_DDR3_CS_N,
    output wire [3:0]  HPS_DDR3_DM,
    inout  wire [31:0] HPS_DDR3_DQ,
    inout  wire [3:0]  HPS_DDR3_DQS_N,
    inout  wire [3:0]  HPS_DDR3_DQS_P,
    output wire        HPS_DDR3_ODT,
    output wire        HPS_DDR3_RAS_N,
    output wire        HPS_DDR3_RESET_N,
    input  wire        HPS_DDR3_RZQ,
    output wire        HPS_DDR3_WE_N
);

wire hps_fpga_reset_n = KEY[0];

wire [31:0] data_in_w;
wire [31:0] data_out_w;
wire [31:0] data_out_qsys_nc;
wire [2:0]  ctrl_w;

wire elm_enable = ctrl_w[0];
wire elm_clr    = ctrl_w[1];
wire elm_rst    = ctrl_w[2];

wire        hps_h2f_mpu_eventi     = 1'b0;
wire        hps_h2f_mpu_evento;
wire [1:0]  hps_h2f_mpu_standbywfe;
wire [1:0]  hps_h2f_mpu_standbywfi;

elm_system u0 (
    .clk_clk                              ( CLOCK_50          ),
    .reset_reset_n                        ( hps_fpga_reset_n  ),
    .memory_mem_a                         ( HPS_DDR3_ADDR     ),
    .memory_mem_ba                        ( HPS_DDR3_BA       ),
    .memory_mem_ck                        ( HPS_DDR3_CK_P     ),
    .memory_mem_ck_n                      ( HPS_DDR3_CK_N     ),
    .memory_mem_cke                       ( HPS_DDR3_CKE      ),
    .memory_mem_cs_n                      ( HPS_DDR3_CS_N     ),
    .memory_mem_ras_n                     ( HPS_DDR3_RAS_N    ),
    .memory_mem_cas_n                     ( HPS_DDR3_CAS_N    ),
    .memory_mem_we_n                      ( HPS_DDR3_WE_N     ),
    .memory_mem_reset_n                   ( HPS_DDR3_RESET_N  ),
    .memory_mem_dq                        ( HPS_DDR3_DQ       ),
    .memory_mem_dqs                       ( HPS_DDR3_DQS_P    ),
    .memory_mem_dqs_n                     ( HPS_DDR3_DQS_N    ),
    .memory_mem_odt                       ( HPS_DDR3_ODT      ),
    .memory_mem_dm                        ( HPS_DDR3_DM       ),
    .memory_oct_rzqin                     ( HPS_DDR3_RZQ      ),
    .hps_h2f_mpu_events_eventi            ( hps_h2f_mpu_eventi     ),
    .hps_h2f_mpu_events_evento            ( hps_h2f_mpu_evento     ),
    .hps_h2f_mpu_events_standbywfe        ( hps_h2f_mpu_standbywfe ),
    .hps_h2f_mpu_events_standbywfi        ( hps_h2f_mpu_standbywfi ),
    .ctrl_reset_reset_n                   ( hps_fpga_reset_n  ),
    .data_in_reset_reset_n                ( hps_fpga_reset_n  ),
    .data_out_reset_reset_n               ( hps_fpga_reset_n  ),
    .data_in_external_connection_export   ( data_in_w         ),
    .data_out_external_connection_export  ( data_out_qsys_nc  ),
    .ctrl_external_connection_export      ( ctrl_w            )
);

CoProcessor elm_inst (
    .clk           ( CLOCK_50   ),
    .data_in       ( data_in_w  ),
    .enable        ( elm_enable ),
    .clr_operation ( elm_clr    ),
    .rst           ( elm_rst    ),
    .data_out      ( data_out_w )
);

display_resultado visor_elm (
    .resultado_bin ( data_out_w[3:0] ),
    .hex_out       ( HEX0            )
);

assign HEX1 = 7'h7F;
assign HEX2 = 7'h7F;
assign HEX3 = 7'h7F;
assign HEX4 = 7'h7F;
assign HEX5 = 7'h7F;

assign LEDR[0]   = data_out_w[4];
assign LEDR[1]   = data_out_w[5];
assign LEDR[2]   = data_out_w[6];
assign LEDR[9:3] = 7'b0;

endmodule
