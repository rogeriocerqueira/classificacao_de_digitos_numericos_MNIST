`timescale 1ns / 1ps

// ============================================================
//  Testbench: elm_accel_tb.v
//
//  Correções aplicadas:
//    - u_tanh_tb: removidas portas .clk e .en (tanh_lut agora
//      combinacional — sem clock, sem enable)
//    - u_argmax_tb: adicionada porta .clr (Bug #4 corrigido)
//    - Teste 4E reescrito: verifica comportamento combinacional
//      (dout muda com din sem depender de en)
//    - Removido sinal tanh_en (inutilizado após correção)
//    - TIMEOUT_NS recalculado para cobrir camada de saída
//
//  ARQUIVOS NECESSÁRIOS (mesma pasta do testbench):
//    W_in_q.hex  — pesos W_in  (100352 × 16-bit, um valor por linha)
//    png.hex     — imagem      (784    ×  8-bit, zeros para teste)
//    b_q.hex     — bias        (128    × 16-bit, zeros para teste)
//    beta_q.hex  — beta        (1280   × 16-bit, zeros para teste)
// ============================================================


// ============================================================
//  STUB: altsyncram
// ============================================================



// ============================================================
//  TESTBENCH PRINCIPAL
// ============================================================
module elm_accel_tb;

    parameter CLK_PERIOD = 10; // 10 ns = 100 MHz

    // Ciclos totais estimados com camada de saída:
    //   Oculta : 128 × (784 + 2) = 100.736  (HIDDEN_MAC acumula todos os 784)
    //   Saída  : 10  × (128 + 2) = 1.300
    //   Margem : 200
    parameter TIMEOUT_NS = 102_680 * 10;

    // ----------------------------------------------------------
    // Sinais do DUT
    // ----------------------------------------------------------
    reg  clk, reset, start;
    wire done;
    wire [3:0] predicted_digit;

    // Sinais para teste unitário do MAC
    reg         mac_clr, mac_en, mac_load_bias;
    reg  [15:0] mac_din_x, mac_din_w, mac_din_bias;
    wire [15:0] mac_dout;

    // Sinais para teste unitário do tanh (combinacional — sem tanh_en)
    reg  [15:0] tanh_din;
    wire [15:0] tanh_dout;

    // Sinais para teste unitário do argmax
    reg         argmax_rst, argmax_clr, argmax_en;  // argmax_clr: NOVO
    reg  [15:0] argmax_din;
    wire [3:0]  argmax_digit;

    integer error_count;
    reg [3:0] digit1, digit2, digit3;
    reg       timeout_flag;

    // ----------------------------------------------------------
    // DUT principal
    // ----------------------------------------------------------
    elm_accel_core dut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // ----------------------------------------------------------
    // Submódulos isolados para testes unitários
    // ----------------------------------------------------------
    mac u_mac_tb (
        .clk      (clk),
        .clr      (mac_clr),
        .en       (mac_en),
        .load_bias(mac_load_bias),
        .din_x    (mac_din_x),
        .din_w    (mac_din_w),
        .din_bias (mac_din_bias),
        .dout     (mac_dout)
    );

    // [FIX] tanh_lut agora combinacional: sem .clk e sem .en
    tanh_lut u_tanh_tb (
        .din  (tanh_din),
        .dout (tanh_dout)
    );

    // [FIX] argmax_block: adicionada porta .clr
    argmax_block u_argmax_tb (
        .clk   (clk),
        .reset (argmax_rst),
        .clr   (argmax_clr),   // NOVO
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
        tanh_din      = 0;      // sem tanh_en (combinacional)
        argmax_rst    = 1;
        argmax_clr    = 0;      // NOVO
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
        // TESTE 2: IDLE sem start
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

        // 3C: acumulação 1.0+1.0=2.0
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

        // 3E: load_bias — acumula 1.0*1.0=1.0, injeta bias=0.5 → espera 1.5
        $display("--- MAC 3E: load_bias ---");
        @(posedge clk); #1;
        mac_clr=1; mac_en=0; mac_load_bias=0;
        mac_din_x=16'h1000; mac_din_w=16'h1000;
        mac_din_bias=16'h0800;
        @(posedge clk); #1;
        mac_clr=0; mac_en=1;
        @(posedge clk); #1;
        mac_en=0;
        @(posedge clk); #1;
        mac_load_bias=1;
        @(posedge clk); #1;
        mac_load_bias=0;
        @(negedge clk);
        check(mac_dout, 16'h1800, "MAC 3E: 1.0*1.0 + bias(0.5) = 1.5");

        // 3F: saída preservada sem enable (acc não muda)
        @(posedge clk); #1;
        @(negedge clk);
        check(mac_dout, 16'h1800, "MAC 3F: saida preservada sem enable");

        // ======================================================
        // TESTE 4: tanh_lut COMBINACIONAL
        // (sem tanh_en — dout muda imediatamente com din)
        // ======================================================
        $display("\n===== TESTE 4: tanh_lut combinacional =====");

        // 4A: Saturação positiva: x > 1.0 → 1.0
        tanh_din = 16'h2000; // 2.0
        #1;
        check(tanh_dout, 16'h1000, "tanh 4A: 2.0 -> 1.0 (sat+)");

        // 4B: Saturação negativa: grande negativo → -1.0
        tanh_din = 16'h8000; // -8.0 (maior negativo em Q4.12)
        #1;
        check(tanh_dout, 16'hF000, "tanh 4B: -8.0 -> -1.0 (sat-)");

        // 4C: Região linear: 0.5 → 0.5
        tanh_din = 16'h0800; // 0.5
        #1;
        check(tanh_dout, 16'h0800, "tanh 4C: 0.5 -> 0.5 (linear)");

        // 4D: Fronteira: x = 1.0 → 1.0 (não satura, condição é >)
        tanh_din = 16'h1000; // 1.0
        #1;
        check(tanh_dout, 16'h1000, "tanh 4D: 1.0 -> 1.0 (borda, linear)");

        // [FIX] 4E: Comportamento combinacional — dout muda com din sem clock
        // Na versão original (registrada) este teste verificava hold.
        // Com módulo combinacional, a saída acompanha a entrada.
        tanh_din = 16'hF800; // -0.5 → região linear
        #1;
        check(tanh_dout, 16'hF800, "tanh 4E: combinacional -0.5 -> -0.5");

        // 4F: Fronteira negativa: x = -1.0 → -1.0 (não satura)
        tanh_din = 16'hF000; // -1.0
        #1;
        check(tanh_dout, 16'hF000, "tanh 4F: -1.0 -> -1.0 (borda, linear)");

        // ======================================================
        // TESTE 5: argmax — máximo no índice 9 (sequência crescente)
        // ======================================================
        $display("\n===== TESTE 5: argmax indice 9 =====");
        argmax_rst=1; @(posedge clk); #1; argmax_rst=0;
        argmax_clr=1; @(posedge clk); #1; argmax_clr=0;  // clr entre inferências
        begin : blk5
            reg [3:0] k5;
            k5 = 0;
            repeat(10) begin
                @(posedge clk); #1;
                argmax_en  = 1;
                argmax_din = (k5 + 1) * 16'h0100;
                k5 = k5 + 1;
            end
        end
        @(posedge clk); #1; argmax_en=0;
        @(negedge clk);
        check(argmax_digit, 9, "argmax 5: max no indice 9");

        // ======================================================
        // TESTE 6: argmax — máximo no índice 0 (sequência decrescente)
        // ======================================================
        $display("\n===== TESTE 6: argmax indice 0 =====");
        argmax_rst=1; @(posedge clk); #1; argmax_rst=0;
        argmax_clr=1; @(posedge clk); #1; argmax_clr=0;
        begin : blk6
            reg [3:0] k6;
            k6 = 0;
            repeat(10) begin
                @(posedge clk); #1;
                argmax_en  = 1;
                argmax_din = (10 - k6) * 16'h0100;
                k6 = k6 + 1;
            end
        end
        @(posedge clk); #1; argmax_en=0;
        @(negedge clk);
        check(argmax_digit, 0, "argmax 6: max no indice 0");

        // ======================================================
        // TESTE 7: argmax — único positivo no índice 5
        // ======================================================
        $display("\n===== TESTE 7: argmax indice 5 =====");
        argmax_rst=1; @(posedge clk); #1; argmax_rst=0;
        argmax_clr=1; @(posedge clk); #1; argmax_clr=0;
        repeat(5) begin
            @(posedge clk); #1;
            argmax_en  = 1;
            argmax_din = 16'hF000;
        end
        @(posedge clk); #1; argmax_en=1; argmax_din=16'h0200;
        repeat(4) begin
            @(posedge clk); #1;
            argmax_en  = 1;
            argmax_din = 16'hF000;
        end
        @(posedge clk); #1; argmax_en=0;
        @(negedge clk);
        check(argmax_digit, 5, "argmax 7: unico positivo no indice 5");

        // ======================================================
        // TESTE 8: Inferência completa
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
        // TESTE 10: Reset durante inferência
        // ======================================================
        $display("\n===== TESTE 10: Reset mid-op =====");
        @(posedge clk); #1; start=1;
        @(posedge clk); #1; start=0;
        repeat(400) @(posedge clk);
        reset=1; @(posedge clk); reset=0;
        @(negedge clk);
        check(done, 0, "Teste 10A: done=0 imediatamente apos reset");
        repeat(20) @(posedge clk); @(negedge clk);
        check(done, 0, "Teste 10B: done=0 permanece em IDLE apos reset");

        // ======================================================
        // TESTE 11: Segunda inferência
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
        // TESTE 12: Consistência — 3 inferências devem retornar
        //           o mesmo dígito (verifica Bug #4 corrigido)
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

    // Monitor passivo
    always @(posedge clk)
        if (done)
            $display("[%0t ns] MONITOR: done=1  predicted_digit=%0d",
                     $time/1000, predicted_digit);

endmodule
