#!/usr/bin/env python3
"""
mif_to_npz.py — Converte os arquivos .mif dos pesos da rede ELM
                para o formato .npz que o test_hardware.py espera.

Uso:
    python3 mif_to_npz.py \
        --win  memory_files/W_in_q.mif \
        --bias memory_files/b_q.mif \
        --beta memory_files/beta_q.mif \
        --out  model_elm_q.npz

Formato dos .mif:
    W_in_q : DEPTH=100352, WIDTH=16 → shape (128, 784) Q4.12 signed
    b_q    : DEPTH=128,    WIDTH=16 → shape (128,)     Q4.12 signed
    beta_q : DEPTH=1280,   WIDTH=16 → shape (128, 10)  Q4.12 signed
"""

import argparse
import re
import numpy as np


def ler_mif(caminho):
    """
    Lê um arquivo .mif e retorna um array numpy de inteiros com sinal (int16).
    Suporta ADDRESS_RADIX=DEC e DATA_RADIX=HEX.
    """
    with open(caminho, 'r') as f:
        conteudo = f.read()

    # Lê o tamanho declarado
    depth_match = re.search(r'DEPTH\s*=\s*(\d+)', conteudo, re.IGNORECASE)
    if not depth_match:
        raise ValueError(f"DEPTH não encontrado em {caminho}")
    depth = int(depth_match.group(1))

    # Extrai o bloco CONTENT BEGIN ... END
    match = re.search(r'CONTENT\s+BEGIN(.*?)END\s*;',
                      conteudo, re.DOTALL | re.IGNORECASE)
    if not match:
        raise ValueError(f"Bloco CONTENT BEGIN...END não encontrado em {caminho}")

    dados = np.zeros(depth, dtype=np.int64)

    linhas = match.group(1).strip().split('\n')
    for linha in linhas:
        linha = linha.strip()
        if not linha or linha.startswith('--'):
            continue
        if ':' not in linha:
            continue
        partes = linha.split(':')
        endereco = int(partes[0].strip())
        valor_hex = partes[1].strip().rstrip(';').strip()
        # Converte hex para inteiro sem sinal e depois para com sinal (16 bits)
        valor_uint = int(valor_hex, 16)
        # Interpretação como complemento de 2 (signed 16 bits)
        if valor_uint >= 0x8000:
            valor_sint = valor_uint - 0x10000
        else:
            valor_sint = valor_uint
        dados[endereco] = valor_sint

    return dados


def main():
    ap = argparse.ArgumentParser(
        description="Converte arquivos .mif de pesos ELM para .npz")
    ap.add_argument("--win",  required=True, help="Caminho para W_in_q.mif")
    ap.add_argument("--bias", required=True, help="Caminho para b_q.mif")
    ap.add_argument("--beta", required=True, help="Caminho para beta_q.mif")
    ap.add_argument("--out",  default="model_elm_q.npz",
                    help="Arquivo de saída .npz (padrão: model_elm_q.npz)")
    args = ap.parse_args()

    print(f"Lendo W_in_q  : {args.win}")
    W_flat = ler_mif(args.win)   # shape (100352,)
    W_in_q = W_flat.reshape(128, 784)
    print(f"  → shape: {W_in_q.shape}  min={W_in_q.min()}  max={W_in_q.max()}")

    print(f"Lendo b_q     : {args.bias}")
    b_q = ler_mif(args.bias)     # shape (128,)
    print(f"  → shape: {b_q.shape}  min={b_q.min()}  max={b_q.max()}")

    print(f"Lendo beta_q  : {args.beta}")
    beta_flat = ler_mif(args.beta)  # shape (1280,)
    # beta é armazenado como [neurônio0_classe0, neurônio0_classe1, ...,
    #                          neurônio1_classe0, ...]
    # shape final: (128 neurônios, 10 classes)
    beta_q = beta_flat.reshape(128, 10)
    print(f"  → shape: {beta_q.shape}  min={beta_q.min()}  max={beta_q.max()}")

    np.savez(args.out,
             W_in_q=W_in_q,
             b_q=b_q,
             beta_q=beta_q)

    print(f"\n✓ Arquivo salvo: {args.out}")
    print(f"  Chaves: W_in_q{W_in_q.shape}, b_q{b_q.shape}, beta_q{beta_q.shape}")


if __name__ == "__main__":
    main()
