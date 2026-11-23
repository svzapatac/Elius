"""
Genera la documentación de la base de datos que se puede derivar automáticamente:
  - diccionario de datos y relaciones (desde modelo.py)
  - inventario de triggers, políticas RLS, vistas, procedimientos y matriz de permisos
    (consultando la base de prueba ya migrada, para que el documento refleje lo que corre)
Uso: python3 documentar.py <carpeta_docs> [conexión psql]
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(__file__))
from modelo import TABLAS, nombre_completo, por_nombre, fks  # noqa: E402
from dominios import CHECKS, DEFAULTS_COLUMNA, DEFAULTS_NOMBRE  # noqa: E402
from sql import RESTRICT  # noqa: E402

IDX = por_nombre()
GRUPOS = [("Modelo general", ["platform", "audit", "elius", "ext"]),
          ("Plugins", ["plugin_vet", "plugin_restaurant", "plugin_airline"])]
PRIV = {"S": "Sensible", "R": "Restringido", "P": "Personal"}
AVISO = "> Archivo generado por `database/modelo/documentar.py`. No editar a mano.\n"


def celda(s):
    return str(s).replace("|", "\\|").replace("\n", " ")


def diccionario():
    out = ["# Diccionario de datos", "", AVISO,
           "Cada tabla con sus columnas: tipo, si admite nulos, valor por defecto, restricción de dominio, "
           "descripción y nivel de privacidad (Ley 1581). Todas las tablas de negocio tienen además "
           "`creado_en` y `actualizado_en`.", "",
           "**Privacidad:** *Personal* = dato personal; *Sensible* = dato sensible del art. 5 de la Ley 1581; "
           "*Restringido* = solo con permiso especial.", "",
           "**Tipo de tabla:** *entidad*, *transición* (resuelve un muchos a muchos y guarda datos propios) o "
           "*referencia* (catálogo global).", ""]
    for grupo, esquemas in GRUPOS:
        out.append(f"## {grupo}\n")
        for esq in esquemas:
            ts = [t for t in TABLAS if t["esquema"] == esq]
            out.append(f"### Esquema `{esq}` ({len(ts)} tablas)\n")
            for t in ts:
                n = nombre_completo(t)
                extra = " · tabla de Supabase Auth (`auth.users`)" if t["externa"] else ""
                out.append(f"#### `{n}`\n")
                out.append(f"{t['descripcion']}. Tipo: **{t['tipo']}**{extra}.")
                if t["resuelve"]:
                    a, b = t["resuelve"]
                    out.append(f" Resuelve el muchos a muchos entre `{a}` y `{b}`.")
                out.append("\n")
                out.append("| Columna | Tipo | Nulo | Por defecto | Restricción | Descripción | Privacidad |")
                out.append("| --- | --- | --- | --- | --- | --- | --- |")
                for c, tipo, flags, d in t["columnas"]:
                    fl = flags.split()
                    clave = f"{n}.{c}"
                    restr = []
                    if "pk" in fl:
                        restr.append("PK")
                    for f in fl:
                        if f.startswith("fk:"):
                            restr.append(f"FK → `{f[3:]}`")
                    if "uq" in fl:
                        restr.append("UNIQUE")
                    if clave in CHECKS:
                        restr.append("IN (" + ", ".join(CHECKS[clave]) + ")")
                    if c == "tenant_id" and t["tenant"]:
                        defecto = "app.current_tenant_id()"
                    elif "pk" in fl:
                        defecto = "gen_random_uuid()"
                    else:
                        defecto = DEFAULTS_COLUMNA.get(clave, DEFAULTS_NOMBRE.get(c, ""))
                    nulo = "sí" if "null" in fl else "no"
                    priv = ", ".join(PRIV[m] for m in ("S", "R", "P") if m in fl)
                    out.append(f"| `{c}` | {tipo} | {nulo} | {celda(defecto)} | {celda('; '.join(restr))} | {celda(d)} | {priv} |")
                if t["unicos"]:
                    out.append("")
                    out.append("Únicos: " + "; ".join("(" + ", ".join(u) + ")" for u in t["unicos"]))
                out.append("")
    return "\n".join(out)


def relaciones():
    filas, transiciones = [], []
    for t in TABLAS:
        n = nombre_completo(t)
        for col, destino, nullable in fks(t):
            dest = IDX[destino]
            compuesta = t["tenant"] and dest["tenant"] and col != "tenant_id"
            if col == "tenant_id":
                accion = "CASCADE"
            elif nullable:
                accion = "SET NULL"
            elif dest["nombre"] in RESTRICT:
                accion = "RESTRICT"
            else:
                accion = "CASCADE"
            card = "0..1 a 0..N" if nullable else "1 a 0..N"
            filas.append((t["esquema"], n, col, destino, card, "sí" if compuesta else "no", accion))
        if t["tipo"] == "transicion":
            a, b = t["resuelve"]
            from generar import utiles  # noqa: E402
            transiciones.append((n, a, b, ", ".join(utiles(t))))
    out = ["# Relaciones", "", AVISO,
           f"El modelo tiene **{len(filas)} relaciones**, todas de uno a muchos. No hay relaciones 1 a 1 ni "
           "muchos a muchos directas; el script `generar.py` lo verifica cada vez que se genera el modelo.", "",
           "- **Cardinalidad** se lee desde la tabla padre hacia la tabla hija: `1 a 0..N` = un padre tiene cero o "
           "muchos hijos y cada hijo tiene exactamente un padre; `0..1 a 0..N` = el hijo puede no tener padre (FK opcional).",
           "- **Compuesta = sí**: la llave es `(tenant_id, columna)` → `(tenant_id, id)`, así una fila nunca apunta a "
           "otro tenant (DT-07).",
           "- **Al borrar el padre**: CASCADE borra los hijos; SET NULL deja el hijo sin padre; RESTRICT impide "
           "borrar catálogos y configuración que están en uso.", "",
           f"## Tablas de transición ({len(transiciones)})", "",
           "| Tabla | Resuelve el muchos a muchos entre | Datos propios de la relación |", "| --- | --- | --- |"]
    out += [f"| `{a}` | `{b}` y `{c}` | {d} |" for a, b, c, d in transiciones]
    for grupo, esquemas in GRUPOS:
        out += ["", f"## {grupo}", ""]
        for esq in esquemas:
            fs = [f for f in filas if f[0] == esq]
            if not fs:
                continue
            out += [f"### `{esq}` ({len(fs)} relaciones)", "",
                    "| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |",
                    "| --- | --- | --- | --- | --- | --- |"]
            out += [f"| `{f[1]}` | `{f[2]}` | `{f[3]}` | {f[4]} | {f[5]} | {f[6]} |" for f in fs]
    return "\n".join(out)


def consulta(conn, sql):
    r = subprocess.run(conn + ["-At", "-F", "\t", "-c", sql], capture_output=True, text=True, check=True)
    return [linea.split("\t") for linea in r.stdout.rstrip("\n").splitlines() if linea.strip()]


def inventario(conn):
    esquemas = "('platform','elius','ext','audit','plugin_vet','plugin_restaurant','plugin_airline','reportes','app')"
    trig = consulta(conn, f"""
      select n.nspname || '.' || c.relname, t.tgname, p.proname,
             case when t.tgtype & 2 = 2 then 'BEFORE' else 'AFTER' end ||
             case when t.tgtype & 4 = 4 then ' INSERT' else '' end ||
             case when t.tgtype & 16 = 16 then ' UPDATE' else '' end ||
             case when t.tgtype & 8 = 8 then ' DELETE' else '' end
      from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = t.tgfoid
      where not t.tgisinternal and n.nspname in {esquemas} and t.tgname not like 't01_%' and t.tgname not like 't02_%'
      order by 1, 2""")
    n_t01 = consulta(conn, "select count(*) from pg_trigger where tgname = 't01_actualizado_en'")[0][0]
    n_t02 = consulta(conn, "select count(*) from pg_trigger where tgname = 't02_auditoria'")[0][0]
    pol = consulta(conn, f"""
      select schemaname || '.' || tablename, policyname, cmd, permissive,
             regexp_replace(coalesce(qual, with_check, ''), '\\s+', ' ', 'g')
      from pg_policies where schemaname in {esquemas} order by 1, 2""")
    vis = consulta(conn, f"""
      select n.nspname || '.' || c.relname, coalesce(obj_description(c.oid), ''),
             coalesce((select 'sí' from unnest(c.reloptions) o where o = 'security_invoker=true'), 'no')
      from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where c.relkind = 'v' and n.nspname in {esquemas} order by 1""")
    fun = consulta(conn, f"""
      select n.nspname || '.' || p.proname, pg_get_function_identity_arguments(p.oid),
             case when p.prosecdef then 'DEFINER' else 'INVOKER' end, coalesce(obj_description(p.oid), '')
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('platform','elius','plugin_vet','plugin_restaurant','plugin_airline','app')
        and p.prorettype <> 'trigger'::regtype order by 1""")
    perm = consulta(conn, """
      select coalesce(pl.codigo, 'núcleo'), p.codigo, p.es_acceso_especial,
             max(rp.nivel) filter (where r.codigo = 'super_admin'),
             max(rp.nivel) filter (where r.codigo = 'soporte'),
             max(rp.nivel) filter (where r.codigo = 'administrador'),
             max(rp.nivel) filter (where r.codigo = 'operador'),
             max(rp.nivel) filter (where r.codigo = 'analista'),
             max(rp.nivel) filter (where r.codigo = 'eli')
      from platform.permisos p left join platform.plugins pl on pl.id = p.plugin_id
      left join platform.rol_permisos rp on rp.permiso_id = p.id left join platform.roles r on r.id = rp.rol_id
      group by pl.codigo, p.codigo, p.es_acceso_especial order by pl.codigo nulls first, p.codigo""")

    t = ["# Inventario de triggers", "", AVISO,
         f"Además de los de esta tabla hay dos triggers genéricos: `t01_actualizado_en` en **{n_t01} tablas** "
         f"(mantiene la fecha de modificación) y `t02_auditoria` en **{n_t02} tablas** (bitácora de cambios).", "",
         "| Tabla | Trigger | Función | Momento |", "| --- | --- | --- | --- |"]
    t += [f"| `{a}` | `{b}` | `{c}` | {d.strip()} |" for a, b, c, d in trig]

    p = ["# Inventario de políticas RLS", "", AVISO,
         f"Hay **{len(pol)} políticas**. `PERMISSIVE` se suman con OR; `RESTRICTIVE` se suman con AND "
         "(solo la usan las tablas de la extensión de Chrome, regla RN-E01).", "",
         "| Tabla | Política | Operación | Tipo | Condición |", "| --- | --- | --- | --- | --- |"]
    p += [f"| `{a}` | `{b}` | {c} | {d} | `{celda(e)[:180]}` |" for a, b, c, d, e in pol]

    v = ["# Inventario de vistas", "", AVISO,
         "| Vista | security_invoker (aplica el RLS de quien consulta) | Descripción |", "| --- | --- | --- |"]
    v += [f"| `{a}` | {c} | {celda(b)} |" for a, b, c in vis]

    f = ["# Inventario de funciones y procedimientos", "", AVISO,
         "**INVOKER** corre con los permisos de quien llama (RLS aplica). **DEFINER** corre con los del dueño "
         "y se reserva para casos justificados (ver 09_procedimientos.md).", "",
         "| Función | Parámetros | Seguridad | Descripción |", "| --- | --- | --- | --- |"]
    f += [f"| `{a}` | `{celda(b)}` | {c} | {celda(d)} |" for a, b, c, d in fun]

    m = ["# Matriz de permisos (rol general × módulo)", "", AVISO,
         "Niveles: **lectura** < **escritura** < **total**. *con_autorizacion* = Soporte solo cuando el "
         "Administrador abrió un acceso vigente (equivale a total). Los accesos especiales (★) los da el "
         "Administrador por usuario con `platform.otorgar_acceso_especial`.", "",
         "| Plugin | Permiso | Super Admin | Soporte | Administrador | Operador | Analista | Eli |",
         "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for row in perm:
        pl, cod, esp, *niv = row
        star = " ★" if esp == "t" else ""
        m.append(f"| {pl} | `{cod}`{star} | " + " | ".join(x or "—" for x in niv) + " |")
    return "\n".join(t), "\n".join(p), "\n".join(v), "\n".join(f), "\n".join(m)


if __name__ == "__main__":
    destino = sys.argv[1]
    conn = sys.argv[2:] or ["psql", "-h", "/tmp", "-p", "5433", "-U", "postgres", "-d", "elius"]
    os.makedirs(destino, exist_ok=True)
    escribir = lambda nombre, txt: open(os.path.join(destino, nombre), "w").write(txt + "\n")  # noqa: E731
    escribir("02_diccionario_datos.md", diccionario())
    escribir("03_relaciones.md", relaciones())
    trig, pol, vis, fun, mat = inventario(conn)
    escribir("anexo_a_inventario_triggers.md", trig)
    escribir("anexo_b_inventario_politicas_rls.md", pol)
    escribir("anexo_c_inventario_vistas.md", vis)
    escribir("anexo_d_inventario_funciones.md", fun)
    escribir("anexo_e_matriz_permisos.md", mat)
    print("documentación generada en", destino)
