module mac (
    input wire clk,
    input wire clr,
    input wire en,
    input wire [15:0] din_x, // Pixel (Q4.12)
    input wire [15:0] din_w, // Peso (Q4.12)
    output wire [15:0] dout
);
    // Acumulador de 32 bits para evitar overflow durante as 784 somas
    reg signed [31:0] acc;
    wire signed [31:0] mult_result;

    // Multiplicação com sinal: Q4.12 * Q4.12 = Q8.24 (32 bits)
    assign mult_result = $signed(din_x) * $signed(din_w);

    always @(posedge clk) begin
        if (clr) begin
            acc <= 32'b0;
        end else if (en) begin
            acc <= acc + mult_result;
        end
    end

    // Truncamento para retornar ao formato Q4.12:
    // Pegamos do bit 12 (início da parte fracionária) até o 27
    assign dout = acc[27:12];

endmodule