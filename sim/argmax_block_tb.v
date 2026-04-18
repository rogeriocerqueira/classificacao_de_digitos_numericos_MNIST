`timescale 1ns / 1ps

// ============================================================
//  Testbench: argmax_block_tb.v
//
//  Correções aplicadas:
//    - Adicionada porta clr (nova porta do argmax_block corrigido)
//    - Adicionado Teste 2: verifica que clr reseta max_val
//      e digit entre inferências consecutivas (Bug #4 corrigido)
//    - Adicionado Teste 3: sequência com valores negativos
//      confirma comparação sinalizada
// ============================================================

module argmax_block_tb;

    reg        clk;
    reg        reset;
    reg        clr;      // NOVO: porta adicionada
    reg        en;
    reg [15:0] din;
    wire [3:0] digit;

    argmax_block uut (
        .clk  (clk),
        .reset(reset),
        .clr  (clr),     // NOVO: conectado
        .en   (en),
        .din  (din),
        .digit(digit)
    );

    // Clock 50 MHz → período 20 ns
    initial clk = 0;
    always #10 clk = ~clk;

    integer errors = 0;

    task check_digit;
        input [3:0]      esperado;
        input [8*40-1:0] nome;
        begin
            if (digit === esperado)
                $display("[PASS] %-40s | digit=%0d", nome, digit);
            else begin
                $display("[FAIL] %-40s | digit=%0d  esperado=%0d",
                         nome, digit, esperado);
                errors = errors + 1;
            end
        end
    endtask

    // Envia 10 valores com en=1 (um por ciclo), depois en=0
    task send_values;
        input [15:0] v0, v1, v2, v3, v4, v5, v6, v7, v8, v9;
        begin
            @(posedge clk); #1; en=1; din=v0;
            @(posedge clk); #1;       din=v1;
            @(posedge clk); #1;       din=v2;
            @(posedge clk); #1;       din=v3;
            @(posedge clk); #1;       din=v4;
            @(posedge clk); #1;       din=v5;
            @(posedge clk); #1;       din=v6;
            @(posedge clk); #1;       din=v7;
            @(posedge clk); #1;       din=v8;
            @(posedge clk); #1;       din=v9;
            @(posedge clk); #1; en=0;
        end
    endtask

    initial begin
        $display("============================================================");
        $display("           TESTE DO ARGMAX BLOCK                           ");
        $display("============================================================");

        // Inicialização
        clk   = 0;
        reset = 1;
        clr   = 0;
        en    = 0;
        din   = 16'h0000;
        #30;
        reset = 0;
        @(negedge clk);

        // =========================================================
        // TESTE 1: Máximo no índice 3
        //   Valores: 0x0100, 0x0500, 0x0200, 0x7000, 0x0050 (×6)
        //   Esperado: digit = 3
        // =========================================================
        $display("\n----- Teste 1: maximo no indice 3 -----");
        send_values(
            16'h0100, 16'h0500, 16'h0200, 16'h7000,
            16'h0050, 16'h0050, 16'h0050, 16'h0050,
            16'h0050, 16'h0050
        );
        @(negedge clk);
        check_digit(4'd3, "Teste 1: maximo no indice 3");

        // =========================================================
        // TESTE 2: clr reseta entre inferências (Bug #4)
        //   Após Teste 1, max_val = 0x7000 (muito alto).
        //   Sem clr: nenhum valor da 2ª inferência superaria 0x7000
        //   e digit ficaria preso no valor anterior.
        //   Com clr: max_val = 0x8000 → digit atualiza corretamente.
        //   Esperado: digit = 7 (valor 0x0800)
        // =========================================================
        $display("\n----- Teste 2: clr reseta entre inferencias -----");
        @(posedge clk); #1; clr=1;
        @(posedge clk); #1; clr=0;   // 1 ciclo de clr
        send_values(
            16'h0010, 16'h0020, 16'h0030, 16'h0040,
            16'h0050, 16'h0060, 16'h0070, 16'h0800,   // índice 7 é maior
            16'h0090, 16'h00A0
        );
        @(negedge clk);
        check_digit(4'd7, "Teste 2: clr correto (indice 7)");

        // =========================================================
        // TESTE 3: Valores negativos — comparação sinalizada
        //   Todos negativos exceto índice 5 (único positivo).
        //   Esperado: digit = 5
        // =========================================================
        $display("\n----- Teste 3: valores negativos, positivo no indice 5 -----");
        @(posedge clk); #1; clr=1;
        @(posedge clk); #1; clr=0;
        send_values(
            16'hF000, 16'hF100, 16'hF200, 16'hF300,
            16'hF400, 16'h0200,                        // índice 5 positivo
            16'hF600, 16'hF700, 16'hF800, 16'hF900
        );
        @(negedge clk);
        check_digit(4'd5, "Teste 3: unico positivo no indice 5");

        // =========================================================
        // TESTE 4: reset global recomeça do zero
        //   Após reset: digit deve voltar a 0, max_val = 0x8000
        //   Verifica que reset assíncrono funciona corretamente
        // =========================================================
        $display("\n----- Teste 4: reset global -----");
        reset = 1;
        @(posedge clk); #1;
        reset = 0;
        @(negedge clk);
        check_digit(4'd0, "Teste 4: digit=0 apos reset global");

        // =========================================================
        // Resultado final
        // =========================================================
        #20;
        $display("\n============================================================");
        if (errors == 0)
            $display("  RESULTADO: TODOS OS TESTES PASSARAM");
        else
            $display("  RESULTADO: %0d ERRO(S) DETECTADO(S)", errors);
        $display("============================================================");
        $stop;
    end

endmodule
