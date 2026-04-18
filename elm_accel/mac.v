// =============================================================
// MAC — Multiply-Accumulate  (formato Q4.12)
//
// Operação: acc += din_x * din_w   (quando en=1)
//           acc += din_bias        (quando load_bias=1)
//           acc  = 0               (quando clr=1)
//
// Representação interna:
//   din_x, din_w, din_bias : Q4.12  (16 bits com sinal)
//   acc                    : Q8.24  (32 bits com sinal)
//   dout                   : Q4.12  (fatia acc[27:12])
//
// Prioridade de controle: clr > load_bias > en
// =============================================================

module mac (
    input  wire               clk,
    input  wire               clr,
    input  wire               en,
    input  wire               load_bias,
    input  wire signed [15:0] din_x,
    input  wire signed [15:0] din_w,
    input  wire signed [15:0] din_bias,
    output wire signed [15:0] dout
);

    reg  signed [31:0] acc;
    wire signed [31:0] mult_result;

    // Q4.12 × Q4.12 → Q8.24 (32 bits — sem perda de precisão)
    assign mult_result = din_x * din_w;

    // -------------------------------------------------------
    // CORREÇÃO: din_bias precisa ser alargado para 32 bits
    // ANTES do shift, caso contrário o shift ocorre em 16 bits
    // e todos os bits úteis são perdidos por overflow.
    //
    // Conversão Q4.12 → Q8.24: shifta 12 bits à esquerda.
    // O sinal é preservado via extensão explícita de sinal.
    // -------------------------------------------------------
    wire signed [31:0] bias_shifted;
    assign bias_shifted = $signed({{16{din_bias[15]}}, din_bias}) <<< 12;

    always @(posedge clk) begin
        if (clr)
            acc <= 32'sb0;
        else if (load_bias)
            acc <= acc + bias_shifted;
        else if (en)
            acc <= acc + mult_result;
    end

    // Fatia Q8.24 → Q4.12: descarta os 12 bits fracionários extras
    // e os 4 bits inteiros superiores (overflow não tratado aqui).
    assign dout = acc[27:12];

endmodule
