# Triggers

Hay **364 triggers**: dos genéricos repetidos en muchas tablas (82 y 71) y **42 específicos** (211 instalaciones, porque algunos como la baja lógica se repiten por tabla) que hacen cumplir reglas de negocio que un `CHECK` no puede, porque necesitan consultar otras filas o tablas. El inventario exacto que sale de la base está en el [anexo A](anexo_a_inventario_triggers.md); el código, en `database/supabase/migrations/…0500_triggers.sql`.

## Triggers genéricos

| Trigger | Tablas | Qué hace |
| --- | --- | --- |
| `t01_actualizado_en` | 82 | `BEFORE UPDATE`: pone `actualizado_en = now()` |
| `t02_auditoria` | 71 | `AFTER INSERT/UPDATE/DELETE`: escribe en `audit.registros_auditoria` el tenant, el usuario, su rol, el origen (app, eli, soporte, sistema), la tabla, la fila y los datos antes y después (RN-P15, DT-12) |

La auditoría no se aplica a las tablas de alto volumen o técnicas, como mensajes, consumo de IA, embudo, eventos, fragmentos y notificaciones del webhook. Ahí auditar cada fila multiplicaría el tamaño sin aportar trazabilidad útil.

## Triggers de reglas de negocio

| Trigger | Tabla | Momento | Regla | Qué hace |
| --- | --- | --- | --- | --- |
| `t10_nivel_rol` | `membresias`, `asignaciones_plataforma` | BEFORE INSERT/UPDATE | RN-P13 | Un rol de plataforma no se asigna en un negocio, ni al revés |
| `t11_ultimo_admin` | `membresias` | BEFORE UPDATE/DELETE | RN-P04 | Impide quitar, desactivar o cambiar de rol al último Administrador |
| `t12_limite_usuarios` | `membresias` | BEFORE INSERT | RN-P10 | No deja pasar el máximo de usuarios del plan |
| `t20_antes_de_mensaje` | `mensajes` | BEFORE INSERT | RN-C19, RN-C20, RN-C06 | Eli no habla si la atiende un humano o si está apagada; un mensaje del cliente reabre una conversación cerrada |
| `t21_despues_de_mensaje` | `mensajes` | AFTER INSERT | — | Actualiza la fecha del último mensaje y del último contacto |
| `t22_asignar_escalamiento` | `escalamientos` | BEFORE INSERT | RN-C18 | Asigna por turnos al Operador con menos casos abiertos |
| `t23_despues_de_escalamiento` | `escalamientos` | AFTER INSERT/UPDATE | RN-C19 | Pasa la conversación a humano; al resolver el último caso, la libera |
| `t30_codigo_reserva` | `reservas` | BEFORE INSERT | — | Genera el código o localizador de 6 caracteres, único en el negocio |
| `t31_fecha_reserva` | `reservas` | BEFORE INSERT/UPDATE | RN-C08, RN-R10 | No reservar en el pasado ni más allá de la anticipación configurada |
| `t32_transicion_reserva` | `reservas` | BEFORE UPDATE | RN-C09 | Solo pendiente → confirmada/cancelada y confirmada → asistió/no asistió/cancelada |
| `t33_eventos_reserva` | `reservas` | AFTER INSERT/UPDATE | RN-R08 | Emite eventos para n8n, incluido el aviso de grupo grande |
| `t40_numero_orden` | `ordenes` | BEFORE INSERT | RN-C10 | Consecutivo por negocio, con bloqueo para que dos pedidos simultáneos no repitan número |
| `t41_antes_de_linea` | `orden_items` | BEFORE INSERT/UPDATE/DELETE | RN-C12, RN-R03 | Toma el precio del catálogo, calcula la línea, bloquea ítems agotados y órdenes ya pagadas |
| `t42_recalcular_orden` | `orden_items` | AFTER INSERT/UPDATE/DELETE | RN-C11 | Recalcula subtotal, impuestos y total de la orden |
| `t43_proteger_totales` | `ordenes` | BEFORE UPDATE | RN-C11 | Los totales no se escriben a mano |
| `t44_eventos_orden` | `ordenes` | AFTER UPDATE | — | Evento por cada cambio de estado (cocina, domicilio, cliente) |
| `t50_proteger_pago` | `pagos` | BEFORE UPDATE/DELETE | RN-C12 | Un pago aprobado no se modifica ni se borra |
| `t51_aplicar_pago` | `pagos` | AFTER INSERT/UPDATE | RN-C17 | Si lo pagado más lo que se cobrará al entregar cubre el total, confirma la orden y su reserva |
| `t52_revisar_comprobante` | `comprobantes_pago` | BEFORE INSERT | RN-C16 | Marca alertas: comprobante repetido, monto distinto, destinatario raro |
| `t53_evento_comprobante` | `comprobantes_pago` | AFTER INSERT | — | Avisa al equipo que llegó un comprobante |
| `t54_recaudo_pagado` | `recaudos` | AFTER UPDATE | RN-C22 | Cuando Factus confirma el recaudo, crea el pago (una sola vez) |
| `tv1_no_atender_fallecida` | `plugin_vet.atenciones` | BEFORE INSERT | RN-V06 | Una mascota fallecida no recibe citas |
| `tv2_historia_inmutable` | `plugin_vet.registros_clinicos` | BEFORE UPDATE/DELETE | RN-V04 | La historia clínica no se edita después de 24 horas |
| `tr0_precio_opcion` | `plugin_restaurant.orden_item_opciones` | BEFORE INSERT | — | Toma el recargo de la opción |
| `tr1_sumar_recargos` | `plugin_restaurant.orden_item_opciones` | AFTER INSERT/UPDATE/DELETE | RN-R04 | Suma los recargos en la línea del núcleo (`orden_items.recargos`) |
| `ta1_capacidad` | `plugin_airline.tarifas_vuelo` | BEFORE INSERT/UPDATE | RN-A04 | Los cupos de un vuelo no superan la capacidad de la aeronave |
| `ta2_ocupar_cupo` | `plugin_airline.tramos_reserva` | BEFORE INSERT | RN-A04 | Ocupa un cupo por pasajero; el `CHECK` impide la sobreventa |
| `ta3_infantes` | `plugin_airline.reserva_pasajeros` | CONSTRAINT TRIGGER, al final de la transacción | RN-A06 | En una reserva los infantes no superan a los adultos |
| `ta4_silla` | `plugin_airline.tiquetes` | BEFORE INSERT/UPDATE | RN-A07 | Una silla no se asigna dos veces en el mismo vuelo |
| `ta5_evento_vuelo` | `plugin_airline.vuelos` | AFTER UPDATE | RN-A09 | Vuelo cancelado o retrasado → aviso a sus pasajeros |

## Decisiones de diseño

- **Los triggers de un plugin viven en el esquema del plugin.** El núcleo no sabe que existen. Por ejemplo, `tr1_sumar_recargos` escribe en `elius.orden_items.recargos`, pero el núcleo solo suma esa columna (DT-09).
- **`SECURITY DEFINER` solo donde hace falta:** auditoría, eventos, consecutivos y recálculos escriben en filas o tablas que el usuario no puede tocar directamente.
- **Un `CONSTRAINT TRIGGER` diferido** para los infantes, porque los pasajeros de una reserva se cargan uno por uno: la regla se revisa al confirmar la transacción.
- **La base no llama servicios externos.** Los triggers escriben en `elius.eventos_salida`, y n8n los lee y envía WhatsApp, push o eventos de Calendar (DT-16).
