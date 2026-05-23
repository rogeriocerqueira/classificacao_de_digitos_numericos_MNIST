/*
 * elm_mif.h — leitor de arquivos .mif (Altera Memory Initialization File).
 *
 * Os .mif fornecidos no projeto contêm os pesos, biases, beta e a imagem
 * em formato texto. No Marco 1 esses arquivos vão direto para o
 * altsyncram via INIT_FILE. No Marco 2 precisamos lê-los em runtime
 * a partir do HPS e enviar via instruções STORE_*.
 *
 * Formato suportado:
 *   - Comentários '--linha' e '%...%' (inclusive multi-linha)
 *   - Campos: DEPTH, WIDTH, ADDRESS_RADIX, DATA_RADIX (HEX/DEC/UNS/OCT/BIN)
 *   - CONTENT BEGIN ... END;
 *   - Atribuição simples: addr : value;
 *   - Atribuição por range: [lo..hi] : value;  e também: lo..hi : value;
 */

#ifndef ELM_MIF_H
#define ELM_MIF_H

#include <stdint.h>
#include <stddef.h>

/* Códigos de retorno específicos do parser. */
#define ELM_MIF_OK         0
#define ELM_MIF_E_OPEN    -10  /* não conseguiu abrir o arquivo            */
#define ELM_MIF_E_READ    -11  /* falha na leitura                         */
#define ELM_MIF_E_NOMEM   -12  /* malloc falhou                            */
#define ELM_MIF_E_FORMAT  -13  /* .mif mal formado (campos faltando, etc.) */
#define ELM_MIF_E_WIDTH   -14  /* largura inesperada para a função usada   */

/*
 * Parser genérico. Aloca *out_data (caller deve free()) com `*out_size`
 * entradas de 32 bits, e devolve a largura declarada no arquivo em
 * *out_width. Valores são preservados em complemento de dois — quem
 * chama interpreta como signed ou unsigned conforme o caso.
 */
int elm_mif_load_raw(const char *path,
                     uint32_t **out_data,
                     size_t   *out_size,
                     int      *out_width);

/* Wrappers tipados para os dois casos do projeto: */

/* Imagem: WIDTH deve ser 8, valores tratados como uint8_t. */
int elm_mif_load_image(const char *path, uint8_t **out_data, size_t *out_size);

/* Pesos/bias/beta: WIDTH deve ser 16, valores int16_t em Q4.12. */
int elm_mif_load_q4_12(const char *path, int16_t **out_data, size_t *out_size);

#endif /* ELM_MIF_H */
