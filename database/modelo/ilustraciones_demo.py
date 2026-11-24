"""Genera las ilustraciones SVG (originales) de los 15 ítems de prueba y los 3 logos.
Uso: python3 database/modelo/ilustraciones_demo.py <carpeta_public/demo>"""
import sys, os
out = sys.argv[1] if len(sys.argv) > 1 else '.'
os.makedirs(out, exist_ok=True)

def lienzo(c1, c2, cuerpo, etiqueta=''):
    t = f'<text x="200" y="278" text-anchor="middle" font-family="Georgia,serif" font-size="22" fill="#fff" opacity=".95">{etiqueta}</text>' if etiqueta else ''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300" width="400" height="300">
<defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>
<rect width="400" height="300" fill="url(#g)"/><circle cx="340" cy="50" r="90" fill="#fff" opacity=".08"/><circle cx="50" cy="270" r="110" fill="#fff" opacity=".08"/>
{cuerpo}{t}</svg>'''

def guardar(nombre, svg):
    open(os.path.join(out, nombre), 'w', encoding='utf-8').write(svg)

# ---------------- Restaurante ----------------
guardar('restaurante-1.svg', lienzo('#b45309', '#78350f', '''
<ellipse cx="200" cy="165" rx="150" ry="85" fill="#f8fafc"/><ellipse cx="200" cy="165" rx="130" ry="70" fill="#e2e8f0"/>
<ellipse cx="160" cy="165" rx="55" ry="38" fill="#fff7ed"/>
<ellipse cx="245" cy="150" rx="50" ry="32" fill="#7c2d12"/><ellipse cx="238" cy="146" rx="40" ry="22" fill="#9a3412"/>
<circle cx="235" cy="195" r="26" fill="#fff"/><circle cx="235" cy="195" r="11" fill="#facc15"/>
<rect x="120" y="120" width="70" height="18" rx="9" fill="#dc2626" transform="rotate(-12 155 129)"/>
<ellipse cx="290" cy="185" rx="22" ry="12" fill="#fbbf24"/><ellipse cx="170" cy="205" rx="20" ry="11" fill="#fbbf24"/>
<circle cx="290" cy="130" r="22" fill="#fde68a"/>''', 'Bandeja paisa'))
guardar('restaurante-2.svg', lienzo('#c2410c', '#7c2d12', '''
<path d="M105 140 Q200 40 295 140 Z" fill="#f59e0b"/><circle cx="160" cy="105" r="3" fill="#fde68a"/><circle cx="200" cy="90" r="3" fill="#fde68a"/><circle cx="240" cy="105" r="3" fill="#fde68a"/>
<path d="M100 142 q15 14 30 0 q15 14 30 0 q15 14 30 0 q15 14 30 0 q15 14 30 0 q15 14 30 0 v8 h-180z" fill="#4d7c0f"/>
<rect x="105" y="150" width="190" height="14" rx="7" fill="#dc2626"/>
<path d="M110 164 h180 l-12 22 h-156z" fill="#fbbf24"/>
<rect x="105" y="170" width="190" height="26" rx="13" fill="#451a03"/>
<path d="M105 200 h190 q0 32 -40 32 h-110 q-40 0 -40 -32z" fill="#f59e0b"/>''', 'Hamburguesa de la casa'))
guardar('restaurante-3.svg', lienzo('#a16207', '#713f12', '''
<ellipse cx="200" cy="155" rx="125" ry="82" fill="#fbbf24"/><ellipse cx="200" cy="155" rx="108" ry="66" fill="#fcd34d"/>
<path d="M95 155 Q200 120 305 155" stroke="#b45309" stroke-width="4" fill="none"/>
<path d="M110 150 q20 -30 45 -8 q25 -26 45 -4 q22 -24 48 0 q22 -22 42 12 q-40 30 -90 28 q-60 4 -90 -28z" fill="#f1f5f9"/>
<circle cx="150" cy="140" r="10" fill="#65a30d"/><circle cx="215" cy="136" r="12" fill="#84cc16"/><circle cx="262" cy="146" r="9" fill="#65a30d"/>''', 'Arepa rellena de pollo'))
guardar('restaurante-4.svg', lienzo('#4d7c0f', '#14532d', '''
<path d="M135 70 h130 l-18 160 q-2 14 -16 14 h-62 q-14 0 -16 -14z" fill="#fefce8" opacity=".92"/>
<path d="M141 110 h118 l-14 118 q-1 10 -12 10 h-66 q-11 0 -12 -10z" fill="#d9f99d"/>
<rect x="165" y="125" width="30" height="30" rx="6" fill="#fff" opacity=".7" transform="rotate(14 180 140)"/><rect x="210" y="150" width="30" height="30" rx="6" fill="#fff" opacity=".7" transform="rotate(-10 225 165)"/>
<circle cx="270" cy="82" r="36" fill="#a3e635"/><circle cx="270" cy="82" r="28" fill="#ecfccb"/><path d="M270 82 l0 -26 M270 82 l22 -14 M270 82 l22 14 M270 82 l0 26 M270 82 l-22 14 M270 82 l-22 -14" stroke="#a3e635" stroke-width="3"/>
<rect x="215" y="30" width="10" height="120" rx="5" fill="#f43f5e" transform="rotate(14 220 90)"/>''', 'Limonada de coco'))
guardar('restaurante-5.svg', lienzo('#be185d', '#831843', '''
<ellipse cx="200" cy="228" rx="120" ry="18" fill="#fff" opacity=".9"/>
<rect x="95" y="130" width="210" height="95" rx="10" fill="#fef3c7"/><rect x="95" y="168" width="210" height="26" fill="#fde68a"/>
<path d="M95 140 q20 -40 55 -18 q25 -34 55 -8 q28 -30 58 -4 q24 -14 42 30 z" fill="#fff"/>
<circle cx="200" cy="108" r="14" fill="#e11d48"/><path d="M200 94 q8 -22 22 -26" stroke="#365314" stroke-width="3" fill="none"/>
<rect x="95" y="190" width="210" height="4" fill="#f59e0b" opacity=".5"/>''', 'Tres leches'))

# ---------------- Veterinaria ----------------
PATA = '<ellipse cx="200" cy="175" rx="48" ry="40" fill="#fff"/><ellipse cx="135" cy="125" rx="20" ry="28" fill="#fff" transform="rotate(-20 135 125)"/><ellipse cx="180" cy="95" rx="20" ry="30" fill="#fff"/><ellipse cx="225" cy="95" rx="20" ry="30" fill="#fff"/><ellipse cx="268" cy="125" rx="20" ry="28" fill="#fff" transform="rotate(20 268 125)"/>'
guardar('veterinaria-1.svg', lienzo('#0f766e', '#134e4a', PATA + '<circle cx="290" cy="200" r="34" fill="#f43f5e"/><path d="M290 182 v36 M272 200 h36" stroke="#fff" stroke-width="9" stroke-linecap="round"/>', 'Consulta general'))
guardar('veterinaria-2.svg', lienzo('#0e7490', '#164e63', '''
<g transform="rotate(-35 200 150)"><rect x="110" y="132" width="150" height="36" rx="8" fill="#e0f2fe"/><rect x="118" y="140" width="95" height="20" rx="4" fill="#38bdf8"/>
<rect x="260" y="144" width="50" height="12" fill="#cbd5e1"/><rect x="305" y="150" width="2" height="0" fill="#fff"/><path d="M310 150 l34 0" stroke="#e2e8f0" stroke-width="4"/>
<rect x="90" y="126" width="22" height="48" rx="5" fill="#94a3b8"/><rect x="60" y="145" width="32" height="10" rx="3" fill="#64748b"/></g>
<circle cx="300" cy="220" r="8" fill="#fff" opacity=".8"/><circle cx="320" cy="235" r="5" fill="#fff" opacity=".6"/>''', 'Vacuna múltiple'))
guardar('veterinaria-3.svg', lienzo('#0369a1', '#0c4a6e', '''
<path d="M90 160 h220 q0 70 -50 70 h-120 q-50 0 -50 -70z" fill="#f8fafc"/><rect x="85" y="152" width="230" height="14" rx="7" fill="#e2e8f0"/>
<circle cx="150" cy="140" r="26" fill="#e0f2fe"/><circle cx="215" cy="118" r="34" fill="#fff"/><circle cx="262" cy="145" r="22" fill="#bae6fd"/><circle cx="190" cy="95" r="14" fill="#e0f2fe"/>
<circle cx="125" cy="106" r="10" fill="#bae6fd"/><circle cx="300" cy="104" r="12" fill="#e0f2fe"/>
<rect x="115" y="230" width="14" height="22" rx="4" fill="#94a3b8"/><rect x="271" y="230" width="14" height="22" rx="4" fill="#94a3b8"/>''', 'Baño y peluquería'))
guardar('veterinaria-4.svg', lienzo('#15803d', '#14532d', '''
<rect x="110" y="110" width="90" height="120" rx="14" fill="#f8fafc"/><rect x="125" y="86" width="60" height="30" rx="6" fill="#16a34a"/><rect x="122" y="140" width="76" height="50" rx="6" fill="#bbf7d0"/><path d="M160 150 v30 M145 165 h30" stroke="#15803d" stroke-width="8" stroke-linecap="round"/>
<g transform="rotate(-25 270 180)"><rect x="225" y="165" width="90" height="38" rx="19" fill="#fff"/><path d="M270 165 h28 a19 19 0 0 1 0 38 h-28z" fill="#f59e0b"/></g>
<g transform="rotate(20 300 120)"><rect x="262" y="105" width="64" height="28" rx="14" fill="#fff"/><path d="M294 105 h18 a14 14 0 0 1 0 28 h-18z" fill="#ef4444"/></g>''', 'Desparasitación'))
guardar('veterinaria-5.svg', lienzo('#7e22ce', '#4c1d95', '''
<path d="M200 235 C70 160 90 70 150 75 C175 78 192 92 200 110 C208 92 225 78 250 75 C310 70 330 160 200 235z" fill="#f43f5e"/>
<rect x="150" y="135" width="100" height="22" rx="11" fill="#fff" transform="rotate(-20 200 146)"/><rect x="150" y="135" width="100" height="22" rx="11" fill="#fde68a" transform="rotate(-20 200 146)" opacity=".6"/>
<path d="M300 215 v50 M275 240 h50" stroke="#fff" stroke-width="10" stroke-linecap="round"/>''', 'Esterilización canina'))

# ---------------- Aerolínea ----------------
AVION = '<path d="M60 160 L330 120 q30 -4 30 10 q0 14 -30 16 L250 160 L210 235 h-26 l22 -80 L120 168 L96 196 H74 l14 -34 L60 160z" fill="#fff"/>'
def ruta(a, b): return f'<path d="M60 250 Q200 190 340 250" stroke="#fff" stroke-width="3" fill="none" stroke-dasharray="6 8" opacity=".7"/><text x="60" y="275" font-family="Georgia,serif" font-size="20" fill="#fff" text-anchor="middle">{a}</text><text x="340" y="275" font-family="Georgia,serif" font-size="20" fill="#fff" text-anchor="middle">{b}</text>'
guardar('aerolinea-1.svg', lienzo('#1d4ed8', '#1e3a8a', '<g transform="translate(0 -30)">' + AVION + '</g>' + ruta('BOG', 'MDE')))
guardar('aerolinea-2.svg', lienzo('#0369a1', '#082f49', '<g transform="translate(0 -30)">' + AVION + '</g>' + ruta('BOG', 'CTG')))
guardar('aerolinea-3.svg', lienzo('#0d9488', '#134e4a', '<g transform="translate(0 -30)">' + AVION + '</g>' + ruta('BOG', 'ADZ')))
guardar('aerolinea-4.svg', lienzo('#4338ca', '#1e1b4b', '''
<rect x="150" y="60" width="100" height="40" rx="10" fill="none" stroke="#fff" stroke-width="10"/>
<rect x="110" y="90" width="180" height="150" rx="18" fill="#f59e0b"/><rect x="110" y="90" width="180" height="150" rx="18" fill="none" stroke="#fff" stroke-width="4" opacity=".5"/>
<rect x="150" y="90" width="12" height="150" fill="#b45309" opacity=".5"/><rect x="238" y="90" width="12" height="150" fill="#b45309" opacity=".5"/>
<rect x="175" y="150" width="50" height="22" rx="4" fill="#fff"/><circle cx="135" cy="248" r="9" fill="#1e293b"/><circle cx="265" cy="248" r="9" fill="#1e293b"/>''', 'Maleta de bodega 23 kg'))
guardar('aerolinea-5.svg', lienzo('#0891b2', '#164e63', '''
<rect x="140" y="50" width="120" height="110" rx="26" fill="#f1f5f9"/><rect x="128" y="130" width="144" height="82" rx="20" fill="#e2e8f0"/>
<rect x="105" y="120" width="30" height="85" rx="14" fill="#94a3b8"/><rect x="265" y="120" width="30" height="85" rx="14" fill="#94a3b8"/>
<rect x="150" y="212" width="16" height="30" rx="4" fill="#64748b"/><rect x="234" y="212" width="16" height="30" rx="4" fill="#64748b"/>
<circle cx="320" cy="75" r="26" fill="#22c55e"/><path d="M308 75 l9 10 l18 -20" stroke="#fff" stroke-width="7" fill="none" stroke-linecap="round" stroke-linejoin="round"/>''', 'Selección de asiento'))

# ---------------- Logos ----------------
def logo(nombre, c1, c2, simbolo):
    guardar(nombre, f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120" width="120" height="120"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>
<circle cx="60" cy="60" r="58" fill="url(#g)"/><circle cx="60" cy="60" r="52" fill="none" stroke="#fff" stroke-width="2" opacity=".6"/>{simbolo}</svg>''')
logo('logo-restaurante.svg', '#d97706', '#78350f', '<path d="M42 28 v26 a8 8 0 0 0 16 0 v-26 M50 28 v64 M78 28 q-14 14 -8 36 h8 v28" stroke="#fff" stroke-width="6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>')
logo('logo-veterinaria.svg', '#14b8a6', '#115e59', '<g fill="#fff" transform="translate(60 64) scale(.42) translate(-200 -140)">' + PATA + '</g>')
logo('logo-aerolinea.svg', '#3b82f6', '#1e3a8a', '<g transform="translate(60 62) scale(.3) translate(-210 -150)">' + AVION + '</g>')
print('Ilustraciones generadas en', out)
