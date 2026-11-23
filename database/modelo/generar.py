"""Valida las reglas del modelo y genera diagramas (Graphviz) y DBML."""
import html
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from modelo import TABLAS, AUDITORIA, nombre_completo, por_nombre, fks  # noqa: E402

SALIDA = os.path.join(os.path.dirname(__file__), "salida")
os.makedirs(SALIDA, exist_ok=True)
IDX = por_nombre()


# -----------------------------------------------------------------------------
# 1. Validación
# -----------------------------------------------------------------------------
def utiles(t):
    out = []
    for c, _tipo, flags, _d in t["columnas"]:
        fl = flags.split()
        if c in AUDITORIA or "pk" in fl or any(f.startswith("fk:") for f in fl):
            continue
        out.append(c)
    return out


def validar():
    errores, relaciones, transiciones = [], [], []
    for t in TABLAS:
        n = nombre_completo(t)
        unicos = [set(u) for u in t["unicos"]]
        unicos += [{c} for c, _ty, fl, _d in t["columnas"] if "uq" in fl.split()]
        for col, destino, nullable in fks(t):
            if destino not in IDX:
                errores.append(f"{n}.{col}: destino inexistente {destino}")
            # R1: una FK es 1-1 si la columna es única por sí sola. Si el destino vive dentro
            # de un tenant, la FK real es (tenant_id, col), así que también cuenta (tenant_id, col).
            # Si el destino es global (usuarios, plugins), tenant_id es el otro lado de la relación.
            destino_con_tenant = IDX.get(destino, {}).get("tenant", False)
            alcance = {col, "tenant_id"} if destino_con_tenant else {col}
            es_1a1 = any(col in u and u <= alcance for u in unicos)
            if es_1a1:
                errores.append(f"R1 · {n}.{col} → {destino} es una relación 1-1")
            relaciones.append(dict(origen=n, columna=col, destino=destino,
                                   opcional=nullable, tenant=(col == "tenant_id")))
        if not utiles(t):
            errores.append(f"R3 · {n} no tiene datos útiles además de llaves")
        if t["tipo"] == "transicion":
            if len([f for f in fks(t)]) < 2:
                errores.append(f"R2 · {n} es transición pero no une dos tablas")
            transiciones.append(dict(tabla=n, resuelve=t["resuelve"], datos=utiles(t),
                                     descripcion=t["descripcion"]))
    return errores, relaciones, transiciones


# -----------------------------------------------------------------------------
# 2. Diagramas Graphviz en notación pata de gallo
# -----------------------------------------------------------------------------
COLORES = {  # encabezado, cuerpo
    "entidad": ("#F4B6A6", "#FFFFFF"),
    "transicion": ("#A9CCE3", "#FFFFFF"),
    "referencia": ("#D5D8DC", "#FFFFFF"),
}
OCULTAS = {"creado_en", "actualizado_en"}


def nodo(t, completo=True):
    head, body = COLORES[t["tipo"]]
    n = nombre_completo(t)
    titulo = t["nombre"] if completo else n
    filas = [f'<TR><TD BGCOLOR="{head}" ALIGN="LEFT" COLSPAN="2" PORT="h">'
             f'<B>{html.escape(titulo)}</B></TD></TR>']
    if completo:
        for i, (c, tipo, flags, _d) in enumerate(t["columnas"]):
            if c in OCULTAS:
                continue
            fl = flags.split()
            marca = "PK" if "pk" in fl else ("FK" if any(f.startswith("fk:") for f in fl) else "")
            if "uq" in fl and not marca:
                marca = "UQ"
            bg = "#F2F3F4" if i % 2 else body
            nombre = html.escape(c)
            if marca == "PK":
                nombre = f"<U>{nombre}</U>"
            filas.append(
                f'<TR><TD BGCOLOR="{bg}" ALIGN="LEFT">{nombre}</TD>'
                f'<TD BGCOLOR="{bg}" ALIGN="RIGHT" PORT="{c}">'
                + (f'<FONT COLOR="#7B7D7D">{marca}</FONT>' if marca else ' ') + '</TD></TR>')
    estilo = "" if completo else ' STYLE="dashed"'
    return (f'"{n}" [label=<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="4"'
            f' COLOR="#566573"{estilo}>{"".join(filas)}</TABLE>>];')


def arista(rel, puertos=True):
    cabeza = "teeodot" if rel["opcional"] else "teetee"
    o, d = rel["origen"], rel["destino"]
    po = f':"{rel["columna"]}":e' if puertos else ""
    pd = ':"h":w' if o != d else ':"h":e'
    return (f'"{o}"{po} -> "{d}"{pd} [dir=both, arrowtail=crowodot, arrowhead={cabeza},'
            f' color="#566573", penwidth=1.1, arrowsize=0.9];')


def diagrama(archivo, titulo, esquemas, relaciones, extra_tablas=(), rankdir="LR", solo=None):
    propias = [t for t in TABLAS if (t["esquema"] in esquemas or nombre_completo(t) in extra_tablas)
               and (solo is None or t["nombre"] in solo)]
    nombres = {nombre_completo(t) for t in propias}
    rels = [r for r in relaciones if r["origen"] in nombres and not r["tenant"]]
    externas = {r["destino"] for r in rels if r["destino"] not in nombres}
    lineas = [
        "digraph G {",
        f'  graph [rankdir={rankdir}, splines=true, nodesep=0.35, ranksep=1.2, pad=0.3,'
        f' fontname="Helvetica", labelloc=t, fontsize=20, label=<<B>{html.escape(titulo)}</B>>];',
        '  node [shape=plain, fontname="Helvetica", fontsize=11];',
        '  edge [fontname="Helvetica"];',
    ]
    for t in propias:
        lineas.append("  " + nodo(t))
    for n in sorted(externas):
        lineas.append("  " + nodo(IDX[n], completo=False))
    for r in rels:
        lineas.append("  " + arista(r))
    lineas.append("}")
    dot = os.path.join(SALIDA, archivo + ".dot")
    with open(dot, "w") as f:
        f.write("\n".join(lineas))
    for fmt in ("png", "svg"):
        args = ["dot", f"-T{fmt}", dot, "-o", os.path.join(SALIDA, f"{archivo}.{fmt}")]
        if fmt == "png":
            args.insert(1, "-Gdpi=130")
        subprocess.run(args, check=True)


def diagrama_general(relaciones):
    """Vista general: solo nombres de tabla agrupados por esquema."""
    grupos = {}
    for t in TABLAS:
        grupos.setdefault(t["esquema"], []).append(t)
    etiquetas = {"platform": "platform · lógica del tenant", "audit": "audit",
                 "elius": "elius · núcleo", "ext": "ext · extensión Chrome",
                 "plugin_vet": "plugin_vet", "plugin_restaurant": "plugin_restaurant",
                 "plugin_airline": "plugin_airline"}
    lineas = ["digraph G {",
              '  graph [rankdir=LR, splines=true, nodesep=0.25, ranksep=1.1, pad=0.3, compound=true,'
              ' fontname="Helvetica", labelloc=t, fontsize=22,'
              ' label=<<B>Elius · vista general del modelo E/R</B>>];',
              '  node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11, color="#566573"];']
    for esq, ts in grupos.items():
        lineas.append(f'  subgraph "cluster_{esq}" {{ label=<<B>{etiquetas[esq]}</B>>; fontsize=14;'
                      ' style="rounded"; color="#99A3A4";')
        for t in ts:
            lineas.append(f'    "{nombre_completo(t)}" [label="{t["nombre"]}", fillcolor="{COLORES[t["tipo"]][0]}"];')
        lineas.append("  }")
    for r in relaciones:
        if r["tenant"]:
            continue
        lineas.append(f'  "{r["origen"]}" -> "{r["destino"]}" [dir=both, arrowtail=crowodot,'
                      f' arrowhead={"teeodot" if r["opcional"] else "teetee"}, color="#85929E", arrowsize=0.6];')
    lineas.append("}")
    dot = os.path.join(SALIDA, "00_vista_general.dot")
    with open(dot, "w") as f:
        f.write("\n".join(lineas))
    subprocess.run(["dot", "-Tpng", "-Gdpi=110", dot, "-o", os.path.join(SALIDA, "00_vista_general.png")], check=True)
    subprocess.run(["dot", "-Tsvg", dot, "-o", os.path.join(SALIDA, "00_vista_general.svg")], check=True)


def vista(archivo, titulo, esquemas, relaciones):
    """Vista general de un grupo de esquemas; las tablas de otros esquemas salen punteadas."""
    etiquetas = {"platform": "platform · lógica del tenant", "audit": "audit · auditoría",
                 "elius": "elius · núcleo de negocio", "ext": "ext · extensión Chrome",
                 "plugin_vet": "plugin_vet · veterinaria", "plugin_restaurant": "plugin_restaurant · restaurante",
                 "plugin_airline": "plugin_airline · aerolínea"}
    propias = [t for t in TABLAS if t["esquema"] in esquemas]
    nombres = {nombre_completo(t) for t in propias}
    rels = [r for r in relaciones if r["origen"] in nombres and not r["tenant"]]
    externas = sorted({r["destino"] for r in rels if r["destino"] not in nombres})
    lineas = ["digraph G {",
              '  graph [rankdir=LR, splines=true, nodesep=0.25, ranksep=1.0, pad=0.3,'
              f' fontname="Helvetica", labelloc=t, fontsize=22, label=<<B>{html.escape(titulo)}</B>>];',
              '  node [shape=box, style="rounded,filled", fontname="Helvetica", fontsize=11, color="#566573"];']
    for esq in esquemas:
        ts = [t for t in propias if t["esquema"] == esq]
        lineas.append(f'  subgraph "cluster_{esq}" {{ label=<<B>{etiquetas[esq]}</B>>; fontsize=14;'
                      ' style="rounded"; color="#99A3A4";')
        for t in ts:
            lineas.append(f'    "{nombre_completo(t)}" [label="{t["nombre"]}", fillcolor="{COLORES[t["tipo"]][0]}"];')
        lineas.append("  }")
    if externas:
        lineas.append('  subgraph "cluster_ext_refs" { label=<<B>tablas del modelo general que usan</B>>;'
                      ' fontsize=14; style="rounded,dashed"; color="#99A3A4";')
        for n in externas:
            lineas.append(f'    "{n}" [label="{n}", fillcolor="#FFFFFF", style="rounded,dashed"];')
        lineas.append("  }")
    for r in rels:
        lineas.append(f'  "{r["origen"]}" -> "{r["destino"]}" [dir=both, arrowtail=crowodot,'
                      f' arrowhead={"teeodot" if r["opcional"] else "teetee"}, color="#85929E", arrowsize=0.6];')
    lineas.append("}")
    dot = os.path.join(SALIDA, archivo + ".dot")
    with open(dot, "w") as f:
        f.write("\n".join(lineas))
    subprocess.run(["dot", "-Tpng", "-Gdpi=110", dot, "-o", os.path.join(SALIDA, archivo + ".png")], check=True)
    subprocess.run(["dot", "-Tsvg", dot, "-o", os.path.join(SALIDA, archivo + ".svg")], check=True)


# -----------------------------------------------------------------------------
# 3. DBML para dbdiagram.io
# -----------------------------------------------------------------------------
def dbml(relaciones):
    out = ["// Elius · modelo entidad-relación", "// Generado desde modelo/modelo.py", ""]
    for t in TABLAS:
        n = nombre_completo(t)
        out.append(f"Table {n} [note: '{t['descripcion']} ({t['tipo']})'] {{")
        for c, tipo, flags, d in t["columnas"]:
            fl = flags.split()
            attrs = []
            if "pk" in fl:
                attrs.append("pk")
            if "uq" in fl:
                attrs.append("unique")
            attrs.append("null" if "null" in fl else "not null")
            marcas = []
            if "S" in fl:
                marcas.append("SENSIBLE")
            if "R" in fl:
                marcas.append("RESTRINGIDO")
            if "P" in fl:
                marcas.append("PERSONAL")
            nota = d + (f" [{', '.join(marcas)}]" if marcas else "")
            attrs.append("note: '" + nota.replace("'", "´") + "'")
            out.append(f'  {c} "{tipo}" [{", ".join(attrs)}]')
        if t["unicos"]:
            out.append("  indexes {")
            for u in t["unicos"]:
                out.append(f"    ({', '.join(u)}) [unique]")
            out.append("  }")
        out.append("}\n")
    for r in relaciones:
        out.append(f"Ref: {r['origen']}.{r['columna']} > {r['destino']}.id")
    grupos = [("modelo_general_platform", ["platform", "audit"]), ("modelo_general_elius", ["elius"]),
              ("modelo_general_ext", ["ext"]), ("plugin_vet", ["plugin_vet"]),
              ("plugin_restaurant", ["plugin_restaurant"]), ("plugin_airline", ["plugin_airline"])]
    out.append("")
    for nombre, esqs in grupos:
        out.append(f"TableGroup {nombre} {{")
        out += [f"  {nombre_completo(t)}" for t in TABLAS if t["esquema"] in esqs]
        out.append("}\n")
    with open(os.path.join(SALIDA, "elius_modelo.dbml"), "w") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    errores, relaciones, transiciones = validar()
    resumen = dict(
        tablas=len(TABLAS),
        por_tipo={k: sum(1 for t in TABLAS if t["tipo"] == k) for k in COLORES},
        relaciones=len(relaciones),
        relaciones_sin_tenant=sum(1 for r in relaciones if not r["tenant"]),
        transiciones=transiciones,
        errores=errores,
    )
    with open(os.path.join(SALIDA, "validacion.json"), "w") as f:
        json.dump(resumen, f, ensure_ascii=False, indent=2)
    print(json.dumps({k: v for k, v in resumen.items() if k != "transiciones"}, ensure_ascii=False, indent=2))
    if errores:
        sys.exit(1)
    diagrama_general(relaciones)
    vista("00a_modelo_general", "Elius · modelo general (núcleo de la plataforma)",
          ["platform", "audit", "elius", "ext"], relaciones)
    vista("00b_plugins", "Elius · plugins y cómo se conectan al modelo general",
          ["plugin_vet", "plugin_restaurant", "plugin_airline"], relaciones)
    diagrama("01_platform", "platform · lógica del tenant (+ audit)", ["platform", "audit"], relaciones)
    grupos_nucleo = {
        "02a_elius_conversaciones": ("elius · contactos, canales y conversaciones con Eli",
            {"contactos", "direcciones", "consentimientos", "agentes", "canales", "identidades_contacto",
             "conversaciones", "mensajes", "consumos_llm", "escalamientos", "eventos_embudo", "errores_agente"}),
        "02b_elius_catalogo_reservas": ("elius · catálogo y reservas",
            {"categorias_catalogo", "items_catalogo", "item_adicionales", "medios_item", "recursos",
             "horarios_atencion", "reservas", "asignaciones_recurso"}),
        "02c_elius_ordenes_pagos": ("elius · órdenes, pagos, comprobantes y entregas",
            {"ordenes", "orden_items", "pagos", "comprobantes_pago", "entregas"}),
        "02e_elius_factus_pay": ("elius · cobro por llave Bre-B con Factus Pay",
            {"pasarelas_pago", "recaudos", "notificaciones_pasarela", "pagos", "ordenes"}),
        "02d_elius_configuracion": ("elius · conocimiento de Eli, configuración y eventos",
            {"documentos_conocimiento", "fragmentos_conocimiento", "eventos_salida",
             "parametros_negocio", "suscripciones_push"}),
    }
    cubiertas = set().union(*[g[1] for g in grupos_nucleo.values()])
    faltan = {t["nombre"] for t in TABLAS if t["esquema"] == "elius"} - cubiertas
    assert not faltan, f"Tablas del núcleo sin diagrama: {faltan}"
    for archivo, (titulo, solo) in grupos_nucleo.items():
        diagrama(archivo, titulo, ["elius"], relaciones, solo=solo)
    diagrama("03_ext_chrome", "ext · extensión de Chrome", ["ext"], relaciones)
    diagrama("04_plugin_vet", "plugin_vet · veterinaria", ["plugin_vet"], relaciones)
    diagrama("05_plugin_restaurant", "plugin_restaurant · restaurante", ["plugin_restaurant"], relaciones)
    diagrama("06_plugin_airline", "plugin_airline · aerolínea", ["plugin_airline"], relaciones)
    dbml(relaciones)
    print("OK: diagramas y DBML generados en", SALIDA)
