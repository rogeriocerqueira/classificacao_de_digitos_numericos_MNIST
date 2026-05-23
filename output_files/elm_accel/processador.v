// ============================================================
//  Top-level: processador
//  DE1-SoC — Cyclone V (5CSEMA5F31C6)
//
//  Integra:
//    - elm_accel  : co-processador ELM (inferência MNIST)
//    - display_7seg: saída visual nos HEX0..HEX5
//
//  Interface com a placa:
//    Entradas:
//      CLOCK_50    : clock de 50 MHz da DE1-SoC
//      KEY[0]      : reset (ativo baixo)
//      KEY[1]      : start (ativo baixo, borda de descida)
//
//    Saídas:
//      HEX0..HEX5 : displays de 7 segmentos
//      LEDR[0]     : done (LED vermelho pisca ao concluir)
//      LEDR[9]     : busy (LED aceso durante inferência)
// ============================================================

module processador (
    input  wire        CLOCK_50,
    input  wire [1:0]  KEY,       // KEY[0]=reset, KEY[1]=start (ativo baixo)

    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
    output wire [6:0]  HEX4,
    output wire [6:0]  HEX5,

    output wire [9:0]  LEDR
);

    // ----------------------------------------------------------
    // Sinais internos
    // ----------------------------------------------------------
    wire clk;
    wire reset;
    wire start_pulse;
    wire done;
    wire [3:0] predicted_digit;

    // Clock direto de 50 MHz
    assign clk = CLOCK_50;

    // Reset ativo alto (KEY[0] é ativo baixo na DE1-SoC)
    assign reset = ~KEY[0];

    // ----------------------------------------------------------
    // Detector de borda de descida para KEY[1] (start)
    // Gera pulso de 1 ciclo quando KEY[1] é pressionado
    // ----------------------------------------------------------
    reg key1_prev;
    always @(posedge clk or posedge reset) begin
        if (reset)
            key1_prev <= 1'b1;
        else
            key1_prev <= KEY[1];
    end
    assign start_pulse = key1_prev & ~KEY[1]; // borda de descida

    // ----------------------------------------------------------
    // Co-processador ELM
    // ----------------------------------------------------------
    elm_accel u_elm (
        .clk             (clk),
        .reset           (reset),
        .start           (start_pulse),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // ----------------------------------------------------------
    // Display de 7 segmentos
    // ----------------------------------------------------------
    display_7seg u_display (
        .clk             (clk),
        .reset           (reset),
        .start           (start_pulse),
        .done            (done),
        .predicted_digit (predicted_digit),
        .HEX0            (HEX0),
        .HEX1            (HEX1),
        .HEX2            (HEX2),
        .HEX3            (HEX3),
        .HEX4            (HEX4),
        .HEX5            (HEX5)
    );

    // ----------------------------------------------------------
    // LEDs de status
    // LEDR[0] = done  (acende ao concluir)
    // LEDR[9] = busy  (acende durante inferência)
    // ----------------------------------------------------------
    reg busy;
    always @(posedge clk or posedge reset) begin
        if (reset)
            busy <= 1'b0;
        else if (start_pulse)
            busy <= 1'b1;
        else if (done)
            busy <= 1'b0;
    end

    assign LEDR[0]   = done;
    assign LEDR[9]   = busy;
    assign LEDR[8:1] = 8'b0;

endmodule