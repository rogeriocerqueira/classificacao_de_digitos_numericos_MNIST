// ============================================================
//  elm_accel_core — Núcleo do co-processador ELM
//
//  Correções aplicadas:
//    [BUG #2] tanh_lut agora é combinacional: removidas as
//             portas clk e en da instância u_tanh.
//    [BUG #4] Fio clr_argmax_w adicionado: conecta a saída
//             clr_argmax da FSM à entrada clr do argmax_block,
//             zerando max_val/digit no início de cada inferência.
//
//  Hierarquia:
//    elm_accel_core
//    ├── fsm            (controle)
//    ├── mac            (multiply-accumulate Q4.12)
//    ├── tanh_lut       (ativação combinacional)
//    ├── argmax_block   (seleção do dígito)
//    ├── ram_w_in       (pesos W_in  — 128×784 entradas)
//    ├── ram_image      (pixels x   — 784 bytes)
//    ├── ram_bias       (bias b     — 128 valores)
//    ├── ram_beta       (pesos β    — 10×128 entradas)
//    └── ram_h          (ativações h — 128 valores)
// ============================================================

module elm_accel_core (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    output wire        done,
    output wire [3:0]  predicted_digit
);

    // =========================================================
    // 1. FIOS DE CONTROLE (vindos da FSM)
    // =========================================================
    wire        clr_acc_w;
    wire        en_mac_w;
    wire        load_bias_w;
    wire        en_tanh_w;
    wire        en_argmax_w;
    wire        sel_beta_w;
    wire        clr_argmax_w;   // NOVO: reset do argmax entre inferências

    wire [16:0] addr_w_w;
    wire [9:0]  addr_x_w;
    wire [6:0]  addr_b_w;
    wire [10:0] addr_beta_w;

    // =========================================================
    // 2. FIOS DE DADOS DAS RAMS
    // =========================================================
    wire [15:0] weight_from_ram;

    wire [7:0]  pixel_raw;
    wire [15:0] pixel_from_ram;
    assign pixel_from_ram = {8'b0, pixel_raw};  // zero-extend para 16 bits

    wire [15:0] bias_from_ram;
    wire [15:0] beta_from_ram;
    wire [15:0] h_from_ram;

    // =========================================================
    // 3. FIOS DO DATAPATH
    // =========================================================
    wire [15:0] mac_din_x;
    wire [15:0] mac_din_w;
    wire [15:0] mac_out;      // saída do MAC (renomeado de mac_to_tanh)
    wire [15:0] tanh_out;     // [FIX #2] wire combinacional (não reg)

    assign mac_din_x = sel_beta_w ? h_from_ram    : pixel_from_ram;
    assign mac_din_w = sel_beta_w ? beta_from_ram : weight_from_ram;

    // =========================================================
    // 4. FSM
    // =========================================================
    fsm u_fsm (
        .clk        (clk),
        .reset      (reset),
        .start      (start),
        .clr_acc    (clr_acc_w),
        .en_mac     (en_mac_w),
        .load_bias  (load_bias_w),
        .en_tanh    (en_tanh_w),
        .en_argmax  (en_argmax_w),
        .sel_beta   (sel_beta_w),
        .clr_argmax (clr_argmax_w),  // NOVO
        .addr_w     (addr_w_w),
        .addr_x     (addr_x_w),
        .addr_b     (addr_b_w),
        .addr_beta  (addr_beta_w),
        .done       (done)
    );

    // =========================================================
    // 5. MEMORIAS
    //    Marco 1: pesos pré-carregados via .mif
    //    Marco 2: wren e data controlados pelo HPS via MMIO
    // =========================================================
    ram_w_in u_ram_w (
        .address (addr_w_w),
        .clock   (clk),
        .data    (16'b0),
        .wren    (1'b0),
        .rden    (1'b1),
        .q       (weight_from_ram)
    );

    ram_image u_ram_x (
        .address (addr_x_w),
        .clock   (clk),
        .data    (8'b0),
        .wren    (1'b0),
        .rden    (1'b1),
        .q       (pixel_raw)
    );

    ram_bias u_ram_b (
        .address (addr_b_w),
        .clock   (clk),
        .data    (16'b0),
        .wren    (1'b0),
        .rden    (1'b1),
        .q       (bias_from_ram)
    );

    ram_beta u_ram_beta (
        .address (addr_beta_w),
        .clock   (clk),
        .data    (16'b0),
        .wren    (1'b0),
        .rden    (1'b1),
        .q       (beta_from_ram)
    );

    // ram_h: porta dupla simplificada (single-port)
    // Escrita: addr_b_w / tanh_out / en_tanh_w (durante HIDDEN_ADDR)
    // Leitura: addr_b_w (reutilizado durante OUTPUT_MAC)
    ram_h u_ram_h (
        .address (addr_b_w),
        .clock   (clk),
        .data    (tanh_out),     // [FIX #2] tanh_out é wire combinacional
        .wren    (en_tanh_w),    // ativo 1 ciclo após ACTIVATE (em HIDDEN_ADDR)
        .q       (h_from_ram)
    );

    // =========================================================
    // 6. DATAPATH
    // =========================================================
    mac u_mac (
        .clk       (clk),
        .clr       (clr_acc_w),
        .en        (en_mac_w),
        .load_bias (load_bias_w),
        .din_x     (mac_din_x),
        .din_w     (mac_din_w),
        .din_bias  (bias_from_ram),
        .dout      (mac_out)
    );

    // [FIX #2] tanh_lut agora combinacional: sem clk, sem en.
    // tanh_out = f(mac_out) instantaneamente.
    tanh_lut u_tanh (
        .din  (mac_out),
        .dout (tanh_out)
    );

    // Argmax recebe mac_out diretamente (camada de saída não usa tanh;
    // argmax(tanh(y)) == argmax(y) pois tanh é monotônica crescente).
    argmax_block u_argmax (
        .clk   (clk),
        .reset (reset),
        .clr   (clr_argmax_w),   // [FIX #4] reset entre inferências
        .en    (en_argmax_w),
        .din   (mac_out),
        .digit (predicted_digit)
    );

endmodule