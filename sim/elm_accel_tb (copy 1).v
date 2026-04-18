`timescale 1ns / 1ps

// ============================================================
//  Testbench: elm_accel_tb.v  (v6)
//
//  CORREÇÕES v6:
//    - u_mac_tb atualizado com portas load_bias e din_bias
//    - Adicionados sinais mac_load_bias e mac_din_bias
//    - Adicionado TESTE 3E: load_bias soma bias ao acumulador
//    - TIMEOUT_NS recalculado para cobrir camada de saída
//    - Stub altsyncram documenta ram_h (parte zerada, correto)
//    - Watchdog ajustado proporcionalmente
//
//  ARQUIVOS NECESSÁRIOS (mesma pasta do testbench):
//    W_in_q.hex  — pesos W_in  (100352 x 16-bit, um valor hex por linha)
//    png.hex     — imagem      (784    x  8-bit, zeros para teste)
//    b_q.hex     — bias        (128    x 16-bit, zeros para teste)
//    beta_q.hex  — beta        (1280   x 16-bit, zeros para teste)
//
//  CICLOS ESTIMADOS (FSM corrigida com camada de saída):
//    Camada oculta : 128 neurônios × (784 MAC + 1 bias + 1 tanh) = ~100.480
//    Camada saída  : 10  neurônios × (128 MAC + 1 argmax)        =  ~1.290
//    Total aprox.  : ~101.770 ciclos
// ============================================================


// ============================================================
//  STUB: altsyncram  (v6)
// ============================================================
module altsyncram (
    input  wire [16:0] address_a,
    input  wire        clock0,
    input  wire [15:0] data_a,
    input  wire        rden_a,
    input  wire        wren_a,
    output reg  [15:0] q_a,
    input  wire        aclr0, aclr1,
    input  wire        address_b,
    input  wire        addressstall_a, addressstall_b,
    input  wire        byteena_a, byteena_b,
    input  wire        clock1,
    input  wire        clocken0, clocken1, clocken2, clocken3,
    input  wire        data_b,
    output wire        eccstatus,
    output wire        q_b,
    input  wire        rden_b, wren_b
);
    parameter width_a                       = 16;
    parameter widthad_a                     = 10;
    parameter numwords_a                    = 1024;
    parameter outdata_reg_a                 = "CLOCK0";
    parameter init_file                     = "UNUSED";
    parameter operation_mode                = "SINGLE_PORT";
    parameter ram_block_type                = "M10K";
    parameter power_up_uninitialized        = "FALSE";
    parameter clock_enable_input_a          = "BYPASS";
    parameter clock_enable_output_a         = "BYPASS";
    parameter outdata_aclr_a                = "NONE";
    parameter read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ";
    parameter lpm_hint                      = "";
    parameter lpm_type                      = "altsyncram";
    parameter intended_device_family        = "Cyclone V";
    parameter width_byteena_a               = 1;

    assign eccstatus = 1'b0;
    assign q_b       = 1'b0;

    // Memoria dimensionada ao maximo; leitura limitada por numwords_a.
    reg [15:0] mem [0:131071];

    // ----------------------------------------------------------
    // Carregamento via $readmemh com range explicito [0:numwords_a-1].
    // Elimina warning 10850: "number of words does not match".
    // Cada instancia recebe numwords_a correto via defparam do IP:
    //   ram_w_in : 100352  |  ram_beta : 1280
    //   ram_bias : 128     |  ram_image: 784   |  ram_h: 128
    // ----------------------------------------------------------
    initial begin
        if (init_file == "W_in_q.mif")
            $readmemh("W_in_q.hex", mem, 0, numwords_a-1);
        else if (init_file == "b_q.mif")
            $readmemh("b_q.hex",    mem, 0, numwords_a-1);
        else if (init_file == "beta_q.mif")
            $readmemh("beta_q.hex", mem, 0, numwords_a-1);
        else if (init_file == "png.mif")
            $readmemh("png.hex",    mem, 0, numwords_a-1);
        else if (init_file == "../files/W_in_q.hex")
            $readmemh("W_in_q.hex", mem, 0, numwords_a-1);
        else if (init_file == "../files/png.hex")
            $readmemh("png.hex",    mem, 0, numwords_a-1);
        else if (init_file == "../b_q.hex")
            $readmemh("b_q.hex",    mem, 0, numwords_a-1);
        else if (init_file == "beta_q.hex")
            $readmemh("beta_q.hex", mem, 0, numwords_a-1);
        // ram_h e qualquer outro: parte zerado (correto)
    end

    // Leitura/Escrita sincronas - latencia 1 ciclo
    always @(posedge clock0) begin
        if (wren_a) mem[address_a] <= data_a;
        if (rden_a) q_a            <= mem[address_a];
    end

endmodule


// ============================================================
//  TESTBENCH PRINCIPAL  (v6)
// ============================================================
module elm_accel_tb;

    parameter CLK_PERIOD = 10; // 10 ns = 100 MHz

    // Ciclos totais estimados com camada de saída:
    //   Oculta : 128 × (784 + 2) = 100.736
    //   Saída  : 10  × (128 + 2) = 1.300
    //   Margem : 200
    // Total: ~102.236 ciclos × 10 ns = 1.022.360 ns
    parameter TIMEOUT_NS = 102_500 * 10; // ~1.025.000 ns com folga

    // ----------------------------------------------------------
    // Sinais do DUT
    // ----------------------------------------------------------
    reg  clk, reset, start;
    wire done;
    wire [3:0] predicted_digit;

    // Sinais para teste unitário do MAC
    reg         mac_clr, mac_en, mac_load_bias;   // mac_load_bias: NOVO
    reg  [15:0] mac_din_x, mac_din_w, mac_din_bias; // mac_din_bias: NOVO
    wire [15:0] mac_dout;

    // Sinais para teste unitário do tanh
    reg         tanh_en;
    reg  [15:0] tanh_din;
    wire [15:0] tanh_dout;

    // Sinais para teste unitário do argmax
    reg         argmax_rst, argmax_en;
    reg  [15:0] argmax_din;
    wire [3:0]  argmax_digit;

    integer error_count;
    reg [3:0] digit1, digit2, digit3;
    reg       timeout_flag;

    // ----------------------------------------------------------
    // DUT principal
    // ----------------------------------------------------------
    elm_accel dut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // ----------------------------------------------------------
    // Submódulos isolados para testes unitários
    // ----------------------------------------------------------

    // MAC com novas portas load_bias e din_bias
    mac u_mac_tb (
        .clk      (clk),
        .clr      (mac_clr),
        .en       (mac_en),
        .load_bias(mac_load_bias),   // NOVO
        .din_x    (mac_din_x),
        .din_w    (mac_din_w),
        .din_bias (mac_din_bias),    // NOVO
        .dout     (mac_dout)
    );

    tanh_lut u_tanh_tb (
        .clk  (clk),
        .en   (tanh_en),
        .din  (tanh_din),
        .dout (tanh_dout)
    );

    argmax_block u_argmax_tb (
        .clk   (clk),
        .reset (argmax_rst),
        .en    (argmax_en),
        .din   (argmax_din),
        .digit (argmax_digit)
    );

    // ----------------------------------------------------------
    // Clock
    // ----------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ----------------------------------------------------------
    // Watchdog global
    // ----------------------------------------------------------
    initial begin
        #(TIMEOUT_NS * 6);
        $display("WATCHDOG [%0t ns]: simulacao travada. Abortando.", $time/1000);
        $finish;
    end

    // ----------------------------------------------------------
    // Task: wait_done — fork/join com timeout interno
    // ----------------------------------------------------------
    task wait_done;
        input [200*8-1:0] label;
        begin
            timeout_flag = 0;
            fork
                begin : th_event
                    wait (done == 1);
                    $display("OK     [%0t ns] %s — done=1.", $time/1000, label);
                    disable th_timeout;
                end
                begin : th_timeout
                    #(TIMEOUT_NS);
                    timeout_flag = 1;
                    $display("FALHA  [%0t ns] %s — Timeout esperando done.", $time/1000, label);
                    error_count = error_count + 1;
                    disable th_event;
                end
            join
        end
    endtask

    // ----------------------------------------------------------
    // Task: run_inference — dispara start e aguarda done
    // ----------------------------------------------------------
    task run_inference;
        output [3:0] digit_out;
        begin
            @(posedge clk); #1; start = 1;
            @(posedge clk); #1; start = 0;
            wait_done("run_inference");
            @(negedge clk);
            digit_out = predicted_digit;
        end
    endtask

    // ----------------------------------------------------------
    // Task: check — compara valor obtido vs esperado
    // ----------------------------------------------------------
    task check;
        input [63:0]      actual, expected;
        input [200*8-1:0] msg;
        begin
            if (actual !== expected) begin
                $display("FALHA  [%0t ns] %s | esp=%0d obt=%0d",
                         $time/1000, msg, expected, actual);
                error_count = error_count + 1;
            end else
                $display("OK     [%0t ns] %s = %0d", $time/1000, msg, actual);
        end
    endtask

    // ----------------------------------------------------------
    // Task: apply_reset
    // ----------------------------------------------------------
    task apply_reset;
        begin
            reset = 1; start = 0;
            repeat(4) @(posedge clk);
            reset = 0;
            @(negedge clk);
            $display("[%0t ns] Reset liberado.", $time/1000);
        end
    endtask

    // ----------------------------------------------------------
    // Inicialização dos sinais de teste unitário
    // ----------------------------------------------------------
    initial begin
        mac_clr       = 1;
        mac_en        = 0;
        mac_load_bias = 0;
        mac_din_x     = 0;
        mac_din_w     = 0;
        mac_din_bias  = 0;
        tanh_en       = 0;
        tanh_din      = 0;
        argmax_rst    = 1;
        argmax_en     = 0;
        argmax_din    = 0;
        timeout_flag  = 0;
    end

    // ----------------------------------------------------------
    // SEQUÊNCIA DE TESTES
    // ----------------------------------------------------------
    initial begin
        $dumpfile("elm_accel_tb.vcd");
        $dumpvars(0, elm_accel_tb);
        error_count = 0;

        // ======================================================
        // TESTE 1: Reset
        // ======================================================
        $display("\n===== TESTE 1: Reset =====");
        apply_reset;
        check(done,            0, "done apos reset");
        check(predicted_digit, 0, "predicted_digit apos reset");

        // ======================================================
        // TESTE 2: IDLE sem start — done deve permanecer 0
        // ======================================================
        $display("\n===== TESTE 2: IDLE sem start =====");
        repeat(15) @(posedge clk);
        @(negedge clk);
        check(done, 0, "done=0 em IDLE");

        // ======================================================
        // TESTE 3: MAC isolado (Q4.12: 1.0 = 16'h1000)
        // ======================================================
        $display("\n===== TESTE 3: MAC =====");

        // 3A: 1.0 * 1.0 = 1.0
        @(posedge clk); #1;
        mac_clr=1; mac_en=0; mac_load_bias=0;
        mac_din_x=16'h1000; mac_din_w=16'h1000;
        @(posedge clk); #1; mac_clr=0; mac_en=1;
        @(posedge clk); #1; mac_en=0;
        @(negedge clk);
        check(mac_dout, 16'h1000, "MAC 3A: 1.0*1.0=1.0");

        // 3B: 2.0 * 0.5 = 1.0
        @(posedge clk); #1; mac_clr=1;
        @(posedge clk); #1;
        mac_clr=0; mac_en=1;
        mac_din_x=16'h2000; mac_din_w=16'h0800;
        @(posedge clk); #1; mac_en=0;
        @(negedge clk);
        check(mac_dout, 16'h1000, "MAC 3B: 2.0*0.5=1.0");

        // 3C: acumulacao 1.0+1.0=2.0
        @(posedge clk); #1; mac_clr=1;
        @(posedge clk); #1;
        mac_clr=0; mac_en=1;
        mac_din_x=16'h1000; mac_din_w=16'h1000;
        @(posedge clk);
        @(posedge clk); #1; mac_en=0;
        @(negedge clk);
        check(mac_dout, 16'h2000, "MAC 3C: 1.0+1.0=2.0 (acum)");

        // 3D: clr zera o acumulador
        @(posedge clk); #1; mac_clr=1;
        @(posedge clk); #1; mac_clr=0;
        @(negedge clk);
        check(mac_dout, 16'h0000, "MAC 3D: clr=0 limpa acc");

        // 3E: load_bias — acumula 1.0*1.0=1.0, injeta bias=0.5 -> espera 1.5
        // Q4.12: 1.0=16'h1000, 0.5=16'h0800, 1.5=16'h1800
        $display("--- MAC 3E: load_bias ---");
        @(posedge clk); #1;
        mac_clr=1; mac_en=0; mac_load_bias=0;
        mac_din_x=16'h1000; mac_din_w=16'h1000;
        mac_din_bias=16'h0800; // bias = 0.5 em Q4.12
        @(posedge clk); #1;
        mac_clr=0; mac_en=1;
        @(posedge clk); #1;
        mac_en=0;
        // Agora injeta bias: load_bias=1 por 1 ciclo
        @(posedge clk); #1;
        mac_load_bias=1;
        @(posedge clk); #1;
        mac_load_bias=0;
        @(negedge clk);
        check(mac_dout, 16'h1800, "MAC 3E: 1.0*1.0 + bias(0.5) = 1.5");

        // 3F: load_bias nao ativa quando en=0 e load_bias=0 (valor preservado)
        @(posedge clk); #1; // sem clr, sem en, sem load_bias
        @(negedge clk);
        check(mac_dout, 16'h1800, "MAC 3F: saida preservada sem enable");

        // ======================================================
        // TESTE 4: tanh_lut
        // ======================================================
        $display("\n===== TESTE 4: tanh_lut =====");

        // Saturacao positiva: x > 1.0 -> tanh ~= 1.0
        @(posedge clk); #1; tanh_en=1; tanh_din=16'h2000; // 2.0
        @(posedge clk); #1; tanh_en=0;
        @(negedge clk);
        check(tanh_dout, 16'h1000, "tanh 4A: 2.0 -> 1.0 (sat+)");

        // Saturacao negativa: bit de sinal 1 -> tanh ~= -1.0
        @(posedge clk); #1; tanh_en=1; tanh_din=16'h8000; // -8.0 (maior negativo)
        @(posedge clk); #1; tanh_en=0;
        @(negedge clk);
        check(tanh_dout, 16'hF000, "tanh 4B: neg_grande -> -1.0 (sat-)");

        // Regiao linear: 0 < x <= 1.0 -> identidade
        @(posedge clk); #1; tanh_en=1; tanh_din=16'h0800; // 0.5
        @(posedge clk); #1; tanh_en=0;
        @(negedge clk);
        check(tanh_dout, 16'h0800, "tanh 4C: 0.5 -> 0.5 (linear)");

        // Fronteira: x = 1.0 -> identidade (nao satura ainda)
        @(posedge clk); #1; tanh_en=1; tanh_din=16'h1000; // 1.0
        @(posedge clk); #1; tanh_en=0;
        @(negedge clk);
        check(tanh_dout, 16'h1000, "tanh 4D: 1.0 -> 1.0 (fronteira)");

        // en=0: saida deve ser preservada (registro nao atualiza)
        @(posedge clk); #1; tanh_en=0; tanh_din=16'hDEAD;
        @(posedge clk); #1;
        @(negedge clk);
        check(tanh_dout, 16'h1000, "tanh 4E: en=0 preserva saida");

        // ======================================================
        // TESTE 5: argmax — maximo no indice 9 (sequencia crescente)
        // ======================================================
        $display("\n===== TESTE 5: argmax indice 9 =====");
        argmax_rst=1; @(posedge clk); #1; argmax_rst=0;
        begin : blk5
            reg [3:0] k5;
            k5 = 0;
            repeat(10) begin
                @(posedge clk); #1;
                argmax_en  = 1;
                argmax_din = (k5 + 1) * 16'h0100; // 0x100, 0x200, ..., 0xA00
                k5 = k5 + 1;
            end
        end
        @(posedge clk); #1; argmax_en=0;
        @(negedge clk);
        check(argmax_digit, 9, "argmax 5: max no indice 9");

        // ======================================================
        // TESTE 6: argmax — maximo no indice 0 (sequencia decrescente)
        // ======================================================
        $display("\n===== TESTE 6: argmax indice 0 =====");
        argmax_rst=1; @(posedge clk); #1; argmax_rst=0;
        begin : blk6
            reg [3:0] k6;
            k6 = 0;
            repeat(10) begin
                @(posedge clk); #1;
                argmax_en  = 1;
                argmax_din = (10 - k6) * 16'h0100; // 0xA00, 0x900, ..., 0x100
                k6 = k6 + 1;
            end
        end
        @(posedge clk); #1; argmax_en=0;
        @(negedge clk);
        check(argmax_digit, 0, "argmax 6: max no indice 0");

        // ======================================================
        // TESTE 7: argmax — unico positivo no indice 5
        // ======================================================
        $display("\n===== TESTE 7: argmax indice 5 =====");
        argmax_rst=1; @(posedge clk); #1; argmax_rst=0;
        // Indices 0..4: valor negativo (16'hF000 = -1.0 em Q4.12)
        repeat(5) begin
            @(posedge clk); #1;
            argmax_en  = 1;
            argmax_din = 16'hF000;
        end
        // Indice 5: unico positivo
        @(posedge clk); #1; argmax_en=1; argmax_din=16'h0200;
        // Indices 6..9: negativos novamente
        repeat(4) begin
            @(posedge clk); #1;
            argmax_en  = 1;
            argmax_din = 16'hF000;
        end
        @(posedge clk); #1; argmax_en=0;
        @(negedge clk);
        check(argmax_digit, 5, "argmax 7: unico positivo no indice 5");

        // ======================================================
        // TESTE 8: Inferencia completa (dados das RAMs inicializadas)
        // ======================================================
        $display("\n===== TESTE 8: Inferencia completa =====");
        apply_reset;
        run_inference(digit1);
        $display("       predicted_digit = %0d", digit1);
        if (digit1 <= 9)
            $display("OK     [%0t ns] Teste 8: digit=%0d no range [0,9]",
                     $time/1000, digit1);
        else begin
            $display("FALHA  [%0t ns] Teste 8: digit=%0d FORA de [0,9]",
                     $time/1000, digit1);
            error_count = error_count + 1;
        end

        // ======================================================
        // TESTE 9: done dura exatamente 1 ciclo de clock
        // ======================================================
        $display("\n===== TESTE 9: Largura do pulso done =====");
        @(posedge clk); #1; start=1;
        @(posedge clk); #1; start=0;
        wait_done("Teste 9");
        if (!timeout_flag) begin
            @(posedge clk); @(negedge clk);
            if (done == 0)
                $display("OK     [%0t ns] Teste 9: done dura 1 ciclo.", $time/1000);
            else begin
                $display("FALHA  [%0t ns] Teste 9: done permanece 1 apos fim.",
                         $time/1000);
                error_count = error_count + 1;
            end
        end

        // ======================================================
        // TESTE 10: Reset durante inferencia — FSM volta para IDLE
        // ======================================================
        $display("\n===== TESTE 10: Reset mid-op =====");
        @(posedge clk); #1; start=1;
        @(posedge clk); #1; start=0;
        // Deixa rodar ~400 ciclos (ainda na camada oculta) e reseta
        repeat(400) @(posedge clk);
        reset=1; @(posedge clk); reset=0;
        @(negedge clk);
        check(done, 0, "Teste 10A: done=0 imediatamente apos reset");
        repeat(20) @(posedge clk); @(negedge clk);
        check(done, 0, "Teste 10B: done=0 permanece em IDLE apos reset");

        // ======================================================
        // TESTE 11: Segunda inferencia — DUT deve funcionar apos reset
        // ======================================================
        $display("\n===== TESTE 11: Segunda inferencia =====");
        run_inference(digit2);
        if (digit2 <= 9)
            $display("OK     [%0t ns] Teste 11: digit2=%0d valido.",
                     $time/1000, digit2);
        else begin
            $display("FALHA  [%0t ns] Teste 11: digit2=%0d invalido.",
                     $time/1000, digit2);
            error_count = error_count + 1;
        end

        // ======================================================
        // TESTE 12: Consistencia — 3 inferencias sobre a mesma imagem
        //           devem retornar o mesmo digito
        // ======================================================
        $display("\n===== TESTE 12: Consistencia entre inferencias =====");
        run_inference(digit3);
        $display("       inf1=%0d  inf2=%0d  inf3=%0d", digit1, digit2, digit3);
        if (digit1 == digit2 && digit2 == digit3)
            $display("OK     [%0t ns] Teste 12: 3 inferencias consistentes.",
                     $time/1000);
        else begin
            $display("FALHA  [%0t ns] Teste 12: Inferencias inconsistentes!",
                     $time/1000);
            error_count = error_count + 1;
        end

        // ======================================================
        // RESULTADO FINAL
        // ======================================================
        $display("\n========================================");
        if (error_count == 0)
            $display("RESULTADO: TODOS OS TESTES PASSARAM.");
        else
            $display("RESULTADO: %0d FALHA(S) DETECTADA(S).", error_count);
        $display("========================================\n");
        $finish;
    end

    // ----------------------------------------------------------
    // Monitor passivo: imprime cada vez que done=1
    // ----------------------------------------------------------
    always @(posedge clk)
        if (done)
            $display("[%0t ns] MONITOR: done=1  predicted_digit=%0d",
                     $time/1000, predicted_digit);

endmodule