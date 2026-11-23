# Inventario de triggers

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

Además de los de esta tabla hay dos triggers genéricos: `t01_actualizado_en` en **79 tablas** (mantiene la fecha de modificación) y `t02_auditoria` en **69 tablas** (bitácora de cambios).

| Tabla | Trigger | Función | Momento |
| --- | --- | --- | --- |
| `elius.comprobantes_pago` | `t52_revisar_comprobante` | `revisar_comprobante` | BEFORE INSERT |
| `elius.comprobantes_pago` | `t53_evento_comprobante` | `evento_comprobante` | AFTER INSERT |
| `elius.escalamientos` | `t22_asignar_escalamiento` | `asignar_escalamiento` | BEFORE INSERT |
| `elius.escalamientos` | `t23_despues_de_escalamiento` | `despues_de_escalamiento` | AFTER INSERT UPDATE |
| `elius.mensajes` | `t20_antes_de_mensaje` | `antes_de_mensaje` | BEFORE INSERT |
| `elius.mensajes` | `t21_despues_de_mensaje` | `despues_de_mensaje` | AFTER INSERT |
| `elius.orden_items` | `t41_antes_de_linea` | `antes_de_linea` | BEFORE INSERT UPDATE DELETE |
| `elius.orden_items` | `t42_recalcular_orden` | `despues_de_linea` | AFTER INSERT UPDATE DELETE |
| `elius.ordenes` | `t40_numero_orden` | `numero_orden` | BEFORE INSERT |
| `elius.ordenes` | `t43_proteger_totales` | `proteger_totales_orden` | BEFORE UPDATE |
| `elius.ordenes` | `t44_eventos_orden` | `eventos_orden` | AFTER UPDATE |
| `elius.pagos` | `t50_proteger_pago` | `proteger_pago` | BEFORE UPDATE DELETE |
| `elius.pagos` | `t51_aplicar_pago` | `aplicar_pago` | AFTER INSERT UPDATE |
| `elius.recaudos` | `t54_recaudo_pagado` | `recaudo_pagado` | AFTER UPDATE |
| `elius.reservas` | `t30_codigo_reserva` | `codigo_reserva` | BEFORE INSERT |
| `elius.reservas` | `t31_fecha_reserva` | `validar_fecha_reserva` | BEFORE INSERT UPDATE |
| `elius.reservas` | `t32_transicion_reserva` | `validar_transicion_reserva` | BEFORE UPDATE |
| `elius.reservas` | `t33_eventos_reserva` | `eventos_reserva` | AFTER INSERT UPDATE |
| `platform.asignaciones_plataforma` | `t10_nivel_rol` | `validar_nivel_rol` | BEFORE INSERT UPDATE |
| `platform.membresias` | `t10_nivel_rol` | `validar_nivel_rol` | BEFORE INSERT UPDATE |
| `platform.membresias` | `t11_ultimo_admin` | `proteger_ultimo_admin` | BEFORE UPDATE DELETE |
| `platform.membresias` | `t12_limite_usuarios` | `validar_limite_usuarios` | BEFORE INSERT |
| `plugin_airline.reserva_pasajeros` | `ta3_infantes` | `validar_infantes` | AFTER INSERT UPDATE |
| `plugin_airline.tarifas_vuelo` | `ta1_capacidad` | `validar_capacidad` | BEFORE INSERT UPDATE |
| `plugin_airline.tiquetes` | `ta4_silla` | `validar_silla` | BEFORE INSERT UPDATE |
| `plugin_airline.tramos_reserva` | `ta2_ocupar_cupo` | `ocupar_cupo` | BEFORE INSERT |
| `plugin_airline.vuelos` | `ta5_evento_vuelo` | `evento_vuelo` | AFTER UPDATE |
| `plugin_restaurant.orden_item_opciones` | `tr0_precio_opcion` | `precio_opcion` | BEFORE INSERT |
| `plugin_restaurant.orden_item_opciones` | `tr1_sumar_recargos` | `sumar_recargos` | AFTER INSERT UPDATE DELETE |
| `plugin_vet.atenciones` | `tv1_no_atender_fallecida` | `no_atender_fallecida` | BEFORE INSERT |
| `plugin_vet.registros_clinicos` | `tv2_historia_inmutable` | `historia_inmutable` | BEFORE UPDATE DELETE |
