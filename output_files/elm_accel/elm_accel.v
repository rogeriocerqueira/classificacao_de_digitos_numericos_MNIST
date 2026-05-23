// ============================================================
//  elm_accel — Top-level DE1-SoC
//  Co-processador ELM para classificação MNIST
//
//  Interface com a placa (Cyclone V — 5CSEMA5F31C6):
//    CLOCK_50  : clock 50 MHz
//    KEY[0]    : reset  (ativo baixo)
//    KEY[1]    : start  (ativo baixo, borda detectada)
//    HEX0      : dígito predito (0-9)
//    HEX1..5   : apagados
//    LEDR[0]   : done  (acende ao concluir, apaga ao iniciar novo)
//    LEDR[9]   : busy  (acende durante inferência)
//
//  Correção aplicada:
//    [Design #1] LEDR[0] era conectado diretamente ao sinal
//                done, que pulsa apenas 1 ciclo a 50 MHz
//                (20 ns — invisível ao olho humano).
//                Agora LEDR[0] é alimentado por done_latch,
//                que mantém o nível alto até o próximo start.
//
//  Hierarquia:
//    elm_accel (top)
//    ├── elm_accel_core  (núcleo: FSM + MAC + RAMs + tanh + argmax)
//    └── display_7seg    (saída visual HEX0..5)
// ============================================================

module elm_accel (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,

    output wire [6:0]  HEX0,
    output wire [9:0]  LEDR
);

    // =========================================================
    // Sinais internos
    // =========================================================
    wire clk;
    wire reset;
    wire start;
    wire done;
    wire [3:0] predicted_digit;

    assign clk   = CLOCK_50;
    assign reset = ~KEY[0];   // KEY ativo baixo → reset ativo alto

    // Detector de borda de descida em KEY[1] → pulso de start (1 ciclo)
    reg key1_prev;
    always @(posedge clk or posedge reset) begin
        if (reset) key1_prev <= 1'b1;
        else       key1_prev <= KEY[1];
    end
    assign start = key1_prev & ~KEY[1];

    // =========================================================
    // Núcleo do co-processador
    // =========================================================
    elm_accel_core u_core (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // =========================================================
    // Display de 7 segmentos
    // =========================================================
    display_7seg u_display (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit),
        .HEX0            (HEX0)
    );

    // =========================================================
    // LEDs de status
    // =========================================================

    // busy: acende ao iniciar, apaga ao concluir
    reg busy;
    always @(posedge clk or posedge reset) begin
        if (reset)      busy <= 1'b0;
        else if (start) busy <= 1'b1;
        else if (done)  busy <= 1'b0;
    end

    // [FIX Design #1] done_latch: mantém LEDR[0] aceso após inferência.
    // done é um pulso de 1 ciclo (20 ns a 50 MHz — invisível ao olho).
    // done_latch é setado por done e limpo pelo próximo start ou reset.
    reg done_latch;
    always @(posedge clk or posedge reset) begin
        if (reset)      done_latch <= 1'b0;
        else if (start) done_latch <= 1'b0;  // apaga ao iniciar nova inferência
        else if (done)  done_latch <= 1'b1;  // acende ao concluir
    end

    assign LEDR[0]   = done_latch;  // [FIX] era: done (pulsava 1 ciclo)
    assign LEDR[9]   = busy;
    assign LEDR[8:1] = 8'b0;

endmodule