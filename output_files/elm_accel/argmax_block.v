// =============================================================
//  ARGMAX BLOCK — Seleciona o índice do maior valor entre y[0..9]
//
//  Correção aplicada:
//    [BUG #4] Adicionada porta clr (ativo alto, síncrono).
//             Na versão original, max_val e digit só eram
//             zerados pelo reset global. Em inferências
//             consecutivas, max_val da inferência anterior
//             permanecia, impedindo a atualização correta de
//             digit. Agora a FSM assina clr=1 no ciclo IDLE→
//             HIDDEN_ADDR (início de cada inferência).
//
//  Porta clr: ativo alto, síncrono (posedge clk).
//             Tem a mesma prioridade que reset asíncrono.
// =============================================================

module argmax_block (
    input wire        clk,
    input wire        reset,    // reset assíncrono global
    input wire        clr,      // NOVO: limpa entre inferências (síncrono)
    input wire        en,       // habilita quando um novo y[i] está pronto
    input wire [15:0] din,      // valor y[i] vindo da camada de saída
    output reg [3:0]  digit     // dígito previsto (0-9)
);

    reg signed [15:0] max_val;
    reg        [3:0]  counter;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            max_val <= 16'h8000;  // menor valor possível (Q4.12 com sinal)
            digit   <= 4'd0;
            counter <= 4'd0;
        end
        else if (clr) begin       // [FIX #4] reset síncrono entre inferências
            max_val <= 16'h8000;
            digit   <= 4'd0;
            counter <= 4'd0;
        end
        else if (en) begin
            // Comparação sinalizada (essencial para valores negativos)
            if ($signed(din) > $signed(max_val)) begin
                max_val <= din;
                digit   <= counter;
            end

            // Contador de 0 a 9 (auto-reinicia)
            if (counter == 4'd9)
                counter <= 4'd0;
            else
                counter <= counter + 1'b1;
        end
    end

endmodule