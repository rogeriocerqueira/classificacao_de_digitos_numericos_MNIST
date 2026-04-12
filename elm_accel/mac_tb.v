`timescale 1ns/1ps

module mac_tb;

reg clk;
reg clr;
reg en;
reg signed [15:0] din_x;
reg signed [15:0] din_w;
wire signed [15:0] dout;

// DUT
mac uut (
    .clk(clk),
    .clr(clr),
    .en(en),
    .din_x(din_x),
    .din_w(din_w),
    .dout(dout)
);

// Clock
always #5 clk = ~clk;

// Controle
integer errors = 0;

// ===============================
// Função: converte Q4.12 → inteiro
// ===============================
function integer q412_to_int;
    input signed [15:0] val;
    begin
        q412_to_int = val >>> 12;
    end
endfunction

// ===============================
// TASK de verificação
// ===============================
task check_result;
    input signed [15:0] expected;
    input [255:0] name;
    begin
        if (dout === expected) begin
            $display("[PASS] %s | Resultado: %0d", name, q412_to_int(dout));
        end else begin
            $display("[FAIL] %s | Esperado: %0d | Obtido: %0d",
                name,
                q412_to_int(expected),
                q412_to_int(dout)
            );
            errors = errors + 1;
        end
    end
endtask

// ===============================
// TESTES
// ===============================
initial begin
    $display("===== TESTE DO MAC Q4.12 =====");

    clk = 0;
    clr = 1;
    en  = 0;
    din_x = 0;
    din_w = 0;

    #10;
    clr = 0;

    // ====================================
    // 🧪 TESTE 1: 1.0 * 1.0 = 1.0
    // ====================================
    $display("\n[TESTE 1] Multiplicação simples");

    en = 1;

    din_x = 16'h1000; // 1.0 em Q4.12
    din_w = 16'h1000; // 1.0

    #10;

    check_result(16'h1000, "1.0 * 1.0");

    // ====================================
    // 🧪 TESTE 2: Acumulação
    // 1.0 + (2.0 * 1.0) = 3.0
    // ====================================
    $display("\n[TESTE 2] Acumulacao");

    din_x = 16'h2000; // 2.0
    din_w = 16'h1000; // 1.0

    #10;

    check_result(16'h3000, "1.0 + (2.0 * 1.0)");

    // ====================================
    // 🧪 TESTE 3: Reset
    // ====================================
    $display("\n[TESTE 3] Reset");

    clr = 1;
    #10;
    clr = 0;

    check_result(16'h0000, "Reset deve zerar");

    // ====================================
    // RESULTADO FINAL
    // ====================================
    #10;

    if (errors == 0) begin
        $display("\n===== TODOS OS TESTES PASSARAM ✅ =====");
    end else begin
        $display("\n===== ERROS DETECTADOS ❌: %0d =====", errors);
    end

    $stop;
end

endmodule