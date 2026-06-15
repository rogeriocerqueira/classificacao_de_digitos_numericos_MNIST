/*
 * app.h - tipos e constantes compartilhados do Marco 3.
 *
 * Inclua este header em todos os modulos da aplicacao.
 */
#ifndef APP_H
#define APP_H

#include <stdint.h>
#include <stddef.h>

/* Modos de operacao */
typedef enum {
    MODO_ARQUIVO    = 0,   /* inferencia a partir de arquivo .mif     */
    MODO_DESENHO    = 1,   /* inferencia a partir de desenho c/ mouse */
    MODO_BENCHMARK  = 2,   /* validacao de N imagens com metricas     */
} modo_t;

/* Configuracao da aplicacao */
typedef struct {
    modo_t      modo;
    const char *img_path;      /* --img    (modo arquivo)              */
    const char *mif_dir;       /* --dir    (modo benchmark)            */
    int         n_imagens;     /* --n      (imagens por digito)        */
    int         offset;        /* --offset (indice inicial por digito) */
    int         classe_esp;    /* --e      (classe esperada)           */
    const char *log_path;      /* --log    (modo benchmark)            */
} app_config_t;

/* Resultado de uma inferencia */
typedef struct {
    uint8_t  pred;             /* digito predito (0-9)      */
    int      correto;          /* 1 se pred == esperado     */
    double   latencia_ms;      /* tempo da inferencia       */
} resultado_t;

/* Constantes da imagem MNIST */
#define IMG_W        28
#define IMG_H        28
#define IMG_PIXELS   (IMG_W * IMG_H)   /* 784 */

/* Codigos de retorno */
#define APP_OK       0
#define APP_ERR     -1

#endif /* APP_H */
