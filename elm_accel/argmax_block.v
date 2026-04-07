module argmax_block (
    input wire clk,
    input wire reset,        // Reset para zerar entre imagens
    input wire en,           // Habilita quando um novo neurônio de saída está pronto
    input wire [15:0] din,   // Valor vindo da camada de saída (H * Beta)
    output reg [3:0] digit   // Dígito final previsto (0-9)
);
    reg [15:0] max_val;
    reg [3:0] counter; 

    always @(posedge clk) begin
        if (reset) begin
            max_val <= 16'h8000; // Menor valor possível em complemento de 2
            digit   <= 4'd0;
            counter <= 4'd0;
        end 
        else if (en) begin
            // Comparação sinalizada (crucial para números negativos)
            if ($signed(din) > $signed(max_val)) begin
                max_val <= din;
                digit   <= counter;
            end
            
            // Incrementa o contador de 0 a 9
            if (counter == 4'd9)
                counter <= 4'd0;
            else
                counter <= counter + 1'b1;
        end
    end
endmodule