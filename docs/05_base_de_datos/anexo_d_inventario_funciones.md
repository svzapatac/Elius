# Inventario de funciones y procedimientos

> Archivo generado por `database/modelo/documentar.py`. No editar a mano.

**INVOKER** corre con los permisos de quien llama (RLS aplica). **DEFINER** corre con los del dueño y se reserva para casos justificados (ver 09_procedimientos.md).

| Función | Parámetros | Seguridad | Descripción |
| --- | --- | --- | --- |
| `app.aplicar_rls` | `p_tabla regclass, p_permiso text` | INVOKER |  |
| `app.codigo_aleatorio` | `p_largo integer` | INVOKER |  |
| `app.current_tenant_id` | `` | DEFINER | Tenant de la petición: JWT/X-Tenant-ID validado contra la membresía, o app.tenant_id para el backend de confianza |
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
| `app.tiene_acceso_tenant` | `p_usuario uuid, p_tenant uuid` | DEFINER |  |
| `elius.agendar_reserva` | `p_contacto uuid, p_tipo text, p_inicio timestamp with time zone, p_fin timestamp with time zone, p_personas integer, p_recursos uuid[], p_notas text, p_conversacion uuid` | INVOKER |  |
| `elius.agregar_item` | `p_orden uuid, p_item uuid, p_cantidad numeric, p_notas text` | INVOKER |  |
| `elius.aprobar_comprobante` | `p_comprobante uuid, p_resto_contra_entrega boolean` | INVOKER |  |
| `elius.avisos_celular_info` | `` | DEFINER |  |
| `elius.cambiar_rol_demo` | `p_rol text` | DEFINER | Cambia el rol de quien prueba un caso (administrador, operador o analista) para ver el panel de cada uno |
| `elius.consola_auditar` | `p_sql text` | DEFINER |  |
| `elius.consola_sql` | `p_sql text` | INVOKER | Consola SQL restringida para revisión: SELECT/INSERT/UPDATE y CREATE solo en practica |
| `elius.crear_orden` | `p_contacto uuid, p_canal text, p_tipo_entrega text, p_reserva uuid, p_conversacion uuid, p_direccion uuid` | INVOKER |  |
| `elius.datos_caso_demo` | `p_vertical text` | INVOKER |  |
| `elius.devolver_a_eli` | `p_conversacion uuid` | INVOKER |  |
| `elius.efectos_demo` | `p_tenant uuid, p_conv uuid, p_msg uuid, p_texto text, p_efectos jsonb, p_tras integer` | DEFINER |  |
| `elius.encender_eli` | `p_activo boolean` | INVOKER |  |
| `elius.enviar_aviso_prueba` | `` | DEFINER |  |
| `elius.enviar_push_prueba` | `` | DEFINER |  |
| `elius.escalar_conversacion` | `p_conversacion uuid, p_motivo text, p_mensaje text, p_resumen text` | INVOKER |  |
| `elius.estado_demo` | `p_tenant uuid, p_d jsonb` | DEFINER |  |
| `elius.estado_push` | `` | DEFINER |  |
| `elius.estrategia_cobro` | `p_monto numeric` | INVOKER |  |
| `elius.guardar_suscripcion_push` | `p_endpoint text, p_p256dh text, p_auth text, p_dispositivo text` | DEFINER |  |
| `elius.limpiar_caso_demo` | `p_tenant uuid` | DEFINER |  |
| `elius.marcar_llegada` | `p_reserva uuid` | INVOKER |  |
| `elius.marcar_no_asistidas` | `` | INVOKER |  |
| `elius.marcar_no_llegada` | `p_reserva uuid` | INVOKER |  |
| `elius.procesar_webhook_factus` | `p_pasarela uuid, p_clave_valida boolean, p_carga jsonb` | INVOKER |  |
| `elius.push_clave_publica` | `` | DEFINER |  |
| `elius.quitar_suscripcion_push` | `p_endpoint text` | DEFINER |  |
| `elius.rechazar_comprobante` | `p_comprobante uuid, p_motivo text` | INVOKER |  |
| `elius.registrar_comprobante` | `p_conversacion uuid, p_orden uuid, p_monto_leido numeric, p_remitente text, p_destinatario text, p_app text, p_referencia text, p_fecha_texto text, p_hash text, p_url text, p_media_id text` | INVOKER |  |
| `elius.registrar_recaudo` | `p_orden uuid, p_codigo text, p_monto numeric, p_llave text, p_url_qr text, p_expira timestamp with time zone` | INVOKER |  |
| `elius.reiniciar_demo` | `` | DEFINER |  |
| `elius.resolver_escalamiento` | `p_escalamiento uuid` | INVOKER |  |
| `elius.sembrar_clientes_demo` | `p_tenant uuid, p_vertical text` | DEFINER |  |
| `elius.siguiente_mensaje_demo` | `` | DEFINER | Entrega el siguiente mensaje del guion del caso de prueba; tras aprobar o rechazar un comprobante, Eli continúa esa conversación |
| `elius.soltar_bloqueo` | `p_conversacion uuid` | INVOKER |  |
| `elius.srv_actualizar_secreto` | `p_id uuid, p_valor text` | DEFINER |  |
| `elius.srv_pasarela_webhook` | `p_pasarela uuid` | DEFINER |  |
| `elius.srv_secreto` | `p_id uuid` | DEFINER |  |
| `elius.tomar_bloqueo` | `p_conversacion uuid, p_segundos integer` | INVOKER |  |
| `elius.tomar_conversacion` | `p_conversacion uuid` | INVOKER |  |
| `elius.webhook_factus` | `p_pasarela uuid, p_clave_valida boolean, p_carga jsonb` | DEFINER |  |
| `platform.aceptar_invitacion` | `p_token text` | DEFINER |  |
| `platform.autorizar_soporte` | `p_usuario_soporte uuid, p_motivo text, p_horas integer` | INVOKER |  |
| `platform.cambiar_tenant` | `p_tenant uuid` | DEFINER |  |
| `platform.cargar_caso_demo` | `p_vertical text` | DEFINER | Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes |
| `platform.crear_tenant` | `p_nombre text, p_slug text, p_vertical text, p_plan text` | DEFINER |  |
| `platform.invitar_usuario` | `p_email text, p_rol text` | INVOKER |  |
| `platform.otorgar_acceso_especial` | `p_membresia uuid, p_permiso text, p_motivo text, p_vence timestamp with time zone` | INVOKER |  |
| `plugin_airline.hacer_checkin` | `p_tiquete uuid, p_silla text` | INVOKER |  |
| `plugin_restaurant.agregar_opcion` | `p_linea uuid, p_opcion uuid, p_cantidad integer` | INVOKER |  |
| `plugin_restaurant.confirmar_menu_dia` | `p_menu uuid` | INVOKER |  |
| `plugin_vet.registrar_vacuna` | `p_mascota uuid, p_vacuna uuid, p_lote text, p_atencion uuid, p_proxima date` | INVOKER |  |
