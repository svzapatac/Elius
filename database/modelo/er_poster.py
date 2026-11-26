"""Modelo E-R general PARA IMPRIMIR: acomoda las tablas muy juntas (casi sin espacios en blanco), del tamaño justo
para una cuadrícula de hojas carta, y dibuja las relaciones encima.  Uso:
  python3 er_poster.py <columnas> <filas> <salida.png> [vertical]
Después: python3 imprimir_poster.py <salida.png> <columnas> <filas> <salida.pdf> "<título>" [vertical]"""
import html, json, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
cols, filas, salida = int(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
VERT = len(sys.argv) > 4 and sys.argv[4] == "vertical"
import er_estilo as E  # noqa: E402

PW, PH = (612, 792) if VERT else (792, 612)
M_, OV = 25, 32
gw, gh = cols * (PW - 2 * M_ - OV) + OV, filas * (PH - 2 * M_ - OV) + OV   # puntos de póster disponibles
GAP = int(os.environ.get("GAP", "20"))

# 1. Tablas del modelo general, en el orden de los módulos (lo relacionado queda cerca)
orden_mod = [i for i, m in enumerate(E.M) if m[3] == "general"]
tablas = []
for i in orden_mod:
    tablas += E.M[i][4].split()
rels = [r for r in E.R if r[0] in tablas and r[2] in tablas]

# 2. Medir cada tabla con Graphviz (sin aristas)
tmp = tempfile.mkdtemp()
L = ["digraph G {", '  node [shape=plain, fontname="Helvetica", fontsize=12];']
for n in tablas:
    L.append(E.nodo(n, True))
L.append("}")
open(os.path.join(tmp, "m.dot"), "w").write("\n".join(L))
js = json.loads(subprocess.run(["dot", "-Tjson", os.path.join(tmp, "m.dot")], capture_output=True, text=True, check=True).stdout)
tam = {o["name"]: (float(o["width"]) * 72, float(o["height"]) * 72) for o in js["objects"] if "width" in o}
# leyenda de colores como una tabla más
leyenda = ['<<table border="1" cellborder="0" cellspacing="0" cellpadding="4" color="#8A93A3" bgcolor="white">'
           '<tr><td colspan="2"><b>MÓDULOS</b></td></tr>']
for i in orden_mod:
    leyenda.append(f'<tr><td bgcolor="{E.M[i][2]}" width="14"> </td><td align="left">{html.escape(E.M[i][1])}</td></tr>')
leyenda.append('<tr><td colspan="2" align="left"><font point-size="10">PK llave · FK llave foránea<br/>pata de gallo = muchos<br/>círculo = opcional</font></td></tr></table>>')
open(os.path.join(tmp, "l.dot"), "w").write('digraph G { node [shape=plain, fontname="Helvetica", fontsize=12]; "LEYENDA" [label=' + "".join(leyenda) + "]; }")
jl = json.loads(subprocess.run(["dot", "-Tjson", os.path.join(tmp, "l.dot")], capture_output=True, text=True, check=True).stdout)
tam["LEYENDA"] = next((float(o["width"]) * 72, float(o["height"]) * 72) for o in jl["objects"] if o["name"] == "LEYENDA")
items = tablas + ["LEYENDA"]


# 3. Empaquetado en dos niveles: tablas dentro de cada módulo, y módulos dentro del póster
def empacar(its, ancho, sep):
    """its: {nombre: (w, h)}. Devuelve posiciones, ancho y alto usados; cada pieza en el sitio más arriba-izquierda libre."""
    puestas = {}
    for n, (w0, h0) in its.items():
        w, h = w0 + sep, h0 + sep
        cx = {0} | {x + ww for (x, y, ww, hh) in puestas.values()}
        cy = {0} | {y + hh for (x, y, ww, hh) in puestas.values()}
        mejor = None
        for y in sorted(cy):
            for x in sorted(cx):
                if x + w > ancho or any(x < px + pw and px < x + w and y < py + ph and py < y + h for (px, py, pw, ph) in puestas.values()):
                    continue
                mejor = (x, y); break
            if mejor: break
        if not mejor: return None
        puestas[n] = (mejor[0], mejor[1], w, h)
    return puestas, max(x + w for (x, y, w, h) in puestas.values()) - sep, max(y + h for (x, y, w, h) in puestas.values()) - sep


PAD, TIT = int(os.environ.get("PAD", "12")), 34                                         # relleno del recuadro de módulo y alto del título
bloques = {}
for i in orden_mod:
    ns = [n for n in E.M[i][4].split()]
    mejor = None
    for ancho in range(int(max(tam[n][0] for n in ns)) + 5, 3000, 20):
        r = empacar({n: tam[n] for n in sorted(ns, key=lambda n: -tam[n][1])}, ancho, GAP)
        if not r: continue
        pos, w, h = r
        score = w * h * (1 + abs((w / h) - 1.5) * 0.15)   # área mínima, prefiriendo bloques ni muy largos ni muy altos
        if not mejor or score < mejor[0]: mejor = (score, pos, w, h)
    bloques[i] = mejor[1:]
from PIL import ImageFont as _IF
_f = _IF.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 22)
bl = {i: (max(bloques[i][1] + 2 * PAD, _f.getlength(E.M[i][1]) + 2 * PAD), bloques[i][2] + 2 * PAD + TIT) for i in orden_mod}
bl["LEYENDA"] = tam["LEYENDA"]
mejor = None
for ancho in range(int(max(w for w, h in bl.values())) + 5, 7000, 40):
    r = empacar(bl, ancho, int(os.environ.get("BSEP", "18")))
    if not r: continue
    pos, W, H = r
    esc = min(gw / W, gh / H)
    if not mejor or esc > mejor[0]: mejor = (esc, pos, W, H, ancho)
esc, bpos, W, H, ancho = mejor
print(f"diseño {W:.0f}x{H:.0f} pt · escala de impresión {esc:.2f} (1.00 = letra de 12 pt)")

# posiciones finales de cada tabla
puestas = {}
for i in orden_mod:
    bx, by = bpos[i][0], bpos[i][1]
    for n, (x, y, w, h) in bloques[i][0].items():
        puestas[n] = (bx + PAD + x, by + PAD + TIT + y, w, h)
puestas["LEYENDA"] = (bpos["LEYENDA"][0], bpos["LEYENDA"][1], tam["LEYENDA"][0] + GAP, tam["LEYENDA"][1] + GAP)

# 4. Relaciones y tablas con Graphviz (fondo transparente) y los recuadros de módulo con Pillow
L = ["digraph G {", f'  graph [splines=true, outputorder=edgesfirst, bgcolor=transparent, pad=0, overlap=true, bb="0,0,{W:.1f},{H:.1f}"];',
     '  node [shape=plain, fontname="Helvetica", fontsize=12];',
     '  edge [dir=both, color="#5A6475", penwidth=1.1, arrowsize=0.8];']
for n in items:
    x, y, w, h = puestas[n]
    cx, cy = x + (w - GAP) / 2, H - (y + (h - GAP) / 2)
    lab = E.nodo(n, True).split("[label=", 1)[1].rsplit("];", 1)[0] if n != "LEYENDA" else "".join(leyenda)
    L.append(f'  "{n}" [label={lab}, pos="{cx:.1f},{cy:.1f}!"];')
for (o, col, d, nulo) in rels:
    cab = "teeodot" if nulo else "teetee"
    L.append(f'  "{o}":"{col}" -> "{d}":"id" [arrowtail=crowodot, arrowhead={cab}];')
L.append("}")
dot = os.path.join(tmp, "p.dot")
open(dot, "w").write("\n".join(L))
dpi = 300 * esc
capa = os.path.join(tmp, "capa.png")
r = subprocess.run(["neato", "-n2", "-Tpng", f"-Gdpi={dpi:.1f}", dot, "-o", capa], capture_output=True, text=True)
if r.returncode: sys.exit(r.stderr[:400])
from PIL import Image, ImageDraw, ImageFont
Image.MAX_IMAGE_PIXELS = None
g = Image.open(capa).convert("RGBA")
k = g.width / W                                            # píxeles por punto de diseño
fondo = Image.new("RGBA", g.size, "white")
d = ImageDraw.Draw(fondo)
fuente = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(22 * k))
for i in orden_mod:
    x, y = bpos[i][0], bpos[i][1]
    w, h = bl[i]
    d.rounded_rectangle((x * k, y * k, (x + w) * k, (y + h) * k), radius=int(14 * k), fill="#F3F5FA", outline=E.M[i][2], width=max(2, int(2.2 * k)))
    d.text(((x + PAD) * k, (y + 6) * k), E.M[i][1], font=fuente, fill=E.M[i][2])
fondo.alpha_composite(g)
fondo.convert("RGB").save(salida)
print("OK", salida, fondo.size)
