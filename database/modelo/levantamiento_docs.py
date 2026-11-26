"""Genera el Word (Arial 12) y el HTML del panel desde docs/01_levantamiento/levantamiento_informacion.md."""
import os, re, subprocess, sys
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "01_levantamiento")
PANEL = "/home/claude/elius-panel/public/modelo/levantamiento.html"
MD = "levantamiento_informacion.md"; OUT = "levantamiento_informacion.docx"
EXTRA = len(sys.argv) > 1; LAND = os.environ.get("LAND") == "1"; PT = 9 if LAND else 10.5; ANCHOS = (3.7, 2.6, 1.3, 2.6, 3.3, 9.1, 2.2) if LAND else ANCHOS
if EXTRA:
    ruta = os.path.abspath(sys.argv[1]); D = os.path.dirname(ruta); MD = os.path.basename(ruta); OUT = MD[:-3] + ".docx"
os.chdir(D)
subprocess.run(["pandoc", "-f", "markdown-smart", MD, "-o", "/tmp/lev_raw.docx", "--resource-path=.:" + os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "01_levantamiento")], check=True)
d = Document("/tmp/lev_raw.docx"); AZ = RGBColor(0x5B, 0x3F, 0xA0); TINTA = RGBColor(0x1F, 0x1A, 0x2E)
def arial(st):
    rpr = st.element.get_or_add_rPr(); rf = rpr.find(qn("w:rFonts"))
    if rf is None: rf = OxmlElement("w:rFonts"); rpr.append(rf)
    for a in ("w:asciiTheme", "w:hAnsiTheme", "w:cstheme", "w:eastAsiaTheme"):
        if rf.get(qn(a)) is not None: del rf.attrib[qn(a)]
    for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"): rf.set(qn(a), "Arial")
    return rpr
H = {"Heading1": 20, "Heading2": 16, "Heading3": 14, "Heading4": 12, "Title": 24}
for s in d.styles:
    if s.type not in (1, 2): continue
    rpr = arial(s); s.font.size = Pt(12)
    if s.style_id in ("SourceCode", "VerbatimChar"): s.font.name = "Consolas"; s.font.size = Pt(10)
    if s.style_id in H:
        for c in rpr.findall(qn("w:color")): rpr.remove(c)
        s.font.size = Pt(H[s.style_id]); s.font.bold = True; s.font.color.rgb = AZ if s.style_id != "Heading4" else TINTA
        pf = s.paragraph_format; pf.space_before = Pt(12 if s.style_id == "Heading4" else 18); pf.space_after = Pt(6); pf.keep_with_next = True
    elif s.style_id in ("BodyText", "FirstParagraph", "Compact", "Normal"):
        s.font.color.rgb = TINTA; s.paragraph_format.line_spacing = 1.25; s.paragraph_format.space_after = Pt(6)
for st in d.styles:
    if st.style_id == "Heading2":
        pb = OxmlElement("w:pBdr"); bt = OxmlElement("w:bottom")
        for k, v in (("val", "single"), ("sz", "12"), ("space", "4"), ("color", "5B3FA0")): bt.set(qn("w:" + k), v)
        pb.append(bt); st.element.get_or_add_pPr().append(pb)
for sec in d.sections:
    sec.left_margin = sec.right_margin = sec.top_margin = sec.bottom_margin = Cm(1.8 if LAND else 2.5)
    if LAND: sec.orientation = 1; sec.page_width, sec.page_height = Cm(29.7), Cm(21.0)
    p = sec.footer.paragraphs[0] if sec.footer.paragraphs else sec.footer.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run((("Elius · Diccionario de datos · Página " if LAND else "Elius · Triggers · Página ") if EXTRA else "Elius · Levantamiento de información y requerimientos · Página ")); r.font.size = Pt(9); r.font.name = "Arial"
    r2 = p.add_run(); r2.font.size = Pt(9)
    for t, x in (("begin", None), ("instr", " PAGE "), ("end", None)):
        if t == "instr": e = OxmlElement("w:instrText"); e.set(qn("xml:space"), "preserve"); e.text = x
        else: e = OxmlElement("w:fldChar"); e.set(qn("w:fldCharType"), t)
        r2._r.append(e)
def sombra(c, hx):
    s = OxmlElement("w:shd"); s.set(qn("w:val"), "clear"); s.set(qn("w:fill"), hx); c._tc.get_or_add_tcPr().append(s)
for t in d.tables:
    b = OxmlElement("w:tblBorders")
    for k in ("top", "left", "bottom", "right", "insideH", "insideV"):
        e = OxmlElement(f"w:{k}"); e.set(qn("w:val"), "single"); e.set(qn("w:sz"), "4"); e.set(qn("w:color"), "DCD9E0"); b.append(e)
    t._tbl.tblPr.append(b)
    for i, row in enumerate(t.rows):
        for c in row.cells:
            if i == 0: sombra(c, "ECE8F6")
            elif i % 2 == 0: sombra(c, "F3F0F9")
            m = OxmlElement("w:tcMar")
            for k, w in (("top", 25 if LAND else 60), ("bottom", 25 if LAND else 60), ("left", 80), ("right", 80)):
                e = OxmlElement(f"w:{k}"); e.set(qn("w:w"), str(w)); e.set(qn("w:type"), "dxa"); m.append(e)
            c._tc.get_or_add_tcPr().append(m)
            for p in c.paragraphs:
                p.paragraph_format.space_after = Pt(0); p.paragraph_format.line_spacing = 1.0
                for r in p.runs:
                    r.font.name = "Arial"; r.font.size = Pt(PT)
                    if i == 0: r.font.bold = True; r.font.color.rgb = AZ
for p in d.paragraphs:
    if p.style.style_id.startswith("Heading"):
        for r in p.runs: r.font.name = "Arial"; r.font.size = p.style.font.size; r.font.bold = True; r.font.color.rgb = p.style.font.color.rgb
if EXTRA:
    for t in d.tables:
        t.autofit = False
        for gc, w in zip(t._tbl.tblGrid.findall(qn("w:gridCol")), ANCHOS): gc.set(qn("w:w"), str(int(w * 567)))
        for el in t._tbl.tblPr.findall(qn("w:tblW")): el.set(qn("w:type"), "dxa"); el.set(qn("w:w"), str(int(sum(ANCHOS) * 567)))
        for row in t.rows:
            for c, w in zip(row.cells, ANCHOS): c.width = Cm(w)
d.save(OUT)
if not EXTRA: h = subprocess.run(["pandoc", "-f", "markdown+ascii_identifiers-smart", MD, "-t", "html"], check=True, capture_output=True, text=True).stdout
if not EXTRA: h = re.sub(r'<h([234]) id="([^"]+)">(\d+(?:\.\d+)*)\.? ', lambda m: f'<h{m.group(1)} id="{m.group(3).replace(".", "-")}-{m.group(2)}">{m.group(3)}{"." if m.group(1) == "2" else ""} ', h)
if not EXTRA: h = re.sub(r'src="elius-logo.png"', 'src="/elius-logo.png"', h)
if not EXTRA and os.path.isdir(os.path.dirname(PANEL)): open(PANEL, "w", encoding="utf-8").write(h)
print("ok")
