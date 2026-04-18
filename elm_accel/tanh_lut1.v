module tanh_lut (
    input wire clk,
    input wire en,        // Habilita a ativação (en_tanh)
    input wire [15:0] din,  // Dado vindo do MAC
    output reg [15:0] dout // Dado ativado em Q4.12
);
    // Exemplo simplificado de LUT (deve ser preenchida com valores reais de tanh)
    always @(posedge clk) begin
        if (en) begin
            // Lógica do Colega B: busca o valor aproximado da Tanh
            if (din[15] == 1'b0 && din > 16'h1000) // Se x > 1
                dout <= 16'h1000; // tanh(x) aprox 1.0 em Q4.12
            else if (din[15] == 1'b1)
                dout <= 16'hF000; // tanh(x) aprox -1.0
            else
                dout <= din; // Identidade simplificada para teste
        end
    end  // <-- FECHA o always block

endmodule  // <-- FECHA o módulo