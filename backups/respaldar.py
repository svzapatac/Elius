"""Copias de seguridad de Elius en XML comprimido.

Cada ejecución crea una carpeta /backups/AAAA-MM-DD_HHMM con un archivo .xml.gz por tabla y un manifiesto.xml
(tablas, filas, tamaño y huella SHA-256). Usa las funciones XML de PostgreSQL (table_to_xml): no hace falta
pg_dump. Corre una vez y se repite cada INTERVALO_HORAS; borra las copias con más de RETENCION_DIAS días.

Variables de entorno:
  DATABASE_URL      cadena de conexión de Supabase (Settings > Database, usuario postgres)   [obligatoria]
  BACKUP_DIR        carpeta de destino (el volumen de Easypanel)                              [/backups]
  INTERVALO_HORAS   cada cuántas horas se repite (0 = una sola vez y termina)                 [24]
  RETENCION_DIAS    días que se conservan las copias                                          [14]
  ESQUEMAS          esquemas a respaldar, separados por coma   [platform,elius,ext,audit,plugin_vet,plugin_restaurant,plugin_airline]
"""
import gzip, hashlib, os, shutil, sys, time
from datetime import datetime, timedelta, timezone
from xml.sax.saxutils import quoteattr
import psycopg

ESQUEMAS = os.environ.get('ESQUEMAS', 'platform,elius,ext,audit,plugin_vet,plugin_restaurant,plugin_airline').split(',')
DESTINO = os.environ.get('BACKUP_DIR', '/backups')
INTERVALO = float(os.environ.get('INTERVALO_HORAS', '24'))
RETENCION = int(os.environ.get('RETENCION_DIAS', '14'))


def respaldar(url):
    marca = datetime.now(timezone.utc).strftime('%Y-%m-%d_%H%M')
    carpeta = os.path.join(DESTINO, marca)
    os.makedirs(carpeta + '.parcial', exist_ok=True)
    manifiesto, total = [], 0
    with psycopg.connect(url, autocommit=True) as con:
        con.execute("set client_encoding to 'UTF8'")
        tablas = con.execute("""select table_schema::text, table_name::text from information_schema.tables
                                where table_type = 'BASE TABLE' and table_schema = any(%s) order by 1, 2""", (ESQUEMAS,)).fetchall()
        for esq, tab in tablas:
            filas = con.execute(f'select count(*) from "{esq}"."{tab}"').fetchone()[0]
            xml = con.execute("select table_to_xml(%s::regclass, true, true, '')", (f'"{esq}"."{tab}"',)).fetchone()[0] if filas else ''
            ruta = os.path.join(carpeta + '.parcial', f'{esq}.{tab}.xml.gz')
            cuerpo = f'<?xml version="1.0" encoding="UTF-8"?>\n<respaldo esquema={quoteattr(esq)} tabla={quoteattr(tab)} filas="{filas}">\n{xml}\n</respaldo>\n'
            with gzip.open(ruta, 'wb', compresslevel=9) as f:
                f.write(cuerpo.encode('utf-8'))
            h = hashlib.sha256(open(ruta, 'rb').read()).hexdigest()
            manifiesto.append((esq, tab, filas, os.path.getsize(ruta), h))
            total += filas
    with open(os.path.join(carpeta + '.parcial', 'manifiesto.xml'), 'w', encoding='utf-8') as f:
        f.write(f'<?xml version="1.0" encoding="UTF-8"?>\n<manifiesto creado="{datetime.now(timezone.utc).isoformat()}" tablas="{len(manifiesto)}" filas="{total}">\n')
        for esq, tab, filas, tam, h in manifiesto:
            f.write(f'  <tabla esquema={quoteattr(esq)} nombre={quoteattr(tab)} filas="{filas}" bytes="{tam}" sha256="{h}"/>\n')
        f.write('</manifiesto>\n')
    os.rename(carpeta + '.parcial', carpeta)      # la copia solo existe si terminó completa
    peso = sum(os.path.getsize(os.path.join(carpeta, x)) for x in os.listdir(carpeta))
    print(f'[{marca}] copia lista: {len(manifiesto)} tablas, {total} filas, {peso / 1024:.0f} KB', flush=True)
    return carpeta


def limpiar():
    limite = datetime.now(timezone.utc) - timedelta(days=RETENCION)
    for nombre in sorted(os.listdir(DESTINO)):
        ruta = os.path.join(DESTINO, nombre)
        try:
            fecha = datetime.strptime(nombre[:15], '%Y-%m-%d_%H%M').replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        if os.path.isdir(ruta) and (fecha < limite or nombre.endswith('.parcial')):
            shutil.rmtree(ruta); print(f'copia antigua eliminada: {nombre}', flush=True)


if __name__ == '__main__':
    url = os.environ.get('DATABASE_URL')
    if not url:
        sys.exit('Falta DATABASE_URL')
    os.makedirs(DESTINO, exist_ok=True)
    while True:
        try:
            respaldar(url); limpiar()
        except Exception as e:                       # un fallo no tumba el servicio: se reintenta en el siguiente turno
            print('ERROR en la copia:', e, flush=True)
            if INTERVALO <= 0: sys.exit(1)
        if INTERVALO <= 0:
            break
        time.sleep(INTERVALO * 3600)
