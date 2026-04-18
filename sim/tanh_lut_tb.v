`timescale 1ns / 1ps

// ============================================================
//  Testbench: tanh_lut_tb.v
//
//  Correções aplicadas:
//    - Removidas portas clk e en (tanh_lut agora combinacional)
//    - Caso 5 reescrito: verifica comportamento combinacional
//      (dout muda instantaneamente com din, sem depender de en)
//    - Adicionado Caso 6: verifica fronteira exata x = -1.0
// ============================================================

module tanh_lut_tb;

    // =========================================================
    // Sinais — sem clk e sem en (módulo combinacional)
    // =========================================================
    reg  signed [15:0] din;
    wire signed [15:0] dout;

    // =========================================================
    // Instância do módulo sob teste (UUT)
    // =========================================================
    tanh_lut uut (
        .din (din),
        .dout(dout)
    );

    // =========================================================
    // Infraestrutura de verificação
    // =========================================================
    integer errors = 0;

    task check_result;
        input signed [15:0] esperado;
        input [8*40-1:0]    nome;
        begin
            #1; // Aguarda propagação combinacional
            if (dout === esperado)
                $display("[PASS] %-40s | din=%h  dout=%h", nome, din, dout);
            else begin
                $display("[FAIL] %-40s | din=%h  dout=%h  esperado=%h",
                         nome, din, dout, esperado);
                errors = errors + 1;
            end
        end
    endtask

    // =========================================================
    // Estímulos
    // =========================================================
    initial begin
        $display("============================================================");
        $display("     TESTE DA TANH LUT COMBINACIONAL  (formato Q4.12)      ");
        $display("============================================================");

        // ---------------------------------------------------------
        // CASO 1: Valor pequeno positivo → região linear (dout = din)
        //   x = 0.125  (Q4.12: 0.125 × 4096 = 512 = 0x0200)
        //   Saída esperada: 0x0200
        // ---------------------------------------------------------
        din = 16'h0200;
        check_result(16'h0200, "Caso 1: linear  x=0.125 -> 0.125");

        // ---------------------------------------------------------
        // CASO 2: Saturação positiva  (x > 1.0)
        //   x = 1.3125  (Q4.12: 1.3125 × 4096 = 5376 = 0x1500)
        //   Saída esperada: 0x1000  (1.0 em Q4.12)
        // ---------------------------------------------------------
        din = 16'h1500;
        check_result(16'h1000, "Caso 2: sat+    x=1.3125 -> 1.0");

        // ---------------------------------------------------------
        // CASO 3: Valor negativo moderado → região linear (dout = din)
        //   x = -0.125  (Q4.12: -512 = 0xFE00)
        //   Saída esperada: 0xFE00
        // ---------------------------------------------------------
        din = 16'hFE00;
        check_result(16'hFE00, "Caso 3: linear  x=-0.125 -> -0.125");

        // ---------------------------------------------------------
        // CASO 4: Saturação negativa  (x < -1.0)
        //   x = -1.3125  (Q4.12: -5376 = 0xEB00)
        //   Saída esperada: 0xF000  (-1.0 em Q4.12)
        // ---------------------------------------------------------
        din = 16'hEB00;
        check_result(16'hF000, "Caso 4: sat-    x=-1.3125 -> -1.0");

        // ---------------------------------------------------------
        // CASO 5: Fronteira positiva exata  x = 1.0
        //   Q4.12: 1.0 = 0x1000 → condição: din > POS_SAT é FALSA
        //   (1.0 NÃO é estritamente maior que 1.0)
        //   Saída esperada: 0x1000  (identidade, não satura)
        // ---------------------------------------------------------
        din = 16'h1000;
        check_result(16'h1000, "Caso 5: borda+  x=1.0 -> 1.0 (linear)");

        // ---------------------------------------------------------
        // CASO 6: Fronteira negativa exata  x = -1.0
        //   Q4.12: -1.0 = 0xF000 → condição: din < NEG_SAT é FALSA
        //   (-1.0 NÃO é estritamente menor que -1.0)
        //   Saída esperada: 0xF000  (identidade, não satura)
        // ---------------------------------------------------------
        din = 16'hF000;
        check_result(16'hF000, "Caso 6: borda-  x=-1.0 -> -1.0 (linear)");

        // ---------------------------------------------------------
        // CASO 7: Comportamento combinacional — dout muda com din
        //   Verifica que a saída acompanha a entrada sem latência
        //   de clock, pois o módulo é puramente combinacional.
        //   Sequência: 0.5 → 1.5 (sat+) → -2.0 (sat-)
        // ---------------------------------------------------------
        din = 16'h0800;                         // 0.5 → linear
        #1;
        if (dout === 16'h0800)
            $display("[PASS] Caso 7a: combinacional x=0.5 -> 0.5 imediato");
        else begin
            $display("[FAIL] Caso 7a: combinacional x=0.5 | dout=%h esp=0800", dout);
            errors = errors + 1;
        end

        din = 16'h1800;                         // 1.5 → sat+
        #1;
        if (dout === 16'h1000)
            $display("[PASS] Caso 7b: combinacional x=1.5 -> 1.0 imediato");
        else begin
            $display("[FAIL] Caso 7b: combinacional x=1.5 | dout=%h esp=1000", dout);
            errors = errors + 1;
        end

        din = 16'hE000;                         // -2.0 → sat-
        #1;
        if (dout === 16'hF000)
            $display("[PASS] Caso 7c: combinacional x=-2.0 -> -1.0 imediato");
        else begin
            $display("[FAIL] Caso 7c: combinacional x=-2.0 | dout=%h esp=F000", dout);
            errors = errors + 1;
        end

        // ---------------------------------------------------------
        // Resultado final
        // ---------------------------------------------------------
        $display("============================================================");
        if (errors == 0)
            $display("  RESULTADO: TODOS OS TESTES PASSARAM");
        else
            $display("  RESULTADO: %0d ERRO(S) DETECTADO(S)", errors);
        $display("============================================================");
        $stop;
    end

endmodule
