"""Convierte docs/01_levantamiento/levantamiento_informacion.md en un fragmento HTML para el panel.
Uso: python3 exportar_levantamiento.py <salida.html>   (necesita el paquete markdown)
Quita las imágenes (en el panel están en la pestaña Modelo E-R) y deja los enlaces internos como texto."""
import os, re, sys, markdown

AQUI = os.path.dirname(os.path.abspath(__file__))
FUENTE = os.path.join(AQUI, "..", "..", "docs", "01_levantamiento", "levantamiento_informacion.md")
md = open(FUENTE, encoding="utf-8").read()
md = re.sub(r"!\[[^\]]*\]\([^)]*\)\n?", "*(El diagrama está en la pestaña «Modelo E-R».)*\n", md)
md = re.sub(r"\[([^\]]+)\]\((?!https?://)[^)]*\)", r"\1", md)           # enlaces relativos → texto
md = re.sub(r"> Diagrama de arquitectura: ver .*\n", "", md)
html = markdown.markdown(md, extensions=["tables", "fenced_code", "toc"], extension_configs={"toc": {"toc_depth": "2-3"}})
html = html.replace("<a href=\"http", "<a target=\"_blank\" rel=\"noopener\" href=\"http")
open(sys.argv[1], "w", encoding="utf-8").write(html)
print("HTML:", len(html), "bytes")
