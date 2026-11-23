# Relaciones

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

El modelo tiene **191 relaciones**, todas de uno a muchos. No hay relaciones 1 a 1 ni muchos a muchos directas; el script `generar.py` lo verifica cada vez que se genera el modelo.

- **Cardinalidad** se lee desde la tabla padre hacia la tabla hija: `1 a 0..N` = un padre tiene cero o muchos hijos y cada hijo tiene exactamente un padre; `0..1 a 0..N` = el hijo puede no tener padre (FK opcional).
- **Compuesta = sí**: la llave es `(tenant_id, columna)` → `(tenant_id, id)`, así una fila nunca apunta a otro tenant (DT-07).
- **Al borrar el padre**: CASCADE borra los hijos; SET NULL deja el hijo sin padre; RESTRICT impide borrar catálogos y configuración que están en uso.

## Tablas de transición (24)

| Tabla | Resuelve el muchos a muchos entre | Datos propios de la relación |
| --- | --- | --- |
| `platform.rol_permisos` | `roles` y `permisos` | nivel, origen |
| `platform.membresias` | `tenants` y `usuarios` | estado, cargo, es_predeterminada, fecha_ingreso |
| `platform.accesos_especiales` | `membresias` y `permisos` | motivo, vence_en |
| `platform.asignaciones_plataforma` | `usuarios` y `roles` | desde, hasta |
| `platform.tenant_plugins` | `tenants` y `plugins` | habilitado, configuracion, version_instalada |
| `platform.accesos_soporte` | `tenants` y `usuarios` | motivo, inicio, vence_en, revocado_en |
| `elius.identidades_contacto` | `contactos` y `canales` | id_externo, nombre_en_canal, verificado, primer_contacto_en, ultimo_contacto_en |
| `elius.asignaciones_recurso` | `reservas` y `recursos` | inicio, fin, estado, notas |
| `elius.orden_items` | `ordenes` y `items_catalogo` | cantidad, precio_unitario, recargos, descuento, total_linea, notas |
| `elius.item_adicionales` | `items_catalogo` y `items_catalogo` | precio_especial, cantidad_maxima, orden |
| `ext.evidencias_patron` | `patrones` y `mensajes_capturados` | relevancia, fragmento, detectado_en |
| `plugin_vet.propietarios_mascota` | `contactos` y `mascotas` | tipo, puede_autorizar, desde |
| `plugin_vet.atenciones` | `reservas` y `mascotas` | motivo, estado, peso_kg, temperatura_c |
| `plugin_vet.aplicaciones_vacuna` | `mascotas` y `items_catalogo` | lote, aplicada_en, proxima_dosis_en |
| `plugin_restaurant.item_alergenos` | `items_catalogo` y `alergenos` | nivel, nota |
| `plugin_restaurant.item_grupos_modificador` | `items_catalogo` y `grupos_modificador` | minimo, maximo, orden |
| `plugin_restaurant.orden_item_opciones` | `orden_items` y `opciones_modificador` | cantidad, precio_aplicado |
| `plugin_restaurant.comanda_items` | `comandas` y `orden_items` | cantidad, estado, nota_cocina |
| `plugin_restaurant.menu_dia_items` | `menus_dia` y `items_catalogo` | seccion, posicion, disponible |
| `plugin_airline.rutas` | `aeropuertos` y `aeropuertos` | distancia_km, duracion_min, activa |
| `plugin_airline.tarifas_vuelo` | `vuelos` y `items_catalogo` | precio, cupos_totales, cupos_vendidos |
| `plugin_airline.reserva_pasajeros` | `reservas` y `contactos` | tipo_pasajero, necesidades_especiales |
| `plugin_airline.tramos_reserva` | `reservas` y `tarifas_vuelo` | orden_tramo, estado |
| `plugin_airline.tiquetes` | `reserva_pasajeros` y `tramos_reserva` | numero_tiquete, silla, estado, checkin_en |

## Modelo general

### `platform` (27 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `platform.tenants` | `plan_id` | `platform.planes` | 1 a 0..N | no | RESTRICT |
| `platform.permisos` | `plugin_id` | `platform.plugins` | 0..1 a 0..N | no | SET NULL |
| `platform.rol_permisos` | `rol_id` | `platform.roles` | 1 a 0..N | no | RESTRICT |
| `platform.rol_permisos` | `permiso_id` | `platform.permisos` | 1 a 0..N | no | RESTRICT |
| `platform.membresias` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `platform.membresias` | `usuario_id` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.membresias` | `rol_id` | `platform.roles` | 1 a 0..N | no | RESTRICT |
| `platform.membresias` | `invitado_por` | `platform.usuarios` | 0..1 a 0..N | no | SET NULL |
| `platform.accesos_especiales` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `platform.accesos_especiales` | `membresia_id` | `platform.membresias` | 1 a 0..N | sí | CASCADE |
| `platform.accesos_especiales` | `permiso_id` | `platform.permisos` | 1 a 0..N | no | RESTRICT |
| `platform.accesos_especiales` | `otorgado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.asignaciones_plataforma` | `usuario_id` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.asignaciones_plataforma` | `rol_id` | `platform.roles` | 1 a 0..N | no | RESTRICT |
| `platform.asignaciones_plataforma` | `asignado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.tenant_plugins` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `platform.tenant_plugins` | `plugin_id` | `platform.plugins` | 1 a 0..N | no | RESTRICT |
| `platform.tenant_plugins` | `instalado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.accesos_soporte` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `platform.accesos_soporte` | `usuario_soporte_id` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.accesos_soporte` | `autorizado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.invitaciones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `platform.invitaciones` | `rol_id` | `platform.roles` | 1 a 0..N | no | RESTRICT |
| `platform.invitaciones` | `invitado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.llaves_api` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `platform.llaves_api` | `creado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `platform.consumos_periodo` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
### `audit` (2 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `audit.registros_auditoria` | `tenant_id` | `platform.tenants` | 0..1 a 0..N | no | CASCADE |
| `audit.registros_auditoria` | `usuario_id` | `platform.usuarios` | 0..1 a 0..N | no | SET NULL |
### `elius` (81 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `elius.contactos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.direcciones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.direcciones` | `contacto_id` | `elius.contactos` | 1 a 0..N | sí | CASCADE |
| `elius.consentimientos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.consentimientos` | `contacto_id` | `elius.contactos` | 1 a 0..N | sí | CASCADE |
| `elius.agentes` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.canales` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.canales` | `agente_id` | `elius.agentes` | 1 a 0..N | sí | RESTRICT |
| `elius.identidades_contacto` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.identidades_contacto` | `contacto_id` | `elius.contactos` | 1 a 0..N | sí | CASCADE |
| `elius.identidades_contacto` | `canal_id` | `elius.canales` | 1 a 0..N | sí | RESTRICT |
| `elius.conversaciones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.conversaciones` | `identidad_id` | `elius.identidades_contacto` | 1 a 0..N | sí | CASCADE |
| `elius.conversaciones` | `asignado_a` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.mensajes` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.mensajes` | `conversacion_id` | `elius.conversaciones` | 1 a 0..N | sí | CASCADE |
| `elius.consumos_llm` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.consumos_llm` | `conversacion_id` | `elius.conversaciones` | 1 a 0..N | sí | CASCADE |
| `elius.consumos_llm` | `mensaje_id` | `elius.mensajes` | 0..1 a 0..N | sí | SET NULL |
| `elius.categorias_catalogo` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.items_catalogo` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.items_catalogo` | `categoria_id` | `elius.categorias_catalogo` | 1 a 0..N | sí | RESTRICT |
| `elius.recursos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.horarios_atencion` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.horarios_atencion` | `recurso_id` | `elius.recursos` | 0..1 a 0..N | sí | SET NULL |
| `elius.reservas` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.reservas` | `contacto_id` | `elius.contactos` | 1 a 0..N | sí | CASCADE |
| `elius.reservas` | `conversacion_id` | `elius.conversaciones` | 0..1 a 0..N | sí | SET NULL |
| `elius.reservas` | `responsable_id` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.asignaciones_recurso` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.asignaciones_recurso` | `reserva_id` | `elius.reservas` | 1 a 0..N | sí | CASCADE |
| `elius.asignaciones_recurso` | `recurso_id` | `elius.recursos` | 1 a 0..N | sí | RESTRICT |
| `elius.ordenes` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.ordenes` | `contacto_id` | `elius.contactos` | 0..1 a 0..N | sí | SET NULL |
| `elius.ordenes` | `reserva_id` | `elius.reservas` | 0..1 a 0..N | sí | SET NULL |
| `elius.ordenes` | `conversacion_id` | `elius.conversaciones` | 0..1 a 0..N | sí | SET NULL |
| `elius.ordenes` | `direccion_entrega_id` | `elius.direcciones` | 0..1 a 0..N | sí | SET NULL |
| `elius.ordenes` | `responsable_id` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.orden_items` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.orden_items` | `orden_id` | `elius.ordenes` | 1 a 0..N | sí | CASCADE |
| `elius.orden_items` | `item_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `elius.pagos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.pagos` | `orden_id` | `elius.ordenes` | 1 a 0..N | sí | CASCADE |
| `elius.pagos` | `pago_original_id` | `elius.pagos` | 0..1 a 0..N | sí | SET NULL |
| `elius.pagos` | `comprobante_id` | `elius.comprobantes_pago` | 0..1 a 0..N | sí | SET NULL |
| `elius.pagos` | `recaudo_id` | `elius.recaudos` | 0..1 a 0..N | sí | SET NULL |
| `elius.comprobantes_pago` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.comprobantes_pago` | `orden_id` | `elius.ordenes` | 0..1 a 0..N | sí | SET NULL |
| `elius.comprobantes_pago` | `conversacion_id` | `elius.conversaciones` | 1 a 0..N | sí | CASCADE |
| `elius.comprobantes_pago` | `decidido_por` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.pasarelas_pago` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.recaudos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.recaudos` | `orden_id` | `elius.ordenes` | 1 a 0..N | sí | CASCADE |
| `elius.recaudos` | `pasarela_id` | `elius.pasarelas_pago` | 1 a 0..N | sí | RESTRICT |
| `elius.notificaciones_pasarela` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.notificaciones_pasarela` | `pasarela_id` | `elius.pasarelas_pago` | 1 a 0..N | sí | RESTRICT |
| `elius.notificaciones_pasarela` | `recaudo_id` | `elius.recaudos` | 0..1 a 0..N | sí | SET NULL |
| `elius.entregas` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.entregas` | `orden_id` | `elius.ordenes` | 1 a 0..N | sí | CASCADE |
| `elius.entregas` | `repartidor_id` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.item_adicionales` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.item_adicionales` | `item_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `elius.item_adicionales` | `adicional_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `elius.medios_item` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.medios_item` | `item_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `elius.escalamientos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.escalamientos` | `conversacion_id` | `elius.conversaciones` | 1 a 0..N | sí | CASCADE |
| `elius.escalamientos` | `asignado_a` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.escalamientos` | `resuelto_por` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `elius.eventos_embudo` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.eventos_embudo` | `conversacion_id` | `elius.conversaciones` | 1 a 0..N | sí | CASCADE |
| `elius.errores_agente` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.errores_agente` | `conversacion_id` | `elius.conversaciones` | 0..1 a 0..N | sí | SET NULL |
| `elius.errores_agente` | `resuelto_por` | `platform.usuarios` | 0..1 a 0..N | no | SET NULL |
| `elius.parametros_negocio` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.suscripciones_push` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.suscripciones_push` | `membresia_id` | `platform.membresias` | 1 a 0..N | sí | CASCADE |
| `elius.documentos_conocimiento` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.fragmentos_conocimiento` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `elius.fragmentos_conocimiento` | `documento_id` | `elius.documentos_conocimiento` | 1 a 0..N | sí | CASCADE |
| `elius.eventos_salida` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
### `ext` (15 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `ext.instalaciones_extension` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `ext.instalaciones_extension` | `membresia_id` | `platform.membresias` | 1 a 0..N | sí | CASCADE |
| `ext.sitios_autorizados` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `ext.sitios_autorizados` | `autorizado_por` | `platform.usuarios` | 1 a 0..N | no | CASCADE |
| `ext.conversaciones_capturadas` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `ext.conversaciones_capturadas` | `instalacion_id` | `ext.instalaciones_extension` | 1 a 0..N | sí | CASCADE |
| `ext.conversaciones_capturadas` | `sitio_id` | `ext.sitios_autorizados` | 1 a 0..N | sí | RESTRICT |
| `ext.conversaciones_capturadas` | `contacto_id` | `elius.contactos` | 0..1 a 0..N | sí | SET NULL |
| `ext.mensajes_capturados` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `ext.mensajes_capturados` | `conversacion_id` | `ext.conversaciones_capturadas` | 1 a 0..N | sí | CASCADE |
| `ext.patrones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `ext.patrones` | `aprobado_por` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `ext.evidencias_patron` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `ext.evidencias_patron` | `patron_id` | `ext.patrones` | 1 a 0..N | sí | CASCADE |
| `ext.evidencias_patron` | `mensaje_id` | `ext.mensajes_capturados` | 1 a 0..N | sí | CASCADE |

## Plugins

### `plugin_vet` (18 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `plugin_vet.mascotas` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_vet.propietarios_mascota` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_vet.propietarios_mascota` | `contacto_id` | `elius.contactos` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.propietarios_mascota` | `mascota_id` | `plugin_vet.mascotas` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.atenciones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_vet.atenciones` | `reserva_id` | `elius.reservas` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.atenciones` | `mascota_id` | `plugin_vet.mascotas` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.atenciones` | `servicio_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `plugin_vet.atenciones` | `profesional_id` | `platform.membresias` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.registros_clinicos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_vet.registros_clinicos` | `atencion_id` | `plugin_vet.atenciones` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.registros_clinicos` | `autor_id` | `platform.membresias` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.registros_clinicos` | `corrige_a` | `plugin_vet.registros_clinicos` | 0..1 a 0..N | sí | SET NULL |
| `plugin_vet.aplicaciones_vacuna` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_vet.aplicaciones_vacuna` | `mascota_id` | `plugin_vet.mascotas` | 1 a 0..N | sí | CASCADE |
| `plugin_vet.aplicaciones_vacuna` | `vacuna_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `plugin_vet.aplicaciones_vacuna` | `atencion_id` | `plugin_vet.atenciones` | 0..1 a 0..N | sí | SET NULL |
| `plugin_vet.aplicaciones_vacuna` | `aplicada_por` | `platform.membresias` | 1 a 0..N | sí | CASCADE |
### `plugin_restaurant` (27 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `plugin_restaurant.alergenos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.item_alergenos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.item_alergenos` | `item_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.item_alergenos` | `alergeno_id` | `plugin_restaurant.alergenos` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.grupos_modificador` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.opciones_modificador` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.opciones_modificador` | `grupo_id` | `plugin_restaurant.grupos_modificador` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.item_grupos_modificador` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.item_grupos_modificador` | `item_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.item_grupos_modificador` | `grupo_id` | `plugin_restaurant.grupos_modificador` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.orden_item_opciones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.orden_item_opciones` | `orden_item_id` | `elius.orden_items` | 1 a 0..N | sí | CASCADE |
| `plugin_restaurant.orden_item_opciones` | `opcion_id` | `plugin_restaurant.opciones_modificador` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.estaciones_cocina` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.comandas` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.comandas` | `orden_id` | `elius.ordenes` | 1 a 0..N | sí | CASCADE |
| `plugin_restaurant.comandas` | `estacion_id` | `plugin_restaurant.estaciones_cocina` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.comanda_items` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.comanda_items` | `comanda_id` | `plugin_restaurant.comandas` | 1 a 0..N | sí | CASCADE |
| `plugin_restaurant.comanda_items` | `orden_item_id` | `elius.orden_items` | 1 a 0..N | sí | CASCADE |
| `plugin_restaurant.menus_dia` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.menus_dia` | `confirmado_por` | `platform.membresias` | 0..1 a 0..N | sí | SET NULL |
| `plugin_restaurant.menu_dia_items` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.menu_dia_items` | `menu_id` | `plugin_restaurant.menus_dia` | 1 a 0..N | sí | CASCADE |
| `plugin_restaurant.menu_dia_items` | `item_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `plugin_restaurant.celebraciones` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_restaurant.celebraciones` | `reserva_id` | `elius.reservas` | 1 a 0..N | sí | CASCADE |
### `plugin_airline` (21 relaciones)

| Tabla hija | Columna | Tabla padre | Cardinalidad | Compuesta | Al borrar el padre |
| --- | --- | --- | --- | --- | --- |
| `plugin_airline.aeronaves` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.rutas` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.rutas` | `origen_id` | `plugin_airline.aeropuertos` | 1 a 0..N | no | RESTRICT |
| `plugin_airline.rutas` | `destino_id` | `plugin_airline.aeropuertos` | 1 a 0..N | no | RESTRICT |
| `plugin_airline.vuelos` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.vuelos` | `ruta_id` | `plugin_airline.rutas` | 1 a 0..N | sí | RESTRICT |
| `plugin_airline.vuelos` | `aeronave_id` | `plugin_airline.aeronaves` | 1 a 0..N | sí | RESTRICT |
| `plugin_airline.tarifas_vuelo` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.tarifas_vuelo` | `vuelo_id` | `plugin_airline.vuelos` | 1 a 0..N | sí | CASCADE |
| `plugin_airline.tarifas_vuelo` | `tarifa_id` | `elius.items_catalogo` | 1 a 0..N | sí | RESTRICT |
| `plugin_airline.reserva_pasajeros` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.reserva_pasajeros` | `reserva_id` | `elius.reservas` | 1 a 0..N | sí | CASCADE |
| `plugin_airline.reserva_pasajeros` | `contacto_id` | `elius.contactos` | 1 a 0..N | sí | CASCADE |
| `plugin_airline.tramos_reserva` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.tramos_reserva` | `reserva_id` | `elius.reservas` | 1 a 0..N | sí | CASCADE |
| `plugin_airline.tramos_reserva` | `tarifa_vuelo_id` | `plugin_airline.tarifas_vuelo` | 1 a 0..N | sí | RESTRICT |
| `plugin_airline.tiquetes` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.tiquetes` | `reserva_pasajero_id` | `plugin_airline.reserva_pasajeros` | 1 a 0..N | sí | CASCADE |
| `plugin_airline.tiquetes` | `tramo_id` | `plugin_airline.tramos_reserva` | 1 a 0..N | sí | CASCADE |
| `plugin_airline.equipajes` | `tenant_id` | `platform.tenants` | 1 a 0..N | no | CASCADE |
| `plugin_airline.equipajes` | `tiquete_id` | `plugin_airline.tiquetes` | 1 a 0..N | sí | CASCADE |
