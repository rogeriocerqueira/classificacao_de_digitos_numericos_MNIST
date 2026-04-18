// =============================================================
//  TANH LUT — Aproximação por regiões (formato Q4.12)
//
//  Correção aplicada:
//    [BUG #2] Módulo convertido para lógica COMBINACIONAL.
//             Na versão original (registrada), tanh_out só
//             ficava disponível 1 ciclo após en=1, fazendo
//             ram_h gravar o valor do neurônio ANTERIOR.
//             Com saída wire (combinacional), tanh_out reflete
//             din imediatamente, e o wren de ram_h (en_tanh,
//             registrado na FSM) chega 1 ciclo depois de
//             ACTIVATE — exatamente quando o acumulador já
//             contém W·x+b. O timing fica correto sem nenhuma
//             alteração na FSM.
//
//  Regiões:
//    din >  1.0  →  dout =  1.0  (saturação positiva)
//    din < -1.0  →  dout = -1.0  (saturação negativa)
//    resto       →  dout =  din  (identidade — região linear)
//
//  Constantes Q4.12:
//     1.0 = 16'h1000  ( 4096)
//    -1.0 = 16'hF000  (-4096 em complemento de 2)
//
//  Portas removidas: clk, en  (não são necessárias)
// =============================================================

module tanh_lut (
    input  wire signed [15:0] din,
    output wire signed [15:0] dout   // wire combinacional — sem latência
);

    localparam signed [15:0] POS_SAT =  16'h1000;  //  1.0 em Q4.12
    localparam signed [15:0] NEG_SAT =  16'hF000;  // -1.0 em Q4.12

    assign dout = ($signed(din) > $signed(POS_SAT)) ? POS_SAT :
                  ($signed(din) < $signed(NEG_SAT)) ? NEG_SAT :
                                                      din;

endmodule