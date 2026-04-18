`timescale 1ns / 1ps

// ============================================================
//  Testbench: fsm_tb.v
//
//  Correções aplicadas:
//    - Adicionado wire clr_argmax e conexão na instância do DUT
//      (nova saída da FSM corrigida — Bug #4)
//    - Adicionado Teste 11: verifica que clr_argmax=1 é emitido
//      exatamente no ciclo IDLE→HIDDEN_ADDR (início de cada
//      inferência), garantindo reset correto do argmax.
// ============================================================

module fsm_tb;

    parameter CLK_PERIOD     = 10;
    parameter CICLOS_NEURONIO = 788; // HIDDEN_ADDR(1)+784×HIDDEN_MAC+ADD_BIAS_ADDR(1)+ADD_BIAS_EXEC(1)+ACTIVATE(1)
    parameter TIMEOUT_CYCLES  = 102_680;

    reg clk, reset, start;

    wire        clr_acc, en_mac, en_tanh, en_argmax;
    wire        load_bias, sel_beta;
    wire        clr_argmax;     // NOVO
    wire [16:0] addr_w;
    wire [9:0]  addr_x;
    wire [6:0]  addr_b;
    wire [10:0] addr_beta;
    wire        done;

    integer error_count;

    fsm dut (
        .clk        (clk),
        .reset      (reset),
        .start      (start),
        .clr_acc    (clr_acc),
        .en_mac     (en_mac),
        .load_bias  (load_bias),
        .en_tanh    (en_tanh),
        .en_argmax  (en_argmax),
        .sel_beta   (sel_beta),
        .clr_argmax (clr_argmax),   // NOVO
        .addr_w     (addr_w),
        .addr_x     (addr_x),
        .addr_b     (addr_b),
        .addr_beta  (addr_beta),
        .done       (done)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    task apply_reset;
        begin
            reset = 1; start = 0;
            repeat(3) @(posedge clk);
            reset = 0;
            @(negedge clk);
            $display("[%0t ns] Reset liberado.", $time/1000);
        end
    endtask

    task check;
        input [63:0]      actual, expected;
        input [200*8-1:0] msg;
        begin
            if (actual !== expected) begin
                $display("FALHA  [%0t ns] %s | esperado=%0d  obtido=%0d",
                         $time/1000, msg, expected, actual);
                error_count = error_count + 1;
            end else
                $display("OK     [%0t ns] %s = %0d", $time/1000, msg, actual);
        end
    endtask

    task wait_for_done;
        input integer     max_cycles;
        input [200*8-1:0] label;
        integer i; reg found;
        begin
            found = 0;
            for (i = 0; i < max_cycles && !found; i = i + 1) begin
                @(posedge clk);
                if (done) found = 1;
            end
            if (found)
                $display("OK     [%0t ns] %s — done=1 recebido.", $time/1000, label);
            else begin
                $display("FALHA  [%0t ns] %s — Timeout!", $time/1000, label);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("fsm_tb.vcd");
        $dumpvars(0, fsm_tb);
        error_count = 0;

        // ======================================================
        // TESTE 1: Reset
        // ======================================================
        $display("\n===== TESTE 1: Reset =====");
        apply_reset;
        check(clr_acc,    0, "clr_acc    apos reset");
        check(en_mac,     0, "en_mac     apos reset");
        check(en_tanh,    0, "en_tanh    apos reset");
        check(en_argmax,  0, "en_argmax  apos reset");
        check(load_bias,  0, "load_bias  apos reset");
        check(sel_beta,   0, "sel_beta   apos reset");
        check(clr_argmax, 0, "clr_argmax apos reset");
        check(done,       0, "done       apos reset");
        check(addr_w,     0, "addr_w     apos reset");
        check(addr_x,     0, "addr_x     apos reset");
        check(addr_b,     0, "addr_b     apos reset");
        check(addr_beta,  0, "addr_beta  apos reset");

        // ======================================================
        // TESTE 2: IDLE sem start
        // ======================================================
        $display("\n===== TESTE 2: IDLE sem start =====");
        repeat(5) @(posedge clk);
        @(negedge clk);
        check(done,   0, "done   permanece 0 em IDLE");
        check(en_mac, 0, "en_mac permanece 0 em IDLE");

        // ======================================================
        // TESTE 3: HIDDEN_ADDR e HIDDEN_MAC
        // Fluxo real:
        //   T0 (posedge com start=1) -> HIDDEN_ADDR
        //   T1 (posedge)            -> HIDDEN_MAC (en_mac = 0 ainda)
        //   T2 (posedge)            -> HIDDEN_MAC (en_mac = 1, incrementos)
        // ======================================================
        $display("\n===== TESTE 3: HIDDEN_ADDR e HIDDEN_MAC =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;   // T0 -> HIDDEN_ADDR
        @(posedge clk);                   // T1 -> HIDDEN_MAC (sem en_mac)
        @(posedge clk); @(negedge clk);  // T2 -> HIDDEN_MAC (en_mac=1, addr_x=1)
        check(en_mac, 1, "en_mac=1 em HIDDEN_MAC");
        check(addr_x, 1, "addr_x=1 (primeiro pixel)");
        check(addr_w, 1, "addr_w=1 (primeiro peso)");

        repeat(100) @(posedge clk);
        @(negedge clk);
        check(addr_x, 101, "addr_x=101 apos 100 ciclos adicionais");
        check(addr_w, 101, "addr_w=101 apos 100 ciclos adicionais");

        // ======================================================
        // TESTE 4: ADD_BIAS_ADDR e ADD_BIAS_EXEC
        // count_x está em 101. Para count_x chegar em 783:
        // 682 posedges → count_x=783, HIDDEN_MAC acumula (FIX #1)
        // 683ª posedge → transição para ADD_BIAS_ADDR
        // ======================================================
        $display("\n===== TESTE 4: ADD_BIAS =====");
        repeat(683) @(posedge clk);
        @(posedge clk); @(negedge clk);   // ADD_BIAS_ADDR estável
        check(en_mac,    0, "en_mac=0    em ADD_BIAS_ADDR");
        check(addr_b,    0, "addr_b=0    (bias neuronio 0)");
        @(posedge clk); @(negedge clk);   // ADD_BIAS_EXEC
        check(load_bias, 1, "load_bias=1 em ADD_BIAS_EXEC");

        // ======================================================
        // TESTE 5: ACTIVATE
        // ======================================================
        $display("\n===== TESTE 5: ACTIVATE =====");
        @(posedge clk); @(negedge clk);   // ACTIVATE
        check(en_tanh,  1, "en_tanh=1  em ACTIVATE");
        check(sel_beta, 0, "sel_beta=0 em camada oculta");

        // ======================================================
        // TESTE 6: addr_w resetado para base do neurônio 1 = 784
        // ======================================================
        $display("\n===== TESTE 6: addr_w no inicio do neuronio 1 =====");
        check(addr_w, 784, "addr_w=784 (base neuronio 1)");
        check(addr_x, 0,   "addr_x=0   (pixel 0 do neuronio 1)");

        // ======================================================
        // TESTE 7: Inferência completa
        // ======================================================
        $display("\n===== TESTE 7: Inferencia completa (done) =====");
        wait_for_done(TIMEOUT_CYCLES, "Inferencia 1");
        @(posedge clk); @(negedge clk);
        check(done,    0, "done=0    apos retorno ao IDLE");
        check(en_tanh, 0, "en_tanh=0 em IDLE");

        // ======================================================
        // TESTE 8: sel_beta na camada de saída
        // ======================================================
        $display("\n===== TESTE 8: sel_beta na camada de saida =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;
        repeat(128 * 788) @(posedge clk);
        @(negedge clk);
        check(sel_beta, 1, "sel_beta=1 na camada de saida");

        // ======================================================
        // TESTE 9: Reset durante operação
        // ======================================================
        $display("\n===== TESTE 9: Reset durante operacao =====");
        wait_for_done(TIMEOUT_CYCLES, "Inferencia pre-reset");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;
        repeat(200) @(posedge clk);
        reset = 1;
        @(posedge clk); reset = 0;
        @(negedge clk);
        check(en_mac,  0, "en_mac=0  apos reset");
        check(en_tanh, 0, "en_tanh=0 apos reset");
        check(done,    0, "done=0    apos reset");
        check(addr_w,  0, "addr_w=0  apos reset");

        // ======================================================
        // TESTE 10: addr_b por neurônio
        // ======================================================
        $display("\n===== TESTE 10: addr_b por neuronio =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;

        begin : bloco_addr_b
            integer n;
            for (n = 0; n < 3; n = n + 1) begin
                if (n == 0)
                    repeat(785) @(posedge clk);
                else
                    repeat(788) @(posedge clk);
                @(negedge clk);
                check(addr_b, n, "addr_b correto em ADD_BIAS_ADDR");
                @(posedge clk); // ADD_BIAS_EXEC
                @(posedge clk); // ACTIVATE
            end
        end

        // ======================================================
        // TESTE 11: clr_argmax emitido no início de cada inferência
        //   Verifica Bug #4 (Fix): clr_argmax deve ser 1 exatamente
        //   no ciclo em que start é processado (IDLE → HIDDEN_ADDR).
        // ======================================================
        $display("\n===== TESTE 11: clr_argmax no inicio da inferencia =====");
        wait_for_done(TIMEOUT_CYCLES, "Inferencia pre-teste11");

        // Pulsa start e captura clr_argmax no mesmo ciclo (IDLE)
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;   // FSM registrou IDLE→HIDDEN_ADDR
        // clr_argmax deve ser 1 neste ciclo (saída registrada de IDLE)
        @(negedge clk);
        check(clr_argmax, 1, "clr_argmax=1 no ciclo IDLE->HIDDEN_ADDR");

        // No próximo ciclo (HIDDEN_ADDR), clr_argmax volta a 0
        @(posedge clk); @(negedge clk);
        check(clr_argmax, 0, "clr_argmax=0 em HIDDEN_ADDR");

        // ======================================================
        // Resumo
        // ======================================================
        $display("\n========================================");
        if (error_count == 0)
            $display("RESULTADO: TODOS OS TESTES PASSARAM.");
        else
            $display("RESULTADO: %0d FALHA(S) DETECTADA(S).", error_count);
        $display("========================================\n");
        $finish;
    end

    // Monitor de transições
    reg prev_en_mac, prev_en_tanh, prev_done, prev_sel_beta, prev_clr_argmax;
    always @(posedge clk) begin
        prev_en_mac     <= en_mac;
        prev_en_tanh    <= en_tanh;
        prev_done       <= done;
        prev_sel_beta   <= sel_beta;
        prev_clr_argmax <= clr_argmax;
        if (!prev_en_mac     && en_mac)               $display("[%0t ns] -> HIDDEN_MAC",   $time/1000);
        if ( prev_en_mac     && !en_mac && !en_tanh)  $display("[%0t ns] -> ADD_BIAS",     $time/1000);
        if (!prev_en_tanh    && en_tanh)              $display("[%0t ns] -> ACTIVATE",     $time/1000);
        if (!prev_sel_beta   && sel_beta)             $display("[%0t ns] -> CAMADA SAIDA", $time/1000);
        if (!prev_done       && done)                 $display("[%0t ns] -> FINISH",       $time/1000);
        if (!prev_clr_argmax && clr_argmax)           $display("[%0t ns] -> CLR_ARGMAX",   $time/1000);
    end

endmodule
