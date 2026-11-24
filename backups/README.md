# Copias de seguridad en XML (Easypanel)

Guarda los **datos** de todos los esquemas de Elius en archivos **XML comprimidos (.xml.gz)**, una tabla por archivo,
más un `manifiesto.xml` con filas y huella sha256 de cada archivo. El esquema (tablas, vistas, funciones) no se
respalda aquí: se recrea con las migraciones de `database/supabase/migrations`.

## Crear el servicio en Easypanel
1. Proyecto → **+ Servicio → App** → origen **GitHub**: repositorio `svzapatac/Elius`, rama `main`, **ruta de build `backups/`** (Dockerfile).
2. **Montajes → Volumen**: nombre `backups`, ruta de montaje `/backups`.
3. **Entorno** (el `DATABASE_URL` es secreto: se escribe solo aquí, nunca en el repositorio):
   ```
   DATABASE_URL=postgresql://postgres:<CLAVE>@db.xpvxcqvxbujblazuwomb.supabase.co:5432/postgres
   INTERVALO_HORAS=24
   RETENCION_DIAS=14
   ```
4. **Implementar**. Cada 24 h crea `/backups/AAAA-MM-DD_HHMM/` y borra las de más de 14 días.
   Se escribe como `.parcial` y se renombra al terminar, así nunca queda una copia a medias.

## Restaurar
En una base con las migraciones ya aplicadas:
```
DATABASE_URL=postgresql://... python3 restaurar.py /backups/AAAA-MM-DD_HHMM
```
Carga las tablas en orden de llaves foráneas. Probado: la base restaurada tiene los mismos conteos que la original.

## Por qué XML + gzip
El XML se genera con `table_to_xml` de PostgreSQL y se comprime por tabla: ~80 tablas / 1.900 filas ≈ 200 KB.
