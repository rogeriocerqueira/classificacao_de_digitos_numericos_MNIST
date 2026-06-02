/*
 * main.c — ponto de entrada do Marco 3.
 *
 * Uso:
 *   sudo ./app --modo arquivo  --img ./mif_files/imagem_7.mif [-e 7]
 *   sudo ./app --modo desenho
 *   sudo ./app --modo benchmark --dir ./mif_files --n 100 --log res.csv
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <getopt.h>
#include "app.h"
#include "vga.h"
#include "../Marco2-driver/elm.h"

/* ── Protótipos dos modos ──────────────────────────────── */
int modo_arquivo   (elm_t *, vga_t *, const app_config_t *);
int modo_desenho   (elm_t *, vga_t *, const app_config_t *);
int modo_benchmark (elm_t *, vga_t *, const app_config_t *);

/* ── Ajuda ─────────────────────────────────────────────── */
static void usage(const char *prog)
{
    fprintf(stderr,
        "Uso:\n"
        "  %s --modo arquivo  --img <path.mif> [-e <digito>]\n"
        "  %s --modo desenho\n"
        "  %s --modo benchmark --dir <dir> [--n <N>] [--log <log.csv>]\n"
        "\n"
        "Opções:\n"
        "  --modo  arquivo|desenho|benchmark\n"
        "  --img   caminho para arquivo .mif (modo arquivo)\n"
        "  --dir   diretório com imagem_0.mif .. imagem_9.mif\n"
        "  --n     número de inferências no benchmark (padrão: 100)\n"
        "  --e     classe esperada (modo arquivo)\n"
        "  --log   caminho do CSV de saída (padrão: benchmark.csv)\n",
        prog, prog, prog);
}

/* ── Parse de argumentos ───────────────────────────────── */
static int parse_args(int argc, char **argv, app_config_t *cfg)
{
    /* Defaults */
    cfg->modo       = MODO_ARQUIVO;
    cfg->img_path   = NULL;
    cfg->mif_dir    = ".";
    cfg->n_imagens  = 100;
    cfg->classe_esp = -1;
    cfg->log_path   = "benchmark.csv";

    static struct option opts[] = {
        {"modo",  required_argument, 0, 'm'},
        {"img",   required_argument, 0, 'i'},
        {"dir",   required_argument, 0, 'd'},
        {"n",     required_argument, 0, 'n'},
        {"e",     required_argument, 0, 'e'},
        {"log",   required_argument, 0, 'l'},
        {"help",  no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "m:i:d:n:e:l:h", opts, NULL)) != -1) {
        switch (opt) {
        case 'm':
            if      (strcmp(optarg, "arquivo")    == 0) cfg->modo = MODO_ARQUIVO;
            else if (strcmp(optarg, "desenho")    == 0) cfg->modo = MODO_DESENHO;
            else if (strcmp(optarg, "benchmark")  == 0) cfg->modo = MODO_BENCHMARK;
            else {
                fprintf(stderr, "Modo inválido: %s\n", optarg);
                return APP_ERR;
            }
            break;
        case 'i': cfg->img_path   = optarg;         break;
        case 'd': cfg->mif_dir    = optarg;         break;
        case 'n': cfg->n_imagens  = atoi(optarg);   break;
        case 'e': cfg->classe_esp = atoi(optarg);   break;
        case 'l': cfg->log_path   = optarg;         break;
        case 'h': usage(argv[0]); return APP_ERR;
        default:  usage(argv[0]); return APP_ERR;
        }
    }

    /* Validações */
    if (cfg->modo == MODO_ARQUIVO && !cfg->img_path) {
        fprintf(stderr, "Erro: --img obrigatório no modo arquivo.\n");
        return APP_ERR;
    }
    if (cfg->n_imagens < 1) cfg->n_imagens = 1;

    return APP_OK;
}

/* ── main ──────────────────────────────────────────────── */
int main(int argc, char **argv)
{
    printf("╔══════════════════════════════════════════╗\n");
    printf("║  Marco 3 — Aplicação MNIST DE1-SoC      ║\n");
    printf("║  Driver ELM + VGA                       ║\n");
    printf("╚══════════════════════════════════════════╝\n\n");

    /* ── 1. Parse de argumentos ─────────────────────── */
    app_config_t cfg;
    if (parse_args(argc, argv, &cfg) != APP_OK) {
        usage(argv[0]);
        return 1;
    }

    /* ── 2. Inicializa driver Marco 2 (ELM) ─────────── */
    elm_t elm;
    printf("[ELM] Abrindo driver...\n");
    if (elm_open(&elm) != ELM_OK) {
        fprintf(stderr, "Erro: elm_open falhou. Execute como root.\n");
        return 2;
    }
    printf("[ELM] Driver aberto. status = 0x%08x\n\n", *elm.data_out);

    /* ── 3. Inicializa driver VGA ───────────────────── */
    vga_t vga;
    printf("[VGA] Abrindo driver...\n");
    if (vga_open(&vga) != APP_OK) {
        fprintf(stderr, "Erro: vga_open falhou.\n");
        elm_close(&elm);
        return 3;
    }
    vga_clear(&vga);
    printf("[VGA] Pronto.\n\n");

    /* ── 4. Executa o modo selecionado ──────────────── */
    int rc = APP_ERR;
    switch (cfg.modo) {
    case MODO_ARQUIVO:
        rc = modo_arquivo(&elm, &vga, &cfg);
        break;
    case MODO_DESENHO:
        rc = modo_desenho(&elm, &vga, &cfg);
        break;
    case MODO_BENCHMARK:
        rc = modo_benchmark(&elm, &vga, &cfg);
        break;
    }

    /* ── 5. Fecha recursos ──────────────────────────── */
    vga_clear(&vga);
    vga_close(&vga);
    elm_close(&elm);

    printf("[App] Encerrado %s.\n", rc == APP_OK ? "com sucesso" : "com erro");
    return (rc == APP_OK) ? 0 : 1;
}
