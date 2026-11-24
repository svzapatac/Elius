# Base de datos de Elius · índice para sustentar

Cada documento explica una parte por separado: qué se hizo, cómo y por qué. Los marcados con ⚙ se generan automáticamente desde el modelo o desde la base ya migrada, así que siempre coinciden con el código.

| # | Documento | Qué responde |
| --- | --- | --- |
| 00 | [**Modelo E/R completo (diagramas)**](modelo_er.md) | Las 83 tablas con columnas y relaciones, completo y por módulo |
| 01 | [Modelo entidad-relación](01_modelo_entidad_relacion.md) | Qué tablas hay, cómo se relacionan y cómo se cumplen las 3 reglas del curso |
| 02 | [Diccionario de datos](02_diccionario_datos.md) ⚙ | Cada columna: tipo, nulos, valor por defecto, restricción, descripción y privacidad |
| 03 | [Relaciones](03_relaciones.md) ⚙ | Las 192 relaciones con su cardinalidad y qué pasa al borrar |
| 04 | [Restricciones](04_restricciones.md) | `CHECK`, `UNIQUE`, exclusión e índices, y la regla de negocio de cada uno |
| 05 | [Seguridad multi-tenant y RLS](05_seguridad_multitenant_rls.md) | Cómo se aísla cada negocio dentro de una sola base |
| 06 | [Roles y permisos](06_roles_y_permisos.md) | Los 6 roles generales, accesos especiales, plugins y los 3 usuarios de PostgreSQL |
| 07 | [Triggers](07_triggers.md) | Los 31 triggers de reglas de negocio, más auditoría y fechas |
| 08 | [Vistas](08_vistas.md) | Las 20 vistas, quién las usa y por qué son seguras |
| 09 | [Procedimientos](09_procedimientos.md) | Las operaciones atómicas que llaman los paneles, Eli y los webhooks |
| 10 | [Cómo lo hicimos](10_como_lo_hicimos.md) | El método completo, del levantamiento a las pruebas, y preguntas de sustentación |
| 11 | [Pruebas](11_pruebas.md) | Cómo correr las 94 pruebas y qué verifica cada grupo |
| A–E | Anexos ⚙ | Inventarios exactos: [triggers](anexo_a_inventario_triggers.md), [políticas RLS](anexo_b_inventario_politicas_rls.md), [vistas](anexo_c_inventario_vistas.md), [funciones](anexo_d_inventario_funciones.md), [matriz de permisos](anexo_e_matriz_permisos.md) |

## Cifras del modelo implementado

| Objeto | Cantidad |
| --- | --- |
| Tablas | 83 (57 del modelo general, 26 de plugins); 82 propias + `auth.users` de Supabase |
| Relaciones (llaves foráneas) | 191, de ellas 95 compuestas `(tenant_id, columna)` |
| Tablas de transición | 24, todas con datos propios |
| Restricciones `CHECK` | 110 |
| Restricciones `UNIQUE` | 109 |
| Restricción de exclusión | 1 (reservas que se cruzan) |
| Índices | 326 |
| Tablas con RLS activo | 80 de 80 |
| Políticas RLS | 288 |
| Triggers | 179 (31 de reglas de negocio, 79 de fecha de modificación, 69 de auditoría) |
| Vistas | 20 (17 de negocio con `security_invoker`, 3 agregadas en `reportes`) |
| Funciones | 79 en total, entre ellas 24 procedimientos de negocio que se llaman por RPC |
| Reglas de negocio | 73 (sección 9 del levantamiento) |
| Pruebas automáticas | 94, todas aprobadas |

## Archivos de código

| Archivo | Contenido |
| --- | --- |
| `database/supabase/migrations/…0100_extensiones_esquemas_roles.sql` | Extensiones, esquemas, usuarios de PostgreSQL, `current_tenant_id()` |
| `…0200_tablas.sql` ⚙ | Las 80 tablas, llaves, índices y comentarios (generado desde el modelo) |
| `…0300_restricciones.sql` | Reglas declarativas: `CHECK`, `UNIQUE` parciales, exclusión |
| `…0400_seguridad_rls.sql` | Permisos, hook del JWT y las políticas RLS |
| `…0500_triggers.sql` | Triggers de reglas de negocio, auditoría y eventos |
| `…0600_vistas.sql` | Vistas de negocio y de reportes |
| `…0700_procedimientos.sql` | Procedimientos (RPC) |
| `…0800_roles_base_de_datos.sql` | `GRANT` / `REVOKE` de `elius_admin`, `elius_app`, `elius_consulta` |
| `…0900_datos_base.sql` | Planes, roles, plugins, permisos, matriz y aeropuertos |
| `…1000_integraciones.sql` | Funciones solo para el servidor: Vault y webhook de Factus |
| `database/modelo/modelo.py` | **Fuente única** del modelo E/R |
| `database/tests/10_pruebas_negocio.sql` | Las 94 pruebas |
