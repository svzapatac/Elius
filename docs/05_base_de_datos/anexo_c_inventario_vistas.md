# Inventario de vistas

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

| Vista | security_invoker (aplica el RLS de quien consulta) | Descripción |
| --- | --- | --- |
| `elius.v_agenda_calendario` | sí | Todas las reservas con cliente y recursos (calendario del panel) |
| `elius.v_agenda_dia` | sí | Reservas de hoy con cliente y recursos (panel Operador) |
| `elius.v_auditoria` | sí | Bitácora legible: quién (cargo y rol), qué tabla, qué operación y qué campos cambiaron o qué consulta ejecutó |
| `elius.v_comprobantes_pendientes` | sí | Comprobantes por aprobar, con alertas (RN-C16) |
| `elius.v_consumo_ia_mensual` | sí |  |
| `elius.v_embudo_diario` | sí |  |
| `elius.v_embudo_ultima_fase` | sí | Fase más reciente de cada conversación (métricas de conversión) |
| `elius.v_escalamientos_abiertos` | sí | Casos que Eli pasó a una persona y siguen abiertos (RN-C18) |
| `elius.v_items_mas_vendidos` | sí |  |
| `elius.v_items_mas_vendidos_mensual` | sí | Ítems más vendidos por mes (filtra por la columna mes) |
| `elius.v_metricas_conversaciones` | sí |  |
| `elius.v_mis_reportes` | no | Tickets que la persona creó (el Administrador ve los de todo el negocio): estado y solución que les da Soporte |
| `elius.v_papelera` | no | Productos, clientes, pedidos y reservas eliminados (desactivados) del negocio; el Administrador los restaura, el CIS adm los borra de verdad |
| `elius.v_recaudos_abiertos` | sí | Cobros por llave Bre-B pendientes de pago (RN-C22) |
| `elius.v_resumen_mensual` | sí | Un renglón por mes: órdenes, ventas, ticket promedio y atención de Eli (reutiliza v_ventas_diarias y v_metricas_conversaciones) |
| `elius.v_saldo_ordenes` | sí | Total, pagado y saldo de cada orden (RN-C17) |
| `elius.v_soporte_auditoria` | no |  |
| `elius.v_soporte_clientes` | no | Clientes del negocio con teléfono, correo y documento enmascarados |
| `elius.v_soporte_errores` | no |  |
| `elius.v_soporte_eventos` | no |  |
| `elius.v_soporte_historial_tickets` | no | Tickets ya resueltos con su solución: consultar si otra persona ya lo solucionó |
| `elius.v_soporte_manual` | no | Manual de soporte por categoría |
| `elius.v_soporte_ticket_notas` | no |  |
| `elius.v_soporte_tickets` | no |  |
| `elius.v_soporte_tickets_pendientes` | no | Tickets abiertos o en proceso del negocio (Soporte y Administrador) |
| `elius.v_soporte_usuarios` | no | Usuarios del negocio con su rol y estado; nunca muestra claves |
| `elius.v_trab_celebraciones` | sí |  |
| `elius.v_trab_checkin` | sí |  |
| `elius.v_trab_citas_vet` | sí |  |
| `elius.v_trab_cocina` | sí |  |
| `elius.v_trab_menu` | sí |  |
| `elius.v_trab_necesidades` | sí |  |
| `elius.v_trab_vacunas` | sí |  |
| `elius.v_trab_vuelos` | sí |  |
| `elius.v_triggers_tabla` | sí | Triggers de cada tabla: cuándo se disparan y para qué sirven (lo usa la auditoría del panel) |
| `elius.v_ventas_diarias` | sí | Ventas confirmadas por día, canal y tipo de entrega |
| `plugin_airline.v_manifiesto` | sí |  |
| `plugin_airline.v_ocupacion_vuelos` | sí |  |
| `plugin_restaurant.v_cocina_pendiente` | sí |  |
| `plugin_restaurant.v_menu_vigente` | sí |  |
| `plugin_vet.v_historia_clinica` | sí |  |
| `plugin_vet.v_vacunas_por_vencer` | sí |  |
| `reportes.v_resumen_tenants` | no |  |
| `reportes.v_uso_por_tenant` | no | Uso mensual por tenant, sin datos personales |
| `reportes.v_ventas_por_tenant` | no |  |
