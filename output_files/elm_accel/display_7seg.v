// ============================================================
//  Módulo: display_7seg
//  Placa:  DE1-SoC (Cyclone V)
//
//  Comportamento simplificado:
//    - Antes de done : todos os displays apagados
//    - Após done     : HEX0 mostra o dígito predito (0-9)
//                      HEX1..HEX5 apagados
//
//  Lógica: catodo comum — segmento ACESO com nível BAIXO (0)
// ============================================================

module display_7seg (
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire       done,
    input  wire [3:0] predicted_digit,

    output reg  [6:0] HEX0
);

    // Todos os segmentos apagados
    localparam SEG_OFF = 7'b1111111;

    // Codificação dos dígitos 0-9 (catodo comum, ativo em 0)
    // Ordem dos bits: gfedcba
    function [6:0] decode_digit;
        input [3:0] d;
        case (d)
            4'd0: decode_digit = 7'b1000000;
            4'd1: decode_digit = 7'b1111001;
            4'd2: decode_digit = 7'b0100100;
            4'd3: decode_digit = 7'b0110000;
            4'd4: decode_digit = 7'b0011001;
            4'd5: decode_digit = 7'b0010010;
            4'd6: decode_digit = 7'b0000010;
            4'd7: decode_digit = 7'b1111000;
            4'd8: decode_digit = 7'b0000000;
            4'd9: decode_digit = 7'b0010000;
            default: decode_digit = SEG_OFF;
        endcase
    endfunction

    // Registra o dígito quando done=1
    reg [3:0] digit_latch;
    reg       result_valid;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            digit_latch  <= 4'd0;
            result_valid <= 1'b0;
        end else if (start) begin
            result_valid <= 1'b0;
        end else if (done) begin
            digit_latch  <= predicted_digit;
            result_valid <= 1'b1;
        end
    end

    // Saídas
    always @(*) begin

        // HEX0: mostra o dígito após done, apagado antes
        if (result_valid)
            HEX0 = decode_digit(digit_latch);
        else
            HEX0 = SEG_OFF;
    end

endmodule