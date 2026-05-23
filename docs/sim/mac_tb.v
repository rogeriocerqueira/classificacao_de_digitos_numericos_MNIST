`timescale 1ns/1ps

module mac_tb;

reg clk;
reg clr;
reg en;
reg load_bias;
reg signed [15:0] din_x;
reg signed [15:0] din_w;
reg signed [15:0] din_bias;
wire signed [15:0] dout;

// DUT
mac uut (
    .clk      (clk),
    .clr      (clr),
    .en       (en),
    .load_bias(load_bias),
    .din_x    (din_x),
    .din_w    (din_w),
    .din_bias (din_bias),
    .dout     (dout)
);

always #5 clk = ~clk;

integer errors = 0;

function integer q412_to_int;
    input signed [15:0] val;
    begin
        q412_to_int = val >>> 12;
    end
endfunction

task check_result;
    input signed [15:0] expected;
    input [255:0] name;
    begin
        if (dout === expected)
            $display("[PASS] %s | Resultado: %0d (raw: %h)", name, q412_to_int(dout), dout);
        else begin
            $display("[FAIL] %s | Esperado: %h | Obtido: %h", name, expected, dout);
            errors = errors + 1;
        end
    end
endtask

initial begin
    $display("===== TESTE DO MAC Q4.12 =====");

    clk       = 0;
    clr       = 1;
    en        = 0;
    load_bias = 0;
    din_x     = 0;
    din_w     = 0;
    din_bias  = 0;

    #10;
    clr = 0;

    // ====================================
    // TESTE 1: 1.0 * 1.0 = 1.0
    // Q4.12: 1.0 = 16'h1000
    // ====================================
    $display("\n[TESTE 1] 1.0 * 1.0 = 1.0");
    en    = 1;
    din_x = 16'h1000;
    din_w = 16'h1000;
    #10;
    en = 0;
    check_result(16'h1000, "1.0 * 1.0");

    // ====================================
    // TESTE 2: Acumulacao 1.0 + (2.0 * 1.0) = 3.0
    // ====================================
    $display("\n[TESTE 2] Acumulacao: 1.0 + (2.0 * 1.0) = 3.0");
    en    = 1;
    din_x = 16'h2000; // 2.0
    din_w = 16'h1000; // 1.0
    #10;
    en = 0;
    check_result(16'h3000, "1.0 + (2.0 * 1.0)");

    // ====================================
    // TESTE 3: Reset zera acumulador
    // ====================================
    $display("\n[TESTE 3] Reset");
    clr = 1;
    #10;
    clr = 0;
    check_result(16'h0000, "Reset deve zerar");

    // ====================================
    // TESTE 4: load_bias injeta bias no acumulador
    // Acumula 1.0*1.0=1.0, injeta bias=0.5 -> espera 1.5
    // Q4.12: 0.5=16'h0800, 1.5=16'h1800
    // ====================================
    $display("\n[TESTE 4] load_bias: 1.0*1.0 + bias(0.5) = 1.5");
    clr      = 1; #10; clr = 0;
    en       = 1;
    din_x    = 16'h1000; // 1.0
    din_w    = 16'h1000; // 1.0
    din_bias = 16'h0800; // 0.5
    #10;
    en        = 0;
    load_bias = 1;
    #10;
    load_bias = 0;
    check_result(16'h1800, "1.0*1.0 + bias(0.5) = 1.5");

    // ====================================
    // TESTE 5: Multiplo negativo
    // (-1.0) * 2.0 = -2.0
    // Q4.12: -1.0=16'hF000, 2.0=16'h2000, -2.0=16'hE000
    // ====================================
    $display("\n[TESTE 5] Negativo: (-1.0) * 2.0 = -2.0");
    clr   = 1; #10; clr = 0;
    en    = 1;
    din_x = 16'hF000; // -1.0
    din_w = 16'h2000; // 2.0
    #10;
    en = 0;
    check_result(16'hE000, "(-1.0) * 2.0 = -2.0");

    // ====================================
    // RESULTADO FINAL
    // ====================================
    #10;
    if (errors == 0)
        $display("\n===== TODOS OS TESTES PASSARAM =====");
    else
        $display("\n===== ERROS: %0d =====", errors);

    $stop;
end

endmodule
