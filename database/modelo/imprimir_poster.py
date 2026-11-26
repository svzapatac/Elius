"""Divide un diagrama grande en hojas tamaño carta para imprimir y pegar (póster).
Uso: python3 imprimir_poster.py <imagen.png> <columnas> <filas> <salida.pdf> "<título>"
Cada hoja trae un borde de solape: se corta el margen blanco de la IZQUIERDA y de ARRIBA (línea punteada) y se pega
la hoja encima de la anterior haciendo coincidir las cruces +. Necesita Pillow y reportlab."""
import io, sys
from PIL import Image
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader
from reportlab.pdfgen import canvas

Image.MAX_IMAGE_PIXELS = None
img_path, cols, filas, salida, titulo = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4], sys.argv[5]
PW, PH = landscape(letter)
M = 0.35 * inch          # margen que la impresora no imprime
OV = 0.45 * inch         # solape entre hojas
W, H = PW - 2 * M, PH - 2 * M
img = Image.open(img_path).convert("RGB")
iw, ih = img.size
gw, gh = cols * (W - OV) + OV, filas * (H - OV) + OV      # área total del póster (puntos)
esc = min(gw / iw, gh / ih)                                # puntos por píxel
pw, ph = iw * esc, ih * esc
ox, oy = (gw - pw) / 2, (gh - ph) / 2                      # centrado
DPI = 300
ppp = DPI / 72.0                                           # píxeles de salida por punto

c = canvas.Canvas(salida, pagesize=(PW, PH))
c.setTitle(titulo)

# --- Página 1: instrucciones y mapa de hojas ---
c.setFont("Helvetica-Bold", 20); c.drawString(M, PH - M - 18, titulo)
c.setFont("Helvetica", 11)
tx = [f"Póster de {cols * filas} hojas tamaño carta ({cols} columnas × {filas} filas). Imprime TODAS las páginas siguientes al 100 % (sin 'ajustar a la página').",
      "1. Ordena las hojas como en el mapa de abajo (A1, B1, C1 …).",
      "2. En cada hoja, corta el margen blanco de la IZQUIERDA y de ARRIBA siguiendo la línea punteada. No cortes la derecha ni abajo.",
      "3. Pega cada hoja ENCIMA de la anterior (la de su izquierda o la de arriba), haciendo coincidir las cruces + y el dibujo.",
      "4. Empieza por la fila de arriba, pega las filas entre sí al final. Usa cinta o pegante en barra por detrás."]
y = PH - M - 44
for t in tx:
    c.drawString(M, y, t); y -= 16
# mapa
mw = 6.2 * inch; mh = mw * (filas * (H - OV) + OV) / (cols * (W - OV) + OV)
mx, my = M, M + 0.2 * inch
c.setStrokeColorRGB(.4, .4, .4)
th = img.copy(); th.thumbnail((1400, 1400))
c.drawImage(ImageReader(th), mx + ox / gw * mw, my + (gh - oy - ph) / gh * mh, pw / gw * mw, ph / gh * mh)
c.setFont("Helvetica-Bold", 14)
for j in range(filas):
    for i in range(cols):
        x0 = mx + i * (W - OV) / gw * mw; y0 = my + mh - (j + 1) * (H - OV) / gh * mh - OV / gh * mh
        c.setStrokeColorRGB(.8, .1, .1); c.setLineWidth(1.2)
        c.rect(x0, y0, W / gw * mw, H / gh * mh)
        c.setFillColorRGB(.8, .1, .1); c.drawString(x0 + 5, y0 + H / gh * mh - 17, f"{chr(65 + i)}{j + 1}")
c.setFillColorRGB(0, 0, 0); c.setFont("Helvetica", 9)
c.drawString(mx + mw + 20, my + mh - 12, f"Tamaño final del póster: {gw / 72 * 2.54:.0f} × {gh / 72 * 2.54:.0f} cm (con solapes)")
c.drawString(mx + mw + 20, my + mh - 26, "Los rectángulos rojos son las hojas; se superponen un poco: es normal.")
c.showPage()

# --- Hojas ---
for j in range(filas):
    for i in range(cols):
        # región del póster que cubre esta hoja (puntos, origen arriba-izquierda del póster)
        x0, y0 = i * (W - OV), j * (H - OV)
        # a píxeles de la imagen original
        sx0, sy0 = (x0 - ox) / esc, (y0 - oy) / esc
        sx1, sy1 = (x0 + W - ox) / esc, (y0 + H - oy) / esc
        tile = Image.new("RGB", (int(round(W * ppp)), int(round(H * ppp))), "white")
        a0, b0, a1, b1 = max(sx0, 0), max(sy0, 0), min(sx1, iw), min(sy1, ih)
        if a1 > a0 and b1 > b0:
            recorte = img.crop((int(a0), int(b0), int(a1), int(b1)))
            nw, nh = max(1, int(round(recorte.width * esc * ppp))), max(1, int(round(recorte.height * esc * ppp)))
            recorte = recorte.resize((nw, nh), Image.LANCZOS)
            tile.paste(recorte, (int(round((a0 - sx0) * esc * ppp)), int(round((b0 - sy0) * esc * ppp))))
        buf = io.BytesIO(); tile.save(buf, "PNG"); buf.seek(0)
        c.drawImage(ImageReader(buf), M, M, W, H)
        # guías: línea de corte (izquierda y arriba), cruces de registro en las 4 esquinas de la imagen
        c.setDash(3, 3); c.setStrokeColorRGB(.2, .2, .2); c.setLineWidth(.6)
        if i > 0: c.line(M, M, M, PH - M + 0)
        if j > 0: c.line(M, PH - M, PW - M, PH - M)
        c.setDash()
        c.setLineWidth(.8)
        for cx, cy in ((M, M), (PW - M, M), (M, PH - M), (PW - M, PH - M)):
            c.line(cx - 6, cy, cx + 6, cy); c.line(cx, cy - 6, cx, cy + 6)
        # solape: cruces también en el borde donde empieza la siguiente hoja
        for cx in ((PW - M - OV,) if i < cols - 1 else ()):
            for cy in (M, PH - M): c.line(cx - 6, cy, cx + 6, cy); c.line(cx, cy - 6, cx, cy + 6)
        for cy in ((M + OV,) if j < filas - 1 else ()):
            for cx in (M, PW - M): c.line(cx - 6, cy, cx + 6, cy); c.line(cx, cy - 6, cx, cy + 6)
        c.setFont("Helvetica-Bold", 10); c.setFillColorRGB(.8, .1, .1)
        c.drawRightString(PW - 6, 8, f"Hoja {chr(65 + i)}{j + 1} de {cols * filas}")
        c.setFont("Helvetica", 7); c.setFillColorRGB(.3, .3, .3)
        c.drawString(6, 8, f"{titulo} · corta izquierda y arriba por la línea punteada")
        c.setFillColorRGB(0, 0, 0)
        c.showPage()
c.save()
print("OK", salida, f"{cols * filas} hojas + instrucciones")
