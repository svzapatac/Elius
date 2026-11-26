![](elius-logo.png){width=5cm}

# Triggers de Elius: qué hace cada uno

Versión 0.1 · 26 de noviembre de 2026

Un **trigger** es una regla que la base de datos ejecuta sola cuando alguien inserta, modifica o borra una fila. En Elius sirven para que las reglas de negocio se cumplan **sin importar desde dónde se use el sistema** (panel, Eli, consola o API): ni una persona ni Eli pueden saltárselas.

La letra y el número del nombre indican el área (`t0x` protección, `t1x` usuarios, `t2x` conversaciones, `t3x` reservas, `t4x` órdenes, `t5x` pagos, `t6x` tickets, `ta*` aerolínea, `tr*` restaurante, `tv*` veterinaria). Los dos primeros se repiten en casi todas las tablas.

**Total:** 43 triggers distintos (instalados en cientos de tablas y filas).

## Protección, auditoría y genéricos

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t00_origen_conexion` | registros_auditoria | Before Insert | Auditoría: completa cada registro con la instancia, base, puerto, IP del cliente, login de BD y correo de quien lo hizo. |
| `t00_sin_baja_directa` | accesos_bd, accesos_especiales, accesos_soporte y 81 más | Before Update Delete | Protección: nadie borra filas con DELETE; la baja se hace marcando la fila (borrado lógico) para conservar el historial. |
| `t00_sin_truncate_directo` | accesos_bd, accesos_especiales, accesos_soporte y 81 más | Before | Protección: bloquea TRUNCATE, que vaciaría la tabla completa de un golpe. |
| `t01_actualizado_en` | casi todas |  | Genérico (BEFORE UPDATE): pone actualizado_en = now() para saber cuándo cambió la fila por última vez. |
| `t02_auditoria` | casi todas |  | Genérico (AFTER): escribe en la bitácora quién, con qué rol, qué tabla y fila, y los datos antes y después (RN-P15). |
| `t02_auditoria_mensaje_humano` | mensajes |  | Auditoría: registra cuando una persona (no Eli) responde un mensaje a un cliente, sin guardar el texto completo. |
| `t06_marcada_por` | reservas | Before Update | Guarda quién marcó la reserva como asistió o no asistió y, si no tenía responsable, deja como responsable a esa persona (Administrador u Operador). |
| `t07_proteger_baja` | contactos, ordenes, reservas | Before Update | Solo el Administrador puede mandar a la Papelera una orden, reserva o contacto; no se puede si la orden tiene pago aprobado o la reserva ya asistió. |

## Usuarios y roles (plataforma)

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t10_nivel_rol` | asignaciones_plataforma, membresias | Before Insert Update | RN-P13: un rol de plataforma no se asigna dentro de un negocio, ni al revés. |
| `t11_ultimo_admin` | membresias | Before Update Delete | RN-P04: impide quitar, desactivar o cambiar de rol al último Administrador de un negocio. |
| `t12_limite_usuarios` | membresias | Before Insert | RN-P10: no deja pasar el máximo de usuarios que permite el plan. |

## Conversaciones y mensajes

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t20_antes_de_mensaje` | mensajes | Before Insert | RN-C19/C20/C06: Eli no habla si atiende un humano o está apagada; un mensaje del cliente reabre una conversación cerrada. |
| `t21_despues_de_mensaje` | mensajes | After Insert | Actualiza la fecha del último mensaje y del último contacto de la conversación. |
| `t22_asignar_escalamiento` | escalamientos | Before Insert | RN-C18: asigna el caso por turnos al Operador con menos casos abiertos. |
| `t23_despues_de_escalamiento` | escalamientos | After Insert Update | RN-C19: pasa la conversación a un humano; al resolver el último caso, la devuelve a Eli. |

## Reservas

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t30_codigo_reserva` | reservas | Before Insert | Genera el código o localizador de 6 caracteres, único dentro del negocio. |
| `t31_fecha_reserva` | reservas | Before Insert Update | RN-C08/R10: no se reserva en el pasado ni más allá de la anticipación configurada. |
| `t32_transicion_reserva` | reservas | Before Update | RN-C09: solo se permiten los cambios de estado válidos (pendiente → confirmada → asistió, etc.). |
| `t33_eventos_reserva` | reservas | After Insert Update | RN-R08: emite eventos de salida (para n8n), incluido el aviso de grupo grande. |

## Órdenes y pedidos

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t40_numero_orden` | ordenes | Before Insert | RN-C10: numera las órdenes de forma consecutiva por negocio, con bloqueo para que dos pedidos simultáneos no repitan número. |
| `t41_antes_de_linea` | orden_items | Before Insert Update Delete | RN-C12/R03: toma el precio del catálogo, calcula la línea y bloquea ítems agotados u órdenes ya pagadas. |
| `t42_recalcular_orden` | orden_items | After Insert Update Delete | RN-C11: recalcula subtotal, impuestos y total de la orden cada vez que cambian sus líneas. |
| `t43_proteger_totales` | ordenes | Before Update | RN-C11: los totales de una orden no se escriben a mano; solo los calcula el sistema. |
| `t44_eventos_orden` | ordenes | After Update | Emite un evento de salida por cada cambio de estado de la orden (cocina, domicilio, cliente). |

## Pagos y comprobantes

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t50_proteger_pago` | pagos | Before Update Delete | RN-C12: un pago aprobado no se modifica ni se borra; se corrige con otro pago. |
| `t51_aplicar_pago` | pagos | After Insert Update | RN-C17: si lo pagado más lo que se cobrará al entregar cubre el total, confirma la orden y su reserva. |
| `t52_revisar_comprobante` | comprobantes_pago | Before Insert | RN-C16: marca alertas en el comprobante: repetido, monto distinto o destinatario raro. |
| `t53_evento_comprobante` | comprobantes_pago | After Insert | Avisa al equipo que llegó un comprobante de pago. |
| `t55_solo_admin_decide` | comprobantes_pago | Before Update | RN-C26: solo el Administrador aprueba o rechaza comprobantes. |
| `t56_aviso_celular_comprobante` | comprobantes_pago | After Insert | Avisa por notificación al celular del equipo cuando llega un comprobante. |

## Tickets de soporte

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t60_codigo_ticket` | tickets | Before Insert | Numera los tickets de soporte (TCK-0001, TCK-0002…) de forma consecutiva. |
| `t61_estado_ticket` | tickets | Before Update | Controla los cambios de estado del ticket (abierto → en proceso → resuelto) y registra cuándo se tomó y se resolvió. |

## Accesos a la base

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `t90_accesos_bd` | tenants | After Insert | Al crear un negocio, le prepara los accesos de base de datos por rol. |
| `t91_usuarios_por_negocio` | tenants | After Insert | Al crear un negocio, crea sus usuarios de prueba (superadmin, administrador, operador y soporte). |

## Aerolínea

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `ta1_capacidad` | tarifas_vuelo | Before Insert Update | RN-A04: los cupos de un vuelo no superan la capacidad de la aeronave. |
| `ta2_ocupar_cupo` | tramos_reserva | Before Insert | RN-A04: ocupa un cupo por pasajero; el CHECK impide vender más de lo disponible. |
| `ta3_infantes` | reserva_pasajeros | After Insert Update | RN-A06: en una reserva los infantes no superan a los adultos (se revisa al terminar la transacción). |
| `ta4_silla` | tiquetes | Before Insert Update | RN-A07: una silla no se asigna dos veces en el mismo vuelo. |
| `ta5_evento_vuelo` | vuelos | After Update | RN-A09: si el vuelo se cancela o se retrasa, avisa a sus pasajeros mediante un evento de salida. |

## Restaurante

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `tr0_precio_opcion` | orden_item_opciones | Before Insert | Toma el recargo de la opción elegida desde el catálogo del restaurante. |
| `tr1_sumar_recargos` | orden_item_opciones | After Insert Update Delete | RN-R04: suma los recargos de las opciones en la línea de la orden. |

## Veterinaria

| Trigger | Tabla(s) | Cuándo | Para qué sirve |
| --- | --- | --- | --- |
| `tv1_no_atender_fallecida` | atenciones | Before Insert | RN-V06: una mascota fallecida no recibe citas. |
| `tv2_historia_inmutable` | registros_clinicos | Before Update Delete | RN-V04: la historia clínica no se edita ni se borra pasadas 24 horas. |
