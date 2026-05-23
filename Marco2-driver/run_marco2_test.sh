#!/usr/bin/env bash
#
# run_marco2_test.sh — automação do teste de estabilidade do Marco 2.
#
# Executa:
#   1. Build limpo do driver e do programa de teste
#   2. Smoke test rápido (5 iterações) para detectar problemas grosseiros
#   3. Teste completo (100 iterações por default) com captura de log
#   4. Verificação de pass/fail
#
# Variáveis de ambiente (com defaults):
#   MIF_DIR    — diretório com os .mif (default: ./mif_files)
#   ITERS      — número de inferências (default: 100)
#   EXPECTED   — classe esperada (default: vazio = não verifica)
#   LOGFILE    — arquivo de log (default: marco2_test.log)
#
# Códigos de saída:
#   0 = passou
#   1 = falhou no smoke test
#   2 = falhou no teste completo
#   3 = build falhou

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJ_DIR"

MIF_DIR="${MIF_DIR:-./mif_files}"
ITERS="${ITERS:-100}"
EXPECTED="${EXPECTED:-}"
LOGFILE="${LOGFILE:-marco2_test.log}"

color() {
    case "$1" in
        red)    printf '\033[31m%s\033[0m\n' "$2" ;;
        green)  printf '\033[32m%s\033[0m\n' "$2" ;;
        yellow) printf '\033[33m%s\033[0m\n' "$2" ;;
        bold)   printf '\033[1m%s\033[0m\n'  "$2" ;;
    esac
}

color bold "[1/4] Build limpo"
if ! make clean && make; then
    color red "FALHA no build"
    exit 3
fi
echo

color bold "[2/4] Verificação de pré-requisitos"
if [ ! -d "$MIF_DIR" ]; then
    color red "ERRO: diretório $MIF_DIR não existe"
    color yellow "      coloque mem_img.mif, mem_bias.mif, mem_win.mif, mem_beta.mif lá"
    exit 1
fi
for f in mem_img.mif mem_bias.mif mem_win.mif mem_beta.mif; do
    if [ ! -f "$MIF_DIR/$f" ]; then
        color red "ERRO: $MIF_DIR/$f não encontrado"
        exit 1
    fi
done
if [ "$(id -u)" -ne 0 ]; then
    color yellow "AVISO: você não é root. /dev/mem provavelmente vai falhar."
    color yellow "       Rode novamente com sudo, ou ajuste permissões."
fi
echo "OK: todos os .mif presentes em $MIF_DIR"
echo

color bold "[3/4] Smoke test (5 iterações)"
if ! ./marco2_test -d "$MIF_DIR" -n 5 2>&1 | tee /dev/stderr | grep -q "^PASS$"; then
    color red "Smoke test falhou. Veja a saída acima."
    exit 1
fi
echo

color bold "[4/4] Teste completo ($ITERS iterações)"
ARGS=(-d "$MIF_DIR" -n "$ITERS")
if [ -n "$EXPECTED" ]; then
    ARGS+=(-e "$EXPECTED")
fi

./marco2_test "${ARGS[@]}" 2>&1 | tee "$LOGFILE"
echo

if grep -q "^PASS$" "$LOGFILE"; then
    color green "RESULTADO: PASS"
    color green "Log salvo em: $LOGFILE"
    exit 0
else
    color red "RESULTADO: FAIL"
    color red "Log salvo em: $LOGFILE"
    exit 2
fi
