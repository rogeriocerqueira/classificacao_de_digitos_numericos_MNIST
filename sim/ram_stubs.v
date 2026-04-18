// ============================================================
//  ram_stubs.v — Stubs das RAMs para simulação (VERSÃO CORRIGIDA)
//
//  Mudança principal: Leituras transformadas em COMBINACIONAIS (assign q = mem[addr])
//  para eliminar o atraso de 1 ciclo que causava predict=0 na FSM atual.
// ============================================================

// ------------------------------------------------------------
//  ram_w_in — W_in: 100.352 palavras de 16 bits
// ------------------------------------------------------------
module ram_w_in (
    input  wire [16:0] address,
    input  wire        clock,
    input  wire [15:0] data,
    input  wire        wren,
    input  wire        rden,
    output wire [15:0] q
);
    reg [15:0] mem [0:100351];

    initial begin
        $readmemh("W_in_q.hex", mem, 0, 100351);
    end

    // Escrita síncrona
    always @(posedge clock) begin
        if (wren) mem[address] <= data;
    end

    // LEITURA COMBINACIONAL (Correção para FSM sem wait-state)
    assign q = mem[address];
endmodule

// ------------------------------------------------------------
//  ram_image — Imagem: 784 pixels em Q4.12
// ------------------------------------------------------------
module ram_image (
    input  wire [9:0]  address,
    input  wire        clock,
    input  wire [15:0] data,
    input  wire        wren,
    input  wire        rden,
    output wire [15:0] q
);
    reg [15:0] mem [0:783];

    initial begin
        $readmemh("png.hex", mem, 0, 783);
    end

    always @(posedge clock) begin
        if (wren) mem[address] <= data;
    end

    assign q = mem[address];
endmodule

// ------------------------------------------------------------
//  ram_bias — Bias: 128 palavras de 16 bits
// ------------------------------------------------------------
module ram_bias (
    input  wire [6:0]  address,
    input  wire        clock,
    input  wire [15:0] data,
    input  wire        wren,
    input  wire        rden,
    output wire [15:0] q
);
    reg [15:0] mem [0:127];

    initial begin
        $readmemh("b_q.hex", mem, 0, 127);
    end

    always @(posedge clock) begin
        if (wren) mem[address] <= data;
    end

    assign q = mem[address];
endmodule

// ------------------------------------------------------------
//  ram_beta — Beta: 1.280 palavras de 16 bits
// ------------------------------------------------------------
module ram_beta (
    input  wire [10:0] address,
    input  wire        clock,
    input  wire [15:0] data,
    input  wire        wren,
    input  wire        rden,
    output wire [15:0] q
);
    reg [15:0] mem [0:1279];

    initial begin
        $readmemh("beta_q.hex", mem, 0, 1279);
    end

    always @(posedge clock) begin
        if (wren) mem[address] <= data;
    end

    assign q = mem[address];
endmodule

// ------------------------------------------------------------
//  ram_h — Ativacoes ocultas: 128 palavras de 16 bits
// ------------------------------------------------------------
module ram_h (
    input  wire [6:0]  address,
    input  wire        clock,
    input  wire [15:0] data,
    input  wire        wren,
    output wire [15:0] q
);
    reg [15:0] mem [0:127];

    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1)
            mem[i] = 16'h0000;
    end

    always @(posedge clock) begin
        if (wren) mem[address] <= data;
    end

    assign q = mem[address];
endmodule
