#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
transform.py - Gera 'atendimento.html' a partir de 'index.html'.

Os dois arquivos sao GEMEOS: identicos, exceto 4 linhas
(1x <title>, 2x etiqueta de perfil, 1x const MODE).

REGRA DE OURO: nunca edite atendimento.html na mao.
Edite SEMPRE index.html e rode este script para regerar o gemeo.

Uso (na pasta do repositorio):
    python3 transform.py
    node --check <(sed -n '/<script>$/,/<\\/script>/p' atendimento.html)   # opcional

Se alguma ancora nao for encontrada, o script ABORTA sem gravar nada.
Isso e proposital: significa que index.html mudou de forma inesperada.
"""

import io
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
ORIGEM = os.path.join(AQUI, "index.html")
DESTINO = os.path.join(AQUI, "atendimento.html")

# (texto_procurado, texto_substituto, quantas_ocorrencias_esperadas, rotulo)
TROCAS = [
    (
        "<title>DANF \u2014 Controle de Repasses \u00b7 Gest\u00e3o</title>",
        "<title>DANF \u2014 Controle de Repasses \u00b7 Atendimento</title>",
        1,
        "titulo da aba",
    ),
    (
        '<span class="perfil">Gest\u00e3o</span>',
        '<span class="perfil">Atendimento</span>',
        2,  # uma no cabecalho, outra na tela de login
        "etiqueta de perfil (cabecalho + login)",
    ),
    (
        'const MODE = "gestao";',
        'const MODE = "atendimento";',
        1,
        "constante MODE",
    ),
]


def main():
    if not os.path.exists(ORIGEM):
        sys.exit("[ERRO] index.html nao encontrado em %s" % AQUI)

    html = io.open(ORIGEM, encoding="utf-8").read()

    for procurado, substituto, esperado, rotulo in TROCAS:
        achou = html.count(procurado)
        if achou != esperado:
            sys.exit(
                "[ERRO] '%s': esperava %d ocorrencia(s), encontrei %d.\n"
                "       Nada foi gravado. Confira se index.html foi alterado."
                % (rotulo, esperado, achou)
            )
        html = html.replace(procurado, substituto)

    io.open(DESTINO, "w", encoding="utf-8").write(html)
    print("OK: atendimento.html gerado a partir de index.html (%d caracteres)." % len(html))


if __name__ == "__main__":
    main()
