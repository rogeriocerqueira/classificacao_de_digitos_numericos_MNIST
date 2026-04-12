`timescale 1ns / 1ps

module tanh_lut_tb;

    // Sinais do Testbench
    reg clk;
    reg en;
    reg [15:0] din;
    wire [15:0] dout;

    // Instância do módulo sob teste (UUT)
    tanh_lut uut (
        .clk(clk),
        .en(en),
        .din(din),
        .dout(dout)
    );

    // Geração do Clock (50MHz)
    always #10 clk = ~clk;

    initial begin
        // Inicialização
        clk = 0;
        en = 0;
        din = 0;

        $display("Iniciando Teste da Tanh LUT...");
        #25 en = 1; // Habilita o módulo 

        // --- Caso 1: Valor Pequeno Positivo (Deve retornar o próprio valor) ---
        din = 16'h0200; // 0.125 em Q4.12
        #20;
        $display("Entrada: %h | Saida: %h (Esperado: 0200)", din, dout);

        // --- Caso 2: Limite Positivo (x > 1.0) ---
        din = 16'h1500; // 1.3125 em Q4.12 [cite: 6]
        #20;
        $display("Entrada: %h | Saida: %h (Esperado: 1000)", din, dout); // [cite: 7]

        // --- Caso 3: Valor Negativo (Teste de Saturação) ---
        din = 16'hFF00; // -0.0625 em Q4.12
        #20;
        $display("Entrada: %h | Saida: %h (Esperado: F000)", din, dout); // [cite: 8]

        // --- Caso 4: Desabilitar o módulo ---
        en = 0;
        din = 16'h0500;
        #20;
        $display("Módulo Desabilitado | Entrada: %h | Saida: %h (Nao deve mudar)", din, dout);

        #40;
        $display("Teste Finalizado.");
        $stop;
    end

endmodule