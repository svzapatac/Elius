"""Genera docs/03_flujos_usuario/flujos_para_imprimir.pdf: un flujo por hoja,
eligiendo sentido (TD/LR) y orientación de hoja para que cada uno salga lo más grande posible."""
import re, glob, os, subprocess, sys, tempfile
from PIL import Image
from reportlab.lib.pagesizes import letter, landscape
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader
ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "docs", "03_flujos_usuario")
OUT = os.path.join(ROOT, "flujos_para_imprimir.pdf")
MMDC = "/home/claude/.npm-global/bin/mmdc"
tmp = tempfile.mkdtemp(); cfg = os.path.join(tmp, "pp.json")
open(cfg, "w").write('{"args":["--no-sandbox"]}')
flujos = []
for f in sorted(glob.glob(os.path.join(ROOT, "[0-9]*.md"))):
    txt = open(f, encoding="utf-8").read()
    panel = re.search(r"^# (.+)$", txt, re.M).group(1)
    titulo = panel
    for m in re.finditer(r"(?:^## (.+)$)?(?:(?!^## ).)*?```mermaid\n(.*?)```", txt, re.M | re.S):
        pass
    partes = re.split(r"^## ", txt, flags=re.M)
    for p in partes[1:]:
        t = p.split("\n", 1)[0].strip()
        for code in re.findall(r"```mermaid\n(.*?)```", p, re.S):
            flujos.append((panel, t, code))
def render(code, d, n):
    code = re.sub(r"^(\s*(?:flowchart|graph))\s+(TD|TB|LR|RL)", lambda m: f"{m.group(1)} {d}", code, count=1, flags=re.M)
    mmd = os.path.join(tmp, f"{n}{d}.mmd"); png = os.path.join(tmp, f"{n}{d}.png")
    open(mmd, "w").write(code)
    subprocess.run([MMDC, "-i", mmd, "-o", png, "-p", cfg, "-s", "3", "-b", "white"], check=True, capture_output=True)
    return png
W, H = letter; M = 36; TOP = 70
c = canvas.Canvas(OUT, pagesize=letter)
c.setTitle("Flujos de usuario - Elius")
# portada/índice
c.setFont("Helvetica-Bold", 22); c.drawString(M, H-70, "Elius · Flujos de usuario")
c.setFont("Helvetica", 10); c.drawString(M, H-90, "Un flujo por hoja; cada uno con el sentido y la orientación que mejor lo muestran.")
y = H-125
for i, (p, t, _) in enumerate(flujos, 1):
    if y < 50: c.showPage(); y = H-60
    c.setFont("Helvetica", 9); c.drawString(M, y, f"{i+1:>3}.  {p.replace('Flujo de usuario · ','')} — {t}"[:105]); y -= 14
c.showPage()
for i, (p, t, code) in enumerate(flujos, 1):
    best = None
    for d in ("TD", "LR"):
        try: png = render(code, d, i)
        except Exception as e: print("fallo", i, d, e); continue
        w, h = Image.open(png).size
        for land in (False, True):
            pw, ph = (landscape(letter) if land else letter)
            aw, ah = pw-2*M, ph-TOP-M
            s = min(aw/w, ah/h, 1.8*72/216)  # tope de ampliación
            s = min(aw/w, ah/h, 0.6)
            if best is None or w*s*h*s > best[0]: best = (w*s*h*s, png, land, w*s, h*s)
    _, png, land, dw, dh = best
    pw, ph = (landscape(letter) if land else letter)
    c.setPageSize((pw, ph))
    c.setFont("Helvetica", 8); c.setFillGray(.4); c.drawString(M, ph-30, p.replace("Flujo de usuario · ", "Panel: ")); c.drawRightString(pw-M, ph-30, f"Flujo {i} de {len(flujos)} · hoja {i+1}")
    c.setFillGray(0); c.setFont("Helvetica-Bold", 15); c.drawString(M, ph-52, t[:90])
    aw, ah = pw-2*M, ph-TOP-M
    c.drawImage(ImageReader(png), M+(aw-dw)/2, M+(ah-dh)/2, dw, dh)
    c.showPage()
c.save(); print(len(flujos), "flujos ->", OUT)
