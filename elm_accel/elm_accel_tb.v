// ============================================================
//  STUB: altsyncram (PARAMETRIZADO - Verilog padrão)
//  Simula RAM síncrona de 1 porta com latência de 1 ciclo.
//  Suporta diferentes larguras de dados via parameter.
// ============================================================
module altsyncram (
    input  wire [16:0] address_a,   // largura máxima (17 bits)
    input  wire        clock0,
    input  wire [15:0] data_a,      // largura máxima (16 bits)
    input  wire        rden_a,
    input  wire        wren_a,
    output reg  [15:0] q_a,
    // Portas não utilizadas (sem defaults - conectadas externamente)
    input  wire        aclr0,
    input  wire        aclr1,
    input  wire        address_b,
    input  wire        addressstall_a,
    input  wire        addressstall_b,
    input  wire        byteena_a,
    input  wire        byteena_b,
    input  wire        clock1,
    input  wire        clocken0,
    input  wire        clocken1,
    input  wire        clocken2,
    input  wire        clocken3,
    input  wire        data_b,
    output wire        eccstatus,
    output wire        q_b,
    input  wire        rden_b,
    input  wire        wren_b
);
    // Parâmetros (compatíveis com defparam dos módulos RAM)
    parameter width_a            = 16;
    parameter widthad_a          = 10;
    parameter numwords_a         = 1024;
    parameter outdata_reg_a      = "CLOCK0";
    parameter init_file          = "UNUSED";
    parameter operation_mode     = "SINGLE_PORT";
    parameter ram_block_type     = "M10K";
    parameter power_up_uninitialized = "FALSE";
    parameter clock_enable_input_a   = "BYPASS";
    parameter clock_enable_output_a  = "BYPASS";
    parameter outdata_aclr_a         = "NONE";
    parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ";
    parameter lpm_hint               = "";
    parameter lpm_type               = "altsyncram";
    parameter intended_device_family = "Cyclone V";
    parameter width_byteena_a        = 1;

    assign eccstatus = 1'b0;
    assign q_b       = 1'b0;

    // Memória interna: tamanho máximo para cobrir todas as RAMs.
    // ram_w_in tem 100352 palavras (2^17 = 131072 cobre)
    reg [width_a-1:0] mem [0:131071];

    integer i_init;
    initial begin
        for (i_init = 0; i_init < 131072; i_init = i_init + 1)
            mem[i_init] = {width_a{1'b0}};
        // Para usar arquivos MIF convertidos em HEX, descomente:
        // if (init_file != "UNUSED") $readmemh(init_file, mem);
    end

    always @(posedge clock0) begin
        if (wren_a)
            mem[address_a] <= data_a;
        if (rden_a)
            q_a <= mem[address_a];
    end
endmodule