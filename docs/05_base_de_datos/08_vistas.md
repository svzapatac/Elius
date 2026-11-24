# Vistas

Hay **20 vistas**: 17 de negocio y 3 de reportes agregados. El código está en `database/supabase/migrations/…0600_vistas.sql`; el inventario, en el [anexo C](anexo_c_inventario_vistas.md).

## Por qué hay dos familias

| Familia | Opción | Corre con los permisos de | Quién la usa |
| --- | --- | --- | --- |
| Vistas de negocio (`elius`, plugins) | `security_invoker = true` | **Quien consulta**: aplica su RLS | Paneles, rol Analista, Eli |
| Vistas de `reportes` | por defecto | Su dueño, pero **solo agregan** conteos y montos, sin datos personales | Usuario `elius_consulta`, Super Admin |

Sin `security_invoker`, una vista de negocio mostraría los datos de todos los negocios, porque correría con los permisos de su dueño (DT-14). La prueba 16 lo comprueba: la veterinaria consulta `v_saldo_ordenes` y no ve las órdenes del restaurante.

## Vistas del modelo general

| Vista | Para qué | Quién la usa |
| --- | --- | --- |
| `elius.v_agenda_dia` | Reservas de hoy con cliente, recursos y responsable | Operador (recepción) |
| `elius.v_saldo_ordenes` | Total, pagado, cobro contra entrega y saldo pendiente de cada orden (RN-C17) | Operador, Analista, procedimientos de pago |
| `elius.v_comprobantes_pendientes` | Comprobantes por aprobar, con alertas primero (RN-C16) | Administrador (el Operador y el Analista la ven sin decidir) |
| `elius.v_recaudos_abiertos` | Cobros por llave Bre-B pendientes o vencidos | Administrador, Operador |
| `elius.v_escalamientos_abiertos` | Pendientes del equipo con su antigüedad | Operador |
| `elius.v_embudo_ultima_fase` | Fase más reciente de cada conversación | Analista |
| `elius.v_embudo_diario` | Conversaciones por día y fase | Analista |
| `elius.v_ventas_diarias` | Órdenes, ventas y ticket promedio por día, canal y tipo de entrega | Analista, Administrador |
| `elius.v_items_mas_vendidos` | Unidades y ventas por ítem | Analista |
| `elius.v_metricas_conversaciones` | Conversaciones, escaladas y % resueltas por Eli | Analista |
| `elius.v_consumo_ia_mensual` | Tokens, costo y latencia promedio y p95 de la IA | Analista, Administrador |

## Vistas de los plugins

| Vista | Para qué |
| --- | --- |
| `plugin_vet.v_vacunas_por_vencer` | Vacunas que vencen en 30 días, con propietario y teléfono, para que Eli recuerde (RN-V05) |
| `plugin_vet.v_historia_clinica` | Historia clínica completa por mascota. Solo la ve quien tiene el acceso especial, porque hereda el RLS de `registros_clinicos` |
| `plugin_restaurant.v_menu_vigente` | Menú del día de hoy, solo si el dueño lo confirmó (RN-R11) |
| `plugin_restaurant.v_cocina_pendiente` | Platos pendientes por estación y tiempo de espera |
| `plugin_airline.v_ocupacion_vuelos` | Vendidos y % de ocupación por vuelo |
| `plugin_airline.v_manifiesto` | Pasajeros por vuelo con tiquete, silla y check-in |

## Vistas de reportes (usuario `elius_consulta`)

| Vista | Para qué |
| --- | --- |
| `reportes.v_resumen_tenants` | Negocios con su plan, estado, usuarios activos y plugins |
| `reportes.v_uso_por_tenant` | Conversaciones, tokens y costo de IA por negocio y mes |
| `reportes.v_ventas_por_tenant` | Órdenes y ventas por negocio y mes |

Ninguna de estas tres devuelve nombres, teléfonos ni contenidos de mensajes. Por eso se pueden dar a un usuario de consulta sin exponer datos personales (Ley 1581).
