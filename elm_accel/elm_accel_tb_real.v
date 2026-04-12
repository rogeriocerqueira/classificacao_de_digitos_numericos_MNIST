`timescale 1ns / 1ps

// ============================================================
//  Testbench: elm_accel_tb_real.v
//  DUT: elm_accel (acelerador ELM para classificação MNIST)
//  COM DADOS REAIS DOS ARQUIVOS:
//    - png.txt: imagem 28x28 de um dígito (valores hexadecimais)
//    - W_in_q.txt: pesos da camada oculta (128x784)
//    - b_q.txt: biases da camada oculta (128)
//    - beta_q.txt: pesos da camada de saída (10x128)
// ============================================================

module elm_accel_tb_real;

    // ----------------------------------------------------------
    // Parâmetros
    // ----------------------------------------------------------
    parameter CLK_PERIOD     = 10;        // 10 ns = 100 MHz
    parameter TIMEOUT_CYCLES = 128 * 820; // 128 neurônios × 820 ciclos
    parameter NUM_NEURONS    = 128;
    parameter NUM_PIXELS     = 784;
    parameter NUM_OUTPUTS    = 10;

    // ----------------------------------------------------------
    // Sinais do DUT
    // ----------------------------------------------------------
    reg  clk, reset, start;
    wire done;
    wire [3:0] predicted_digit;

    // ----------------------------------------------------------
    // Sinais para RAMs (inicialização com dados reais)
    // ----------------------------------------------------------
    reg [16:0] w_addr;
    reg [9:0]  img_addr;
    reg [6:0]  b_addr;
    reg [10:0] beta_addr;
    
    reg        w_wren, img_wren, b_wren, beta_wren;
    reg [15:0] w_data;
    reg [7:0]  img_data;
    reg [15:0] b_data;
    reg [7:0]  beta_data;
    
    wire [15:0] w_q;
    wire [7:0]  img_q;
    wire [15:0] b_q;
    wire [7:0]  beta_q;

    // ----------------------------------------------------------
    // Dados reais (arrays para inicialização)
    // ----------------------------------------------------------
    
    // Imagem: 784 pixels (do arquivo png.txt)
    reg [7:0] image_data [0:783];
    
    // Pesos W_in: 128×784 = 100352 valores (16 bits, signed)
    reg [15:0] win_data [0:100351];
    
    // Bias: 128 valores (16 bits, signed)
    reg [15:0] bias_data [0:127];
    
    // Beta: 1280 valores (8 bits, signed) - convertido para 16 bits
    reg [15:0] beta_data_ext [0:1279];

    // ----------------------------------------------------------
    // DUT
    // ----------------------------------------------------------
    elm_accel dut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // ----------------------------------------------------------
    // RAMs com dados reais (modo escrita inicial)
    // ----------------------------------------------------------
    
    ram_w_in u_ram_w (
        .address (w_addr),
        .clock   (clk),
        .data    (w_data),
        .rden    (1'b1),
        .wren    (w_wren),
        .q       (w_q)
    );
    
    ram_image u_ram_img (
        .address (img_addr),
        .clock   (clk),
        .data    (img_data),
        .rden    (1'b1),
        .wren    (img_wren),
        .q       (img_q)
    );
    
    ram_bias u_ram_b (
        .address (b_addr),
        .clock   (clk),
        .data    (b_data),
        .rden    (1'b1),
        .wren    (b_wren),
        .q       (b_q)
    );
    
    ram_beta u_ram_beta (
        .address (beta_addr),
        .clock   (clk),
        .data    (beta_data),
        .rden    (1'b1),
        .wren    (beta_wren),
        .q       (beta_q)
    );
    
    // ----------------------------------------------------------
    // Clock
    // ----------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;
    
    // ----------------------------------------------------------
    // Inicialização dos arrays com dados dos arquivos
    // ----------------------------------------------------------
    integer file, idx;
    integer val_int;
    
    initial begin : load_data
        // ------------------------------------------------------
        // 1. Carregar imagem (png.txt)
        // ------------------------------------------------------
        $display("\n===== Carregando imagem do arquivo png.txt =====");
        file = $fopen("png.txt", "r");
        if (file == 0) begin
            $display("ERRO: Não foi possível abrir png.txt");
            $finish;
        end
        
        for (idx = 0; idx < 784; idx = idx + 1) begin
            $fscanf(file, "%d: %h\n", val_int, image_data[idx]);
        end
        $fclose(file);
        $display("Imagem carregada: %0d pixels", 784);
        
        // Exibir um resumo da imagem (primeiros 28 pixels da primeira linha)
        $write("Primeira linha da imagem: ");
        for (idx = 0; idx < 28; idx = idx + 1)
            $write("%02X ", image_data[idx]);
        $display("");
        
        // ------------------------------------------------------
        // 2. Carregar pesos W_in (W_in_q.txt)
        // ------------------------------------------------------
        $display("\n===== Carregando pesos W_in do arquivo W_in_q.txt =====");
        file = $fopen("W_in_q.txt", "r");
        if (file == 0) begin
            $display("ERRO: Não foi possível abrir W_in_q.txt");
            $finish;
        end
        
        for (idx = 0; idx < 100352; idx = idx + 1) begin
            $fscanf(file, "%d\n", val_int);
            win_data[idx] = val_int[15:0];
        end
        $fclose(file);
        $display("Pesos W_in carregados: %0d valores", 100352);
        
        // ------------------------------------------------------
        // 3. Carregar bias (b_q.txt)
        // ------------------------------------------------------
        $display("\n===== Carregando bias do arquivo b_q.txt =====");
        file = $fopen("b_q.txt", "r");
        if (file == 0) begin
            $display("ERRO: Não foi possível abrir b_q.txt");
            $finish;
        end
        
        for (idx = 0; idx < 128; idx = idx + 1) begin
            $fscanf(file, "%d\n", val_int);
            bias_data[idx] = val_int[15:0];
        end
        $fclose(file);
        $display("Bias carregados: %0d valores", 128);
        
        // ------------------------------------------------------
        // 4. Carregar beta (beta_q.txt) e estender para 16 bits
        // ------------------------------------------------------
        $display("\n===== Carregando beta do arquivo beta_q.txt =====");
        file = $fopen("beta_q.txt", "r");
        if (file == 0) begin
            $display("ERRO: Não foi possível abrir beta_q.txt");
            $finish;
        end
        
        for (idx = 0; idx < 1280; idx = idx + 1) begin
            $fscanf(file, "%d\n", val_int);
            // Estender sinal de 8 para 16 bits
            if (val_int < 0)
                beta_data_ext[idx] = {8'hFF, val_int[7:0]};
            else
                beta_data_ext[idx] = {8'h00, val_int[7:0]};
        end
        $fclose(file);
        $display("Beta carregados: %0d valores", 1280);
    end
    
    // ----------------------------------------------------------
    // Inicialização das RAMs (escrita dos dados reais)
    // ----------------------------------------------------------
    integer i_ram, j_ram;
    
    initial begin : init_rams
        // Aguarda os arrays serem carregados
        #100;
        
        $display("\n===== Inicializando RAMs com dados reais =====");
        
        // ------------------------------------------------------
        // Escrever imagem na RAM
        // ------------------------------------------------------
        $display("Escrevendo imagem na RAM_image...");
        img_wren = 1;
        for (i_ram = 0; i_ram < 784; i_ram = i_ram + 1) begin
            @(posedge clk);
            img_addr = i_ram;
            img_data = image_data[i_ram];
        end
        @(posedge clk);
        img_wren = 0;
        $display("Imagem escrita com sucesso!");
        
        // ------------------------------------------------------
        // Escrever pesos W_in na RAM
        // ------------------------------------------------------
        $display("Escrevendo pesos W_in na RAM_w_in...");
        w_wren = 1;
        for (i_ram = 0; i_ram < 100352; i_ram = i_ram + 1) begin
            @(posedge clk);
            w_addr = i_ram;
            w_data = win_data[i_ram];
            if (i_ram % 10000 == 0 && i_ram > 0)
                $display("  Escritos %0d/%0d pesos...", i_ram, 100352);
        end
        @(posedge clk);
        w_wren = 0;
        $display("Pesos W_in escritos com sucesso!");
        
        // ------------------------------------------------------
        // Escrever bias na RAM
        // ------------------------------------------------------
        $display("Escrevendo bias na RAM_bias...");
        b_wren = 1;
        for (i_ram = 0; i_ram < 128; i_ram = i_ram + 1) begin
            @(posedge clk);
            b_addr = i_ram;
            b_data = bias_data[i_ram];
        end
        @(posedge clk);
        b_wren = 0;
        $display("Bias escritos com sucesso!");
        
        // ------------------------------------------------------
        // Escrever beta na RAM (8 bits)
        // ------------------------------------------------------
        $display("Escrevendo beta na RAM_beta...");
        beta_wren = 1;
        for (i_ram = 0; i_ram < 1280; i_ram = i_ram + 1) begin
            @(posedge clk);
            beta_addr = i_ram;
            beta_data = beta_data_ext[i_ram][7:0];  // Pega apenas os 8 bits inferiores
        end
        @(posedge clk);
        beta_wren = 0;
        $display("Beta escritos com sucesso!");
        
        $display("\n===== Inicialização das RAMs concluída! =====");
    end
    
    // ----------------------------------------------------------
    // Controle principal
    // ----------------------------------------------------------
    initial begin : main_control
        // Inicializa sinais
        reset = 1;
        start = 0;
        w_wren = 0;
        img_wren = 0;
        b_wren = 0;
        beta_wren = 0;
        w_addr = 0;
        img_addr = 0;
        b_addr = 0;
        beta_addr = 0;
        w_data = 0;
        img_data = 0;
        b_data = 0;
        beta_data = 0;
        
        // Aguarda inicialização das RAMs
        #5000;
        
        // Libera reset
        reset = 0;
        repeat(5) @(posedge clk);
        
        // Inicia inferência
        @(posedge clk); start = 1;
        @(posedge clk); start = 0;
        
        $display("\n===== INFERÊNCIA INICIADA =====");
        $display("Tempo de início: %0t ns", $time);
    end
    
    // ----------------------------------------------------------
    // Monitor de done e resultado
    // ----------------------------------------------------------
    reg [3:0] final_digit;
    
    always @(posedge clk) begin
        if (done) begin
            final_digit = predicted_digit;
            $display("\n===== INFERÊNCIA CONCLUÍDA =====");
            $display("Tempo: %0t ns", $time);
            $display("Dígito predito: %0d", final_digit);
            $display("================================\n");
            $finish;
        end
    end
    
    // ----------------------------------------------------------
    // Timeout de segurança
    // ----------------------------------------------------------
    initial begin : timeout
        #10000000;  // 10 ms de timeout
        $display("\nERRO: Timeout! Inferência não concluída em 10ms.");
        $finish;
    end
    
    // ----------------------------------------------------------
    // Monitoramento opcional: valores intermediários
    // ----------------------------------------------------------
    integer cycle_count = 0;
    
    always @(posedge clk) begin
        if (!reset && !done && start) begin
            cycle_count = cycle_count + 1;
            if (cycle_count % 10000 == 0)
                $display("[%0t ns] Ciclo %0d... aguardando done", $time, cycle_count);
        end
    end
    
endmodule