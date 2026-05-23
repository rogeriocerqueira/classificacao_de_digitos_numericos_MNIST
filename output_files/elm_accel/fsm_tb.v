`timescale 1ns / 1ps

// ============================================================
//  Testbench: fsm_tb  (v2 - corrigido)
//  Módulo em teste: fsm
//
//  Correções em relação à v1:
//    1. Amostragem de sinais feita na NEGEDGE (estável após posedge)
//       para evitar race condition.
//    2. Contagem de ciclos ajustada ao comportamento real do pipeline.
//    3. fork/join substituído por tarefa de polling com timeout,
//       eliminando o falso disparo do timeout.
//    4. Teste 10 adicionado: verifica addr_b por neurônio.
// ============================================================

module fsm_tb;

    parameter CLK_PERIOD  = 10;
    parameter TIMEOUT_CYCLES = 128 * 800;

    reg clk, reset, start;

    wire        clr_acc, en_mac, en_tanh, en_argmax;
    wire [16:0] addr_w;
    wire [9:0]  addr_x;
    wire [6:0]  addr_b;
    wire        done;

    integer error_count;

    // ----------------------------------------------------------
    // DUT
    // ----------------------------------------------------------
    fsm dut (
        .clk      (clk),   .reset    (reset),  .start    (start),
        .clr_acc  (clr_acc),.en_mac   (en_mac), .en_tanh  (en_tanh),
        .en_argmax(en_argmax),
        .addr_w   (addr_w), .addr_x   (addr_x), .addr_b   (addr_b),
        .done     (done)
    );

    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ----------------------------------------------------------
    // Tarefas auxiliares
    // ----------------------------------------------------------
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
        input [63:0] actual, expected;
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

    // Polling com timeout — sem fork/join problemático
    task wait_for_done;
        input integer max_cycles;
        input [200*8-1:0] label;
        integer i; reg found;
        begin
            found = 0;
            for (i = 0; i < max_cycles && !found; i = i + 1) begin
                @(posedge clk);
                if (done) found = 1;
            end
            if (found)
                $display("OK     [%0t ns] %s - done=1 recebido.", $time/1000, label);
            else begin
                $display("FALHA  [%0t ns] %s - Timeout!", $time/1000, label);
                error_count = error_count + 1;
            end
        end
    endtask

    // ----------------------------------------------------------
    // Bloco principal
    // ----------------------------------------------------------
    initial begin
        $dumpfile("fsm_tb.vcd");
        $dumpvars(0, fsm_tb);
        error_count = 0;

        // ======================================================
        // TESTE 1: Reset
        // ======================================================
        $display("\n===== TESTE 1: Reset =====");
        apply_reset;
        check(clr_acc,   0, "clr_acc   apos reset");
        check(en_mac,    0, "en_mac    apos reset");
        check(en_tanh,   0, "en_tanh   apos reset");
        check(en_argmax, 0, "en_argmax apos reset");
        check(done,      0, "done      apos reset");
        check(addr_w,    0, "addr_w    apos reset");
        check(addr_x,    0, "addr_x    apos reset");
        check(addr_b,    0, "addr_b    apos reset");

        // ======================================================
        // TESTE 2: IDLE sem start
        // ======================================================
        $display("\n===== TESTE 2: IDLE sem start =====");
        repeat(5) @(posedge clk);
        @(negedge clk);
        check(done,   0, "done   permanece 0 em IDLE");
        check(en_mac, 0, "en_mac permanece 0 em IDLE");

        // ======================================================
        // TESTE 3 + 4: Pulsa start e verifica FETCH_HIDDEN
        //
        // Diagrama de ciclos (posedge):
        //   T0: start=1 capturado -> FSM registra transição p/ FETCH_HIDDEN,
        //       clr_acc=1, count_x=0
        //   T1: clr_acc=0, en_mac=1, addr_w=0, addr_x=0, count_x incrementa p/ 1
        //   T2: addr_w=1, addr_x=1 (count_x=1 aplicado às saídas combinacionais)
        //
        // Amostramos na NEGEDGE para pegar saída registrada estável.
        // ======================================================
        $display("\n===== TESTE 3+4: Inferencia / Enderecos em FETCH_HIDDEN =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;  // T0

        @(posedge clk); @(negedge clk); // T1 — clr_acc=0, en_mac=1, addr=0
        check(clr_acc, 0, "clr_acc=0 em FETCH_HIDDEN");
        check(en_mac,  1, "en_mac=1  em FETCH_HIDDEN");
        check(addr_x,  0, "addr_x=0 (pixel 0)");
        check(addr_w,  0, "addr_w=0 (neuronio 0, pixel 0)");

        // Avança 100 ciclos -> count_x chega a 100
        repeat(100) @(posedge clk); @(negedge clk);
        check(addr_x, 100, "addr_x=100 (pixel 100)");
        check(addr_w, 100, "addr_w=100 (neuronio 0)");

        // ======================================================
        // TESTE 5: ADD_BIAS do neurônio 0
        // Faltam 783-100 = 683 ciclos para count_x==783,
        // +1 ciclo para FSM registrar a transição para ADD_BIAS.
        // ======================================================
        $display("\n===== TESTE 5: ADD_BIAS (neuronio 0) =====");
        repeat(683) @(posedge clk);
        @(posedge clk); @(negedge clk); // agora em ADD_BIAS
        check(en_mac, 0, "en_mac=0 em ADD_BIAS");
        check(addr_b, 0, "addr_b=0 (bias neuronio 0)");

        // ======================================================
        // TESTE 6: ACTIVATE do neurônio 0
        // ======================================================
        $display("\n===== TESTE 6: ACTIVATE (neuronio 0) =====");
        @(posedge clk); @(negedge clk); // ADD_BIAS -> ACTIVATE
        check(en_tanh, 1, "en_tanh=1 em ACTIVATE");

        // ======================================================
        // TESTE 7: Aguarda done — inferência completa
        // ======================================================
        $display("\n===== TESTE 7: Aguardando done =====");
        wait_for_done(128 * 800, "Inferencia 1");

        @(posedge clk); @(negedge clk); // FSM retorna ao IDLE
        check(done,    0, "done=0    apos retorno ao IDLE");
        check(en_tanh, 0, "en_tanh=0 em FINISH->IDLE");

        // ======================================================
        // TESTE 8: Segunda inferência
        // ======================================================
        $display("\n===== TESTE 8: Segunda inferencia =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;
        wait_for_done(128 * 800, "Inferencia 2");

        // ======================================================
        // TESTE 9: Reset durante operação
        // ======================================================
        $display("\n===== TESTE 9: Reset durante operacao =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;
        repeat(200) @(posedge clk);
        reset = 1;
        @(posedge clk);  // borda captura o reset
        reset = 0;
        @(negedge clk);
        check(en_mac,  0, "en_mac=0  apos reset durante op");
        check(en_tanh, 0, "en_tanh=0 apos reset durante op");
        check(done,    0, "done=0    apos reset durante op");
        check(addr_w,  0, "addr_w=0  apos reset durante op");

        // ======================================================
        // TESTE 10: addr_b acompanha count_h
        // Inicia nova inferência e verifica addr_b nos
        // estados ADD_BIAS dos primeiros 3 neurônios.
        //
        // Ciclos até ADD_BIAS do neurônio N (após start):
        //   N=0 : 1(clr_acc) + 784(FETCH) + 1(transição) = 786 posedges
        //   N=1 : 786 + 786 = 1572, etc.
        // ======================================================
        $display("\n===== TESTE 10: addr_b por neuronio =====");
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;

        begin : bloco_addr_b
            integer n;
            for (n = 0; n < 3; n = n + 1) begin
                repeat(785) @(posedge clk); // FETCH_HIDDEN (784 pixels + 1 transição)
                @(posedge clk); @(negedge clk); // em ADD_BIAS
                check(addr_b, n, "addr_b correto no ADD_BIAS");
                @(posedge clk); // ACTIVATE
                @(posedge clk); // FETCH_HIDDEN do próximo (clr_acc)
            end
        end

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

    // ----------------------------------------------------------
    // Monitor de transições
    // ----------------------------------------------------------
    reg prev_en_mac, prev_en_tanh, prev_done;
    always @(posedge clk) begin
        prev_en_mac  <= en_mac;
        prev_en_tanh <= en_tanh;
        prev_done    <= done;
        if (!prev_en_mac  && en_mac)              $display("[%0t ns] --> FETCH_HIDDEN",   $time/1000);
        if ( prev_en_mac  && !en_mac && !en_tanh) $display("[%0t ns] --> ADD_BIAS",       $time/1000);
        if (!prev_en_tanh && en_tanh)             $display("[%0t ns] --> ACTIVATE",       $time/1000);
        if (!prev_done    && done)                $display("[%0t ns] --> FINISH (done=1)",$time/1000);
    end

endmodule
