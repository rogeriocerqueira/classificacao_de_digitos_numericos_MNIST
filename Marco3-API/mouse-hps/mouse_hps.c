/*
 * mouse_hps.c
 *
 * Comunicação entre mouse USB e HPS (ARM Cortex-A9) via Linux evdev.
 * Exibe informações do dispositivo, posição relativa, estado dos botões
 * e scroll em tempo real. Toda saída é gravada também em mouse.info.
 *
 * Compilar na DE1-SoC:
 *   gcc -o mouse_hps mouse_hps.c -lm
 *
 * Cross-compilar no host:
 *   arm-linux-gnueabihf-gcc -o mouse_hps mouse_hps.c -lm
 *
 * Uso:
 *   sudo ./mouse_hps                         (auto-detecta o mouse)
 *   sudo ./mouse_hps -d /dev/input/event1    (device manual via flag -d)
 *   sudo ./mouse_hps -h                      (ajuda)
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>
#include <stdint.h>
#include <fcntl.h>
#include <unistd.h>
#include <math.h>
#include <errno.h>
#include <time.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <linux/input.h>

/* =========================================================================
 * CONSTANTES
 * ========================================================================= */

#define MAX_DEVICES         16
#define DEVICE_NAME_LEN     256
#define STOP_TIMEOUT_MS     150     /* ms sem evento → considera mouse parado  */
#define ACCEL_GAIN          0.008f  /* ganho da curva de aceleração SW         */
#define SENSITIVITY         1.0f    /* multiplicador linear base               */
#define LOG_FILE            "mouse.info"

/* =========================================================================
 * LOG DUPLO  (terminal + arquivo)
 *
 * Toda saída do programa passa por mlog(). Internamente ela chama vprintf
 * para o terminal e vfprintf para o arquivo — garantindo que terminal e
 * arquivo são sempre idênticos sem duplicar nenhuma string de formato.
 *
 * O FILE* g_log é aberto no main() e fechado ao encerrar.
 * ========================================================================= */

static FILE *g_log = NULL;  /* handle do arquivo mouse.info */

/*
 * mlog() — substitui printf() em todo o programa.
 * Escreve no stdout E no g_log simultaneamente.
 */
static void mlog(const char *fmt, ...) {
    va_list args;

    /* Escreve no terminal */
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);

    /* Escreve no arquivo (se aberto com sucesso) */
    if (g_log) {
        va_start(args, fmt);
        vfprintf(g_log, fmt, args);
        va_end(args);
        fflush(g_log);  /* garante escrita imediata, mesmo sem Ctrl+C limpo */
    }
}

/*
 * log_open() — abre o arquivo de log e registra data/hora de início.
 * Retorna 0 em sucesso, -1 em falha (programa continua sem gravar).
 */
static int log_open(void) {
    g_log = fopen(LOG_FILE, "w");
    if (!g_log) {
        fprintf(stderr, "Aviso: não foi possível criar %s: %s\n"
                        "O programa continuará sem gravar o log.\n",
                LOG_FILE, strerror(errno));
        return -1;
    }

    /* Cabeçalho com timestamp de início */
    time_t now = time(NULL);
    char ts[64];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&now));
    fprintf(g_log, "# mouse.info — gerado por mouse_hps\n");
    fprintf(g_log, "# Início da sessão: %s\n", ts);
    fprintf(g_log, "# ================================================\n\n");
    fflush(g_log);
    return 0;
}

/*
 * log_close() — registra timestamp de encerramento e fecha o arquivo.
 */
static void log_close(void) {
    if (!g_log) return;

    time_t now = time(NULL);
    char ts[64];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", localtime(&now));
    fprintf(g_log, "\n# ================================================\n");
    fprintf(g_log, "# Fim da sessão: %s\n", ts);
    fclose(g_log);
    g_log = NULL;
}

/* =========================================================================
 * ESTRUTURAS
 * ========================================================================= */

/*
 * MouseInfo — características estáticas do dispositivo.
 * Preenchida uma vez na abertura do fd, via ioctl.
 */
typedef struct {
    char     name[DEVICE_NAME_LEN]; /* nome reportado pelo driver              */
    uint16_t vendor_id;             /* USB Vendor ID  (ex: 0x046D = Logitech)  */
    uint16_t product_id;            /* USB Product ID                          */
    uint16_t version;               /* versão do protocolo HID                 */
    char     vendor_str[64];        /* nome do fabricante (tabela interna)     */

    /* Capacidades detectadas via EVIOCGBIT */
    int      has_rel_x;             /* suporta movimento horizontal            */
    int      has_rel_y;             /* suporta movimento vertical              */
    int      has_wheel;             /* possui scroll vertical                  */
    int      has_hwheel;            /* possui scroll horizontal                */
    int      has_btn_left;
    int      has_btn_right;
    int      has_btn_middle;
    int      num_buttons;

    /* Estimativas dinâmicas (atualizadas durante o loop) */
    float    polling_hz;            /* polling rate estimado (média exp.)      */
    int      hw_accel_suspected;    /* 1 se detectada aceleração de hardware   */
} MouseInfo;

/*
 * MouseState — estado dinâmico atualizado a cada evento.
 * Contém posição acumulada, botões, scroll e dados para diagnóstico.
 */
typedef struct {
    /* Posição relativa acumulada desde o início da execução (sem limite) */
    float    x;
    float    y;

    /* Velocidade instantânea calculada no último EV_SYN (mickeys/segundo) */
    float    speed;

    /* Controle de traços (sequências contínuas de movimento) */
    int      is_moving;
    int      trace_id;

    /* Estado atual dos botões: 1 = pressionado, 0 = solto */
    int      btn_left;
    int      btn_right;
    int      btn_middle;

    /* Scroll acumulado desde o início (unidades de step do scroll) */
    int      scroll_v;   /* positivo = rolar para cima    */
    int      scroll_h;   /* positivo = rolar para direita */

    /* Timestamp do último EV_SYN (usado para calcular dt entre frames).
     * Usamos clock_gettime(CLOCK_MONOTONIC) em vez de ev->time para evitar
     * incompatibilidade do campo time da struct input_event entre arquiteturas. */
    struct timespec last_event_time;

    /* Acumuladores de delta dentro do frame atual (entre dois EV_SYN) */
    int      dx_acc;
    int      dy_acc;

    /* Dados para detecção empírica de aceleração de hardware */
    double   total_distance_slow;   /* mickeys totais em frames lentos         */
    double   total_distance_fast;   /* mickeys totais em frames rápidos        */
    double   physical_slow;         /* tempo total de frames lentos (s)        */
    double   physical_fast;         /* tempo total de frames rápidos (s)       */
} MouseState;

/* =========================================================================
 * UTILITÁRIOS
 * ========================================================================= */

/* Converte vendor_id USB para nome do fabricante */
static const char *vendor_name(uint16_t vendor_id) {
    switch (vendor_id) {
        case 0x046D: return "Logitech";
        case 0x045E: return "Microsoft";
        case 0x093A: return "Pixart (genérico)";
        case 0x04F2: return "Chicony";
        case 0x1BCF: return "Sunplus (genérico)";
        case 0x0458: return "KYE / Genius";
        case 0x04B4: return "Cypress";
        case 0x413C: return "Dell";
        case 0x0461: return "Primax";
        case 0x04CA: return "Lite-On";
        case 0x1532: return "Razer";
        case 0x1B1C: return "Corsair";
        case 0x3554: return "SteelSeries";
        default:     return "Desconhecido";
    }
}

/* Retorna string "SIM" ou "NÃO" */
static const char *yes_no(int v) { return v ? "SIM" : "NÃO"; }

/* Retorna string "PRESSIONADO" ou "SOLTO" */
static const char *btn_state(int v) { return v ? "PRESSIONADO" : "SOLTO"; }

/* =========================================================================
 * AUTO-DETECÇÃO
 * Percorre /dev/input/event0..N e retorna o primeiro device que reporta
 * EV_REL com REL_X e REL_Y — assinatura mínima de um mouse.
 * ========================================================================= */

static int find_mouse_device(char *path_out, size_t path_len) {
    char path[64];
    unsigned long evbit = 0;

    for (int i = 0; i < MAX_DEVICES; i++) {
        snprintf(path, sizeof(path), "/dev/input/event%d", i);
        int fd = open(path, O_RDONLY | O_NONBLOCK);
        if (fd < 0) continue;

        ioctl(fd, EVIOCGBIT(0, sizeof(evbit)), &evbit);
        if (evbit & (1 << EV_REL)) {
            unsigned long relbit = 0;
            ioctl(fd, EVIOCGBIT(EV_REL, sizeof(relbit)), &relbit);
            if ((relbit & (1 << REL_X)) && (relbit & (1 << REL_Y))) {
                close(fd);
                snprintf(path_out, path_len, "%s", path);
                return 0;
            }
        }
        close(fd);
    }
    return -1;
}

/* =========================================================================
 * LEITURA DE INFORMAÇÕES DO DISPOSITIVO (via ioctl)
 * ========================================================================= */

static void read_mouse_info(int fd, MouseInfo *info) {
    memset(info, 0, sizeof(*info));

    /* Nome legível do dispositivo */
    if (ioctl(fd, EVIOCGNAME(DEVICE_NAME_LEN), info->name) < 0)
        snprintf(info->name, DEVICE_NAME_LEN, "Desconhecido");

    /* IDs USB: vendor, product, version */
    struct input_id id;
    if (ioctl(fd, EVIOCGID, &id) == 0) {
        info->vendor_id  = id.vendor;
        info->product_id = id.product;
        info->version    = id.version;
        snprintf(info->vendor_str, sizeof(info->vendor_str), "%s",
                 vendor_name(id.vendor));
    }

    /* Capacidades de eventos relativos */
    unsigned long relbit = 0;
    ioctl(fd, EVIOCGBIT(EV_REL, sizeof(relbit)), &relbit);
    info->has_rel_x  = (relbit >> REL_X)      & 1;
    info->has_rel_y  = (relbit >> REL_Y)       & 1;
    info->has_wheel  = (relbit >> REL_WHEEL)   & 1;
    info->has_hwheel = (relbit >> REL_HWHEEL)  & 1;

    /* Capacidades de botões — bitmask de KEY_MAX bits */
    unsigned long keybit[KEY_MAX / (8 * sizeof(unsigned long)) + 1];
    memset(keybit, 0, sizeof(keybit));
    ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybit)), keybit);

    #define BTN_BIT(code) \
        ((keybit[(code) / (8*sizeof(unsigned long))] >> ((code) % (8*sizeof(unsigned long)))) & 1)

    info->has_btn_left   = BTN_BIT(BTN_LEFT);
    info->has_btn_right  = BTN_BIT(BTN_RIGHT);
    info->has_btn_middle = BTN_BIT(BTN_MIDDLE);
    info->num_buttons    = info->has_btn_left
                         + info->has_btn_right
                         + info->has_btn_middle;
    #undef BTN_BIT
}

/* =========================================================================
 * RELATÓRIO INICIAL DO DISPOSITIVO
 * ========================================================================= */

static void print_device_report(const char *path, const MouseInfo *info) {
    mlog("\n");
    mlog("╔══════════════════════════════════════════════════════════╗\n");
    mlog("║               INFORMAÇÕES DO DISPOSITIVO                ║\n");
    mlog("╠══════════════════════════════════════════════════════════╣\n");
    mlog("║  Device     : %-42s║\n", path);
    mlog("║  Nome       : %-42s║\n", info->name);
    mlog("║  Fabricante : %-32s(0x%04X) ║\n", info->vendor_str, info->vendor_id);
    mlog("║  Product ID : 0x%04X                                     ║\n", info->product_id);
    mlog("║  Versão HID : 0x%04X                                     ║\n", info->version);
    mlog("╠══════════════════════════════════════════════════════════╣\n");
    mlog("║  CAPACIDADES DETECTADAS                                  ║\n");
    mlog("║  Movimento X/Y       : %-33s║\n", yes_no(info->has_rel_x && info->has_rel_y));
    mlog("║  Scroll vertical     : %-33s║\n", yes_no(info->has_wheel));
    mlog("║  Scroll horizontal   : %-33s║\n", yes_no(info->has_hwheel));
    mlog("║  Botão esquerdo      : %-33s║\n", yes_no(info->has_btn_left));
    mlog("║  Botão direito       : %-33s║\n", yes_no(info->has_btn_right));
    mlog("║  Botão do meio       : %-33s║\n", yes_no(info->has_btn_middle));
    mlog("║  Total de botões     : %-33d║\n", info->num_buttons);
    mlog("╠══════════════════════════════════════════════════════════╣\n");
    mlog("║  NOTAS IMPORTANTES                                       ║\n");
    mlog("║  • DPI não é reportado pelo driver Linux (só firmware)   ║\n");
    mlog("║  • Polling rate será estimado durante o uso              ║\n");
    mlog("║  • Aceleração HW será detectada empiricamente            ║\n");
    mlog("║  • Posição X/Y é relativa (acumulada desde o início)     ║\n");
    mlog("╚══════════════════════════════════════════════════════════╝\n\n");
}

/* =========================================================================
 * CÁLCULO DO FATOR DE ACELERAÇÃO DE SOFTWARE
 *
 * Curva linear: factor = 1.0 + ACCEL_GAIN × speed
 *
 * Exemplos com ACCEL_GAIN = 0.008:
 *   speed =    0 mky/s → factor = 1.00  (sem amplificação)
 *   speed =  250 mky/s → factor = 3.00
 *   speed =  500 mky/s → factor = 5.00
 *   speed = 1000 mky/s → factor = 9.00
 *
 * Se o mouse tiver aceleração HW, esta função deve ser desabilitada
 * (retornar 1.0f) para evitar dupla aceleração.
 * ========================================================================= */

static float accel_factor(float speed) {
    return 1.0f + ACCEL_GAIN * speed;
}

/* =========================================================================
 * IMPRESSÃO DO STATUS DOS BOTÕES
 * Chamada sempre que um botão muda de estado.
 * ========================================================================= */

static void print_button_status(const MouseState *s) {
    mlog("  ┌─────────────────────────────────────────┐\n");
    mlog("  │ STATUS DOS BOTÕES                        │\n");
    mlog("  │  Esquerdo : %-28s│\n", btn_state(s->btn_left));
    mlog("  │  Direito  : %-28s│\n", btn_state(s->btn_right));
    mlog("  │  Meio     : %-28s│\n", btn_state(s->btn_middle));
    mlog("  └─────────────────────────────────────────┘\n");
}

/* =========================================================================
 * IMPRESSÃO DO STATUS DO SCROLL
 * Chamada sempre que o scroll é acionado.
 * ========================================================================= */

static void print_scroll_status(const MouseState *s, int delta_v, int delta_h) {
    const char *dir_v = (delta_v > 0) ? "▲ CIMA"
                      : (delta_v < 0) ? "▼ BAIXO"
                      :                 "—";
    const char *dir_h = (delta_h > 0) ? "► DIREITA"
                      : (delta_h < 0) ? "◄ ESQUERDA"
                      :                 "—";

    mlog("  ┌─────────────────────────────────────────┐\n");
    mlog("  │ SCROLL                                   │\n");
    if (delta_v != 0)
        mlog("  │  Vertical  : %-5s  delta: %+2d  total: %4d │\n",
             dir_v, delta_v, s->scroll_v);
    if (delta_h != 0)
        mlog("  │  Horizontal: %-7s  delta: %+2d  total: %4d │\n",
             dir_h, delta_h, s->scroll_h);
    mlog("  └─────────────────────────────────────────┘\n");
}

/* =========================================================================
 * PROCESSAMENTO DO FIM DE FRAME (EV_SYN)
 * ========================================================================= */

static void process_syn(MouseState *s, MouseInfo *info,
                        const struct input_event *ev) {
    /*
     * dt: tempo entre este EV_SYN e o anterior.
     * No primeiro frame usamos 1/125s como fallback (125 Hz é o padrão USB).
     */
    float dt;
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    if (s->last_event_time.tv_sec == 0 && s->last_event_time.tv_nsec == 0) {
        dt = 1.0f / 125.0f;  /* fallback no primeiro frame */
    } else {
        dt = (now.tv_sec  - s->last_event_time.tv_sec)
           + (now.tv_nsec - s->last_event_time.tv_nsec) * 1e-9f;
        if (dt <= 0.0f || dt > 1.0f) dt = 1.0f / 125.0f;
    }
    s->last_event_time = now;
    (void)ev;  /* ev não é mais usado para timestamp */

    /* Polling rate: média exponencial para suavizar jitter */
    float instant_hz = 1.0f / dt;
    if (info->polling_hz == 0.0f)
        info->polling_hz = instant_hz;
    else
        info->polling_hz = 0.95f * info->polling_hz + 0.05f * instant_hz;

    /* Velocidade: magnitude do delta / dt (mickeys por segundo) */
    float dist = sqrtf((float)(s->dx_acc * s->dx_acc + s->dy_acc * s->dy_acc));
    s->speed = dist / dt;

    /*
     * Detecção empírica de aceleração HW:
     * Compara densidade de mickeys em faixas de velocidade diferentes.
     * Mouse linear → densidade constante. Aceleração HW → densidade cresce.
     */
    if (s->speed > 10.0f && s->speed < 300.0f) {
        s->total_distance_slow += dist;
        s->physical_slow       += dt;
    } else if (s->speed > 1000.0f) {
        s->total_distance_fast += dist;
        s->physical_fast       += dt;
    }
    if (s->physical_slow > 0.5f && s->physical_fast > 0.5f) {
        float avg_slow = (float)(s->total_distance_slow / s->physical_slow);
        float avg_fast = (float)(s->total_distance_fast / s->physical_fast);
        info->hw_accel_suspected = (avg_fast / avg_slow > 1.25f) ? 1 : 0;
    }

    /* Só processa se houve movimento neste frame */
    if (s->dx_acc == 0 && s->dy_acc == 0) return;

    /* Marca início de traço se o mouse estava parado */
    if (!s->is_moving) {
        s->trace_id++;
        mlog("\n┌─────────────────────────────────────────────────────────┐\n");
        mlog("│ TRAÇO #%-3d  início em  X: %+9.1f   Y: %+9.1f       │\n",
             s->trace_id, s->x, s->y);
        mlog("└─────────────────────────────────────────────────────────┘\n");
        s->is_moving = 1;
    }

    /* Aplica sensibilidade + aceleração SW e atualiza posição */
    float factor = SENSITIVITY * accel_factor(s->speed);
    s->x += s->dx_acc * factor;
    s->y += s->dy_acc * factor;

    mlog("  mov │ X: %+9.1f   Y: %+9.1f"
         "  │ delta: (%+4d, %+4d)"
         "  │ %7.1f mky/s"
         "  │ poll: %4.0f Hz"
         "  │ ×%.2f%s\n",
         s->x, s->y,
         s->dx_acc, s->dy_acc,
         s->speed,
         info->polling_hz,
         factor,
         info->hw_accel_suspected ? "  ⚠ accel HW?" : "");

    s->dx_acc = 0;
    s->dy_acc = 0;
}

/* =========================================================================
 * LOOP PRINCIPAL DE LEITURA
 * ========================================================================= */

static void run_mouse_loop(int fd, MouseInfo *info) {
    MouseState state;
    memset(&state, 0, sizeof(state));

    mlog("Aguardando eventos do mouse  (Ctrl+C para sair)\n");
    mlog("Posição X/Y: relativa ao ponto de início (sem limite de tela)\n");
    mlog("Saída gravada em: %s\n", LOG_FILE);
    mlog("─────────────────────────────────────────────────────────────\n\n");

    struct input_event ev;

    while (1) {
        fd_set fds;
        FD_ZERO(&fds);
        FD_SET(fd, &fds);
        struct timeval timeout = { .tv_sec = 0, .tv_usec = STOP_TIMEOUT_MS * 1000 };

        int ret = select(fd + 1, &fds, NULL, NULL, &timeout);
        if (ret < 0) { perror("select"); break; }

        /* ── Timeout: silêncio por STOP_TIMEOUT_MS → mouse parou ── */
        if (ret == 0) {
            if (state.is_moving) {
                mlog("└─────────────────────────────────────────────────────────┘\n");
                mlog("  TRAÇO #%d encerrado em  X: %+9.1f   Y: %+9.1f\n",
                     state.trace_id, state.x, state.y);
                mlog("  Polling médio: %.0f Hz%s\n",
                     info->polling_hz,
                     info->hw_accel_suspected
                         ? "   ⚠ Suspeita de aceleração de hardware!" : "");
                mlog("\n");
                state.is_moving = 0;
            }
            continue;
        }

        ssize_t n = read(fd, &ev, sizeof(ev));
        if (n < (ssize_t)sizeof(ev)) {
            if (errno == EAGAIN) continue;
            perror("read");
            break;
        }

        /* ── EV_REL: movimento e scroll ── */
        if (ev.type == EV_REL) {
            if      (ev.code == REL_X)      { state.dx_acc += ev.value; }
            else if (ev.code == REL_Y)      { state.dy_acc += ev.value; }
            else if (ev.code == REL_WHEEL)  {
                int delta = ev.value;
                state.scroll_v += delta;
                print_scroll_status(&state, delta, 0);
            }
            else if (ev.code == REL_HWHEEL) {
                int delta = ev.value;
                state.scroll_h += delta;
                print_scroll_status(&state, 0, delta);
            }
        }

        /* ── EV_SYN: fim de frame, processa movimento acumulado ── */
        else if (ev.type == EV_SYN && ev.code == SYN_REPORT) {
            process_syn(&state, info, &ev);
        }

        /* ── EV_KEY: botões ── */
        else if (ev.type == EV_KEY) {
            /*
             * ev.value:
             *   1 = pressionado
             *   0 = solto
             *   2 = auto-repeat (manter pressionado) — ignorado aqui
             */
            if      (ev.code == BTN_LEFT)   state.btn_left   = (ev.value == 1);
            else if (ev.code == BTN_RIGHT)  state.btn_right  = (ev.value == 1);
            else if (ev.code == BTN_MIDDLE) state.btn_middle = (ev.value == 1);

            if (ev.value == 0 || ev.value == 1)
                print_button_status(&state);
        }
    }
}

/* =========================================================================
 * AJUDA DE USO
 * ========================================================================= */

static void print_usage(const char *prog) {
    printf("Uso:\n");
    printf("  %s                       Auto-detecta o mouse\n", prog);
    printf("  %s -d /dev/input/eventX  Especifica o device manualmente\n", prog);
    printf("  %s -h                    Exibe esta ajuda\n\n", prog);
    printf("Exemplos:\n");
    printf("  sudo %s\n", prog);
    printf("  sudo %s -d /dev/input/event1\n", prog);
    printf("\nSaída: toda informação exibida é gravada também em '%s'\n", LOG_FILE);
}

/* =========================================================================
 * MAIN
 * ========================================================================= */

int main(int argc, char *argv[]) {
    char device_path[128] = {0};
    int  manual_device    = 0;

    /* ── Parsing de argumentos ── */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        }
        if (strcmp(argv[i], "-d") == 0 || strcmp(argv[i], "--device") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "Erro: -d requer um caminho. Ex: -d /dev/input/event1\n");
                return 1;
            }
            snprintf(device_path, sizeof(device_path), "%s", argv[i + 1]);
            manual_device = 1;
            i++;
        }
    }

    /* ── Abre o arquivo de log antes de qualquer saída ── */
    log_open();

    mlog("╔══════════════════════════════════════════════════════════╗\n");
    mlog("║             mouse_hps  —  DE1-SoC / HPS                 ║\n");
    mlog("╚══════════════════════════════════════════════════════════╝\n\n");

    /* ── Resolve o device ── */
    if (manual_device) {
        mlog("Device especificado manualmente: %s\n", device_path);
    } else {
        mlog("Procurando mouse em /dev/input/event0..%d...\n", MAX_DEVICES - 1);
        if (find_mouse_device(device_path, sizeof(device_path)) < 0) {
            fprintf(stderr,
                "\nNenhum mouse encontrado.\n"
                "Verifique se o mouse está conectado e tente:\n"
                "  sudo %s\n"
                "Ou especifique o device manualmente:\n"
                "  sudo %s -d /dev/input/event1\n", argv[0], argv[0]);
            log_close();
            return 1;
        }
        mlog("Mouse encontrado automaticamente: %s\n", device_path);
    }

    /* ── Abre o device ── */
    int fd = open(device_path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "\nErro ao abrir %s: %s\n", device_path, strerror(errno));
        fprintf(stderr, "Tente executar com sudo.\n");
        log_close();
        return 1;
    }

    /* ── Lê e exibe informações do dispositivo ── */
    MouseInfo info;
    read_mouse_info(fd, &info);
    print_device_report(device_path, &info);

    /* ── Loop principal ── */
    run_mouse_loop(fd, &info);

    close(fd);
    log_close();
    return 0;
}
