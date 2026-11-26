# Copias de seguridad cifradas (Easypanel)

Cada noche guarda los **datos** de todos los esquemas de Elius en **XML**, una tabla por archivo, con un `manifiesto.xml`
(filas, **eliminados lógicos**, huella sha256). Todo se empaqueta y se **cifra con age**: en el volumen solo queda
`AAAA-MM-DD_HHMM.tar.age`. Sin la llave privada nadie puede leerla, ni quien tenga acceso al servidor.
El esquema (tablas, vistas, funciones) se recrea con las migraciones de `database/supabase/migrations`.

## Qué queda guardado
- **Todo lo que hay en la base a la hora de la copia**, incluida la auditoría (`audit.registros_auditoria`: quién, qué, antes/después, IP, instancia).
- **Lo eliminado (desactivado) también va en la copia**: productos y clientes con `eliminado_en` siguen ahí. El manifiesto cuenta cuántos.
- **Aunque el CIS adm borre algo de verdad**, las copias anteriores lo conservan hasta que se cumpla la retención (30 días).
- La auditoría registra cada cambio en el instante en que ocurre; la copia nocturna es la foto del día.
  (Recuperar la base a un segundo exacto requiere PITR, que Supabase ofrece solo en el plan Pro.)

## Llaves (una sola vez)
En tu computador (nunca en el repositorio):
```
age-keygen -o llave_privada_elius.txt        # imprime "Public key: age1..."
```
- La **pública** (`age1...`) va en el servicio como `AGE_PUBLICA`. Sirve solo para cifrar.
- La **privada** (el archivo) la guarda solo el CIS adm, fuera de Easypanel. Sin ella no se restaura nada: no la pierdas.

## Crear el servicio en Easypanel
1. Proyecto → **+ Servicio → App** → origen **GitHub**: `svzapatac/Elius`, rama `main`, **ruta de build `backups/`** (Dockerfile).
2. **Montajes → Volumen**: nombre `backups`, ruta de montaje `/backups`.
3. **Entorno** (secretos: se escriben solo aquí):
   ```
   DATABASE_URL=postgresql://postgres.<ref>:<CLAVE>@<host del pooler>:5432/postgres
   AGE_PUBLICA=age1...
   HORA_DIARIA=02:00
   TZ=America/Bogota
   RETENCION_DIAS=30
   SUPABASE_URL=https://xpvxcqvxbujblazuwomb.supabase.co
   SUPABASE_SERVICE_KEY=<llave service_role: Supabase > Project Settings > API>
   ```
   Las dos últimas hacen que cada copia **también se suba a un bucket privado** de Supabase (`respaldos`), desde donde el CIS adm las ve y las descarga en el panel (menú **Respaldos**). Sin ellas, las copias quedan solo en el volumen.
   La `DATABASE_URL` se copia del botón **Connect** de Supabase (usa el *Session pooler*: funciona por IPv4).
4. **Implementar**. Hace una copia al arrancar (`AL_INICIAR=1`) y luego una cada noche a la hora indicada.
   Se escribe como `.parcial` y se renombra al terminar: nunca queda una copia a medias. Si falta `AGE_PUBLICA`, **no guarda nada sin cifrar**.

## Restaurar
En una base con las migraciones ya aplicadas, con el archivo de la llave privada a mano:
```
DATABASE_URL=postgresql://... AGE_PRIVADA=llave_privada_elius.txt python3 restaurar.py /backups/AAAA-MM-DD_HHMM.tar.age
```
Descifra, verifica la huella sha256 de cada archivo y carga las tablas en orden de llaves foráneas (omite lo que ya existe).
Para solo mirar una copia: `age -d -i llave_privada_elius.txt copia.tar.age | tar -xv`.

## Probado
Copia de 83 tablas / 1.392 filas: la copia no contiene texto legible, una llave equivocada no abre el archivo, el manifiesto cuenta el cliente eliminado
lógicamente y la restauración termina sin errores.

## Descargarlas desde el panel (CIS adm)
En el panel, el CIS adm ve el menú **Respaldos**: lista de copias con tablas, filas y eliminados guardados, botón para descargar la copia cifrada (`.tar.age`) y su `manifiesto.xml` (legible, sin datos), y tres ejemplos de cómo se guarda cada tabla en XML.
El bucket es privado: la política `respaldos_cis_leer` solo deja leer a quien es Super Administrador de plataforma. La llave `service_role` vive únicamente en Easypanel.
