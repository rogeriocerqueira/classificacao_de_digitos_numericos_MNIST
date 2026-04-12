module fsm (
    input wire clk,
    input wire reset,
    input wire start,           // Sinal para iniciar a inferência
    
    // Controles para o Datapath (elm_accel)
    output reg clr_acc,
    output reg en_mac,
    output reg en_tanh,
    output reg en_argmax,
    
    // Endereçamento das Memórias
    output reg [16:0] addr_w,   // Endereço para W_in (128 * 784)
    output reg [9:0]  addr_x,   // Endereço para Imagem (784)
    output reg [6:0]  addr_b,   // Endereço para Bias (128)
    
    // Status
    output reg done
);

    // Definição de Estados
    localparam IDLE         = 3'd0;
    localparam FETCH_HIDDEN = 3'd1; // Processa Camada Oculta
    localparam ADD_BIAS     = 3'd2;
    localparam ACTIVATE     = 3'd3;
    localparam FINISH       = 3'd4;

    reg [2:0] state;
    reg [9:0] count_x; // Conta até 784 pixels
    reg [6:0] count_h; // Conta até 128 neurônios ocultos

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            {addr_w, addr_x, addr_b} <= 0;
            {clr_acc, en_mac, en_tanh, en_argmax, done} <= 0;
            {count_x, count_h} <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    if (start) begin
                        state <= FETCH_HIDDEN;
                        clr_acc <= 1; // Limpa para o primeiro neurônio
                        count_x <= 0;
                        count_h <= 0;
                    end
                end

                FETCH_HIDDEN: begin
                    clr_acc <= 0;
                    en_mac <= 1;
                    addr_w <= (count_h * 784) + count_x;
                    addr_x <= count_x;
                    
                    if (count_x == 783) begin
                        state <= ADD_BIAS;
                        en_mac <= 0;
                    end else begin
                        count_x <= count_x + 1;
                    end
                end

                ADD_BIAS: begin
                    addr_b <= count_h;
                    // Lógica para injetar o bias no MAC (pode ser via data_weight)
                    state <= ACTIVATE;
                end

                ACTIVATE: begin
                    en_tanh <= 1;
                    if (count_h == 127) begin
                        state <= FINISH;
                    end else begin
                        count_h <= count_h + 1;
                        count_x <= 0;
                        clr_acc <= 1; // Limpa para o próximo neurônio
                        state <= FETCH_HIDDEN;
                    end
                end

                FINISH: begin
                    en_tanh <= 0;
                    done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule