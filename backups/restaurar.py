"""Restaura una copia XML en una base que ya tiene el esquema (migraciones aplicadas).
Uso:  DATABASE_URL=... python3 restaurar.py /backups/2026-11-24_0300 [--solo elius.items_catalogo,...]
Inserta las tablas en orden de dependencias (primero las referenciadas) y omite las filas que ya existen.
Comprueba la huella SHA-256 de cada archivo contra el manifiesto antes de leerlo."""
import gzip, hashlib, json, os, sys
import xml.etree.ElementTree as ET
import psycopg

XSI = '{http://www.w3.org/2001/XMLSchema-instance}nil'


def valor(el, tipo):
    if el.get(XSI) == 'true':
        return None
    hijos = list(el)
    if tipo == 'ARRAY' or (hijos and all(h.tag == 'element' for h in hijos)):          # arreglo de PostgreSQL
        return [valor(h, 'text') for h in hijos]
    txt = el.text or ''
    return json.loads(txt) if tipo in ('json', 'jsonb') and txt else txt


def orden_tablas(con, tablas):
    """Orden topológico por llaves foráneas (padres antes que hijos)."""
    deps = {t: set() for t in tablas}
    for es, t, ps, p in con.execute("""select (cl.relnamespace::regnamespace)::text, cl.relname, (cf.relnamespace::regnamespace)::text, cf.relname
        from pg_constraint c join pg_class cl on cl.oid = c.conrelid join pg_class cf on cf.oid = c.confrelid where c.contype = 'f'"""):
        if (es, t) in deps and (ps, p) in deps and (es, t) != (ps, p):
            deps[(es, t)].add((ps, p))
    salida, listos = [], set()
    while deps:
        libres = sorted(t for t, d in deps.items() if d <= listos)
        if not libres:
            libres = sorted(deps)[:1]                              # ciclo: se rompe por el primero
        for t in libres:
            salida.append(t); listos.add(t); deps.pop(t)
    return salida


def main():
    carpeta = sys.argv[1]
    solo = set()
    if '--solo' in sys.argv:
        solo = set(sys.argv[sys.argv.index('--solo') + 1].split(','))
    man = ET.parse(os.path.join(carpeta, 'manifiesto.xml')).getroot()
    huellas = {(t.get('esquema'), t.get('nombre')): t.get('sha256') for t in man}
    with psycopg.connect(os.environ['DATABASE_URL']) as con:
        con.execute("set client_encoding to 'UTF8'")
        try:
            con.execute("set session_replication_role = replica")   # no dispara triggers (auditoría, reglas) al cargar
            print('Carga sin triggers')
        except Exception:
            con.rollback(); print('Aviso: sin permiso para desactivar triggers; se cargará con ellos activos')
        for esq, tab in orden_tablas(con, list(huellas)):
            if solo and f'{esq}.{tab}' not in solo:
                continue
            ruta = os.path.join(carpeta, f'{esq}.{tab}.xml.gz')
            if hashlib.sha256(open(ruta, 'rb').read()).hexdigest() != huellas[(esq, tab)]:
                sys.exit(f'Huella distinta en {esq}.{tab}: la copia está dañada')
            tipos = dict(con.execute("select column_name::text, data_type::text from information_schema.columns where table_schema = %s and table_name = %s", (esq, tab)).fetchall())
            n = 0
            with gzip.open(ruta, 'rb') as f:
                for _, el in ET.iterparse(f):
                    if el.tag in ('respaldo',) or el.get('filas') is not None:
                        continue
                    if el.tag != tab:
                        continue
                    fila = {c.tag: valor(c, tipos.get(c.tag, 'text')) for c in el}
                    con.execute(f'insert into "{esq}"."{tab}" select * from json_populate_record(null::"{esq}"."{tab}", %s::json) on conflict do nothing',
                                (json.dumps(fila, ensure_ascii=False),))
                    n += 1; el.clear()
            con.commit(); print(f'{esq}.{tab}: {n} filas leídas')
    print('Restauración terminada')


if __name__ == '__main__':
    main()
