`timescale 1ns / 1ps

// ============================================================
//  Testbench: elm_accel_tb_real.v  (v4)
//
//  Correções v4:
//    - $time/1000 substituído por $time nas mensagens de
//      progresso e resultado (linhas 143 e 153 da v3).
//      Com timescale 1ns/1ps, $time já retorna o valor em ns.
//      A divisão por 1000 fazia o log exibir ~100 ns quando
//      o tempo real era ~100.000 ns.
//    - Formato %0t trocado por %0d para evitar ambiguidade
//      de unidade nas mensagens numéricas.
//    - Comentário do TIMEOUT_CYCLES corrigido:
//      ciclos reais = 128 × 788 + 10 × 130 = 102.164
//      (não 100.736 como constava na v3).
//
//  ARQUIVOS NECESSÁRIOS NA PASTA sim/:
//    W_in_q.hex  — 100352 valores hex, um por linha
//    b_q.hex     —    128 valores hex, um por linha
//    beta_q.hex  —   1280 valores hex, um por linha
//    png.hex     —    784 valores hex, um por linha (imagem teste)
//
//  DEPENDÊNCIA DE COMPILAÇÃO:
//    ram_stubs.v deve ser compilado antes deste testbench.
//    O run_all.do já garante essa ordem.
// ============================================================

module elm_accel_tb_real;

    // ----------------------------------------------------------
    // Parâmetros de tempo
    // ----------------------------------------------------------
    parameter CLK_PERIOD = 10; // 10 ns = 100 MHz

    // Ciclos totais com FSM completa (oculta + saída):
    //   Oculta : 128 × (HIDDEN_ADDR + 784×HIDDEN_MAC +
    //                   ADD_BIAS_ADDR + ADD_BIAS_EXEC + ACTIVATE)
    //          = 128 × 788 = 100.864
    //   Saída  : 10  × (OUTPUT_ADDR + 128×OUTPUT_MAC + DO_ARGMAX)
    //          = 10  × 130 = 1.300
    //   FINISH : 1
    //   Total  : 102.165 ciclos
    //   Margem : 515
    parameter TIMEOUT_CYCLES = 102_680;
    parameter TIMEOUT_NS     = TIMEOUT_CYCLES * CLK_PERIOD; // 1.026.800 ns

    // ----------------------------------------------------------
    // Sinais do DUT
    // ----------------------------------------------------------
    reg  clk, reset, start;
    wire done;
    wire [3:0] predicted_digit;

    // ----------------------------------------------------------
    // Evento: sinaliza que todos os arquivos foram verificados
    // ----------------------------------------------------------
    event ev_files_ok;

    // ----------------------------------------------------------
    // DUT — elm_accel_core instancia todas as RAMs internamente.
    //       Dados carregados pelo ram_stubs.v via $readmemh.
    // ----------------------------------------------------------
    elm_accel_core dut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit)
    );

    // ----------------------------------------------------------
    // Clock
    // ----------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // ----------------------------------------------------------
    // Verificação de arquivos + controle principal
    // ----------------------------------------------------------
    integer fcheck;
    integer cycle_count;

    initial begin : main_control
        reset       = 1;
        start       = 0;
        cycle_count = 0;

        // Verifica presença dos arquivos .hex antes de simular
        fcheck = $fopen("W_in_q.hex", "r");
        if (fcheck == 0) begin $display("ERRO: W_in_q.hex nao encontrado."); $finish; end
        $fclose(fcheck);
        $display("OK: W_in_q.hex");

        fcheck = $fopen("b_q.hex", "r");
        if (fcheck == 0) begin $display("ERRO: b_q.hex nao encontrado."); $finish; end
        $fclose(fcheck);
        $display("OK: b_q.hex");

        fcheck = $fopen("beta_q.hex", "r");
        if (fcheck == 0) begin $display("ERRO: beta_q.hex nao encontrado."); $finish; end
        $fclose(fcheck);
        $display("OK: beta_q.hex");

        fcheck = $fopen("png.hex", "r");
        if (fcheck == 0) begin $display("ERRO: png.hex nao encontrado."); $finish; end
        $fclose(fcheck);
        $display("OK: png.hex");

        -> ev_files_ok;

        // Reset por 8 ciclos
        repeat(8) @(posedge clk);
        reset = 0;
        repeat(5) @(posedge clk);

        // Dispara inferência
        @(posedge clk); #1; start = 1;
        @(posedge clk); #1; start = 0;

        $display("\n===== INFERENCIA INICIADA =====");
        $display("Tempo de inicio: %0d ns", $time);  // [FIX] era $time sem unidade
    end

    // ----------------------------------------------------------
    // Contador de ciclos após start
    // ----------------------------------------------------------
    reg inferencia_ativa;
    initial inferencia_ativa = 0;

    always @(posedge clk) begin
        if (start)
            inferencia_ativa <= 1;
        if (done)
            inferencia_ativa <= 0;
        if (inferencia_ativa) begin
            cycle_count = cycle_count + 1;
            if (cycle_count % 10_000 == 0)
                // [FIX] era $time/1000 com %0t → exibia ~100 em vez de ~100000
                $display("[%0d ns] Ciclo %0d de ~%0d...",
                         $time, cycle_count, TIMEOUT_CYCLES);
        end
    end

    // ----------------------------------------------------------
    // Monitor de done — imprime resultado e encerra
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (done) begin
            $display("\n===== INFERENCIA CONCLUIDA =====");
            // [FIX] era $time/1000 com %0t → valor 1000x menor que o real
            $display("Tempo total   : %0d ns", $time);
            $display("Ciclos totais : %0d",    cycle_count);
            $display("Digito predito: %0d",    predicted_digit);
            if (predicted_digit <= 9)
                $display("RESULTADO: OK — digito %0d no range [0,9].", predicted_digit);
            else
                $display("RESULTADO: FALHA — digito %0d fora de [0,9]!", predicted_digit);
            $display("================================\n");
            $finish;
        end
    end

    // ----------------------------------------------------------
    // Timeout de segurança
    // ----------------------------------------------------------
    initial begin : timeout_guard
        @(ev_files_ok);
        #(TIMEOUT_NS + 500);
        $display("\nERRO: Timeout! Inferencia nao concluiu em %0d ciclos.", TIMEOUT_CYCLES);
        $display("Possiveis causas:");
        $display("  - FSM travada em algum estado");
        $display("  - done nunca vai para 1");
        $display("  - RAMs com dados incorretos");
        $finish;
    end

endmodule
