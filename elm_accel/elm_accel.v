module elm_accel (
    input wire clk,
    input wire reset,
    input wire start,                  
    output wire done,                  
    output wire [3:0] predicted_digit  
);

    // --- 1. FIOS DE INTERCONEXÃO ---
    wire clr_acc_w, en_mac_w, en_tanh_w, en_argmax_w;
    wire [16:0] addr_w_w; 
    wire [9:0]  addr_x_w; 
    wire [6:0]  addr_b_w; 
    wire [10:0] addr_beta_w; 

    // Wires de saída das RAMs
    wire [15:0] weight_from_ram;
    wire [15:0] pixel_from_ram;
    wire [15:0] bias_from_ram;
    wire [15:0] beta_from_ram; 
    
    wire [15:0] mac_to_tanh;
    wire [15:0] tanh_to_argmax;

    // --- 2. MÁQUINA DE ESTADOS ---
    fsm u_fsm (
        .clk(clk),
        .reset(reset),
        .start(start),
        .clr_acc(clr_acc_w),
        .en_mac(en_mac_w),
        .en_tanh(en_tanh_w),
        .en_argmax(en_argmax_w),
        .addr_w(addr_w_w),
        .addr_x(addr_x_w),
        .addr_b(addr_b_w),
        .done(done)
    );

    // --- 3. MEMÓRIAS (TODAS COMO RAM: 1-PORT) ---
    // IMPORTANTE: Ao gerar no IP Catalog, escolha "RAM: 1-PORT" para todas.

    // Pesos W_in
    ram_w_in u_ram_w (
        .address ( addr_w_w ),
        .clock   ( clk ),
        .data    ( 16'b0 ), // Entrada de dados (Marco 2)
        .wren    ( 1'b0 ),  // Write Enable desativado (Marco 1)
        .q       ( weight_from_ram )
    );

    // Imagem x
    ram_image u_ram_x (
        .address ( addr_x_w ),
        .clock   ( clk ),
        .data    ( 16'b0 ), 
        .wren    ( 1'b0 ),
        .q       ( pixel_from_ram )
    );

    // Bias b
    ram_bias u_ram_b (
        .address ( addr_b_w ),
        .clock   ( clk ),
        .data    ( 16'b0 ),
        .wren    ( 1'b0 ),
        .q       ( bias_from_ram )
    );

    // Beta
    ram_beta u_ram_beta (
        .address ( addr_beta_w ),
        .clock   ( clk ),
        .data    ( 16'b0 ),
        .wren    ( 1'b0 ),
        .q       ( beta_from_ram )
    );

    // --- 4. DATAPATH ---
    mac u_mac (
        .clk(clk),
        .clr(clr_acc_w),
        .en(en_mac_w),
        .din_x(pixel_from_ram), 
        .din_w(weight_from_ram), 
        .dout(mac_to_tanh)
    );

    tanh_lut u_tanh (
        .clk(clk),
        .en(en_tanh_w),
        .din(mac_to_tanh),
        .dout(tanh_to_argmax)
    );

    argmax_block u_argmax (
        .clk(clk),
        .reset(reset), 
        .en(en_argmax_w),
        .din(tanh_to_argmax),
        .digit(predicted_digit)
    );

endmodule