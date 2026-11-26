# Restricciones

Hay **120 `CHECK`, 113 `UNIQUE`, 1 restricción de exclusión y 340 índices**. Se usan restricciones declarativas siempre que la regla se pueda expresar sin consultar otras filas, porque el motor las garantiza en cualquier camino de escritura, incluso uno que no pase por la aplicación. Lo que necesita mirar otras tablas va como trigger ([07_triggers.md](07_triggers.md)).

## Dónde están

| Tipo | Archivo | Ejemplo |
| --- | --- | --- |
| Dominios de estado (`IN (...)`) | `0200_tablas.sql`, generados desde `database/modelo/dominios.py` | `reservas.estado IN ('pendiente_pago','confirmada','asistio','no_asistio','cancelada')` |
| Reglas de negocio declarativas | `0300_restricciones.sql` | `ck_rutas_distintas: origen_id <> destino_id` |
| Unicidad por tenant | `0200_tablas.sql` | `UNIQUE (tenant_id, numero)` en órdenes |
| Unicidad parcial | `0300_restricciones.sql` | un solo agente activo por tenant: `UNIQUE (tenant_id) WHERE activo` |
| Exclusión | `0300_restricciones.sql` | reservas que no se cruzan |

## Restricciones que hacen cumplir reglas de negocio

| Regla | Restricción | Qué impide |
| --- | --- | --- |
| RN-P05 | `ck_tenants_slug_formato` y `UNIQUE (slug)` | Identificadores repetidos o con caracteres raros |
| RN-P16 | `ck_accesos_soporte_vigencia` | Accesos de soporte de más de 7 días |
| RN-C01, RN-C02 | `ck_contactos_identificable`, `ck_contactos_telefono_e164`, `UNIQUE (tenant_id, telefono)` | Contactos sin forma de ubicarlos, teléfonos mal escritos, duplicados en el mismo negocio |
| RN-C07 | `ex_asignaciones_sin_cruce` (`EXCLUDE USING gist`) | Que un recurso tenga dos asignaciones activas cruzadas en el tiempo |
| RN-C08 | `ck_reservas_fin` | Reservas que terminan antes de empezar |
| RN-C12, RN-C25 | `ck_pagos_reverso` | Pagos negativos sin pago original, o reversos positivos |
| RN-C16 | `ck_comprobantes_decision` | Comprobantes decididos sin fecha, o pendientes con fecha |
| RN-C22 | `ck_pagos_factus_recaudo` | Un pago por Bre-B que no venga de un recaudo |
| RN-C23 | `ck_recaudos_monto`, `ck_pasarelas_montos` | Recaudos fuera de 1.000 a 12.100.000 COP |
| RN-R04 | `ck_modificador_rango` | Grupos de opciones con mínimo mayor que el máximo |
| RN-R05 | `ck_ordenes_domicilio_direccion` | Domicilios confirmados sin dirección |
| RN-E02 | `ck_patrones_aprobacion` | Patrones aprobados sin quién los aprobó |
| RN-V04 | `ck_registros_correccion` | Correcciones de historia clínica que no apuntan al registro corregido |
| RN-A02, RN-A03 | `ck_rutas_distintas`, `ck_vuelos_horario` | Rutas de un aeropuerto a sí mismo; vuelos que llegan antes de salir |
| RN-A04 | `ck_tarifas_cupos` | Vender más cupos de los asignados |

## La restricción de exclusión, explicada

```sql
alter table elius.asignaciones_recurso
  add constraint ex_asignaciones_sin_cruce exclude using gist (
    tenant_id with =, recurso_id with =, tstzrange(inicio, fin, '[)') with &&
  ) where (estado = 'activa');
```

Rechaza una fila si ya existe otra **del mismo tenant, del mismo recurso y con un rango de tiempo que se cruce** (`&&`). El rango `[)` incluye el inicio y excluye el fin, así que una reserva de 1 a 3 y otra de 3 a 5 no chocan. Solo cuenta las asignaciones activas: una liberada no bloquea. Necesita la extensión `btree_gist` para comparar `uuid` con `=` dentro de un índice GiST. Es más fuerte que un trigger, porque también resuelve las inserciones simultáneas.

## Llaves foráneas compuestas

97 de las 196 llaves son compuestas: `FOREIGN KEY (tenant_id, contacto_id) REFERENCES elius.contactos (tenant_id, id)`. Para eso cada tabla de negocio tiene `UNIQUE (tenant_id, id)`. La razón: **las verificaciones de llaves foráneas no pasan por RLS**, así que sin esto una reserva de un negocio podría apuntar al contacto de otro. Lo prueba la sección 3 de las pruebas.

Cuando la FK es opcional se usa `ON DELETE SET NULL (columna)`, una sintaxis de PostgreSQL 15 que limpia solo la referencia y deja `tenant_id` intacto.
