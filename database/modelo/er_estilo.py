"""Genera los diagramas E/R en estilo legible (módulos con color, relaciones con nombre).
Uso: python3 er_estilo.py ../../docs/05_base_de_datos/er   (necesita Graphviz)"""
import html, os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from modelo import TABLAS, nombre_completo, fks

SALIDA = sys.argv[1] if len(sys.argv) > 1 and __name__ == "__main__" else "er"
if __name__ == "__main__":
    os.makedirs(SALIDA, exist_ok=True)

# (archivo, título, color de encabezado, [esquema.tabla...]) · "general" o "plugin"
M = [
 ("01-cuentas-y-planes", "Cuentas, planes y plugins", "#031641", "general",
  "platform.planes platform.tenants platform.usuarios platform.plugins platform.tenant_plugins platform.consumos_periodo platform.llaves_api"),
 ("02-roles-y-accesos", "Roles, permisos, accesos y auditoría", "#0033DD", "general",
  "platform.roles platform.permisos platform.rol_permisos platform.membresias platform.accesos_especiales platform.asignaciones_plataforma platform.accesos_soporte platform.accesos_bd platform.invitaciones audit.registros_auditoria"),
 ("03-contactos-y-canales", "Contactos y canales", "#2E3F6B", "general",
  "elius.contactos elius.direcciones elius.consentimientos elius.canales elius.identidades_contacto"),
 ("04-conversaciones-con-eli", "Conversaciones con Eli", "#1E5AA8", "general",
  "elius.agentes elius.conversaciones elius.mensajes elius.consumos_llm elius.escalamientos elius.eventos_embudo elius.errores_agente"),
 ("05-catalogo-y-reservas", "Catálogo y reservas", "#4A5A82", "general",
  "elius.categorias_catalogo elius.items_catalogo elius.item_adicionales elius.medios_item elius.recursos elius.horarios_atencion elius.reservas elius.asignaciones_recurso"),
 ("06-ordenes-y-pagos", "Órdenes, pagos y Factus Pay", "#0B6E4F", "general",
  "elius.ordenes elius.orden_items elius.entregas elius.pagos elius.comprobantes_pago elius.pasarelas_pago elius.recaudos elius.notificaciones_pasarela"),
 ("07-configuracion-y-conocimiento", "Configuración, avisos y conocimiento de Eli", "#6B4C9A", "general",
  "elius.parametros_negocio platform.ajustes_globales platform.push_suscripciones elius.suscripciones_push elius.documentos_conocimiento elius.fragmentos_conocimiento elius.eventos_salida"),
 ("12-soporte-y-tickets", "Soporte: tickets, cronología y manual", "#7C3AED", "general",
  "elius.tickets elius.ticket_notas elius.manual_soporte"),
 ("08-extension-chrome", "Extensión de Chrome", "#8A4B08", "general",
  " ".join(f"ext.{n}" for n in "instalaciones_extension sitios_autorizados conversaciones_capturadas mensajes_capturados patrones evidencias_patron".split())),
 ("09-plugin-veterinaria", "PLUGIN · Veterinaria", "#B5174B", "plugin",
  " ".join(f"plugin_vet.{n}" for n in "mascotas propietarios_mascota atenciones registros_clinicos aplicaciones_vacuna".split())),
 ("10-plugin-restaurante", "PLUGIN · Restaurante", "#C2410C", "plugin",
  " ".join(f"plugin_restaurant.{n}" for n in "alergenos item_alergenos grupos_modificador opciones_modificador item_grupos_modificador orden_item_opciones estaciones_cocina comandas comanda_items menus_dia menu_dia_items celebraciones".split())),
 ("11-plugin-aerolinea", "PLUGIN · Aerolínea", "#0E7490", "plugin",
  " ".join(f"plugin_airline.{n}" for n in "aeropuertos aeronaves rutas vuelos tarifas_vuelo reserva_pasajeros tramos_reserva tiquetes equipajes".split())),
]
MOD = {}
for i, (_a, _t, _c, _g, ts) in enumerate(M):
    for n in ts.split():
        MOD[n] = i
IDX = {nombre_completo(t): t for t in TABLAS}
faltan = [n for n in IDX if n not in MOD]
assert not faltan, faltan
OCULTAS = {"tenant_id", "creado_en", "actualizado_en"}
TIPO = {"timestamptz": "fecha", "numeric": "num", "integer": "int", "boolean": "bool", "jsonb": "json"}


def corto(t):
    t = t.split("(")[0].strip()
    return TIPO.get(t, t)


def nodo(n, completo):
    t = IDX[n]
    head = M[MOD[n]][2]
    nom = html.escape(t["nombre"].upper())
    if not completo:
        return (f'"{n}" [label=<<table border="1" cellborder="0" cellspacing="0" cellpadding="6" color="#8A93A3" bgcolor="white">'
                f'<tr><td bgcolor="{head}"><font color="white" face="Helvetica-Bold" point-size="13">{nom}</font></td></tr></table>>];')
    marca = "<font color='#B45309'>TRANSICIÓN</font>" if t["tipo"] == "transicion" else ""
    filas = [f'<tr><td bgcolor="{head}" colspan="3"><font color="white" face="Helvetica-Bold" point-size="14">{nom}</font></td></tr>']
    k = 0
    for c, ty, fl, _d in t["columnas"]:
        if c in OCULTAS:
            continue
        f = fl.split()
        mk = "PK" if "pk" in f else ("FK" if any(x.startswith("fk:") for x in f) else ("UQ" if "uq" in f else ""))
        bg = "#E9EEFC" if mk in ("PK", "FK") else ("#FFFFFF" if k % 2 == 0 else "#F5F7FB")
        k += 1
        filas.append(f'<tr><td bgcolor="{bg}" align="left"><font color="#5A6475" point-size="10">{html.escape(corto(ty))}</font></td>'
                     f'<td bgcolor="{bg}" align="left" port="{c}">{html.escape(c)}</td>'
                     f'<td bgcolor="{bg}" align="right">{('<font color="#0033DD" point-size="10"><b>'+mk+'</b></font>') if mk else ' '}</td></tr>')
    return (f'"{n}" [label=<<table border="1" cellborder="0" cellspacing="0" cellpadding="4" color="#8A93A3" bgcolor="white">'
            f'{"".join(filas)}</table>>];')


def relaciones():
    out = []
    for t in TABLAS:
        o = nombre_completo(t)
        for col, dest, nulo in fks(t):
            if col == "tenant_id":
                continue
            out.append((o, col, dest, nulo))
    return out


def arista(o, col, d, nulo):
    et = html.escape(col[:-3] if col.endswith("_id") else col)
    cab = "teeodot" if nulo else "teetee"
    return (f'"{o}" -> "{d}" [dir=both, arrowtail=crowodot, arrowhead={cab}, color="#5A6475", penwidth=1.3,'
            f' arrowsize=0.9, fontsize=10, fontcolor="#5A6475", label="{et}"];')


def dibujar(archivo, titulo, propias, rels, compacto=False, rank="TB"):
    propias = set(propias)
    vecinas = sorted({x for o, _c, d, _n in rels for x in (o, d)} - propias)
    L = ["digraph G {", f'  graph [rankdir={rank}, splines=true, nodesep=0.5, ranksep=0.9, pad=0.4, fontname="Helvetica",'
         f' labelloc=t, fontsize=30, label=<<b>{html.escape(titulo)}</b>>, newrank=true];',
         '  node [shape=plain, fontname="Helvetica", fontsize=12];']
    grupos = {}
    for n in list(propias) + vecinas:
        grupos.setdefault(MOD[n], []).append(n)
    for i, ns in sorted(grupos.items()):
        L.append(f'  subgraph "cluster_{i}" {{ label=<<b>{html.escape(M[i][1])}</b>>; fontsize=16; fontname="Helvetica-Bold";'
                 f' style="rounded,filled"; fillcolor="#F5F7FB"; color="#DDE2EE"; fontcolor="{M[i][2]}";')
        for n in ns:
            L.append("    " + nodo(n, n in propias and not compacto))
        L.append("  }")
    for r in rels:
        L.append("  " + arista(*r))
    L.append("}")
    dot = os.path.join(SALIDA, archivo + ".dot")
    open(dot, "w").write("\n".join(L))
    subprocess.run(["dot", "-Tsvg", dot, "-o", os.path.join(SALIDA, archivo + ".svg")], check=True)
    subprocess.run(["dot", "-Tpng", "-Gdpi=110", dot, "-o", os.path.join(SALIDA, archivo + ".png")], check=True)
    os.remove(dot)


R = relaciones()
if __name__ == "__main__":
    # Vistas por módulo
    for i, (a, tit, _c, _g, ts) in enumerate(M):
        p = set(ts.split())
        dibujar(a, tit, p, [r for r in R if r[0] in p or (r[2] in p and False)])
    # Modelo general completo y plugins completos
    for archivo, tit, grupo in (("00a-modelo-general-completo", "Elius · Modelo general (todas las tablas)", "general"),
                                ("00b-plugins-completo", "Elius · Plugins: veterinaria, restaurante y aerolínea", "plugin"),
                                ("00-modelo-er-completo", "Elius · Modelo E/R completo (87 tablas)", None)):
        p = {n for n in IDX if grupo is None or M[MOD[n]][3] == grupo}
        dibujar(archivo, tit, p, [r for r in R if r[0] in p and r[2] in p])
    print("ok", len(os.listdir(SALIDA)))
