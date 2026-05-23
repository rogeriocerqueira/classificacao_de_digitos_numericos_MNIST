`timescale 1ns / 1ps

// ============================================================
//  Testbench: display_7seg_tb
//  Verifica todos os estados e decodificação de dígitos
// ============================================================
module display_7seg_tb;

    parameter CLK_PERIOD = 10;

    reg        clk, reset, start, done;
    reg  [3:0] predicted_digit;
    wire [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;

    integer error_count;

    display_7seg dut (
        .clk             (clk),
        .reset           (reset),
        .start           (start),
        .done            (done),
        .predicted_digit (predicted_digit),
        .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2),
        .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // Constantes de segmentos (espelho do módulo)
    localparam SEG_0   = 7'b1000000;
    localparam SEG_1   = 7'b1111001;
    localparam SEG_2   = 7'b0100100;
    localparam SEG_3   = 7'b0110000;
    localparam SEG_4   = 7'b0011001;
    localparam SEG_5   = 7'b0010010;
    localparam SEG_6   = 7'b0000010;
    localparam SEG_7   = 7'b1111000;
    localparam SEG_8   = 7'b0000000;
    localparam SEG_9   = 7'b0010000;
    localparam SEG_d   = 7'b0100001;
    localparam SEG_i   = 7'b1111011;
    localparam SEG_t   = 7'b0000111;
    localparam SEG_n   = 7'b0101011;
    localparam SEG_b   = 7'b0000011;
    localparam SEG_U   = 7'b1000001;
    localparam SEG_OFF = 7'b1111111;

    task check;
        input [6:0]       actual, expected;
        input [200*8-1:0] msg;
        begin
            if (actual !== expected) begin
                $display("FALHA  [%0t ns] %s | esperado=7'b%07b obtido=7'b%07b",
                         $time/1000, msg, expected, actual);
                error_count = error_count + 1;
            end else
                $display("OK     [%0t ns] %s", $time/1000, msg);
        end
    endtask

    task pulse_start;
        begin
            @(posedge clk); #1; start = 1;
            @(posedge clk); #1; start = 0;
        end
    endtask

    task pulse_done;
        input [3:0] digit;
        begin
            predicted_digit = digit;
            @(posedge clk); #1; done = 1;
            @(posedge clk); #1; done = 0;
        end
    endtask

    initial begin
        $dumpfile("display_7seg_tb.vcd");
        $dumpvars(0, display_7seg_tb);
        error_count = 0;
        start = 0; done = 0; predicted_digit = 0;

        // ======================================================
        // TESTE 1: Reset -> estado IDLE
        // ======================================================
        $display("\n===== TESTE 1: Reset (estado IDLE) =====");
        reset = 1; repeat(3) @(posedge clk); reset = 0;
        @(negedge clk);
        check(HEX5, SEG_i,   "IDLE: HEX5 = 'i'");
        check(HEX4, SEG_d,   "IDLE: HEX4 = 'd'");
        check(HEX3, SEG_OFF, "IDLE: HEX3 apagado");
        check(HEX2, SEG_OFF, "IDLE: HEX2 apagado");
        check(HEX1, SEG_OFF, "IDLE: HEX1 apagado");
        check(HEX0, SEG_OFF, "IDLE: HEX0 apagado");

        // ======================================================
        // TESTE 2: start -> estado BUSY
        // ======================================================
        $display("\n===== TESTE 2: Start (estado BUSY) =====");
        pulse_start;
        @(negedge clk);
        check(HEX5, SEG_b,   "BUSY: HEX5 = 'b'");
        check(HEX4, SEG_U,   "BUSY: HEX4 = 'U'");
        check(HEX3, SEG_OFF, "BUSY: HEX3 apagado");
        check(HEX2, SEG_OFF, "BUSY: HEX2 apagado");
        check(HEX1, SEG_OFF, "BUSY: HEX1 apagado");
        check(HEX0, SEG_OFF, "BUSY: HEX0 apagado");

        // ======================================================
        // TESTE 3: done -> estado DONE, dígito = 7
        // ======================================================
        $display("\n===== TESTE 3: Done (estado DONE, digito=7) =====");
        pulse_done(4'd7);
        @(negedge clk);
        check(HEX5, SEG_d,   "DONE: HEX5 = 'd'");
        check(HEX4, SEG_n,   "DONE: HEX4 = 'n'");
        check(HEX3, SEG_d,   "DONE: HEX3 = 'd'");
        check(HEX2, SEG_i,   "DONE: HEX2 = 'i'");
        check(HEX1, SEG_t,   "DONE: HEX1 = 't'");
        check(HEX0, SEG_7,   "DONE: HEX0 = '7'");

        // ======================================================
        // TESTE 4: Decodificação de todos os dígitos (0-9)
        // ======================================================
        $display("\n===== TESTE 4: Decodificacao de digitos 0-9 =====");
        begin : decode_loop
            integer d;
            reg [6:0] expected_seg;
            reg [3:0] d4;
            for (d = 0; d <= 9; d = d + 1) begin
                d4 = d[3:0];
                // Vai para BUSY e depois DONE com dígito d
                pulse_start;
                pulse_done(d4);
                @(negedge clk);
                case (d)
                    0: expected_seg = SEG_0;
                    1: expected_seg = SEG_1;
                    2: expected_seg = SEG_2;
                    3: expected_seg = SEG_3;
                    4: expected_seg = SEG_4;
                    5: expected_seg = SEG_5;
                    6: expected_seg = SEG_6;
                    7: expected_seg = SEG_7;
                    8: expected_seg = SEG_8;
                    9: expected_seg = SEG_9;
                    default: expected_seg = SEG_OFF;
                endcase
                check(HEX0, expected_seg, {"HEX0 digito correto"});
            end
        end

        // ======================================================
        // TESTE 5: Novo start em DONE retorna a BUSY
        // ======================================================
        $display("\n===== TESTE 5: DONE -> novo start -> BUSY =====");
        // Já estamos em DONE (saiu do loop acima no dígito 9)
        pulse_start;
        @(negedge clk);
        check(HEX5, SEG_b, "DONE->BUSY: HEX5 = 'b'");
        check(HEX4, SEG_U, "DONE->BUSY: HEX4 = 'U'");

        // ======================================================
        // TESTE 6: Reset em qualquer estado retorna a IDLE
        // ======================================================
        $display("\n===== TESTE 6: Reset durante BUSY =====");
        // Ainda em BUSY
        reset = 1; @(posedge clk); #1; reset = 0;
        @(negedge clk);
        check(HEX5, SEG_i,   "RESET->IDLE: HEX5 = 'i'");
        check(HEX4, SEG_d,   "RESET->IDLE: HEX4 = 'd'");
        check(HEX0, SEG_OFF, "RESET->IDLE: HEX0 apagado");

        // ======================================================
        // TESTE 7: digit_latch preserva valor entre inferências
        //          Após nova inferência, HEX0 deve exibir novo dígito
        // ======================================================
        $display("\n===== TESTE 7: digit_latch atualizado corretamente =====");
        pulse_start;
        pulse_done(4'd3);
        @(negedge clk);
        check(HEX0, SEG_3, "Latch: HEX0 = '3' apos primeira inferencia");

        pulse_start;
        pulse_done(4'd9);
        @(negedge clk);
        check(HEX0, SEG_9, "Latch: HEX0 = '9' apos segunda inferencia");

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

endmodule
