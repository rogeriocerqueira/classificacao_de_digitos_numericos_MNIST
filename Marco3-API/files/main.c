/*
 * main.c — ponto de entrada do Marco 3.
 *
 * Uso com argumentos:
 *   sudo ./app --modo arquivo  --img ./image_files/imagem_7.mif [-e 7]
 *   sudo ./app --modo desenho
 *   sudo ./app --modo benchmark --dir ./image_files --n 100 --log res.csv
 *
 * Uso interativo (sem argumentos):
 *   sudo ./app
 *   → abre menu para escolher modo e dígito
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

/* ── Diretório padrão das imagens ──────────────────────── */
#define DEFAULT_IMG_DIR  "../../Marco2-driver/image_files"

/* ── Ajuda ─────────────────────────────────────────────── */
static void usage(const char *prog)
{
    fprintf(stderr,
        "Uso:\n"
        "  %s                            → menu interativo\n"
        "  %s --modo arquivo --img <path.mif> [-e <digito>]\n"
        "  %s --modo desenho\n"
        "  %s --modo benchmark --dir <dir> [--n <N>] [--log <log.csv>]\n"
        "\n"
        "Opções:\n"
        "  --modo  arquivo|desenho|benchmark\n"
        "  --img   caminho para arquivo .mif\n"
        "  --dir   diretório com imagem_0.mif .. imagem_9.mif\n"
        "  --n     número de inferências no benchmark (padrão: 100)\n"
        "  --e     classe esperada (modo arquivo)\n"
        "  --log   caminho do CSV de saída (padrão: benchmark.csv)\n",
        prog, prog, prog, prog);
}

/* ── Menu interativo ───────────────────────────────────── */
static int menu_modo(void)
{
    int escolha = -1;
    while (escolha < 1 || escolha > 3) {
        printf("╔══════════════════════════════════════════╗\n");
        printf("║  Selecione o modo de operação:           ║\n");
        printf("╠══════════════════════════════════════════╣\n");
        printf("║  1. Arquivo   (exibe imagem do dígito)  ║\n");
        printf("║  2. Desenho   (desenha com mouse)       ║\n");
        printf("║  3. Benchmark (testa N imagens)         ║\n");
        printf("╚══════════════════════════════════════════╝\n");
        printf("Escolha [1-3]: ");
        fflush(stdout);
        if (scanf("%d", &escolha) != 1) {
            /* limpa buffer em caso de entrada inválida */
            int c;
            while ((c = getchar()) != '\n' && c != EOF);
            escolha = -1;
        }
        if (escolha < 1 || escolha > 3)
            printf("Opção inválida. Tente novamente.\n\n");
    }
    return escolha;
}

static int menu_digito(void)
{
    int digito = -1;
    while (digito < 0 || digito > 9) {
        printf("\nSelecione o dígito [0-9]: ");
        fflush(stdout);
        if (scanf("%d", &digito) != 1) {
            int c;
            while ((c = getchar()) != '\n' && c != EOF);
            digito = -1;
        }
        if (digito < 0 || digito > 9)
            printf("Dígito inválido. Tente novamente.\n");
    }
    return digito;
}

static int menu_benchmark_n(void)
{
    int n = -1;
    while (n < 1) {
        printf("\nNúmero de imagens para benchmark [1-100]: ");
        fflush(stdout);
        if (scanf("%d", &n) != 1) {
            int c;
            while ((c = getchar()) != '\n' && c != EOF);
            n = -1;
        }
        if (n < 1)
            printf("Número inválido. Tente novamente.\n");
        if (n > 100) n = 100;
    }
    return n;
}

/* ── Modo interativo ───────────────────────────────────── */
static int modo_interativo(app_config_t *cfg)
{
    static char img_path_buf[256];

    int escolha = menu_modo();

    switch (escolha) {
    case 1:
        cfg->modo = MODO_ARQUIVO;
        {
            int digito = menu_digito();
            cfg->classe_esp = digito;
            snprintf(img_path_buf, sizeof(img_path_buf),
                     "%s/imagem_%d.mif", DEFAULT_IMG_DIR, digito);
            cfg->img_path = img_path_buf;
            printf("\nCarregando: %s\n", cfg->img_path);
        }
        break;

    case 2:
        cfg->modo = MODO_DESENHO;
        break;

    case 3:
        cfg->modo = MODO_BENCHMARK;
        cfg->mif_dir   = DEFAULT_IMG_DIR;
        cfg->n_imagens = menu_benchmark_n();
        break;
    }

    return APP_OK;
}

/* ── Parse de argumentos ───────────────────────────────── */
static int parse_args(int argc, char **argv, app_config_t *cfg)
{
    /* Defaults */
    cfg->modo       = MODO_ARQUIVO;
    cfg->img_path   = NULL;
    cfg->mif_dir    = DEFAULT_IMG_DIR;
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
            if      (strcmp(optarg, "arquivo")   == 0) cfg->modo = MODO_ARQUIVO;
            else if (strcmp(optarg, "desenho")   == 0) cfg->modo = MODO_DESENHO;
            else if (strcmp(optarg, "benchmark") == 0) cfg->modo = MODO_BENCHMARK;
            else {
                fprintf(stderr, "Modo inválido: %s\n", optarg);
                return APP_ERR;
            }
            break;
        case 'i': cfg->img_path   = optarg;       break;
        case 'd': cfg->mif_dir    = optarg;       break;
        case 'n': cfg->n_imagens  = atoi(optarg); break;
        case 'e': cfg->classe_esp = atoi(optarg); break;
        case 'l': cfg->log_path   = optarg;       break;
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

    app_config_t cfg;

    /* ── 1. Sem argumentos → menu interativo ─────────── */
    if (argc == 1) {
        /* defaults antes do menu */
        cfg.modo       = MODO_ARQUIVO;
        cfg.img_path   = NULL;
        cfg.mif_dir    = DEFAULT_IMG_DIR;
        cfg.n_imagens  = 100;
        cfg.classe_esp = -1;
        cfg.log_path   = "benchmark.csv";

        if (modo_interativo(&cfg) != APP_OK) return 1;
    }
    /* ── Com argumentos → parse normal ──────────────── */
    else {
        if (parse_args(argc, argv, &cfg) != APP_OK) {
            usage(argv[0]);
            return 1;
        }
    }

    /* ── 2. Inicializa driver Marco 2 (ELM) ─────────── */
    elm_t elm;
    printf("\n[ELM] Abrindo driver...\n");
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
    printf("[VGA] aberto. addr=0x%08X color=0x%08X ctrl=0x%08X\n",
           VGA_BRIDGE_BASE + VGA_ADDR_OFF,
           VGA_BRIDGE_BASE + VGA_COLOR_OFF,
           VGA_BRIDGE_BASE + VGA_CTRL_OFF);
    printf("[VGA] Pronto.\n\n");

    /* ── 4. Loop principal ──────────────────────────── */
    int rc = APP_OK;
    int continuar = 1;

    while (continuar) {
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

        /* ── Pergunta se quer continuar (modo interativo) ── */
        if (argc == 1) {
            printf("\n┌─────────────────────────────────────┐\n");
            printf("│  Deseja fazer outra inferência?     │\n");
            printf("│  1. Sim — voltar ao menu            │\n");
            printf("│  2. Não — encerrar                  │\n");
            printf("└─────────────────────────────────────┘\n");
            printf("Escolha [1-2]: ");
            fflush(stdout);

            int op = -1;
            if (scanf("%d", &op) == 1 && op == 1) {
                /* Reseta config e volta ao menu */
                cfg.img_path   = NULL;
                cfg.classe_esp = -1;
                vga_clear(&vga);
                printf("\n");
                modo_interativo(&cfg);
            } else {
                continuar = 0;
            }
        } else {
            continuar = 0;
        }
    }

    /* ── 5. Fecha recursos ──────────────────────────── */
    vga_clear(&vga);
    vga_close(&vga);
    elm_close(&elm);
    printf("\n[App] Encerrado %s.\n",
           rc == APP_OK ? "com sucesso" : "com erro");
    return (rc == APP_OK) ? 0 : 1;
}
