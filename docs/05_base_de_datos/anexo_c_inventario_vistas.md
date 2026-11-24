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
| `elius.v_recaudos_abiertos` | sí | Cobros por llave Bre-B pendientes de pago (RN-C22) |
| `elius.v_resumen_mensual` | sí | Un renglón por mes: órdenes, ventas, ticket promedio y atención de Eli (reutiliza v_ventas_diarias y v_metricas_conversaciones) |
| `elius.v_saldo_ordenes` | sí | Total, pagado y saldo de cada orden (RN-C17) |
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
