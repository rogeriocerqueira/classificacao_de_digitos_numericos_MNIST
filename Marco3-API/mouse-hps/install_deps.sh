#!/usr/bin/env bash
# =============================================================================
# install_deps.sh
#
# Instala todas as dependências necessárias para cross-compilar mouse_hps.c
# para ARM Cortex-A9 (DE1-SoC HPS) em um host x86_64 Ubuntu/Debian.
#
# Uso:
#   chmod +x install_deps.sh
#   ./install_deps.sh
#
# Testado em: Ubuntu 20.04, 22.04, 24.04 / Debian 11, 12
# =============================================================================

set -e  # aborta imediatamente se qualquer comando falhar

# -----------------------------------------------------------------------------
# Cores para saída legível
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'  # sem cor

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC}  $*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# Verificações iniciais
# -----------------------------------------------------------------------------

# Garante que está rodando em Linux x86_64
if [[ "$(uname -s)" != "Linux" ]]; then
    error "Este script é para Linux. Para outros sistemas, instale manualmente."
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
    warn "Arquitetura detectada: $(uname -m). Este script foi feito para x86_64."
    warn "Os pacotes podem ter nomes diferentes no seu sistema."
fi

# Garante que apt está disponível (Ubuntu/Debian)
if ! command -v apt-get &>/dev/null; then
    error "apt-get não encontrado. Este script suporta apenas Ubuntu/Debian."
fi

# Verifica se tem sudo ou é root
if [[ $EUID -ne 0 ]]; then
    if ! command -v sudo &>/dev/null; then
        error "Execute como root ou instale sudo."
    fi
    SUDO="sudo"
else
    SUDO=""
fi

# -----------------------------------------------------------------------------
# Início da instalação
# -----------------------------------------------------------------------------

echo ""
echo "============================================================"
echo "  Instalação de dependências — cross-compilação DE1-SoC"
echo "============================================================"
echo ""

info "Atualizando lista de pacotes..."
$SUDO apt-get update -qq
success "Lista de pacotes atualizada."

echo ""

# -----------------------------------------------------------------------------
# 1. Toolchain ARM hard-float
#
#    gcc-arm-linux-gnueabihf  — compilador C para ARM (hard-float ABI)
#    binutils-arm-linux-gnueabihf — assembler, linker, objdump, etc.
#    libc6-dev-armhf-cross    — headers e libs C padrão para ARM
#
#    Por que gnueabihf e não gnueabi?
#    O HPS da DE1-SoC tem FPU VFPv3, então usa hard-float ABI (hf).
#    gnueabi usaria soft-float e seria mais lento.
# -----------------------------------------------------------------------------

info "Instalando toolchain ARM hard-float (gnueabihf)..."
$SUDO apt-get install -y \
    gcc-arm-linux-gnueabihf \
    binutils-arm-linux-gnueabihf \
    libc6-dev-armhf-cross
success "Toolchain ARM instalado."

echo ""

# -----------------------------------------------------------------------------
# 2. Ferramentas de build
#
#    make  — para executar o Makefile
#    file  — para inspecionar o binário gerado (verifica arquitetura)
# -----------------------------------------------------------------------------

info "Instalando ferramentas de build..."
$SUDO apt-get install -y make file
success "Ferramentas de build instaladas."

echo ""

# -----------------------------------------------------------------------------
# 3. Ferramentas de transferência para a DE1-SoC
#
#    openssh-client  — ssh e scp para copiar o binário para a placa
#    sshpass         — permite passar senha do SSH por argumento
#                      (útil para scripts de deploy automático)
# -----------------------------------------------------------------------------

info "Instalando ferramentas de transferência SSH..."
$SUDO apt-get install -y openssh-client sshpass
success "Ferramentas SSH instaladas."

echo ""

# -----------------------------------------------------------------------------
# Verificação final — confirma que o compilador está no PATH
# -----------------------------------------------------------------------------

echo "------------------------------------------------------------"
info "Verificando instalação..."
echo ""

CC="arm-linux-gnueabihf-gcc"

if command -v "$CC" &>/dev/null; then
    VERSION=$($CC --version | head -1)
    success "Compilador encontrado: $VERSION"
else
    error "$CC não encontrado no PATH após instalação. Tente reiniciar o terminal."
fi

# Mostra as ferramentas disponíveis
echo ""
info "Ferramentas da toolchain disponíveis:"
for tool in gcc g++ as ld objdump objcopy strip nm size; do
    bin="arm-linux-gnueabihf-${tool}"
    if command -v "$bin" &>/dev/null; then
        echo "    $(command -v $bin)"
    fi
done

echo ""
echo "============================================================"
success "Instalação concluída!"
echo ""
echo "  Para compilar:   make"
echo "  Para transferir: make deploy DE1SOC_IP=<ip-da-placa>"
echo "============================================================"
echo ""
