module datapath (
    input wire clk,
    input wire reset,
    // Sinais de dados vindos das memórias/HPS
    input wire [15:0] data_in,      // Pixel ou Peso no formato Q4.12 
    // Sinais de controle vindos da FSM 
    input wire clr_acc,             // Limpa o acumulador do MAC
    input wire en_mac,              // Habilita o cálculo do MAC
    input wire en_tanh,             // Habilita a passagem pela ativação
    input wire en_argmax,           // Habilita a comparação final
    // Saídas para a FSM ou Top-Level
    output wire [3:0] predicted_digit // Resultado 0-9 
);

    // Fios internos para interconexão (Netlist)
    wire [15:0] mac_to_tanh;
    wire [15:0] tanh_to_argmax;

    // 1. Instância do MAC (Criado pelo Jones) 
    // Realiza: acumulador = acumulador + (data_pixel * data_peso)
    mac u_mac (
        .clk(clk),
        .clr(clr_acc),
        .en(en_mac),
        .din(data_in),
        .dout(mac_to_tanh) // Saída Q4.12 
    );

    // 2. Instância da Função de Ativação (Criado pelo Rick)
    // Implementa a Tanh via LUT ou Aproximação Linear
    tanh_lut u_tanh (
        .clk(clk),
        .en(en_tanh),
        .din(mac_to_tanh),
        .dout(tanh_to_argmax)
    );

    // 3. Instância do Argmax (Criado pelo Ricardo)
    // Identifica o maior valor entre os neurônios de saída
    argmax_block u_argmax (
        .clk(clk),
        .en(en_argmax),
        .din(tanh_to_argmax),
        .digit(predicted_digit) // 4-bit (0 a 9)
    );

endmodule