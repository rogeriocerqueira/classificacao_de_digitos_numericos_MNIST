// ============================================================
//  FSM — Controlador do co-processador ELM
//
//  Correções aplicadas:
//    [BUG #1] HIDDEN_MAC: elemento x[783] agora é acumulado
//             (en_mac=1 permanece no último ciclo antes de
//              transicionar para ADD_BIAS_ADDR)
//    [BUG #3] OUTPUT_MAC: elemento h[127] agora é acumulado
//             (mesmo padrão do BUG #1)
//    [BUG #4] Adicionado sinal clr_argmax: é assinalado no
//             início de cada inferência (IDLE→HIDDEN_ADDR),
//             resetando max_val e digit no argmax_block.
// ============================================================

module fsm (
    input wire clk,
    input wire reset,
    input wire start,

    output reg clr_acc,
    output reg en_mac,
    output reg load_bias,
    output reg en_tanh,
    output reg en_argmax,
    output reg sel_beta,
    output reg clr_argmax,      // NOVO: reseta argmax entre inferências

    output reg [16:0] addr_w,
    output reg [9:0]  addr_x,
    output reg [6:0]  addr_b,
    output reg [10:0] addr_beta,

    output reg done
);

    localparam IDLE            = 4'd0;
    localparam HIDDEN_ADDR     = 4'd1;
    localparam HIDDEN_MAC      = 4'd2;
    localparam ADD_BIAS_ADDR   = 4'd3;
    localparam ADD_BIAS_EXEC   = 4'd4;
    localparam ACTIVATE        = 4'd5;
    localparam OUTPUT_ADDR     = 4'd6;
    localparam OUTPUT_MAC      = 4'd7;
    localparam DO_ARGMAX       = 4'd8;
    localparam FINISH          = 4'd9;

    reg [3:0]  state;
    reg [9:0]  count_x;
    reg [6:0]  count_h;
    reg [3:0]  count_y;
    reg [16:0] base_w;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state       <= IDLE;
            addr_w      <= 0;
            addr_x      <= 0;
            addr_b      <= 0;
            addr_beta   <= 0;
            base_w      <= 0;
            clr_acc     <= 0;
            en_mac      <= 0;
            load_bias   <= 0;
            en_tanh     <= 0;
            en_argmax   <= 0;
            sel_beta    <= 0;
            clr_argmax  <= 0;
            done        <= 0;
            count_x     <= 0;
            count_h     <= 0;
            count_y     <= 0;
        end else begin
            // Valores padrão: desativados a cada ciclo
            clr_acc    <= 0;
            en_mac     <= 0;
            load_bias  <= 0;
            en_tanh    <= 0;
            en_argmax  <= 0;
            clr_argmax <= 0;
            done       <= 0;

            case (state)

                // -------------------------------------------------
                IDLE: begin
                    sel_beta <= 0;
                    if (start) begin
                        count_x    <= 0;
                        count_h    <= 0;
                        count_y    <= 0;
                        clr_acc    <= 1;
                        clr_argmax <= 1;   // [FIX #4] reseta argmax
                        base_w     <= 17'd0;
                        addr_w     <= 17'd0;
                        addr_x     <= 10'd0;
                        state      <= HIDDEN_ADDR;
                    end
                end

                // -------------------------------------------------
                // Aguarda 1 ciclo para dado ficar disponível na RAM
                HIDDEN_ADDR: begin
                    sel_beta <= 0;
                    state    <= HIDDEN_MAC;
                end

                // -------------------------------------------------
                // [FIX #1] en_mac=1 permanece ativo quando count_x==783,
                // garantindo que W[783]*x[783] seja acumulado antes
                // de transicionar para ADD_BIAS_ADDR.
                HIDDEN_MAC: begin
                    sel_beta <= 0;
                    en_mac   <= 1;  // sempre acumula neste estado

                    if (count_x == 783) begin
                        // en_mac=1 (do padrão acima) → acumula W[783]*x[783]
                        count_x <= 0;
                        addr_b  <= count_h[6:0];
                        state   <= ADD_BIAS_ADDR;
                        // addr_w e addr_x não são incrementados (não serão usados)
                    end else begin
                        count_x <= count_x + 1;
                        addr_w  <= addr_w + 1'b1;
                        addr_x  <= addr_x + 1'b1;
                        state   <= HIDDEN_MAC;
                    end
                end

                // -------------------------------------------------
                ADD_BIAS_ADDR: begin
                    addr_b <= count_h[6:0];
                    state  <= ADD_BIAS_EXEC;
                end

                // -------------------------------------------------
                ADD_BIAS_EXEC: begin
                    load_bias <= 1;
                    state     <= ACTIVATE;
                end

                // -------------------------------------------------
                // Aplica tanh (combinacional no tanh_lut) e grava em
                // ram_h. O sinal en_tanh permanece registrado e
                // ativo no próximo ciclo (HIDDEN_ADDR / OUTPUT_ADDR),
                // quando tanh_out já reflete o acumulador com bias.
                ACTIVATE: begin
                    en_tanh <= 1;

                    if (count_h == 127) begin
                        count_h   <= 0;
                        count_y   <= 0;
                        clr_acc   <= 1;
                        sel_beta  <= 1;
                        addr_beta <= 11'd0;
                        addr_b    <= 7'd0;
                        state     <= OUTPUT_ADDR;
                    end else begin
                        count_h <= count_h + 1;
                        clr_acc <= 1;
                        base_w  <= base_w + 17'd784;
                        addr_w  <= base_w + 17'd784;
                        addr_x  <= 10'd0;
                        state   <= HIDDEN_ADDR;
                    end
                end

                // -------------------------------------------------
                OUTPUT_ADDR: begin
                    sel_beta <= 1;
                    state    <= OUTPUT_MAC;
                end

                // -------------------------------------------------
                // [FIX #3] en_mac=1 permanece ativo quando count_h==127,
                // garantindo que β[127]*h[127] seja acumulado antes
                // de transicionar para DO_ARGMAX.
                OUTPUT_MAC: begin
                    sel_beta <= 1;
                    en_mac   <= 1;  // sempre acumula neste estado

                    if (count_h == 127) begin
                        // en_mac=1 (do padrão acima) → acumula β[127]*h[127]
                        count_h <= 0;
                        state   <= DO_ARGMAX;
                    end else begin
                        count_h   <= count_h + 1;
                        addr_beta <= addr_beta + 1'b1;
                        addr_b    <= addr_b    + 1'b1;
                        state     <= OUTPUT_MAC;
                    end
                end

                // -------------------------------------------------
                DO_ARGMAX: begin
                    sel_beta  <= 1;
                    en_argmax <= 1;
                    clr_acc   <= 1;

                    if (count_y == 9) begin
                        state <= FINISH;
                    end else begin
                        count_y   <= count_y + 1;
                        count_h   <= 0;
                        addr_beta <= addr_beta + 11'd128;
                        addr_b    <= 7'd0;
                        state     <= OUTPUT_ADDR;
                    end
                end

                // -------------------------------------------------
                FINISH: begin
                    sel_beta  <= 0;
                    en_argmax <= 0;
                    done      <= 1;
                    state     <= IDLE;
                end

            endcase
        end
    end

endmodule