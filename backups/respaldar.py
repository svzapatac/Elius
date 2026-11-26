"""Copias de seguridad de Elius en XML comprimido.

Cada ejecución crea una carpeta /backups/AAAA-MM-DD_HHMM con un archivo .xml.gz por tabla y un manifiesto.xml
(tablas, filas, tamaño y huella SHA-256). Usa las funciones XML de PostgreSQL (table_to_xml): no hace falta
pg_dump. Corre una vez y se repite cada INTERVALO_HORAS; borra las copias con más de RETENCION_DIAS días.

Variables de entorno:
  DATABASE_URL      cadena de conexión de Supabase (Settings > Database, usuario postgres)   [obligatoria]
  BACKUP_DIR        carpeta de destino (el volumen de Easypanel)                              [/backups]
  HORA_DIARIA       hora a la que se hace la copia cada noche, HH:MM en la zona TZ               [02:00]
  TZ                zona horaria de HORA_DIARIA                                                  [America/Bogota]
  INTERVALO_HORAS   si se define, ignora HORA_DIARIA y repite cada N horas (0 = una sola vez)    []
  AGE_PUBLICA       llave PÚBLICA age (age1...) con la que se CIFRA la copia; la privada no       [obligatoria]
                    está aquí: solo quien la guarda (el CIS adm) puede descifrar
  SUPABASE_URL      https://<ref>.supabase.co  (con SUPABASE_SERVICE_KEY sube cada copia al bucket privado "respaldos")   []
  SUPABASE_SERVICE_KEY  llave service_role (secreta; solo en Easypanel)                                          []
  AL_INICIAR        1 = hace una copia al arrancar el servicio además de la nocturna              [1]
  RETENCION_DIAS    días que se conservan las copias                                          [30]
  ESQUEMAS          esquemas a respaldar, separados por coma   [platform,elius,ext,audit,plugin_vet,plugin_restaurant,plugin_airline]
"""
import gzip, hashlib, json, os, shutil, subprocess, sys, tarfile, time, urllib.request, urllib.error
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo
from xml.sax.saxutils import quoteattr
import psycopg

ESQUEMAS = os.environ.get('ESQUEMAS', 'platform,elius,ext,audit,plugin_vet,plugin_restaurant,plugin_airline').split(',')
DESTINO = os.environ.get('BACKUP_DIR', '/backups')
INTERVALO = os.environ.get('INTERVALO_HORAS')
HORA = os.environ.get('HORA_DIARIA', '02:00')
ZONA = ZoneInfo(os.environ.get('TZ', 'America/Bogota'))
RETENCION = int(os.environ.get('RETENCION_DIAS', '30'))
AGE_PUBLICA = os.environ.get('AGE_PUBLICA', '')
SB_URL = os.environ.get('SUPABASE_URL', '').rstrip('/')
SB_KEY = os.environ.get('SUPABASE_SERVICE_KEY', '')
BUCKET = 'respaldos'


def _storage(metodo, ruta, datos=None, tipo='application/octet-stream', extra=None):
    req = urllib.request.Request(f'{SB_URL}/storage/v1/{ruta}', data=datos, method=metodo)
    req.add_header('Authorization', f'Bearer {SB_KEY}'); req.add_header('apikey', SB_KEY); req.add_header('Content-Type', tipo)
    for k, v in (extra or {}).items(): req.add_header(k, v)
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def subir(marca, archivo_cifrado, manifiesto):
    """Sube la copia cifrada y su manifiesto al bucket privado (solo el CIS adm los ve en el panel)."""
    if not (SB_URL and SB_KEY):
        print('Storage: sin SUPABASE_URL/SUPABASE_SERVICE_KEY, la copia queda solo en el volumen', flush=True); return
    for nombre, ruta, tipo in ((f'{marca}.tar.age', archivo_cifrado, 'application/octet-stream'), ('manifiesto.xml', manifiesto, 'application/xml')):
        with open(ruta, 'rb') as f:
            _storage('POST', f'object/{BUCKET}/{marca}/{nombre}', f.read(), tipo, {'x-upsert': 'true'})
    print(f'[{marca}] copia subida al bucket privado "{BUCKET}"', flush=True)


def limpiar_storage():
    if not (SB_URL and SB_KEY): return
    limite = datetime.now(timezone.utc) - timedelta(days=RETENCION)
    carpetas = json.loads(_storage('POST', f'object/list/{BUCKET}', json.dumps({'prefix': '', 'limit': 1000}).encode(), 'application/json'))
    viejos = []
    for c in carpetas:
        try:
            if datetime.strptime(c['name'][:15], '%Y-%m-%d_%H%M').replace(tzinfo=timezone.utc) < limite:
                for o in json.loads(_storage('POST', f'object/list/{BUCKET}', json.dumps({'prefix': c['name'], 'limit': 100}).encode(), 'application/json')):
                    viejos.append(f"{c['name']}/{o['name']}")
        except ValueError:
            continue
    if viejos:
        _storage('DELETE', f'object/{BUCKET}', json.dumps({'prefixes': viejos}).encode(), 'application/json')
        print(f'Storage: {len(viejos)} archivos antiguos eliminados', flush=True)


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
            tiene_baja = con.execute("select 1 from information_schema.columns where table_schema=%s and table_name=%s and column_name='eliminado_en'", (esq, tab)).fetchone()
            elim = con.execute(f'select count(*) from "{esq}"."{tab}" where eliminado_en is not null').fetchone()[0] if tiene_baja else None
            manifiesto.append((esq, tab, filas, os.path.getsize(ruta), h, elim))
            total += filas
    with open(os.path.join(carpeta + '.parcial', 'manifiesto.xml'), 'w', encoding='utf-8') as f:
        f.write(f'<?xml version="1.0" encoding="UTF-8"?>\n<manifiesto creado="{datetime.now(timezone.utc).isoformat()}" tablas="{len(manifiesto)}" filas="{total}">\n')
        for esq, tab, filas, tam, h, elim in manifiesto:
            extra = f' eliminados_logicos="{elim}"' if elim is not None else ''
            f.write(f'  <tabla esquema={quoteattr(esq)} nombre={quoteattr(tab)} filas="{filas}"{extra} bytes="{tam}" sha256="{h}"/>\n')
        f.write('</manifiesto>\n')
    elim_total = sum(e for *_, e in manifiesto if e)
    cifrar(carpeta + '.parcial', carpeta + '.tar.age')            # solo queda el archivo cifrado; la carpeta en claro se borra
    man_ruta = os.path.join(DESTINO, marca + '.manifiesto.xml')
    shutil.copy(os.path.join(carpeta + '.parcial', 'manifiesto.xml'), man_ruta)   # el manifiesto no tiene datos: se guarda aparte
    shutil.rmtree(carpeta + '.parcial')
    print(f'[{marca}] copia cifrada lista: {len(manifiesto)} tablas, {total} filas (incluye {elim_total} eliminados lógicos), '
          f'{os.path.getsize(carpeta + ".tar.age") / 1024:.0f} KB', flush=True)
    try:
        subir(marca, carpeta + '.tar.age', man_ruta)
    except Exception as e:                                            # la copia local ya existe: un fallo de subida no la invalida
        print('Storage: no se pudo subir la copia:', e, flush=True)
    return carpeta + '.tar.age'


def cifrar(carpeta, destino):
    """tar + age con llave pública: cualquiera puede cifrar, solo quien tiene la privada puede abrir la copia."""
    if not AGE_PUBLICA.startswith('age1'):
        raise RuntimeError('Falta AGE_PUBLICA (llave pública age1...): no se guarda ninguna copia sin cifrar')
    tmp = destino + '.parcial'
    tar = subprocess.Popen(['tar', '-C', os.path.dirname(carpeta), '-cf', '-', os.path.basename(carpeta)], stdout=subprocess.PIPE)
    r = subprocess.run(['age', '-r', AGE_PUBLICA, '-o', tmp], stdin=tar.stdout)
    tar.stdout.close()
    if tar.wait() != 0 or r.returncode != 0:
        if os.path.exists(tmp): os.remove(tmp)
        raise RuntimeError('No se pudo cifrar la copia')
    os.rename(tmp, destino)


def limpiar():
    limite = datetime.now(timezone.utc) - timedelta(days=RETENCION)
    for nombre in sorted(os.listdir(DESTINO)):
        ruta = os.path.join(DESTINO, nombre)
        try:
            fecha = datetime.strptime(nombre[:15], '%Y-%m-%d_%H%M').replace(tzinfo=timezone.utc)
        except ValueError:
            continue
        if fecha < limite or nombre.endswith('.parcial'):
            shutil.rmtree(ruta) if os.path.isdir(ruta) else os.remove(ruta)
            print(f'copia antigua eliminada: {nombre}', flush=True)


if __name__ == '__main__':
    url = os.environ.get('DATABASE_URL')
    if not url:
        sys.exit('Falta DATABASE_URL')
    os.makedirs(DESTINO, exist_ok=True)
    primera = True
    while True:
        if not primera or os.environ.get('AL_INICIAR', '1') == '1':
            try:
                respaldar(url); limpiar(); limpiar_storage()
            except Exception as e:                   # un fallo no tumba el servicio: se reintenta en el siguiente turno
                print('ERROR en la copia:', e, flush=True)
                if INTERVALO is not None and float(INTERVALO) <= 0: sys.exit(1)
        primera = False
        if INTERVALO is not None:
            if float(INTERVALO) <= 0: break
            time.sleep(float(INTERVALO) * 3600)
        else:
            ahora = datetime.now(ZONA)
            h, m = (int(x) for x in HORA.split(':'))
            prox = ahora.replace(hour=h, minute=m, second=0, microsecond=0)
            if prox <= ahora: prox += timedelta(days=1)
            print(f'próxima copia: {prox:%Y-%m-%d %H:%M} ({ZONA})', flush=True)
            time.sleep((prox - ahora).total_seconds())
