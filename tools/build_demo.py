"""Arma la demo navegable (una sola página) a partir de index.html y un backend simulado.

Uso:
  python3 tools/build_demo.py RUTA/banco_completo.json SALIDA.html

Solo toma de banco_completo.json los campos públicos (id, pilar, enunciado, opciones).
La clave real nunca entra en la demo: tools/demo_backend.js genera una ficticia.
"""
import json
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(RAIZ, "tools"))
from generar_seeds import BIBLIOTECA  # noqa: E402


def main():
    banco = json.load(open(sys.argv[1], encoding="utf8"))
    orden, pregs = {}, []
    for b in banco:
        orden[b["pilar"]] = orden.get(b["pilar"], 0) + 1
        pregs.append({"id": b["id"], "grupo": b["pilar"], "orden": orden[b["pilar"]], "enunciado": b["enunciado"], "opciones": b["opciones"]})
    bib = [{"id": i + 1, "pilar": n, "horizonte": h, "accion": a, "indicador": ind}
           for i, (n, h, a, ind) in enumerate((n, h, a, ind) for n, fs in BIBLIOTECA.items() for h, a, ind in fs)]

    html = open(os.path.join(RAIZ, "index.html"), encoding="utf8").read()
    backend = open(os.path.join(RAIZ, "tools", "demo_backend.js"), encoding="utf8").read()
    datos = ("<script>window.IAB_DEMO_PREGUNTAS=" + json.dumps(pregs, ensure_ascii=False).replace("</", "<\\/") +
             ";window.IAB_DEMO_BIBLIOTECA=" + json.dumps(bib, ensure_ascii=False) + ";</script>\n<script>" + backend + "</script>")
    # Sin cliente de Supabase ni configuración: la demo usa el backend simulado
    html = re.sub(r'<script src="https://cdn\.jsdelivr\.net/npm/@supabase[^>]*></script>\s*<script>.*?</script>', datos, html, count=1, flags=re.S)
    assert "IAB_DEMO_PREGUNTAS" in html
    # La publicación agrega su propio esqueleto
    for pat in [r"<!doctype html>\s*", r"<html[^>]*>\s*", r"</html>\s*", r"<head>\s*", r"</head>\s*", r"<body>\s*", r"</body>\s*",
                r'<meta charset="utf-8">\s*', r'<meta name="viewport"[^>]*>\s*']:
        html = re.sub(pat, "", html, flags=re.I)
    html = html.replace("<title>IT Assessment Board</title>", "<title>IT Assessment Board Demo</title>")
    open(sys.argv[2], "w", encoding="utf8").write(html)
    print("ok", len(html) // 1024, "KB")


if __name__ == "__main__":
    main()
