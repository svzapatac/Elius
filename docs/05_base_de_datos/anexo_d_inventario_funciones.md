# Inventario de funciones y procedimientos

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

**INVOKER** corre con los permisos de quien llama (RLS aplica). **DEFINER** corre con los del dueño y se reserva para casos justificados (ver 09_procedimientos.md).

| Función | Parámetros | Seguridad | Descripción |
| --- | --- | --- | --- |
| `app.aplicar_rls` | `p_tabla regclass, p_permiso text` | INVOKER |  |
| `app.clave_temporal` | `` | INVOKER |  |
| `app.codigo_aleatorio` | `p_largo integer` | INVOKER |  |
| `app.correo_miembro` | `p_usuario uuid` | DEFINER |  |
| `app.current_tenant_id` | `` | DEFINER | Tenant de la petición: JWT/X-Tenant-ID validado contra la membresía, o app.tenant_id para el backend de confianza |
| `app.dinero_de_reserva` | `p_reserva uuid` | DEFINER |  |
| `app.emitir_evento` | `p_tenant uuid, p_tipo text, p_entidad text, p_id uuid, p_carga jsonb` | DEFINER |  |
| `app.enviar_push_tenant` | `p_tenant uuid, p_mensaje jsonb, p_usuario uuid` | DEFINER |  |
| `app.es_super_admin` | `` | DEFINER |  |
| `app.es_uuid` | `p text` | INVOKER |  |
| `app.mi_membresia` | `` | DEFINER |  |
| `app.mi_rol` | `` | DEFINER |  |
| `app.nivel_permiso` | `p_codigo text` | DEFINER |  |
| `app.parametro` | `p_tenant uuid, p_clave text` | DEFINER |  |
| `app.plugin_habilitado` | `p_codigo text` | DEFINER |  |
| `app.puede` | `p_codigo text, p_nivel text` | DEFINER | true si el usuario actual tiene al menos ese nivel (lectura, escritura, total) en el módulo |
| `app.recalcular_orden` | `p_tenant uuid, p_orden uuid` | DEFINER |  |
| `app.soporte_autorizado` | `p_usuario uuid, p_tenant uuid` | DEFINER |  |
| `app.soporte_o_admin` | `` | DEFINER |  |
| `app.tiene_acceso_tenant` | `p_usuario uuid, p_tenant uuid` | DEFINER |  |
| `app.uid` | `` | DEFINER |  |
| `elius.agendar_reserva` | `p_contacto uuid, p_tipo text, p_inicio timestamp with time zone, p_fin timestamp with time zone, p_personas integer, p_recursos uuid[], p_notas text, p_conversacion uuid` | INVOKER |  |
| `elius.agregar_item` | `p_orden uuid, p_item uuid, p_cantidad numeric, p_notas text` | INVOKER |  |
| `elius.aprobar_comprobante` | `p_comprobante uuid, p_resto_contra_entrega boolean` | INVOKER |  |
| `elius.avisos_celular_info` | `` | DEFINER |  |
| `elius.cambiar_rol_demo` | `p_rol text` | DEFINER | Cambia el rol de quien prueba un caso (administrador, operador o analista) para ver el panel de cada uno |
| `elius.cancelar_reserva` | `p_id uuid, p_motivo text` | DEFINER | El Administrador cancela una reserva con motivo: libera la mesa, cancela el pedido sin pago y avisa si hay pago aprobado |
| `elius.consola_auditar` | `p_sql text, p_motivo text` | DEFINER |  |
| `elius.consola_sql` | `p_sql text` | INVOKER | Consola SQL restringida para revisión: SELECT/INSERT/UPDATE y CREATE solo en practica |
| `elius.crear_orden` | `p_contacto uuid, p_canal text, p_tipo_entrega text, p_reserva uuid, p_conversacion uuid, p_direccion uuid` | INVOKER |  |
| `elius.crear_pedido_manual` | `p_contacto uuid, p_tipo_entrega text, p_items jsonb` | INVOKER | El Administrador crea un pedido a mano con sus líneas; precios y total los calcula la base de datos |
| `elius.crear_ticket` | `p_categoria text, p_prioridad text, p_asunto text, p_descripcion text, p_contacto uuid` | DEFINER | Abre un ticket (registro manual) con categoría y prioridad |
| `elius.datos_caso_demo` | `p_vertical text` | INVOKER |  |
| `elius.devolver_a_eli` | `p_conversacion uuid` | INVOKER |  |
| `elius.efectos_demo` | `p_tenant uuid, p_conv uuid, p_msg uuid, p_texto text, p_efectos jsonb, p_tras integer` | DEFINER |  |
| `elius.eliminar_definitivo` | `p_tipo text, p_id uuid` | DEFINER | Borrado real de un producto o cliente que ya está en la Papelera; solo CIS adm |
| `elius.eliminar_pedido` | `p_id uuid` | DEFINER | Elimina (desactiva) un pedido: va a la Papelera. Solo Administrador; no aplica si tiene pagos aprobados |
| `elius.eliminar_reserva` | `p_id uuid` | DEFINER | Elimina (desactiva) una reserva: va a la Papelera. Solo Administrador |
| `elius.encender_eli` | `p_activo boolean` | INVOKER |  |
| `elius.enmascarar_correo` | `p text` | INVOKER |  |
| `elius.enmascarar_telefono` | `p text` | INVOKER |  |
| `elius.enviar_aviso_prueba` | `` | DEFINER |  |
| `elius.enviar_push_prueba` | `` | DEFINER |  |
| `elius.escalar_conversacion` | `p_conversacion uuid, p_motivo text, p_mensaje text, p_resumen text` | INVOKER |  |
| `elius.estado_demo` | `p_tenant uuid, p_d jsonb` | DEFINER |  |
| `elius.estado_push` | `` | DEFINER |  |
| `elius.estrategia_cobro` | `p_monto numeric` | INVOKER |  |
| `elius.generar_comprobante_prueba` | `p_caso text` | DEFINER | Crea un cliente, un pedido y un comprobante de pago de prueba (exacto, de monto distinto o repetido) para ver actuar los triggers; solo Administrador en negocios demo |
| `elius.generar_ticket_prueba` | `p_tipo text` | DEFINER | Inventa un ticket real con su problema para la prueba en vivo (solo negocios de demostración) |
| `elius.guardar_suscripcion_push` | `p_endpoint text, p_p256dh text, p_auth text, p_dispositivo text` | DEFINER |  |
| `elius.liberar_reserva` | `p_reserva uuid` | DEFINER | El Administrador quita al responsable de una reserva para que otro Operador la tome |
| `elius.limpiar_caso_demo` | `p_tenant uuid` | DEFINER |  |
| `elius.marcar_llegada` | `p_reserva uuid` | INVOKER | El equipo registra que el cliente llegó: solo el día de la reserva y si está confirmada |
| `elius.marcar_no_asistidas` | `` | INVOKER |  |
| `elius.marcar_no_llegada` | `p_reserva uuid` | INVOKER | El equipo registra que el cliente no llegó: solo cuando ya pasó la hora; libera la mesa o recurso |
| `elius.nombre_categoria_ticket` | `p text` | INVOKER |  |
| `elius.nota_ticket_interna` | `p_ticket uuid, p_tipo text, p_texto text` | DEFINER |  |
| `elius.procesar_webhook_factus` | `p_pasarela uuid, p_clave_valida boolean, p_carga jsonb` | INVOKER |  |
| `elius.push_clave_publica` | `` | DEFINER |  |
| `elius.quitar_suscripcion_push` | `p_endpoint text` | DEFINER |  |
| `elius.rechazar_comprobante` | `p_comprobante uuid, p_motivo text` | INVOKER |  |
| `elius.registrar_comprobante` | `p_conversacion uuid, p_orden uuid, p_monto_leido numeric, p_remitente text, p_destinatario text, p_app text, p_referencia text, p_fecha_texto text, p_hash text, p_url text, p_media_id text` | INVOKER |  |
| `elius.registrar_recaudo` | `p_orden uuid, p_codigo text, p_monto numeric, p_llave text, p_url_qr text, p_expira timestamp with time zone` | INVOKER |  |
| `elius.reiniciar_demo` | `` | DEFINER |  |
| `elius.reportar_problema` | `p_mensaje text` | DEFINER | El Trabajador (o el Administrador) reporta un problema; queda en los errores que atiende Soporte |
| `elius.resolver_escalamiento` | `p_escalamiento uuid` | INVOKER |  |
| `elius.restaurar_pedido` | `p_id uuid` | DEFINER |  |
| `elius.restaurar_reserva` | `p_id uuid` | DEFINER |  |
| `elius.sembrar_clientes_demo` | `p_tenant uuid, p_vertical text` | DEFINER |  |
| `elius.sembrar_plugin_demo` | `p_tenant uuid, p_vertical text` | DEFINER |  |
| `elius.siguiente_mensaje_demo` | `` | DEFINER | Entrega el siguiente mensaje del guion del caso de prueba; tras aprobar o rechazar un comprobante, Eli continúa esa conversación |
| `elius.soltar_bloqueo` | `p_conversacion uuid` | INVOKER |  |
| `elius.soporte_cambiar_rol_usuario` | `p_usuario uuid, p_rol text, p_ticket uuid` | DEFINER |  |
| `elius.soporte_corregir_cliente` | `p_contacto uuid, p_ticket uuid, p_nombres text, p_apellidos text, p_telefono text, p_email text, p_motivo text` | DEFINER | Corrige un dato de un cliente con motivo y ligado a un ticket abierto; queda en la nota del ticket y en la auditoría |
| `elius.soporte_crear_usuario` | `p_ticket uuid, p_email text, p_rol text, p_cargo text` | DEFINER | Crea un usuario del negocio con su rol y una clave temporal que se muestra una sola vez |
| `elius.soporte_estado_integraciones` | `` | DEFINER | Conteos de salud (errores, eventos, avisos) sin datos del cliente |
| `elius.soporte_estado_usuario` | `p_usuario uuid, p_activo boolean, p_ticket uuid` | DEFINER |  |
| `elius.soporte_nota_ticket` | `p_id uuid, p_texto text` | DEFINER |  |
| `elius.soporte_reintentar_evento` | `p_id uuid` | DEFINER | Soporte/Administrador deja un evento de salida fallido otra vez en pendiente para que se reintente |
| `elius.soporte_resolver_error` | `p_id uuid, p_nota text` | DEFINER | Soporte/Administrador marca un error como resuelto, con una nota |
| `elius.soporte_resolver_ticket` | `p_id uuid, p_solucion text` | DEFINER | Soporte resuelve el ticket con la solución escrita |
| `elius.soporte_restablecer_clave` | `p_usuario uuid, p_ticket uuid` | DEFINER | Genera una clave temporal nueva para un usuario del negocio (se muestra una sola vez) |
| `elius.soporte_tomar_ticket` | `p_id uuid` | DEFINER | Soporte toma el ticket: pasa a En proceso y queda asignado |
| `elius.srv_actualizar_secreto` | `p_id uuid, p_valor text` | DEFINER |  |
| `elius.srv_pasarela_webhook` | `p_pasarela uuid` | DEFINER |  |
| `elius.srv_secreto` | `p_id uuid` | DEFINER |  |
| `elius.tomar_bloqueo` | `p_conversacion uuid, p_segundos integer` | INVOKER |  |
| `elius.tomar_conversacion` | `p_conversacion uuid` | INVOKER |  |
| `elius.tomar_reserva` | `p_reserva uuid` | DEFINER | El Operador toma una reserva libre y queda como su responsable |
| `elius.trab_avanzar_comanda` | `p_comanda uuid` | INVOKER | Restaurante: la comanda pasa de recibida a en preparación y luego a lista |
| `elius.trab_cerrar_atencion` | `p_atencion uuid` | INVOKER | Veterinaria: finaliza la atención |
| `elius.trab_hacer_checkin` | `p_tiquete uuid, p_silla text` | INVOKER | Aerolínea: check-in del pasajero (RN-A08: ventana de 48 h a 1 h antes) |
| `elius.trab_registrar_signos` | `p_atencion uuid, p_peso numeric, p_temperatura numeric` | INVOKER | Veterinaria: registra peso y temperatura y deja la atención en curso |
| `elius.webhook_factus` | `p_pasarela uuid, p_clave_valida boolean, p_carga jsonb` | DEFINER |  |
| `platform.aceptar_invitacion` | `p_token text` | DEFINER |  |
| `platform.asignar_usuarios_por_negocio` | `p_tenant uuid` | DEFINER |  |
| `platform.autorizar_soporte` | `p_usuario_soporte uuid, p_motivo text, p_horas integer` | INVOKER |  |
| `platform.cambiar_tenant` | `p_tenant uuid` | DEFINER |  |
| `platform.cargar_caso_demo` | `p_vertical text` | DEFINER | Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes |
| `platform.completar_usuarios_auth` | `` | DEFINER |  |
| `platform.crear_tenant` | `p_nombre text, p_slug text, p_vertical text, p_plan text` | DEFINER |  |
| `platform.invitar_usuario` | `p_email text, p_rol text` | INVOKER |  |
| `platform.mis_negocios` | `` | DEFINER | Negocios a los que tiene acceso la conexión directa (cuál está activo) |
| `platform.negocios_autorizados_soporte` | `` | DEFINER | Negocios con una autorización vigente para el usuario de Soporte |
| `platform.otorgar_acceso_especial` | `p_membresia uuid, p_permiso text, p_motivo text, p_vence timestamp with time zone` | INVOKER |  |
| `platform.renovar_soporte_bd` | `` | DEFINER | Renueva por 7 días el acceso del usuario de Soporte (conexión directa) a todos los negocios |
| `platform.sincronizar_accesos_bd` | `p_tenant uuid` | DEFINER |  |
| `platform.usar_negocio` | `p_slug text` | DEFINER | Elige el negocio de la sesión en una conexión directa: select platform.usar_negocio('slug') |
| `plugin_airline.hacer_checkin` | `p_tiquete uuid, p_silla text` | INVOKER |  |
| `plugin_restaurant.agregar_opcion` | `p_linea uuid, p_opcion uuid, p_cantidad integer` | INVOKER |  |
| `plugin_restaurant.confirmar_menu_dia` | `p_menu uuid` | INVOKER |  |
| `plugin_vet.registrar_vacuna` | `p_mascota uuid, p_vacuna uuid, p_lote text, p_atencion uuid, p_proxima date` | INVOKER |  |
