module generic_ram #(
    parameter ADDR_WIDTH = 10,       // Tamanho do endereço
    parameter DATA_WIDTH = 16,       // Tamanho do dado (Q4.12)
    parameter DEPTH = 1024,          // Quantidade de palavras
    parameter FILE_NAME = "data.mif" // Nome do arquivo .mif
)(
    input wire clk,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] din, // Dado de entrada para o Marco 2
    input wire wren,                 // Habilita escrita para o Marco 2
    output reg [DATA_WIDTH-1:0] q    // Saída de dados
);

    // Declaração da memória
    // O atributo ramstyle força o Quartus a usar os blocos M10K
    (* ramstyle = "M10K" *) reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Inicialização da memória
    // Diferente do $readmemh, o atributo ram_init_file 
    // permite que o Quartus leia o .mif nativamente
    initial begin
        if (FILE_NAME != "") begin
            $readmemh(FILE_NAME, mem); 
            // DICA: Se o .mif der erro aqui, o ideal é usar o IP Catalog.
            // O $readmemh é chato com caminhos no Linux.
        end
    end

    always @(posedge clk) begin
        if (wren) begin
            mem[addr] <= din; // Escrita (Ativa no Marco 2)
        end
        q <= mem[addr];       // Leitura síncrona
    end

endmodule