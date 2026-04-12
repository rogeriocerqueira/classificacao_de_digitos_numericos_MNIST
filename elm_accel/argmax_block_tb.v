`timescale 1ns / 1ps

module argmax_block_tb;

    reg clk;
    reg reset;
    reg en;
    reg [15:0] din;
    wire [3:0] digit;

    // Instancia o Argmax corrigido
    argmax_block uut (
        .clk(clk),
        .reset(reset),
        .en(en),
        .din(din),
        .digit(digit)
    );

    // Clock de 50MHz
    always #10 clk = ~clk;

    initial begin
        // Inicialização
        clk = 0; reset = 1; en = 0; din = 0;
        #30 reset = 0;
        
        $display("Iniciando Teste do Argmax...");

        // Simulando a chegada de 10 neurônios de saída (índices 0 a 9)
        // Índice 0
        din = 16'h0100; en = 1; #20; en = 0; #20; 
        // Índice 1
        din = 16'h0500; en = 1; #20; en = 0; #20;
        // Índice 2
        din = 16'h0200; en = 1; #20; en = 0; #20;
        // Índice 3 -> VALOR MÁXIMO (Vencedor)
        din = 16'h7000; en = 1; #20; en = 0; #20;
        // Índices 4 a 9 (valores menores)
        repeat(6) begin
            din = 16'h0050; en = 1; #20; en = 0; #20;
        end

        $display("Dígito previsto pelo hardware: %d (Esperado: 3)", digit);
        
        #100;
        $display("Teste Finalizado.");
        $stop;
    end
endmodule