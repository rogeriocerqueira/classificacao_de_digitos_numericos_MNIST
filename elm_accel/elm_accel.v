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

    // Wires de saída das RAMs com larguras corretas:
    //   ram_w_in  -> q [15:0]  (16 bits, Q4.12)
    //   ram_image -> q [7:0]   (8 bits, pixel bruto 0-255)
    //   ram_bias  -> q [15:0]  (16 bits, Q4.12)
    //   ram_beta  -> q [7:0]   (8 bits)
    wire [15:0] weight_from_ram;
    wire [7:0]  pixel_from_ram;   // CORRIGIDO: era [15:0], ram_image tem q de 8 bits
    wire [15:0] bias_from_ram;
    wire [7:0]  beta_from_ram;    // CORRIGIDO: era [15:0], ram_beta tem q de 8 bits

    // Pixel estendido para 16 bits (zero-extend) antes de entrar no MAC (Q4.12)
    wire [15:0] pixel_extended;   // ADICIONADO: adaptação de largura para o MAC
    assign pixel_extended = {8'b0, pixel_from_ram};

    wire [15:0] mac_to_tanh;
    wire [15:0] tanh_to_argmax;

    // --- 2. MÁQUINA DE ESTADOS ---
    fsm u_fsm (
        .clk      (clk),
        .reset    (reset),
        .start    (start),
        .clr_acc  (clr_acc_w),
        .en_mac   (en_mac_w),
        .en_tanh  (en_tanh_w),
        .en_argmax(en_argmax_w),
        .addr_w   (addr_w_w),
        .addr_x   (addr_x_w),
        .addr_b   (addr_b_w),
        .done     (done)
    );

    // --- 3. MEMÓRIAS (RAM: 1-PORT) ---

    // Pesos W_in — 100352 palavras de 16 bits (Q4.12)
    ram_w_in u_ram_w (
        .address (addr_w_w),
        .clock   (clk),
        .data    (16'b0),
        .rden    (1'b1),           // CORRIGIDO: porta rden ausente no original
        .wren    (1'b0),
        .q       (weight_from_ram)
    );

    // Imagem x — 784 pixels de 8 bits
    ram_image u_ram_x (
        .address (addr_x_w),
        .clock   (clk),
        .data    (8'b0),           // CORRIGIDO: era 16'b0, data é 8 bits
        .rden    (1'b1),           // CORRIGIDO: porta rden ausente no original
        .wren    (1'b0),
        .q       (pixel_from_ram)
    );

    // Bias b — 128 palavras de 16 bits (Q4.12)
    ram_bias u_ram_b (
        .address (addr_b_w),
        .clock   (clk),
        .data    (16'b0),
        .rden    (1'b1),           // CORRIGIDO: porta rden ausente no original
        .wren    (1'b0),
        .q       (bias_from_ram)
    );

    // Beta — 1280 palavras de 8 bits (não usada pela FSM atual)
    ram_beta u_ram_beta (
        .address (addr_beta_w),
        .clock   (clk),
        .data    (8'b0),           // CORRIGIDO: era 16'b0, data é 8 bits
        .rden    (1'b1),           // CORRIGIDO: porta rden ausente no original
        .wren    (1'b0),
        .q       (beta_from_ram)
    );

    // --- 4. DATAPATH ---

    mac u_mac (
        .clk   (clk),
        .clr   (clr_acc_w),
        .en    (en_mac_w),
        .din_x (pixel_extended),   // CORRIGIDO: era pixel_from_ram (8 bits), MAC espera 16 bits
        .din_w (weight_from_ram),
        .dout  (mac_to_tanh)
    );

    tanh_lut u_tanh (
        .clk  (clk),
        .en   (en_tanh_w),
        .din  (mac_to_tanh),
        .dout (tanh_to_argmax)
    );

    argmax_block u_argmax (
        .clk   (clk),
        .reset (reset),
        .en    (en_argmax_w),      // CORRIGIDO: en_argmax_w agora está conectado à FSM
        .din   (tanh_to_argmax),
        .digit (predicted_digit)
    );

endmodule
