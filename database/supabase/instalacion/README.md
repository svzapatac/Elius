# Instalar la base de datos de Elius en Supabase

13 archivos SQL, para ejecutar **en orden** en el *SQL Editor* de un proyecto Supabase nuevo. Cada uno se pega, se ejecuta con **Run** y debe terminar con `Success`. Si uno falla, **no sigas**: copia el error.

Los 13 archivos aplicados en orden sobre una base limpia pasan las 94 pruebas (`database/tests`). Aún no se han probado sobre un proyecto Supabase real: ese es el primer uso, por eso se ejecutan por partes.

## Antes de empezar

1. Proyecto nuevo en [supabase.com](https://supabase.com) (guarda la contraseña de la base).
2. En *Database → Extensions* no hace falta activar nada a mano: el primer archivo crea `pgcrypto`, `vector`, `pg_trgm` y `btree_gist`.
3. Si el proyecto no es nuevo y tiene tablas propias, no lo uses: estos archivos asumen una base vacía.

## Orden de ejecución

| # | Archivo | Qué hace |
| --- | --- | --- |
| 1 | `01_0100_extensiones_esquemas_roles.sql` | Extensiones, esquemas, usuarios de conexión y la función que identifica al negocio |
| 2 | `02_0200a_tablas.sql` | Crea las 80 tablas |
| 3 | `03_0200b_llaves_foraneas.sql` | Las 191 relaciones (compuestas por negocio) |
| 4 | `04_0200c_indices.sql` | Índices |
| 5 | `05_0200d_comentarios.sql` | Diccionario de datos dentro de la base |
| 6 | `06_0300_restricciones.sql` | Reglas `CHECK`, únicos parciales y reservas sin cruce |
| 7 | `07_0400_seguridad_rls.sql` | Permisos, RLS (288 políticas) y el hook del token |
| 8 | `08_0500_triggers.sql` | Triggers de negocio, auditoría y eventos |
| 9 | `09_0600_vistas.sql` | 20 vistas |
| 10 | `10_0700_procedimientos.sql` | Procedimientos (RPC) |
| 11 | `11_0800_roles_base_de_datos.sql` | Privilegios de `elius_admin`, `elius_app`, `elius_consulta` |
| 12 | `12_0900_datos_base.sql` | **Datos base:** 4 planes, 6 roles, 3 plugins, 21 permisos con la matriz rol × permiso, aeropuertos |
| 13 | `13_1000_integraciones.sql` | Funciones del servidor para Vault y el webhook de Factus |

`TODO_EN_UNO.sql` es la suma de los 18 por si prefieres una sola ejecución (300 KB; el editor puede ir lento).

## Después de instalar

1. **Verificar:** ejecuta `EXTRA_verificar.sql`. Cada fila debe tener `obtenido` igual a `esperado`.
2. **Activar el hook del token:** *Authentication → Hooks → Custom Access Token → Postgres function* → esquema `public`, función `custom_access_token_hook`. Sin esto el token no trae el negocio ni el rol.
3. **Exponer los esquemas a la API:** *Project Settings → API → Exposed schemas*: agrega `platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline`.
4. **Primer Super Admin:** crea tu usuario en *Authentication → Users → Add user* y ejecuta `EXTRA_primer_super_admin.sql` con tu correo.
5. **Contraseñas de los usuarios de conexión** (solo si los vas a usar desde fuera de Supabase), con contraseñas largas y que no se guarden en el repositorio:
   ```sql
   alter role elius_app login password '...';
   alter role elius_consulta login password '...';
   ```

## Si algo falla

| Síntoma | Causa probable |
| --- | --- |
| `must be owner of ...` o `permission denied to create role` | Ejecutaste con un usuario que no es `postgres`. El SQL Editor ya lo es |
| `extension "vector" is not available` | Activa *vector* en *Database → Extensions* y repite el archivo 1 |
| `relation ... already exists` | Repetiste un archivo. Para empezar de cero: *Database → Settings → Reset database* y vuelve a ejecutar desde el 1 |
| El token no trae `tenant_id` | Falta el paso 2 de «Después de instalar» |
