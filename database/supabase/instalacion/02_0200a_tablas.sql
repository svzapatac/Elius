-- =============================================================================
-- ELIUS · Migración 0200 · Tablas (generado desde modelo/modelo.py)
-- No editar a mano: cambiar modelo.py o dominios.py y volver a generar.
-- Las llaves foráneas van al final para no depender del orden de creación.
-- =============================================================================

create table platform.planes (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  precio_mensual numeric(12,2) not null,
  moneda char(3) not null default 'USD',
  max_usuarios int not null,
  max_conversaciones_mes int not null,
  max_tokens_mes bigint not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table platform.tenants (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null,
  slug text not null unique,
  nombre text not null,
  vertical text not null default 'otro' 
      constraint ck_tenants_vertical check (vertical in ('veterinaria', 'restaurante', 'aerolinea', 'otro')),
  estado text not null default 'prueba' 
      constraint ck_tenants_estado check (estado in ('prueba', 'activo', 'suspendido', 'cancelado')),
  fin_prueba date,
  razon_social text,
  nit text,
  pais char(2) not null default 'CO',
  zona_horaria text not null default 'America/Bogota',
  moneda char(3) not null default 'COP',
  eliminado_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table platform.roles (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  nivel text not null 
      constraint ck_roles_nivel check (nivel in ('plataforma', 'tenant')),
  descripcion text not null,
  orden int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table platform.plugins (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nombre text not null,
  esquema text not null unique,
  version text not null default '1.0.0',
  verticales text[] not null default '{}',
  manifiesto jsonb not null default '{}'::jsonb,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table platform.permisos (
  id uuid primary key default gen_random_uuid(),
  plugin_id uuid,
  codigo text not null unique,
  modulo text not null,
  descripcion text not null,
  es_acceso_especial boolean not null default false,
  protege_dato_sensible boolean not null default false,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table platform.rol_permisos (
  id uuid primary key default gen_random_uuid(),
  rol_id uuid not null,
  permiso_id uuid not null,
  nivel text not null 
      constraint ck_rol_permisos_nivel check (nivel in ('lectura', 'escritura', 'total', 'con_autorizacion')),
  origen text not null default 'nucleo',
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_rol_permisos_1 unique (rol_id, permiso_id)
);

create table platform.membresias (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  usuario_id uuid not null,
  rol_id uuid not null,
  estado text not null default 'activo' 
      constraint ck_membresias_estado check (estado in ('invitado', 'activo', 'inactivo')),
  cargo text,
  es_predeterminada boolean not null default false,
  invitado_por uuid,
  fecha_ingreso timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_membresias_tenant_id unique (tenant_id, id),
  constraint uq_membresias_1 unique (tenant_id, usuario_id)
);

create table platform.accesos_especiales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  membresia_id uuid not null,
  permiso_id uuid not null,
  otorgado_por uuid not null,
  motivo text,
  vence_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_accesos_especiales_tenant_id unique (tenant_id, id),
  constraint uq_accesos_especiales_1 unique (membresia_id, permiso_id)
);

create table platform.asignaciones_plataforma (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null,
  rol_id uuid not null,
  asignado_por uuid not null,
  desde timestamptz not null default now(),
  hasta timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table platform.tenant_plugins (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  plugin_id uuid not null,
  habilitado boolean not null default true,
  configuracion jsonb not null default '{}'::jsonb,
  version_instalada text not null default '1.0.0',
  instalado_por uuid not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_tenant_plugins_tenant_id unique (tenant_id, id),
  constraint uq_tenant_plugins_1 unique (tenant_id, plugin_id)
);

create table platform.accesos_soporte (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  usuario_soporte_id uuid not null,
  autorizado_por uuid not null,
  motivo text not null,
  inicio timestamptz not null default now(),
  vence_en timestamptz not null,
  revocado_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_accesos_soporte_tenant_id unique (tenant_id, id)
);

create table platform.invitaciones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  rol_id uuid not null,
  invitado_por uuid not null,
  email text not null,
  hash_token text not null unique,
  vence_en timestamptz not null default now() + interval '7 days',
  aceptada_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_invitaciones_tenant_id unique (tenant_id, id)
);

create table platform.llaves_api (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  creado_por uuid not null,
  nombre text not null,
  prefijo text not null,
  hash_llave text not null unique,
  alcances text[] not null default '{}',
  ultimo_uso timestamptz,
  vence_en timestamptz,
  revocada_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_llaves_api_tenant_id unique (tenant_id, id)
);

create table platform.consumos_periodo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  periodo date not null default date_trunc('month', now())::date,
  metrica text not null,
  valor bigint not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_consumos_periodo_tenant_id unique (tenant_id, id),
  constraint uq_consumos_periodo_1 unique (tenant_id, periodo, metrica)
);

create table audit.registros_auditoria (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid,
  usuario_id uuid,
  rol text not null,
  origen text not null default 'app' 
      constraint ck_registros_auditoria_origen check (origen in ('app', 'eli', 'soporte', 'sistema')),
  esquema text not null,
  tabla text not null,
  registro_id uuid not null,
  operacion text not null 
      constraint ck_registros_auditoria_operacion check (operacion in ('INSERT', 'UPDATE', 'DELETE')),
  datos_anteriores jsonb,
  datos_nuevos jsonb,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table elius.contactos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  tipo text not null default 'persona' 
      constraint ck_contactos_tipo check (tipo in ('persona', 'empresa')),
  nombres text not null,
  apellidos text,
  email text,
  telefono text,
  tipo_documento text,
  numero_documento text,
  fecha_nacimiento date,
  etiquetas text[] not null default '{}',
  origen text not null default 'whatsapp',
  eliminado_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_contactos_tenant_id unique (tenant_id, id),
  constraint uq_contactos_1 unique (tenant_id, telefono),
  constraint uq_contactos_2 unique (tenant_id, email)
);

create table elius.direcciones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  contacto_id uuid not null,
  etiqueta text not null,
  direccion text not null,
  ciudad text not null,
  barrio text,
  indicaciones text,
  latitud numeric(9,6),
  longitud numeric(9,6),
  es_principal boolean not null default false,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_direcciones_tenant_id unique (tenant_id, id)
);

create table elius.consentimientos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  contacto_id uuid not null,
  finalidad text not null,
  canal text not null,
  texto_aceptado text not null,
  aceptado_en timestamptz not null default now(),
  revocado_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_consentimientos_tenant_id unique (tenant_id, id)
);

create table elius.agentes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  nombre text not null default 'Eli',
  modelo_llm text not null,
  prompt_sistema text not null,
  tono text not null default 'cercano',
  temperatura numeric(3,2) not null default 0.30,
  version int not null default 1,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_agentes_tenant_id unique (tenant_id, id)
);

create table elius.canales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  agente_id uuid not null,
  tipo text not null 
      constraint ck_canales_tipo check (tipo in ('whatsapp', 'web', 'chrome', 'api')),
  nombre text not null,
  identificador_externo text not null,
  estado text not null default 'activo' 
      constraint ck_canales_estado check (estado in ('activo', 'pausado', 'error')),
  referencia_secreto uuid,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_canales_tenant_id unique (tenant_id, id)
);

create table elius.identidades_contacto (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  contacto_id uuid not null,
  canal_id uuid not null,
  id_externo text not null,
  nombre_en_canal text,
  verificado boolean not null default false,
  primer_contacto_en timestamptz not null default now(),
  ultimo_contacto_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_identidades_contacto_tenant_id unique (tenant_id, id),
  constraint uq_identidades_contacto_1 unique (tenant_id, canal_id, id_externo)
);

create table elius.conversaciones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  identidad_id uuid not null,
  asignado_a uuid,
  flujo text not null default 'general',
  estado text not null default 'en_progreso' 
      constraint ck_conversaciones_estado check (estado in ('en_progreso', 'humano', 'pausa', 'cerrada')),
  borrador jsonb not null default '{}'::jsonb,
  bloqueada_en timestamptz,
  intencion text,
  sentimiento text 
      constraint ck_conversaciones_sentimiento check (sentimiento in ('positivo', 'neutro', 'negativo')),
  resumen text,
  iniciada_en timestamptz not null default now(),
  ultimo_mensaje_en timestamptz not null default now(),
  cerrada_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_conversaciones_tenant_id unique (tenant_id, id)
);

create table elius.mensajes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  conversacion_id uuid not null,
  emisor text not null 
      constraint ck_mensajes_emisor check (emisor in ('cliente', 'eli', 'humano', 'sistema')),
  tipo_contenido text not null default 'texto' 
      constraint ck_mensajes_tipo_contenido check (tipo_contenido in ('texto', 'imagen', 'audio', 'documento', 'ubicacion', 'plantilla')),
  contenido text not null,
  url_adjunto text,
  id_externo text,
  estado_entrega text not null default 'recibido' 
      constraint ck_mensajes_estado_entrega check (estado_entrega in ('recibido', 'enviado', 'entregado', 'leido', 'fallido')),
  procesado boolean not null default false,
  enviado_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_mensajes_tenant_id unique (tenant_id, id)
);

create table elius.consumos_llm (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  conversacion_id uuid not null,
  mensaje_id uuid,
  proveedor text not null,
  modelo text not null,
  tokens_entrada int not null default 0,
  tokens_salida int not null default 0,
  tokens_cache int not null default 0,
  costo_usd numeric(12,6) not null default 0,
  latencia_ms int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_consumos_llm_tenant_id unique (tenant_id, id)
);

create table elius.categorias_catalogo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  nombre text not null,
  descripcion text,
  orden int not null default 0,
  disponible_desde time,
  disponible_hasta time,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_categorias_catalogo_tenant_id unique (tenant_id, id)
);

create table elius.items_catalogo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  categoria_id uuid not null,
  tipo text not null default 'producto' 
      constraint ck_items_catalogo_tipo check (tipo in ('producto', 'servicio', 'paquete', 'adicional', 'tarifa')),
  sku text,
  nombre text not null,
  descripcion text,
  incluye text,
  precio numeric(14,2) not null default 0,
  impuesto_pct numeric(5,2) not null default 0,
  duracion_min int,
  disponible boolean not null default true,
  atributos jsonb not null default '{}'::jsonb,
  eliminado_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_items_catalogo_tenant_id unique (tenant_id, id),
  constraint uq_items_catalogo_1 unique (tenant_id, sku)
);

create table elius.recursos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  tipo text not null default 'mesa' 
      constraint ck_recursos_tipo check (tipo in ('mesa', 'consultorio', 'sala', 'equipo', 'otro')),
  nombre text not null,
  capacidad int not null default 1,
  ubicacion text,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_recursos_tenant_id unique (tenant_id, id)
);

create table elius.horarios_atencion (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  recurso_id uuid,
  dia_semana smallint not null,
  abre time not null,
  cierra time not null,
  vigente_desde date not null default current_date,
  vigente_hasta date,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_horarios_atencion_tenant_id unique (tenant_id, id)
);

create table elius.reservas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  contacto_id uuid not null,
  conversacion_id uuid,
  codigo text not null,
  tipo text not null default 'cita' 
      constraint ck_reservas_tipo check (tipo in ('cita', 'mesa', 'vuelo', 'otro')),
  estado text not null default 'pendiente_pago' 
      constraint ck_reservas_estado check (estado in ('pendiente_pago', 'confirmada', 'asistio', 'no_asistio', 'cancelada')),
  inicio timestamptz not null,
  fin timestamptz,
  personas int not null default 1,
  responsable_id uuid,
  urgente boolean not null default false,
  visto boolean not null default false,
  llegada_en timestamptz,
  salida_en timestamptz,
  novedades text,
  notas text,
  creada_por_eli boolean not null default false,
  id_evento_calendario text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_reservas_tenant_id unique (tenant_id, id),
  constraint uq_reservas_1 unique (tenant_id, codigo)
);

create table elius.asignaciones_recurso (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  reserva_id uuid not null,
  recurso_id uuid not null,
  inicio timestamptz not null,
  fin timestamptz not null,
  estado text not null default 'activa' 
      constraint ck_asignaciones_recurso_estado check (estado in ('activa', 'liberada')),
  notas text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_asignaciones_recurso_tenant_id unique (tenant_id, id)
);

create table elius.ordenes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  contacto_id uuid,
  reserva_id uuid,
  conversacion_id uuid,
  direccion_entrega_id uuid,
  numero bigint not null,
  canal_venta text not null default 'whatsapp' 
      constraint ck_ordenes_canal_venta check (canal_venta in ('presencial', 'whatsapp', 'web', 'app')),
  responsable_id uuid,
  tipo_entrega text not null default 'recoger' 
      constraint ck_ordenes_tipo_entrega check (tipo_entrega in ('sitio', 'recoger', 'domicilio', 'no_aplica')),
  estado text not null default 'cotizando' 
      constraint ck_ordenes_estado check (estado in ('cotizando', 'esperando_pago', 'confirmada', 'en_preparacion', 'en_camino', 'entregada', 'cancelada')),
  urgente boolean not null default false,
  visto boolean not null default false,
  subtotal numeric(14,2) not null default 0,
  descuento numeric(14,2) not null default 0,
  impuestos numeric(14,2) not null default 0,
  total numeric(14,2) not null default 0,
  colocada_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_ordenes_tenant_id unique (tenant_id, id),
  constraint uq_ordenes_1 unique (tenant_id, numero)
);

create table elius.orden_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_id uuid not null,
  item_id uuid not null,
  cantidad numeric(10,2) not null default 1,
  precio_unitario numeric(14,2) not null,
  recargos numeric(14,2) not null default 0,
  descuento numeric(14,2) not null default 0,
  total_linea numeric(14,2) not null default 0,
  notas text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_orden_items_tenant_id unique (tenant_id, id)
);

create table elius.pagos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_id uuid not null,
  pago_original_id uuid,
  comprobante_id uuid,
  recaudo_id uuid,
  metodo text not null 
      constraint ck_pagos_metodo check (metodo in ('efectivo', 'transferencia', 'breb_factus', 'nequi', 'daviplata', 'tarjeta', 'link')),
  proveedor text,
  referencia_externa text,
  monto numeric(14,2) not null,
  estado text not null default 'pendiente' 
      constraint ck_pagos_estado check (estado in ('pendiente', 'aprobado', 'rechazado')),
  pagado_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_pagos_tenant_id unique (tenant_id, id)
);

create table elius.comprobantes_pago (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_id uuid,
  conversacion_id uuid not null,
  decidido_por uuid,
  monto_leido numeric(14,2),
  monto_esperado numeric(14,2),
  coincide boolean,
  remitente text,
  destinatario text,
  app_origen text,
  referencia text,
  fecha_texto text,
  hash_archivo text,
  url_archivo text,
  media_id text,
  veredicto text not null default 'pendiente' 
      constraint ck_comprobantes_pago_veredicto check (veredicto in ('pendiente', 'aprobado', 'rechazado')),
  motivo text,
  decidido_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_comprobantes_pago_tenant_id unique (tenant_id, id)
);

create table elius.pasarelas_pago (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  proveedor text not null default 'factus_pay' 
      constraint ck_pasarelas_pago_proveedor check (proveedor in ('factus_pay')),
  ambiente text not null default 'sandbox' 
      constraint ck_pasarelas_pago_ambiente check (ambiente in ('sandbox', 'produccion')),
  email_cuenta text not null,
  referencia_credenciales uuid not null,
  referencia_clave_webhook uuid not null,
  monto_minimo numeric(14,2) not null default 1000,
  monto_maximo numeric(14,2) not null default 12100000,
  expiracion_segundos int not null default 86400,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_pasarelas_pago_tenant_id unique (tenant_id, id),
  constraint uq_pasarelas_pago_1 unique (tenant_id, proveedor, ambiente)
);

create table elius.recaudos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_id uuid not null,
  pasarela_id uuid not null,
  codigo_referencia text not null,
  monto numeric(14,2) not null,
  llave_breb text,
  url_qr text,
  expira_en timestamptz,
  estado text not null default 'listo' 
      constraint ck_recaudos_estado check (estado in ('listo', 'pagado', 'vencido', 'anulado')),
  cobrado_en timestamptz,
  pagador_nombre text,
  pagador_documento text,
  confirmado_por_api boolean not null default false,
  renovaciones int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_recaudos_tenant_id unique (tenant_id, id),
  constraint uq_recaudos_1 unique (pasarela_id, codigo_referencia)
);

create table elius.notificaciones_pasarela (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  pasarela_id uuid not null,
  recaudo_id uuid,
  codigo_referencia text not null,
  carga jsonb not null default '{}'::jsonb,
  clave_valida boolean not null default false,
  recibida_en timestamptz not null default now(),
  procesada_en timestamptz,
  resultado text 
      constraint ck_notificaciones_pasarela_resultado check (resultado in ('aplicado', 'duplicado', 'rechazado', 'sin_recaudo')),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_notificaciones_pasarela_tenant_id unique (tenant_id, id)
);

create table elius.entregas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_id uuid not null,
  repartidor_id uuid,
  estado text not null default 'pendiente' 
      constraint ck_entregas_estado check (estado in ('pendiente', 'en_camino', 'entregada', 'fallida')),
  cobro_contra_entrega numeric(14,2) not null default 0,
  tomada_en timestamptz,
  entregada_en timestamptz,
  notas text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_entregas_tenant_id unique (tenant_id, id)
);

create table elius.item_adicionales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  item_id uuid not null,
  adicional_id uuid not null,
  precio_especial numeric(14,2),
  cantidad_maxima int,
  orden int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_item_adicionales_tenant_id unique (tenant_id, id),
  constraint uq_item_adicionales_1 unique (item_id, adicional_id)
);

create table elius.medios_item (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  item_id uuid not null,
  tipo_archivo text not null default 'foto' 
      constraint ck_medios_item_tipo_archivo check (tipo_archivo in ('foto', 'video')),
  url text not null,
  descripcion text,
  orden int not null default 0,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_medios_item_tenant_id unique (tenant_id, id)
);

create table elius.escalamientos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  conversacion_id uuid not null,
  asignado_a uuid,
  resuelto_por uuid,
  motivo text not null,
  mensaje_cliente text,
  resumen text,
  resuelto_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_escalamientos_tenant_id unique (tenant_id, id)
);

create table elius.eventos_embudo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  conversacion_id uuid not null,
  fase text not null,
  detalle jsonb not null default '{}'::jsonb,
  ocurrido_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_eventos_embudo_tenant_id unique (tenant_id, id)
);

create table elius.errores_agente (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  conversacion_id uuid,
  resuelto_por uuid,
  origen text not null,
  mensaje text not null,
  detalle jsonb not null default '{}'::jsonb,
  resuelto_en timestamptz,
  notas text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_errores_agente_tenant_id unique (tenant_id, id)
);

create table elius.parametros_negocio (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  clave text not null,
  valor text not null default 0,
  tipo_dato text not null default 'texto' 
      constraint ck_parametros_negocio_tipo_dato check (tipo_dato in ('numero', 'texto', 'booleano', 'porcentaje')),
  descripcion text not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_parametros_negocio_tenant_id unique (tenant_id, id),
  constraint uq_parametros_negocio_1 unique (tenant_id, clave)
);

create table elius.suscripciones_push (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  membresia_id uuid not null,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  dispositivo text,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_suscripciones_push_tenant_id unique (tenant_id, id)
);

create table elius.documentos_conocimiento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  titulo text not null,
  tipo_fuente text not null 
      constraint ck_documentos_conocimiento_tipo_fuente check (tipo_fuente in ('archivo', 'url', 'faq', 'manual')),
  url_fuente text,
  ruta_archivo text,
  estado text not null default 'procesando' 
      constraint ck_documentos_conocimiento_estado check (estado in ('procesando', 'listo', 'error')),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_documentos_conocimiento_tenant_id unique (tenant_id, id)
);

create table elius.fragmentos_conocimiento (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  documento_id uuid not null,
  orden int not null default 0,
  contenido text not null,
  tokens int not null,
  embedding extensions.vector(1536) not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_fragmentos_conocimiento_tenant_id unique (tenant_id, id)
);

create table elius.eventos_salida (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  tipo_evento text not null,
  entidad text not null,
  entidad_id uuid not null,
  carga jsonb not null default '{}'::jsonb,
  estado text not null default 'pendiente' 
      constraint ck_eventos_salida_estado check (estado in ('pendiente', 'enviado', 'fallido')),
  intentos int not null default 0,
  procesado_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_eventos_salida_tenant_id unique (tenant_id, id)
);

create table ext.instalaciones_extension (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  membresia_id uuid not null,
  navegador text not null,
  version_extension text not null,
  ultimo_uso_en timestamptz,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_instalaciones_extension_tenant_id unique (tenant_id, id)
);

create table ext.sitios_autorizados (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  autorizado_por uuid not null,
  dominio text not null,
  nombre text not null,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_sitios_autorizados_tenant_id unique (tenant_id, id),
  constraint uq_sitios_autorizados_1 unique (tenant_id, dominio)
);

create table ext.conversaciones_capturadas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  instalacion_id uuid not null,
  sitio_id uuid not null,
  contacto_id uuid,
  id_hilo_externo text not null,
  titulo text,
  capturada_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_conversaciones_capturadas_tenant_id unique (tenant_id, id)
);

create table ext.mensajes_capturados (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  conversacion_id uuid not null,
  autor_rol text not null default 'desconocido' 
      constraint ck_mensajes_capturados_autor_rol check (autor_rol in ('cliente', 'agente', 'desconocido')),
  autor_nombre text,
  contenido text not null,
  enviado_en timestamptz not null default now(),
  embedding extensions.vector(1536),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_mensajes_capturados_tenant_id unique (tenant_id, id)
);

create table ext.patrones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  aprobado_por uuid,
  tipo text not null 
      constraint ck_patrones_tipo check (tipo in ('faq', 'objecion', 'intencion', 'plantilla')),
  nombre text not null,
  descripcion text not null,
  respuesta_sugerida text,
  frecuencia int not null default 0,
  confianza numeric(4,3) not null default 0,
  estado text not null default 'sugerido' 
      constraint ck_patrones_estado check (estado in ('sugerido', 'aprobado', 'rechazado')),
  embedding extensions.vector(1536),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_patrones_tenant_id unique (tenant_id, id)
);

create table ext.evidencias_patron (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  patron_id uuid not null,
  mensaje_id uuid not null,
  relevancia numeric(4,3) not null,
  fragmento text not null,
  detectado_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_evidencias_patron_tenant_id unique (tenant_id, id),
  constraint uq_evidencias_patron_1 unique (patron_id, mensaje_id)
);

create table plugin_vet.mascotas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  nombre text not null,
  especie text not null,
  raza text,
  sexo text not null 
      constraint ck_mascotas_sexo check (sexo in ('macho', 'hembra')),
  fecha_nacimiento date,
  peso_kg numeric(6,2),
  microchip text,
  esterilizada boolean not null default false,
  alergias text[] not null default '{}',
  fallecida_en date,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_mascotas_tenant_id unique (tenant_id, id)
);

create table plugin_vet.propietarios_mascota (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  contacto_id uuid not null,
  mascota_id uuid not null,
  tipo text not null default 'principal' 
      constraint ck_propietarios_mascota_tipo check (tipo in ('principal', 'secundario')),
  puede_autorizar boolean not null default false,
  desde date not null default current_date,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_propietarios_mascota_tenant_id unique (tenant_id, id),
  constraint uq_propietarios_mascota_1 unique (mascota_id, contacto_id)
);

create table plugin_vet.atenciones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  reserva_id uuid not null,
  mascota_id uuid not null,
  servicio_id uuid not null,
  profesional_id uuid not null,
  motivo text not null,
  estado text not null default 'programada' 
      constraint ck_atenciones_estado check (estado in ('programada', 'en_curso', 'finalizada', 'cancelada')),
  peso_kg numeric(6,2),
  temperatura_c numeric(4,1),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_atenciones_tenant_id unique (tenant_id, id)
);

create table plugin_vet.registros_clinicos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  atencion_id uuid not null,
  autor_id uuid not null,
  corrige_a uuid,
  tipo text not null 
      constraint ck_registros_clinicos_tipo check (tipo in ('anamnesis', 'examen', 'diagnostico', 'tratamiento', 'correccion')),
  contenido text not null,
  registrado_en timestamptz not null default now(),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_registros_clinicos_tenant_id unique (tenant_id, id)
);

create table plugin_vet.aplicaciones_vacuna (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  mascota_id uuid not null,
  vacuna_id uuid not null,
  atencion_id uuid,
  aplicada_por uuid not null,
  lote text not null,
  aplicada_en date not null default current_date,
  proxima_dosis_en date,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_aplicaciones_vacuna_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.alergenos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  nombre text not null,
  descripcion text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_alergenos_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.item_alergenos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  item_id uuid not null,
  alergeno_id uuid not null,
  nivel text not null default 'contiene' 
      constraint ck_item_alergenos_nivel check (nivel in ('contiene', 'trazas')),
  nota text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_item_alergenos_tenant_id unique (tenant_id, id),
  constraint uq_item_alergenos_1 unique (item_id, alergeno_id)
);

create table plugin_restaurant.grupos_modificador (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  nombre text not null,
  descripcion text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_grupos_modificador_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.opciones_modificador (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  grupo_id uuid not null,
  nombre text not null,
  precio_adicional numeric(14,2) not null default 0,
  disponible boolean not null default true,
  orden int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_opciones_modificador_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.item_grupos_modificador (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  item_id uuid not null,
  grupo_id uuid not null,
  minimo int not null default 0,
  maximo int not null default 1,
  orden int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_item_grupos_modificador_tenant_id unique (tenant_id, id),
  constraint uq_item_grupos_modificador_1 unique (item_id, grupo_id)
);

create table plugin_restaurant.orden_item_opciones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_item_id uuid not null,
  opcion_id uuid not null,
  cantidad int not null default 1,
  precio_aplicado numeric(14,2) not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_orden_item_opciones_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.estaciones_cocina (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  nombre text not null,
  tiempo_objetivo_min int not null default 15,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_estaciones_cocina_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.comandas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  orden_id uuid not null,
  estacion_id uuid not null,
  ronda int not null default 1,
  estado text not null default 'recibida' 
      constraint ck_comandas_estado check (estado in ('recibida', 'en_preparacion', 'lista', 'entregada')),
  enviada_en timestamptz not null,
  lista_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_comandas_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.comanda_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  comanda_id uuid not null,
  orden_item_id uuid not null,
  cantidad numeric(10,2) not null default 1,
  estado text not null default 'pendiente' 
      constraint ck_comanda_items_estado check (estado in ('pendiente', 'preparando', 'listo')),
  nota_cocina text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_comanda_items_tenant_id unique (tenant_id, id)
);

create table plugin_restaurant.menus_dia (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  confirmado_por uuid,
  fecha date not null,
  precio_base numeric(14,2) not null,
  url_foto text,
  confirmado_en timestamptz,
  activo boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_menus_dia_tenant_id unique (tenant_id, id),
  constraint uq_menus_dia_1 unique (tenant_id, fecha)
);

create table plugin_restaurant.menu_dia_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  menu_id uuid not null,
  item_id uuid not null,
  seccion text not null default 'principal' 
      constraint ck_menu_dia_items_seccion check (seccion in ('entrada', 'principal', 'bebida', 'postre')),
  posicion int not null default 0,
  disponible boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_menu_dia_items_tenant_id unique (tenant_id, id),
  constraint uq_menu_dia_items_1 unique (menu_id, item_id)
);

create table plugin_restaurant.celebraciones (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  reserva_id uuid not null,
  tipo_celebracion text not null,
  festejado text not null,
  decoracion text,
  notas text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_celebraciones_tenant_id unique (tenant_id, id)
);

create table plugin_airline.aeropuertos (
  id uuid primary key default gen_random_uuid(),
  codigo_iata char(3) not null unique,
  nombre text not null,
  ciudad text not null,
  pais char(2) not null,
  zona_horaria text not null,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create table plugin_airline.aeronaves (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  matricula text not null,
  modelo text not null,
  capacidad int not null,
  mapa_sillas jsonb not null default '{}'::jsonb,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_aeronaves_tenant_id unique (tenant_id, id),
  constraint uq_aeronaves_1 unique (tenant_id, matricula)
);

create table plugin_airline.rutas (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  origen_id uuid not null,
  destino_id uuid not null,
  distancia_km int not null,
  duracion_min int not null,
  activa boolean not null default true,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_rutas_tenant_id unique (tenant_id, id),
  constraint uq_rutas_1 unique (tenant_id, origen_id, destino_id)
);

create table plugin_airline.vuelos (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  ruta_id uuid not null,
  aeronave_id uuid not null,
  numero_vuelo text not null,
  salida_programada timestamptz not null,
  llegada_programada timestamptz not null,
  estado text not null default 'programado' 
      constraint ck_vuelos_estado check (estado in ('programado', 'abordando', 'salio', 'llego', 'retrasado', 'cancelado')),
  puerta text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_vuelos_tenant_id unique (tenant_id, id)
);

create table plugin_airline.tarifas_vuelo (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  vuelo_id uuid not null,
  tarifa_id uuid not null,
  precio numeric(14,2) not null default 0,
  cupos_totales int not null,
  cupos_vendidos int not null default 0,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_tarifas_vuelo_tenant_id unique (tenant_id, id),
  constraint uq_tarifas_vuelo_1 unique (vuelo_id, tarifa_id)
);

create table plugin_airline.reserva_pasajeros (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  reserva_id uuid not null,
  contacto_id uuid not null,
  tipo_pasajero text not null default 'ADT' 
      constraint ck_reserva_pasajeros_tipo_pasajero check (tipo_pasajero in ('ADT', 'CHD', 'INF')),
  necesidades_especiales text,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_reserva_pasajeros_tenant_id unique (tenant_id, id),
  constraint uq_reserva_pasajeros_1 unique (reserva_id, contacto_id)
);

create table plugin_airline.tramos_reserva (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  reserva_id uuid not null,
  tarifa_vuelo_id uuid not null,
  orden_tramo int not null default 1,
  estado text not null default 'confirmado' 
      constraint ck_tramos_reserva_estado check (estado in ('confirmado', 'cambiado', 'cancelado')),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_tramos_reserva_tenant_id unique (tenant_id, id)
);

create table plugin_airline.tiquetes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  reserva_pasajero_id uuid not null,
  tramo_id uuid not null,
  numero_tiquete text not null unique,
  silla text,
  estado text not null default 'emitido' 
      constraint ck_tiquetes_estado check (estado in ('emitido', 'usado', 'anulado')),
  checkin_en timestamptz,
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_tiquetes_tenant_id unique (tenant_id, id),
  constraint uq_tiquetes_1 unique (reserva_pasajero_id, tramo_id)
);

create table plugin_airline.equipajes (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null default app.current_tenant_id(),
  tiquete_id uuid not null,
  tipo text not null 
      constraint ck_equipajes_tipo check (tipo in ('mano', 'bodega', 'especial')),
  peso_kg numeric(5,2) not null,
  etiqueta text not null,
  estado text not null default 'registrado' 
      constraint ck_equipajes_estado check (estado in ('registrado', 'cargado', 'entregado', 'perdido')),
  creado_en timestamptz not null default now(),
  actualizado_en timestamptz not null default now(),
  constraint uq_equipajes_tenant_id unique (tenant_id, id)
);
