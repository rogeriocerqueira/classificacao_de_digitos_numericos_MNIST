/*
 * elm_mif.c — implementação do leitor de .mif.
 *
 * Estratégia: slurp do arquivo inteiro para memória, remoção de
 * comentários em-place, busca de campos no header e iteração sobre
 * statements no bloco CONTENT separados por ';'.
 *
 * Não usa scanf para os números porque precisamos passar a base
 * explicitamente (HEX/DEC/etc), o que strtoul faz limpinho.
 */

#define _GNU_SOURCE       /* strcasestr */

#include "elm_mif.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>

/* ---------- helpers ---------- */

static int parse_radix(const char *s)
{
    if (!strcasecmp(s, "HEX")) return 16;
    if (!strcasecmp(s, "DEC")) return 10;
    if (!strcasecmp(s, "UNS")) return 10;
    if (!strcasecmp(s, "OCT")) return 8;
    if (!strcasecmp(s, "BIN")) return 2;
    return 0;
}

/* Remove comentários '--linha' e '%...%' em-place. */
static void strip_comments(char *text)
{
    char *in  = text;
    char *out = text;
    int in_pct = 0;

    while (*in) {
        if (in_pct) {
            if (*in == '%') in_pct = 0;
            in++;
            continue;
        }
        if (in[0] == '-' && in[1] == '-') {
            while (*in && *in != '\n') in++;
            continue;
        }
        if (*in == '%') {
            in_pct = 1;
            in++;
            continue;
        }
        *out++ = *in++;
    }
    *out = '\0';
}

static char *trim_lead(char *s)
{
    while (*s && isspace((unsigned char)*s)) s++;
    return s;
}

/*
 * Procura "KEY = value" em texto livre. KEY case-insensitive, precedido
 * por borda de palavra (não-alfanum). Devolve 1 e copia o valor para
 * `value` (sem espaços) se encontrar, ou 0 caso contrário.
 */
static int find_field(const char *text, const char *key,
                      char *value, size_t value_sz)
{
    size_t keylen = strlen(key);
    const char *p = text;

    while ((p = strcasestr(p, key)) != NULL) {
        /* Caractere anterior precisa ser borda */
        if (p > text) {
            char prev = p[-1];
            if (isalnum((unsigned char)prev) || prev == '_') {
                p++;
                continue;
            }
        }
        const char *after = p + keylen;
        /* Aceita espaço, tab, '=' ou newline depois */
        if (*after != ' ' && *after != '\t' &&
            *after != '=' && *after != '\n' && *after != '\r') {
            p++;
            continue;
        }
        /* Pula espaços e '=' */
        while (*after && (isspace((unsigned char)*after) || *after == '='))
            after++;
        /* Copia o token */
        size_t i = 0;
        while (*after && !isspace((unsigned char)*after)
               && *after != ';' && i + 1 < value_sz) {
            value[i++] = *after++;
        }
        value[i] = '\0';
        return 1;
    }
    return 0;
}

/* Processa um statement do bloco CONTENT. Devolve 0 se ignorou (vazio
 * ou sem ':'), 1 se aplicou ao array data[]. */
static int apply_stmt(char *stmt, int addr_base, int data_base,
                      size_t depth, uint32_t *data)
{
    char *colon = strchr(stmt, ':');
    if (!colon) return 0;
    *colon = '\0';
    char *addr_part = trim_lead(stmt);
    char *val_part  = trim_lead(colon + 1);
    if (!*addr_part || !*val_part) return 0;

    unsigned long val = strtoul(val_part, NULL, data_base);

    char *dotdot = strstr(addr_part, "..");
    if (dotdot) {
        *dotdot = '\0';
        char *lo_s = trim_lead(addr_part);
        if (*lo_s == '[') lo_s = trim_lead(lo_s + 1);
        unsigned long lo = strtoul(lo_s, NULL, addr_base);

        char *hi_s = trim_lead(dotdot + 2);
        char *bracket = strchr(hi_s, ']');
        if (bracket) *bracket = '\0';
        unsigned long hi = strtoul(hi_s, NULL, addr_base);

        for (unsigned long a = lo; a <= hi; a++) {
            if (a < depth) data[a] = (uint32_t)val;
        }
    } else {
        unsigned long a = strtoul(trim_lead(addr_part), NULL, addr_base);
        if (a < depth) data[a] = (uint32_t)val;
    }
    return 1;
}

/* ---------- API pública ---------- */

int elm_mif_load_raw(const char *path, uint32_t **out_data,
                     size_t *out_size, int *out_width)
{
    FILE *f = fopen(path, "rb");
    if (!f) return ELM_MIF_E_OPEN;

    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return ELM_MIF_E_READ; }
    long fsize = ftell(f);
    if (fsize <= 0)                 { fclose(f); return ELM_MIF_E_FORMAT; }
    rewind(f);

    char *text = (char *)malloc((size_t)fsize + 1);
    if (!text) { fclose(f); return ELM_MIF_E_NOMEM; }

    if (fread(text, 1, (size_t)fsize, f) != (size_t)fsize) {
        free(text); fclose(f); return ELM_MIF_E_READ;
    }
    text[fsize] = '\0';
    fclose(f);

    strip_comments(text);

    char buf[64];
    size_t depth = 0;
    int width = 0, addr_base = 0, data_base = 0;

    if (find_field(text, "DEPTH",         buf, sizeof(buf))) depth     = strtoul(buf, NULL, 10);
    if (find_field(text, "WIDTH",         buf, sizeof(buf))) width     = atoi(buf);
    if (find_field(text, "ADDRESS_RADIX", buf, sizeof(buf))) addr_base = parse_radix(buf);
    if (find_field(text, "DATA_RADIX",    buf, sizeof(buf))) data_base = parse_radix(buf);

    if (depth == 0 || width == 0 || addr_base == 0 || data_base == 0) {
        free(text); return ELM_MIF_E_FORMAT;
    }

    /* Localiza CONTENT BEGIN ... END */
    char *begin = strcasestr(text, "BEGIN");
    char *end   = begin ? strcasestr(begin + 5, "END") : NULL;
    if (!begin || !end) { free(text); return ELM_MIF_E_FORMAT; }
    begin += 5;
    *end = '\0';

    uint32_t *data = (uint32_t *)calloc(depth, sizeof(uint32_t));
    if (!data) { free(text); return ELM_MIF_E_NOMEM; }

    /* Itera sobre statements separados por ';' */
    char *cursor = begin;
    while (1) {
        char *semi = strchr(cursor, ';');
        if (!semi) break;
        *semi = '\0';
        char *trimmed = trim_lead(cursor);
        if (*trimmed) {
            apply_stmt(trimmed, addr_base, data_base, depth, data);
        }
        cursor = semi + 1;
    }

    free(text);
    *out_data  = data;
    *out_size  = depth;
    *out_width = width;
    return ELM_MIF_OK;
}

int elm_mif_load_image(const char *path, uint8_t **out_data, size_t *out_size)
{
    uint32_t *raw = NULL;
    size_t sz = 0;
    int width = 0;
    int rc = elm_mif_load_raw(path, &raw, &sz, &width);
    if (rc != ELM_MIF_OK) return rc;

    if (width != 8) { free(raw); return ELM_MIF_E_WIDTH; }

    uint8_t *out = (uint8_t *)malloc(sz);
    if (!out) { free(raw); return ELM_MIF_E_NOMEM; }
    for (size_t i = 0; i < sz; i++) out[i] = (uint8_t)(raw[i] & 0xFFu);
    free(raw);
    *out_data = out;
    *out_size = sz;
    return ELM_MIF_OK;
}

int elm_mif_load_q4_12(const char *path, int16_t **out_data, size_t *out_size)
{
    uint32_t *raw = NULL;
    size_t sz = 0;
    int width = 0;
    int rc = elm_mif_load_raw(path, &raw, &sz, &width);
    if (rc != ELM_MIF_OK) return rc;

    if (width != 16) { free(raw); return ELM_MIF_E_WIDTH; }

    int16_t *out = (int16_t *)malloc(sz * sizeof(int16_t));
    if (!out) { free(raw); return ELM_MIF_E_NOMEM; }
    /* Cast via uint16_t para preservar o padrão de bits, depois para
     * int16_t que reinterpreta como complemento de dois. */
    for (size_t i = 0; i < sz; i++) {
        out[i] = (int16_t)(uint16_t)(raw[i] & 0xFFFFu);
    }
    free(raw);
    *out_data = out;
    *out_size = sz;
    return ELM_MIF_OK;
}
