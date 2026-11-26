# Inventario de triggers

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

Además de los de esta tabla hay dos triggers genéricos: `t01_actualizado_en` en **82 tablas** (mantiene la fecha de modificación) y `t02_auditoria` en **71 tablas** (bitácora de cambios).

| Tabla | Trigger | Función | Momento |
| --- | --- | --- | --- |
| `audit.registros_auditoria` | `t00_origen_conexion` | `completar_origen_conexion` | BEFORE INSERT |
| `elius.agentes` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.agentes` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.asignaciones_recurso` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.asignaciones_recurso` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.canales` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.canales` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.categorias_catalogo` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.categorias_catalogo` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.comprobantes_pago` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.comprobantes_pago` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.comprobantes_pago` | `t52_revisar_comprobante` | `revisar_comprobante` | BEFORE INSERT |
| `elius.comprobantes_pago` | `t53_evento_comprobante` | `evento_comprobante` | AFTER INSERT |
| `elius.comprobantes_pago` | `t55_solo_admin_decide` | `solo_admin_decide_comprobantes` | BEFORE UPDATE |
| `elius.comprobantes_pago` | `t56_aviso_celular_comprobante` | `avisar_comprobante_celular` | AFTER INSERT |
| `elius.consentimientos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.consentimientos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.consumos_llm` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.consumos_llm` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.contactos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.contactos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.contactos` | `t07_proteger_baja` | `proteger_baja_cliente` | BEFORE UPDATE |
| `elius.conversaciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.conversaciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.direcciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.direcciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.documentos_conocimiento` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.documentos_conocimiento` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.entregas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.entregas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.errores_agente` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.errores_agente` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.escalamientos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.escalamientos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.escalamientos` | `t22_asignar_escalamiento` | `asignar_escalamiento` | BEFORE INSERT |
| `elius.escalamientos` | `t23_despues_de_escalamiento` | `despues_de_escalamiento` | AFTER INSERT UPDATE |
| `elius.eventos_embudo` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.eventos_embudo` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.eventos_salida` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.eventos_salida` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.fragmentos_conocimiento` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.fragmentos_conocimiento` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.horarios_atencion` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.horarios_atencion` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.identidades_contacto` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.identidades_contacto` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.item_adicionales` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.item_adicionales` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.items_catalogo` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.items_catalogo` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.medios_item` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.medios_item` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.mensajes` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.mensajes` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.mensajes` | `t20_antes_de_mensaje` | `antes_de_mensaje` | BEFORE INSERT |
| `elius.mensajes` | `t21_despues_de_mensaje` | `despues_de_mensaje` | AFTER INSERT |
| `elius.notificaciones_pasarela` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.notificaciones_pasarela` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.orden_items` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.orden_items` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.orden_items` | `t41_antes_de_linea` | `antes_de_linea` | BEFORE INSERT UPDATE DELETE |
| `elius.orden_items` | `t42_recalcular_orden` | `despues_de_linea` | AFTER INSERT UPDATE DELETE |
| `elius.ordenes` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.ordenes` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.ordenes` | `t07_proteger_baja` | `proteger_baja_pedido_reserva` | BEFORE UPDATE |
| `elius.ordenes` | `t40_numero_orden` | `numero_orden` | BEFORE INSERT |
| `elius.ordenes` | `t43_proteger_totales` | `proteger_totales_orden` | BEFORE UPDATE |
| `elius.ordenes` | `t44_eventos_orden` | `eventos_orden` | AFTER UPDATE |
| `elius.pagos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.pagos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.pagos` | `t50_proteger_pago` | `proteger_pago` | BEFORE UPDATE DELETE |
| `elius.pagos` | `t51_aplicar_pago` | `aplicar_pago` | AFTER INSERT UPDATE |
| `elius.parametros_negocio` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.parametros_negocio` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.pasarelas_pago` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.pasarelas_pago` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.recaudos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.recaudos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.recaudos` | `t54_recaudo_pagado` | `recaudo_pagado` | AFTER UPDATE |
| `elius.recursos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.recursos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.reservas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.reservas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.reservas` | `t06_marcada_por` | `reserva_marcada_por` | BEFORE UPDATE |
| `elius.reservas` | `t07_proteger_baja` | `proteger_baja_pedido_reserva` | BEFORE UPDATE |
| `elius.reservas` | `t30_codigo_reserva` | `codigo_reserva` | BEFORE INSERT |
| `elius.reservas` | `t31_fecha_reserva` | `validar_fecha_reserva` | BEFORE INSERT UPDATE |
| `elius.reservas` | `t32_transicion_reserva` | `validar_transicion_reserva` | BEFORE UPDATE |
| `elius.reservas` | `t33_eventos_reserva` | `eventos_reserva` | AFTER INSERT UPDATE |
| `elius.suscripciones_push` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.suscripciones_push` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.ticket_notas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.ticket_notas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.tickets` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `elius.tickets` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `elius.tickets` | `t60_codigo_ticket` | `codigo_ticket` | BEFORE INSERT |
| `elius.tickets` | `t61_estado_ticket` | `estado_ticket` | BEFORE UPDATE |
| `ext.conversaciones_capturadas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `ext.conversaciones_capturadas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `ext.evidencias_patron` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `ext.evidencias_patron` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `ext.instalaciones_extension` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `ext.instalaciones_extension` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `ext.mensajes_capturados` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `ext.mensajes_capturados` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `ext.patrones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `ext.patrones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `ext.sitios_autorizados` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `ext.sitios_autorizados` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.accesos_bd` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.accesos_bd` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.accesos_especiales` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.accesos_especiales` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.accesos_soporte` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.accesos_soporte` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.ajustes_globales` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.ajustes_globales` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.asignaciones_plataforma` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.asignaciones_plataforma` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.asignaciones_plataforma` | `t10_nivel_rol` | `validar_nivel_rol` | BEFORE INSERT UPDATE |
| `platform.consumos_periodo` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.consumos_periodo` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.invitaciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.invitaciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.llaves_api` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.llaves_api` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.membresias` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.membresias` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.membresias` | `t10_nivel_rol` | `validar_nivel_rol` | BEFORE INSERT UPDATE |
| `platform.membresias` | `t11_ultimo_admin` | `proteger_ultimo_admin` | BEFORE UPDATE DELETE |
| `platform.membresias` | `t12_limite_usuarios` | `validar_limite_usuarios` | BEFORE INSERT |
| `platform.permisos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.permisos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.planes` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.planes` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.plugins` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.plugins` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.push_suscripciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.push_suscripciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.rol_permisos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.rol_permisos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.roles` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.roles` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.tenant_plugins` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.tenant_plugins` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.tenants` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `platform.tenants` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `platform.tenants` | `t90_accesos_bd` | `sincronizar_accesos_bd_trg` | AFTER INSERT |
| `platform.tenants` | `t91_usuarios_por_negocio` | `asignar_usuarios_por_negocio_trg` | AFTER INSERT |
| `plugin_airline.aeronaves` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.aeronaves` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.aeropuertos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.aeropuertos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.equipajes` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.equipajes` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.reserva_pasajeros` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.reserva_pasajeros` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.reserva_pasajeros` | `ta3_infantes` | `validar_infantes` | AFTER INSERT UPDATE |
| `plugin_airline.rutas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.rutas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.tarifas_vuelo` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.tarifas_vuelo` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.tarifas_vuelo` | `ta1_capacidad` | `validar_capacidad` | BEFORE INSERT UPDATE |
| `plugin_airline.tiquetes` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.tiquetes` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.tiquetes` | `ta4_silla` | `validar_silla` | BEFORE INSERT UPDATE |
| `plugin_airline.tramos_reserva` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.tramos_reserva` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.tramos_reserva` | `ta2_ocupar_cupo` | `ocupar_cupo` | BEFORE INSERT |
| `plugin_airline.vuelos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_airline.vuelos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_airline.vuelos` | `ta5_evento_vuelo` | `evento_vuelo` | AFTER UPDATE |
| `plugin_restaurant.alergenos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.alergenos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.celebraciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.celebraciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.comanda_items` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.comanda_items` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.comandas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.comandas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.estaciones_cocina` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.estaciones_cocina` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.grupos_modificador` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.grupos_modificador` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.item_alergenos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.item_alergenos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.item_grupos_modificador` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.item_grupos_modificador` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.menu_dia_items` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.menu_dia_items` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.menus_dia` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.menus_dia` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.opciones_modificador` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.opciones_modificador` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.orden_item_opciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_restaurant.orden_item_opciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_restaurant.orden_item_opciones` | `tr0_precio_opcion` | `precio_opcion` | BEFORE INSERT |
| `plugin_restaurant.orden_item_opciones` | `tr1_sumar_recargos` | `sumar_recargos` | AFTER INSERT UPDATE DELETE |
| `plugin_vet.aplicaciones_vacuna` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_vet.aplicaciones_vacuna` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_vet.atenciones` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_vet.atenciones` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_vet.atenciones` | `tv1_no_atender_fallecida` | `no_atender_fallecida` | BEFORE INSERT |
| `plugin_vet.mascotas` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_vet.mascotas` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_vet.propietarios_mascota` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_vet.propietarios_mascota` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_vet.registros_clinicos` | `t00_sin_baja_directa` | `bloquear_baja_directa` | BEFORE UPDATE DELETE |
| `plugin_vet.registros_clinicos` | `t00_sin_truncate_directo` | `bloquear_baja_directa` | BEFORE |
| `plugin_vet.registros_clinicos` | `tv2_historia_inmutable` | `historia_inmutable` | BEFORE UPDATE DELETE |
