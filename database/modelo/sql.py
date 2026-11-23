"""Genera la migración SQL de tablas, llaves y comentarios a partir de modelo.py."""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from modelo import TABLAS, nombre_completo, por_nombre, fks  # noqa: E402
from dominios import CHECKS, DEFAULTS_COLUMNA, DEFAULTS_NOMBRE  # noqa: E402

IDX = por_nombre()
TIPOS = {"vector(1536)": "extensions.vector(1536)"}
# Destinos que no se borran en cascada: catálogos y configuración (se bloquea el borrado)
RESTRICT = {"items_catalogo", "categorias_catalogo", "roles", "permisos", "plugins", "planes",
            "aeropuertos", "aeronaves", "rutas", "estaciones_cocina", "agentes", "canales",
            "alergenos", "grupos_modificador", "opciones_modificador", "pasarelas_pago",
            "sitios_autorizados", "recursos", "tarifas_vuelo"}


def q(s):
    return "'" + s.replace("'", "''") + "'"


def destino_sql(destino):
    return "auth.users" if destino == "platform.usuarios" else destino


def columna_sql(t, c, tipo, flags):
    fl = flags.split()
    clave = f"{nombre_completo(t)}.{c}"
    partes = [f"  {c}", TIPOS.get(tipo, tipo)]
    if "pk" in fl:
        partes.append("primary key default gen_random_uuid()")
        return " ".join(partes)
    if c == "tenant_id" and t["tenant"]:
        partes.append("not null default app.current_tenant_id()")
        return " ".join(partes)
    if "null" not in fl:
        partes.append("not null")
    default = DEFAULTS_COLUMNA.get(clave, DEFAULTS_NOMBRE.get(c))
    if default:
        partes.append(f"default {default}")
    if "uq" in fl:
        partes.append("unique")
    if clave in CHECKS:
        valores = ", ".join(q(v) for v in CHECKS[clave])
        partes.append(f"\n      constraint ck_{t['nombre'][:40]}_{c[:20]} check ({c} in ({valores}))")
    return " ".join(partes)


def generar():
    out = ["-- =============================================================================",
           "-- ELIUS · Migración 0200 · Tablas (generado desde modelo/modelo.py)",
           "-- No editar a mano: cambiar modelo.py o dominios.py y volver a generar.",
           "-- Las llaves foráneas van al final para no depender del orden de creación.",
           "-- =============================================================================", ""]
    fk_sql, comentarios = [], []
    for t in TABLAS:
        if t["externa"]:
            continue  # platform.usuarios = auth.users de Supabase
        n = nombre_completo(t)
        cols = [columna_sql(t, c, tipo, flags) for c, tipo, flags, _d in t["columnas"]]
        restr = []
        if t["tenant"]:
            restr.append(f"  constraint uq_{t['nombre'][:45]}_tenant_id unique (tenant_id, id)")
        for i, u in enumerate(t["unicos"], 1):
            restr.append(f"  constraint uq_{t['nombre'][:45]}_{i} unique ({', '.join(u)})")
        out.append(f"create table {n} (")
        out.append(",\n".join(cols + restr))
        out.append(");\n")
        comentarios.append(f"comment on table {n} is {q(t['descripcion'] + ' [' + t['tipo'] + ']')};")
        for c, _tipo, flags, d in t["columnas"]:
            marcas = [m for m, txt in (("S", "SENSIBLE"), ("R", "RESTRINGIDO"), ("P", "PERSONAL"))
                      if m in flags.split()]
            extra = " [" + ", ".join({"S": "SENSIBLE", "R": "RESTRINGIDO", "P": "PERSONAL"}[m]
                                    for m in marcas) + "]" if marcas else ""
            comentarios.append(f"comment on column {n}.{c} is {q(d + extra)};")
        # llaves foráneas
        for col, destino, nullable in fks(t):
            if col == "tenant_id" and t["tenant"]:
                fk_sql.append(f"alter table {n} add constraint fk_{t['nombre'][:40]}_tenant "
                              f"foreign key (tenant_id) references platform.tenants (id) on delete cascade;")
                continue
            dest = IDX[destino]
            nombre_fk = f"fk_{t['nombre'][:30]}_{col[:25]}"
            if nullable:
                accion = f"on delete set null ({col})"
            elif dest["nombre"] in RESTRICT:
                accion = "on delete restrict"
            else:
                accion = "on delete cascade"
            if t["tenant"] and dest["tenant"]:
                # FK compuesta: garantiza que el destino sea del mismo tenant (DT-07)
                fk_sql.append(f"alter table {n} add constraint {nombre_fk} foreign key (tenant_id, {col}) "
                              f"references {destino} (tenant_id, id) {accion};")
            else:
                accion_simple = "on delete set null" if nullable else accion
                fk_sql.append(f"alter table {n} add constraint {nombre_fk} foreign key ({col}) "
                              f"references {destino_sql(destino)} (id) {accion_simple};")
    out.append("-- -----------------------------------------------------------------------------")
    out.append("-- Llaves foráneas. Si origen y destino viven en un tenant, la llave es compuesta")
    out.append("-- (tenant_id, columna): un registro nunca puede apuntar a otro tenant.")
    out.append("-- -----------------------------------------------------------------------------")
    out += fk_sql
    out.append("")
    out.append("-- -----------------------------------------------------------------------------")
    out.append("-- Índices: toda llave foránea indexada empezando por tenant_id (DT-06)")
    out.append("-- -----------------------------------------------------------------------------")
    for t in TABLAS:
        if t["externa"]:
            continue
        n = nombre_completo(t)
        for col, destino, _nullable in fks(t):
            if col == "tenant_id":
                continue
            cols = f"tenant_id, {col}" if t["tenant"] else col
            out.append(f"create index ix_{t['nombre'][:35]}_{col[:20]} on {n} ({cols});")
    out.append("")
    out.append("-- -----------------------------------------------------------------------------")
    out.append("-- Comentarios: el diccionario de datos vive también dentro de la base")
    out.append("-- -----------------------------------------------------------------------------")
    out += comentarios
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    destino = sys.argv[1]
    with open(destino, "w") as f:
        f.write(generar())
    print("escrito", destino)
