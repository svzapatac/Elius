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

-- -----------------------------------------------------------------------------
-- Llaves foráneas. Si origen y destino viven en un tenant, la llave es compuesta
-- (tenant_id, columna): un registro nunca puede apuntar a otro tenant.
-- -----------------------------------------------------------------------------
alter table platform.tenants add constraint fk_tenants_plan_id foreign key (plan_id) references platform.planes (id) on delete restrict;
alter table platform.permisos add constraint fk_permisos_plugin_id foreign key (plugin_id) references platform.plugins (id) on delete set null;
alter table platform.rol_permisos add constraint fk_rol_permisos_rol_id foreign key (rol_id) references platform.roles (id) on delete restrict;
alter table platform.rol_permisos add constraint fk_rol_permisos_permiso_id foreign key (permiso_id) references platform.permisos (id) on delete restrict;
alter table platform.membresias add constraint fk_membresias_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table platform.membresias add constraint fk_membresias_usuario_id foreign key (usuario_id) references auth.users (id) on delete cascade;
alter table platform.membresias add constraint fk_membresias_rol_id foreign key (rol_id) references platform.roles (id) on delete restrict;
alter table platform.membresias add constraint fk_membresias_invitado_por foreign key (invitado_por) references auth.users (id) on delete set null;
alter table platform.accesos_especiales add constraint fk_accesos_especiales_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table platform.accesos_especiales add constraint fk_accesos_especiales_membresia_id foreign key (tenant_id, membresia_id) references platform.membresias (tenant_id, id) on delete cascade;
alter table platform.accesos_especiales add constraint fk_accesos_especiales_permiso_id foreign key (permiso_id) references platform.permisos (id) on delete restrict;
alter table platform.accesos_especiales add constraint fk_accesos_especiales_otorgado_por foreign key (otorgado_por) references auth.users (id) on delete cascade;
alter table platform.asignaciones_plataforma add constraint fk_asignaciones_plataforma_usuario_id foreign key (usuario_id) references auth.users (id) on delete cascade;
alter table platform.asignaciones_plataforma add constraint fk_asignaciones_plataforma_rol_id foreign key (rol_id) references platform.roles (id) on delete restrict;
alter table platform.asignaciones_plataforma add constraint fk_asignaciones_plataforma_asignado_por foreign key (asignado_por) references auth.users (id) on delete cascade;
alter table platform.tenant_plugins add constraint fk_tenant_plugins_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table platform.tenant_plugins add constraint fk_tenant_plugins_plugin_id foreign key (plugin_id) references platform.plugins (id) on delete restrict;
alter table platform.tenant_plugins add constraint fk_tenant_plugins_instalado_por foreign key (instalado_por) references auth.users (id) on delete cascade;
alter table platform.accesos_soporte add constraint fk_accesos_soporte_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table platform.accesos_soporte add constraint fk_accesos_soporte_usuario_soporte_id foreign key (usuario_soporte_id) references auth.users (id) on delete cascade;
alter table platform.accesos_soporte add constraint fk_accesos_soporte_autorizado_por foreign key (autorizado_por) references auth.users (id) on delete cascade;
alter table platform.invitaciones add constraint fk_invitaciones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table platform.invitaciones add constraint fk_invitaciones_rol_id foreign key (rol_id) references platform.roles (id) on delete restrict;
alter table platform.invitaciones add constraint fk_invitaciones_invitado_por foreign key (invitado_por) references auth.users (id) on delete cascade;
alter table platform.llaves_api add constraint fk_llaves_api_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table platform.llaves_api add constraint fk_llaves_api_creado_por foreign key (creado_por) references auth.users (id) on delete cascade;
alter table platform.consumos_periodo add constraint fk_consumos_periodo_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table audit.registros_auditoria add constraint fk_registros_auditoria_tenant_id foreign key (tenant_id) references platform.tenants (id) on delete set null;
alter table audit.registros_auditoria add constraint fk_registros_auditoria_usuario_id foreign key (usuario_id) references auth.users (id) on delete set null;
alter table elius.contactos add constraint fk_contactos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.direcciones add constraint fk_direcciones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.direcciones add constraint fk_direcciones_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete cascade;
alter table elius.consentimientos add constraint fk_consentimientos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.consentimientos add constraint fk_consentimientos_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete cascade;
alter table elius.agentes add constraint fk_agentes_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.canales add constraint fk_canales_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.canales add constraint fk_canales_agente_id foreign key (tenant_id, agente_id) references elius.agentes (tenant_id, id) on delete restrict;
alter table elius.identidades_contacto add constraint fk_identidades_contacto_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.identidades_contacto add constraint fk_identidades_contacto_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete cascade;
alter table elius.identidades_contacto add constraint fk_identidades_contacto_canal_id foreign key (tenant_id, canal_id) references elius.canales (tenant_id, id) on delete restrict;
alter table elius.conversaciones add constraint fk_conversaciones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.conversaciones add constraint fk_conversaciones_identidad_id foreign key (tenant_id, identidad_id) references elius.identidades_contacto (tenant_id, id) on delete cascade;
alter table elius.conversaciones add constraint fk_conversaciones_asignado_a foreign key (tenant_id, asignado_a) references platform.membresias (tenant_id, id) on delete set null (asignado_a);
alter table elius.mensajes add constraint fk_mensajes_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.mensajes add constraint fk_mensajes_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete cascade;
alter table elius.consumos_llm add constraint fk_consumos_llm_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.consumos_llm add constraint fk_consumos_llm_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete cascade;
alter table elius.consumos_llm add constraint fk_consumos_llm_mensaje_id foreign key (tenant_id, mensaje_id) references elius.mensajes (tenant_id, id) on delete set null (mensaje_id);
alter table elius.categorias_catalogo add constraint fk_categorias_catalogo_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.items_catalogo add constraint fk_items_catalogo_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.items_catalogo add constraint fk_items_catalogo_categoria_id foreign key (tenant_id, categoria_id) references elius.categorias_catalogo (tenant_id, id) on delete restrict;
alter table elius.recursos add constraint fk_recursos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.horarios_atencion add constraint fk_horarios_atencion_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.horarios_atencion add constraint fk_horarios_atencion_recurso_id foreign key (tenant_id, recurso_id) references elius.recursos (tenant_id, id) on delete set null (recurso_id);
alter table elius.reservas add constraint fk_reservas_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.reservas add constraint fk_reservas_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete cascade;
alter table elius.reservas add constraint fk_reservas_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete set null (conversacion_id);
alter table elius.reservas add constraint fk_reservas_responsable_id foreign key (tenant_id, responsable_id) references platform.membresias (tenant_id, id) on delete set null (responsable_id);
alter table elius.asignaciones_recurso add constraint fk_asignaciones_recurso_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.asignaciones_recurso add constraint fk_asignaciones_recurso_reserva_id foreign key (tenant_id, reserva_id) references elius.reservas (tenant_id, id) on delete cascade;
alter table elius.asignaciones_recurso add constraint fk_asignaciones_recurso_recurso_id foreign key (tenant_id, recurso_id) references elius.recursos (tenant_id, id) on delete restrict;
alter table elius.ordenes add constraint fk_ordenes_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.ordenes add constraint fk_ordenes_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete set null (contacto_id);
alter table elius.ordenes add constraint fk_ordenes_reserva_id foreign key (tenant_id, reserva_id) references elius.reservas (tenant_id, id) on delete set null (reserva_id);
alter table elius.ordenes add constraint fk_ordenes_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete set null (conversacion_id);
alter table elius.ordenes add constraint fk_ordenes_direccion_entrega_id foreign key (tenant_id, direccion_entrega_id) references elius.direcciones (tenant_id, id) on delete set null (direccion_entrega_id);
alter table elius.ordenes add constraint fk_ordenes_responsable_id foreign key (tenant_id, responsable_id) references platform.membresias (tenant_id, id) on delete set null (responsable_id);
alter table elius.orden_items add constraint fk_orden_items_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.orden_items add constraint fk_orden_items_orden_id foreign key (tenant_id, orden_id) references elius.ordenes (tenant_id, id) on delete cascade;
alter table elius.orden_items add constraint fk_orden_items_item_id foreign key (tenant_id, item_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table elius.pagos add constraint fk_pagos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.pagos add constraint fk_pagos_orden_id foreign key (tenant_id, orden_id) references elius.ordenes (tenant_id, id) on delete cascade;
alter table elius.pagos add constraint fk_pagos_pago_original_id foreign key (tenant_id, pago_original_id) references elius.pagos (tenant_id, id) on delete set null (pago_original_id);
alter table elius.pagos add constraint fk_pagos_comprobante_id foreign key (tenant_id, comprobante_id) references elius.comprobantes_pago (tenant_id, id) on delete set null (comprobante_id);
alter table elius.pagos add constraint fk_pagos_recaudo_id foreign key (tenant_id, recaudo_id) references elius.recaudos (tenant_id, id) on delete set null (recaudo_id);
alter table elius.comprobantes_pago add constraint fk_comprobantes_pago_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.comprobantes_pago add constraint fk_comprobantes_pago_orden_id foreign key (tenant_id, orden_id) references elius.ordenes (tenant_id, id) on delete set null (orden_id);
alter table elius.comprobantes_pago add constraint fk_comprobantes_pago_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete cascade;
alter table elius.comprobantes_pago add constraint fk_comprobantes_pago_decidido_por foreign key (tenant_id, decidido_por) references platform.membresias (tenant_id, id) on delete set null (decidido_por);
alter table elius.pasarelas_pago add constraint fk_pasarelas_pago_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.recaudos add constraint fk_recaudos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.recaudos add constraint fk_recaudos_orden_id foreign key (tenant_id, orden_id) references elius.ordenes (tenant_id, id) on delete cascade;
alter table elius.recaudos add constraint fk_recaudos_pasarela_id foreign key (tenant_id, pasarela_id) references elius.pasarelas_pago (tenant_id, id) on delete restrict;
alter table elius.notificaciones_pasarela add constraint fk_notificaciones_pasarela_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.notificaciones_pasarela add constraint fk_notificaciones_pasarela_pasarela_id foreign key (tenant_id, pasarela_id) references elius.pasarelas_pago (tenant_id, id) on delete restrict;
alter table elius.notificaciones_pasarela add constraint fk_notificaciones_pasarela_recaudo_id foreign key (tenant_id, recaudo_id) references elius.recaudos (tenant_id, id) on delete set null (recaudo_id);
alter table elius.entregas add constraint fk_entregas_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.entregas add constraint fk_entregas_orden_id foreign key (tenant_id, orden_id) references elius.ordenes (tenant_id, id) on delete cascade;
alter table elius.entregas add constraint fk_entregas_repartidor_id foreign key (tenant_id, repartidor_id) references platform.membresias (tenant_id, id) on delete set null (repartidor_id);
alter table elius.item_adicionales add constraint fk_item_adicionales_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.item_adicionales add constraint fk_item_adicionales_item_id foreign key (tenant_id, item_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table elius.item_adicionales add constraint fk_item_adicionales_adicional_id foreign key (tenant_id, adicional_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table elius.medios_item add constraint fk_medios_item_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.medios_item add constraint fk_medios_item_item_id foreign key (tenant_id, item_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table elius.escalamientos add constraint fk_escalamientos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.escalamientos add constraint fk_escalamientos_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete cascade;
alter table elius.escalamientos add constraint fk_escalamientos_asignado_a foreign key (tenant_id, asignado_a) references platform.membresias (tenant_id, id) on delete set null (asignado_a);
alter table elius.escalamientos add constraint fk_escalamientos_resuelto_por foreign key (tenant_id, resuelto_por) references platform.membresias (tenant_id, id) on delete set null (resuelto_por);
alter table elius.eventos_embudo add constraint fk_eventos_embudo_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.eventos_embudo add constraint fk_eventos_embudo_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete cascade;
alter table elius.errores_agente add constraint fk_errores_agente_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.errores_agente add constraint fk_errores_agente_conversacion_id foreign key (tenant_id, conversacion_id) references elius.conversaciones (tenant_id, id) on delete set null (conversacion_id);
alter table elius.errores_agente add constraint fk_errores_agente_resuelto_por foreign key (resuelto_por) references auth.users (id) on delete set null;
alter table elius.parametros_negocio add constraint fk_parametros_negocio_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.suscripciones_push add constraint fk_suscripciones_push_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.suscripciones_push add constraint fk_suscripciones_push_membresia_id foreign key (tenant_id, membresia_id) references platform.membresias (tenant_id, id) on delete cascade;
alter table elius.documentos_conocimiento add constraint fk_documentos_conocimiento_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.fragmentos_conocimiento add constraint fk_fragmentos_conocimiento_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table elius.fragmentos_conocimiento add constraint fk_fragmentos_conocimiento_documento_id foreign key (tenant_id, documento_id) references elius.documentos_conocimiento (tenant_id, id) on delete cascade;
alter table elius.eventos_salida add constraint fk_eventos_salida_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.instalaciones_extension add constraint fk_instalaciones_extension_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.instalaciones_extension add constraint fk_instalaciones_extension_membresia_id foreign key (tenant_id, membresia_id) references platform.membresias (tenant_id, id) on delete cascade;
alter table ext.sitios_autorizados add constraint fk_sitios_autorizados_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.sitios_autorizados add constraint fk_sitios_autorizados_autorizado_por foreign key (autorizado_por) references auth.users (id) on delete cascade;
alter table ext.conversaciones_capturadas add constraint fk_conversaciones_capturadas_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.conversaciones_capturadas add constraint fk_conversaciones_capturadas_instalacion_id foreign key (tenant_id, instalacion_id) references ext.instalaciones_extension (tenant_id, id) on delete cascade;
alter table ext.conversaciones_capturadas add constraint fk_conversaciones_capturadas_sitio_id foreign key (tenant_id, sitio_id) references ext.sitios_autorizados (tenant_id, id) on delete restrict;
alter table ext.conversaciones_capturadas add constraint fk_conversaciones_capturadas_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete set null (contacto_id);
alter table ext.mensajes_capturados add constraint fk_mensajes_capturados_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.mensajes_capturados add constraint fk_mensajes_capturados_conversacion_id foreign key (tenant_id, conversacion_id) references ext.conversaciones_capturadas (tenant_id, id) on delete cascade;
alter table ext.patrones add constraint fk_patrones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.patrones add constraint fk_patrones_aprobado_por foreign key (tenant_id, aprobado_por) references platform.membresias (tenant_id, id) on delete set null (aprobado_por);
alter table ext.evidencias_patron add constraint fk_evidencias_patron_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table ext.evidencias_patron add constraint fk_evidencias_patron_patron_id foreign key (tenant_id, patron_id) references ext.patrones (tenant_id, id) on delete cascade;
alter table ext.evidencias_patron add constraint fk_evidencias_patron_mensaje_id foreign key (tenant_id, mensaje_id) references ext.mensajes_capturados (tenant_id, id) on delete cascade;
alter table plugin_vet.mascotas add constraint fk_mascotas_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_vet.propietarios_mascota add constraint fk_propietarios_mascota_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_vet.propietarios_mascota add constraint fk_propietarios_mascota_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete cascade;
alter table plugin_vet.propietarios_mascota add constraint fk_propietarios_mascota_mascota_id foreign key (tenant_id, mascota_id) references plugin_vet.mascotas (tenant_id, id) on delete cascade;
alter table plugin_vet.atenciones add constraint fk_atenciones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_vet.atenciones add constraint fk_atenciones_reserva_id foreign key (tenant_id, reserva_id) references elius.reservas (tenant_id, id) on delete cascade;
alter table plugin_vet.atenciones add constraint fk_atenciones_mascota_id foreign key (tenant_id, mascota_id) references plugin_vet.mascotas (tenant_id, id) on delete cascade;
alter table plugin_vet.atenciones add constraint fk_atenciones_servicio_id foreign key (tenant_id, servicio_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table plugin_vet.atenciones add constraint fk_atenciones_profesional_id foreign key (tenant_id, profesional_id) references platform.membresias (tenant_id, id) on delete cascade;
alter table plugin_vet.registros_clinicos add constraint fk_registros_clinicos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_vet.registros_clinicos add constraint fk_registros_clinicos_atencion_id foreign key (tenant_id, atencion_id) references plugin_vet.atenciones (tenant_id, id) on delete cascade;
alter table plugin_vet.registros_clinicos add constraint fk_registros_clinicos_autor_id foreign key (tenant_id, autor_id) references platform.membresias (tenant_id, id) on delete cascade;
alter table plugin_vet.registros_clinicos add constraint fk_registros_clinicos_corrige_a foreign key (tenant_id, corrige_a) references plugin_vet.registros_clinicos (tenant_id, id) on delete set null (corrige_a);
alter table plugin_vet.aplicaciones_vacuna add constraint fk_aplicaciones_vacuna_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_vet.aplicaciones_vacuna add constraint fk_aplicaciones_vacuna_mascota_id foreign key (tenant_id, mascota_id) references plugin_vet.mascotas (tenant_id, id) on delete cascade;
alter table plugin_vet.aplicaciones_vacuna add constraint fk_aplicaciones_vacuna_vacuna_id foreign key (tenant_id, vacuna_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table plugin_vet.aplicaciones_vacuna add constraint fk_aplicaciones_vacuna_atencion_id foreign key (tenant_id, atencion_id) references plugin_vet.atenciones (tenant_id, id) on delete set null (atencion_id);
alter table plugin_vet.aplicaciones_vacuna add constraint fk_aplicaciones_vacuna_aplicada_por foreign key (tenant_id, aplicada_por) references platform.membresias (tenant_id, id) on delete cascade;
alter table plugin_restaurant.alergenos add constraint fk_alergenos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.item_alergenos add constraint fk_item_alergenos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.item_alergenos add constraint fk_item_alergenos_item_id foreign key (tenant_id, item_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table plugin_restaurant.item_alergenos add constraint fk_item_alergenos_alergeno_id foreign key (tenant_id, alergeno_id) references plugin_restaurant.alergenos (tenant_id, id) on delete restrict;
alter table plugin_restaurant.grupos_modificador add constraint fk_grupos_modificador_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.opciones_modificador add constraint fk_opciones_modificador_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.opciones_modificador add constraint fk_opciones_modificador_grupo_id foreign key (tenant_id, grupo_id) references plugin_restaurant.grupos_modificador (tenant_id, id) on delete restrict;
alter table plugin_restaurant.item_grupos_modificador add constraint fk_item_grupos_modificador_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.item_grupos_modificador add constraint fk_item_grupos_modificador_item_id foreign key (tenant_id, item_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table plugin_restaurant.item_grupos_modificador add constraint fk_item_grupos_modificador_grupo_id foreign key (tenant_id, grupo_id) references plugin_restaurant.grupos_modificador (tenant_id, id) on delete restrict;
alter table plugin_restaurant.orden_item_opciones add constraint fk_orden_item_opciones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.orden_item_opciones add constraint fk_orden_item_opciones_orden_item_id foreign key (tenant_id, orden_item_id) references elius.orden_items (tenant_id, id) on delete cascade;
alter table plugin_restaurant.orden_item_opciones add constraint fk_orden_item_opciones_opcion_id foreign key (tenant_id, opcion_id) references plugin_restaurant.opciones_modificador (tenant_id, id) on delete restrict;
alter table plugin_restaurant.estaciones_cocina add constraint fk_estaciones_cocina_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.comandas add constraint fk_comandas_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.comandas add constraint fk_comandas_orden_id foreign key (tenant_id, orden_id) references elius.ordenes (tenant_id, id) on delete cascade;
alter table plugin_restaurant.comandas add constraint fk_comandas_estacion_id foreign key (tenant_id, estacion_id) references plugin_restaurant.estaciones_cocina (tenant_id, id) on delete restrict;
alter table plugin_restaurant.comanda_items add constraint fk_comanda_items_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.comanda_items add constraint fk_comanda_items_comanda_id foreign key (tenant_id, comanda_id) references plugin_restaurant.comandas (tenant_id, id) on delete cascade;
alter table plugin_restaurant.comanda_items add constraint fk_comanda_items_orden_item_id foreign key (tenant_id, orden_item_id) references elius.orden_items (tenant_id, id) on delete cascade;
alter table plugin_restaurant.menus_dia add constraint fk_menus_dia_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.menus_dia add constraint fk_menus_dia_confirmado_por foreign key (tenant_id, confirmado_por) references platform.membresias (tenant_id, id) on delete set null (confirmado_por);
alter table plugin_restaurant.menu_dia_items add constraint fk_menu_dia_items_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.menu_dia_items add constraint fk_menu_dia_items_menu_id foreign key (tenant_id, menu_id) references plugin_restaurant.menus_dia (tenant_id, id) on delete cascade;
alter table plugin_restaurant.menu_dia_items add constraint fk_menu_dia_items_item_id foreign key (tenant_id, item_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table plugin_restaurant.celebraciones add constraint fk_celebraciones_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_restaurant.celebraciones add constraint fk_celebraciones_reserva_id foreign key (tenant_id, reserva_id) references elius.reservas (tenant_id, id) on delete cascade;
alter table plugin_airline.aeronaves add constraint fk_aeronaves_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.rutas add constraint fk_rutas_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.rutas add constraint fk_rutas_origen_id foreign key (origen_id) references plugin_airline.aeropuertos (id) on delete restrict;
alter table plugin_airline.rutas add constraint fk_rutas_destino_id foreign key (destino_id) references plugin_airline.aeropuertos (id) on delete restrict;
alter table plugin_airline.vuelos add constraint fk_vuelos_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.vuelos add constraint fk_vuelos_ruta_id foreign key (tenant_id, ruta_id) references plugin_airline.rutas (tenant_id, id) on delete restrict;
alter table plugin_airline.vuelos add constraint fk_vuelos_aeronave_id foreign key (tenant_id, aeronave_id) references plugin_airline.aeronaves (tenant_id, id) on delete restrict;
alter table plugin_airline.tarifas_vuelo add constraint fk_tarifas_vuelo_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.tarifas_vuelo add constraint fk_tarifas_vuelo_vuelo_id foreign key (tenant_id, vuelo_id) references plugin_airline.vuelos (tenant_id, id) on delete cascade;
alter table plugin_airline.tarifas_vuelo add constraint fk_tarifas_vuelo_tarifa_id foreign key (tenant_id, tarifa_id) references elius.items_catalogo (tenant_id, id) on delete restrict;
alter table plugin_airline.reserva_pasajeros add constraint fk_reserva_pasajeros_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.reserva_pasajeros add constraint fk_reserva_pasajeros_reserva_id foreign key (tenant_id, reserva_id) references elius.reservas (tenant_id, id) on delete cascade;
alter table plugin_airline.reserva_pasajeros add constraint fk_reserva_pasajeros_contacto_id foreign key (tenant_id, contacto_id) references elius.contactos (tenant_id, id) on delete cascade;
alter table plugin_airline.tramos_reserva add constraint fk_tramos_reserva_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.tramos_reserva add constraint fk_tramos_reserva_reserva_id foreign key (tenant_id, reserva_id) references elius.reservas (tenant_id, id) on delete cascade;
alter table plugin_airline.tramos_reserva add constraint fk_tramos_reserva_tarifa_vuelo_id foreign key (tenant_id, tarifa_vuelo_id) references plugin_airline.tarifas_vuelo (tenant_id, id) on delete restrict;
alter table plugin_airline.tiquetes add constraint fk_tiquetes_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.tiquetes add constraint fk_tiquetes_reserva_pasajero_id foreign key (tenant_id, reserva_pasajero_id) references plugin_airline.reserva_pasajeros (tenant_id, id) on delete cascade;
alter table plugin_airline.tiquetes add constraint fk_tiquetes_tramo_id foreign key (tenant_id, tramo_id) references plugin_airline.tramos_reserva (tenant_id, id) on delete cascade;
alter table plugin_airline.equipajes add constraint fk_equipajes_tenant foreign key (tenant_id) references platform.tenants (id) on delete cascade;
alter table plugin_airline.equipajes add constraint fk_equipajes_tiquete_id foreign key (tenant_id, tiquete_id) references plugin_airline.tiquetes (tenant_id, id) on delete cascade;

-- -----------------------------------------------------------------------------
-- Índices: toda llave foránea indexada empezando por tenant_id (DT-06)
-- -----------------------------------------------------------------------------
create index ix_tenants_plan_id on platform.tenants (plan_id);
create index ix_permisos_plugin_id on platform.permisos (plugin_id);
create index ix_rol_permisos_rol_id on platform.rol_permisos (rol_id);
create index ix_rol_permisos_permiso_id on platform.rol_permisos (permiso_id);
create index ix_membresias_usuario_id on platform.membresias (tenant_id, usuario_id);
create index ix_membresias_rol_id on platform.membresias (tenant_id, rol_id);
create index ix_membresias_invitado_por on platform.membresias (tenant_id, invitado_por);
create index ix_accesos_especiales_membresia_id on platform.accesos_especiales (tenant_id, membresia_id);
create index ix_accesos_especiales_permiso_id on platform.accesos_especiales (tenant_id, permiso_id);
create index ix_accesos_especiales_otorgado_por on platform.accesos_especiales (tenant_id, otorgado_por);
create index ix_asignaciones_plataforma_usuario_id on platform.asignaciones_plataforma (usuario_id);
create index ix_asignaciones_plataforma_rol_id on platform.asignaciones_plataforma (rol_id);
create index ix_asignaciones_plataforma_asignado_por on platform.asignaciones_plataforma (asignado_por);
create index ix_tenant_plugins_plugin_id on platform.tenant_plugins (tenant_id, plugin_id);
create index ix_tenant_plugins_instalado_por on platform.tenant_plugins (tenant_id, instalado_por);
create index ix_accesos_soporte_usuario_soporte_id on platform.accesos_soporte (tenant_id, usuario_soporte_id);
create index ix_accesos_soporte_autorizado_por on platform.accesos_soporte (tenant_id, autorizado_por);
create index ix_invitaciones_rol_id on platform.invitaciones (tenant_id, rol_id);
create index ix_invitaciones_invitado_por on platform.invitaciones (tenant_id, invitado_por);
create index ix_llaves_api_creado_por on platform.llaves_api (tenant_id, creado_por);
create index ix_registros_auditoria_usuario_id on audit.registros_auditoria (usuario_id);
create index ix_direcciones_contacto_id on elius.direcciones (tenant_id, contacto_id);
create index ix_consentimientos_contacto_id on elius.consentimientos (tenant_id, contacto_id);
create index ix_canales_agente_id on elius.canales (tenant_id, agente_id);
create index ix_identidades_contacto_contacto_id on elius.identidades_contacto (tenant_id, contacto_id);
create index ix_identidades_contacto_canal_id on elius.identidades_contacto (tenant_id, canal_id);
create index ix_conversaciones_identidad_id on elius.conversaciones (tenant_id, identidad_id);
create index ix_conversaciones_asignado_a on elius.conversaciones (tenant_id, asignado_a);
create index ix_mensajes_conversacion_id on elius.mensajes (tenant_id, conversacion_id);
create index ix_consumos_llm_conversacion_id on elius.consumos_llm (tenant_id, conversacion_id);
create index ix_consumos_llm_mensaje_id on elius.consumos_llm (tenant_id, mensaje_id);
create index ix_items_catalogo_categoria_id on elius.items_catalogo (tenant_id, categoria_id);
create index ix_horarios_atencion_recurso_id on elius.horarios_atencion (tenant_id, recurso_id);
create index ix_reservas_contacto_id on elius.reservas (tenant_id, contacto_id);
create index ix_reservas_conversacion_id on elius.reservas (tenant_id, conversacion_id);
create index ix_reservas_responsable_id on elius.reservas (tenant_id, responsable_id);
create index ix_asignaciones_recurso_reserva_id on elius.asignaciones_recurso (tenant_id, reserva_id);
create index ix_asignaciones_recurso_recurso_id on elius.asignaciones_recurso (tenant_id, recurso_id);
create index ix_ordenes_contacto_id on elius.ordenes (tenant_id, contacto_id);
create index ix_ordenes_reserva_id on elius.ordenes (tenant_id, reserva_id);
create index ix_ordenes_conversacion_id on elius.ordenes (tenant_id, conversacion_id);
create index ix_ordenes_direccion_entrega_id on elius.ordenes (tenant_id, direccion_entrega_id);
create index ix_ordenes_responsable_id on elius.ordenes (tenant_id, responsable_id);
create index ix_orden_items_orden_id on elius.orden_items (tenant_id, orden_id);
create index ix_orden_items_item_id on elius.orden_items (tenant_id, item_id);
create index ix_pagos_orden_id on elius.pagos (tenant_id, orden_id);
create index ix_pagos_pago_original_id on elius.pagos (tenant_id, pago_original_id);
create index ix_pagos_comprobante_id on elius.pagos (tenant_id, comprobante_id);
create index ix_pagos_recaudo_id on elius.pagos (tenant_id, recaudo_id);
create index ix_comprobantes_pago_orden_id on elius.comprobantes_pago (tenant_id, orden_id);
create index ix_comprobantes_pago_conversacion_id on elius.comprobantes_pago (tenant_id, conversacion_id);
create index ix_comprobantes_pago_decidido_por on elius.comprobantes_pago (tenant_id, decidido_por);
create index ix_recaudos_orden_id on elius.recaudos (tenant_id, orden_id);
create index ix_recaudos_pasarela_id on elius.recaudos (tenant_id, pasarela_id);
create index ix_notificaciones_pasarela_pasarela_id on elius.notificaciones_pasarela (tenant_id, pasarela_id);
create index ix_notificaciones_pasarela_recaudo_id on elius.notificaciones_pasarela (tenant_id, recaudo_id);
create index ix_entregas_orden_id on elius.entregas (tenant_id, orden_id);
create index ix_entregas_repartidor_id on elius.entregas (tenant_id, repartidor_id);
create index ix_item_adicionales_item_id on elius.item_adicionales (tenant_id, item_id);
create index ix_item_adicionales_adicional_id on elius.item_adicionales (tenant_id, adicional_id);
create index ix_medios_item_item_id on elius.medios_item (tenant_id, item_id);
create index ix_escalamientos_conversacion_id on elius.escalamientos (tenant_id, conversacion_id);
create index ix_escalamientos_asignado_a on elius.escalamientos (tenant_id, asignado_a);
create index ix_escalamientos_resuelto_por on elius.escalamientos (tenant_id, resuelto_por);
create index ix_eventos_embudo_conversacion_id on elius.eventos_embudo (tenant_id, conversacion_id);
create index ix_errores_agente_conversacion_id on elius.errores_agente (tenant_id, conversacion_id);
create index ix_errores_agente_resuelto_por on elius.errores_agente (tenant_id, resuelto_por);
create index ix_suscripciones_push_membresia_id on elius.suscripciones_push (tenant_id, membresia_id);
create index ix_fragmentos_conocimiento_documento_id on elius.fragmentos_conocimiento (tenant_id, documento_id);
create index ix_instalaciones_extension_membresia_id on ext.instalaciones_extension (tenant_id, membresia_id);
create index ix_sitios_autorizados_autorizado_por on ext.sitios_autorizados (tenant_id, autorizado_por);
create index ix_conversaciones_capturadas_instalacion_id on ext.conversaciones_capturadas (tenant_id, instalacion_id);
create index ix_conversaciones_capturadas_sitio_id on ext.conversaciones_capturadas (tenant_id, sitio_id);
create index ix_conversaciones_capturadas_contacto_id on ext.conversaciones_capturadas (tenant_id, contacto_id);
create index ix_mensajes_capturados_conversacion_id on ext.mensajes_capturados (tenant_id, conversacion_id);
create index ix_patrones_aprobado_por on ext.patrones (tenant_id, aprobado_por);
create index ix_evidencias_patron_patron_id on ext.evidencias_patron (tenant_id, patron_id);
create index ix_evidencias_patron_mensaje_id on ext.evidencias_patron (tenant_id, mensaje_id);
create index ix_propietarios_mascota_contacto_id on plugin_vet.propietarios_mascota (tenant_id, contacto_id);
create index ix_propietarios_mascota_mascota_id on plugin_vet.propietarios_mascota (tenant_id, mascota_id);
create index ix_atenciones_reserva_id on plugin_vet.atenciones (tenant_id, reserva_id);
create index ix_atenciones_mascota_id on plugin_vet.atenciones (tenant_id, mascota_id);
create index ix_atenciones_servicio_id on plugin_vet.atenciones (tenant_id, servicio_id);
create index ix_atenciones_profesional_id on plugin_vet.atenciones (tenant_id, profesional_id);
create index ix_registros_clinicos_atencion_id on plugin_vet.registros_clinicos (tenant_id, atencion_id);
create index ix_registros_clinicos_autor_id on plugin_vet.registros_clinicos (tenant_id, autor_id);
create index ix_registros_clinicos_corrige_a on plugin_vet.registros_clinicos (tenant_id, corrige_a);
create index ix_aplicaciones_vacuna_mascota_id on plugin_vet.aplicaciones_vacuna (tenant_id, mascota_id);
create index ix_aplicaciones_vacuna_vacuna_id on plugin_vet.aplicaciones_vacuna (tenant_id, vacuna_id);
create index ix_aplicaciones_vacuna_atencion_id on plugin_vet.aplicaciones_vacuna (tenant_id, atencion_id);
create index ix_aplicaciones_vacuna_aplicada_por on plugin_vet.aplicaciones_vacuna (tenant_id, aplicada_por);
create index ix_item_alergenos_item_id on plugin_restaurant.item_alergenos (tenant_id, item_id);
create index ix_item_alergenos_alergeno_id on plugin_restaurant.item_alergenos (tenant_id, alergeno_id);
create index ix_opciones_modificador_grupo_id on plugin_restaurant.opciones_modificador (tenant_id, grupo_id);
create index ix_item_grupos_modificador_item_id on plugin_restaurant.item_grupos_modificador (tenant_id, item_id);
create index ix_item_grupos_modificador_grupo_id on plugin_restaurant.item_grupos_modificador (tenant_id, grupo_id);
create index ix_orden_item_opciones_orden_item_id on plugin_restaurant.orden_item_opciones (tenant_id, orden_item_id);
create index ix_orden_item_opciones_opcion_id on plugin_restaurant.orden_item_opciones (tenant_id, opcion_id);
create index ix_comandas_orden_id on plugin_restaurant.comandas (tenant_id, orden_id);
create index ix_comandas_estacion_id on plugin_restaurant.comandas (tenant_id, estacion_id);
create index ix_comanda_items_comanda_id on plugin_restaurant.comanda_items (tenant_id, comanda_id);
create index ix_comanda_items_orden_item_id on plugin_restaurant.comanda_items (tenant_id, orden_item_id);
create index ix_menus_dia_confirmado_por on plugin_restaurant.menus_dia (tenant_id, confirmado_por);
create index ix_menu_dia_items_menu_id on plugin_restaurant.menu_dia_items (tenant_id, menu_id);
create index ix_menu_dia_items_item_id on plugin_restaurant.menu_dia_items (tenant_id, item_id);
create index ix_celebraciones_reserva_id on plugin_restaurant.celebraciones (tenant_id, reserva_id);
create index ix_rutas_origen_id on plugin_airline.rutas (tenant_id, origen_id);
create index ix_rutas_destino_id on plugin_airline.rutas (tenant_id, destino_id);
create index ix_vuelos_ruta_id on plugin_airline.vuelos (tenant_id, ruta_id);
create index ix_vuelos_aeronave_id on plugin_airline.vuelos (tenant_id, aeronave_id);
create index ix_tarifas_vuelo_vuelo_id on plugin_airline.tarifas_vuelo (tenant_id, vuelo_id);
create index ix_tarifas_vuelo_tarifa_id on plugin_airline.tarifas_vuelo (tenant_id, tarifa_id);
create index ix_reserva_pasajeros_reserva_id on plugin_airline.reserva_pasajeros (tenant_id, reserva_id);
create index ix_reserva_pasajeros_contacto_id on plugin_airline.reserva_pasajeros (tenant_id, contacto_id);
create index ix_tramos_reserva_reserva_id on plugin_airline.tramos_reserva (tenant_id, reserva_id);
create index ix_tramos_reserva_tarifa_vuelo_id on plugin_airline.tramos_reserva (tenant_id, tarifa_vuelo_id);
create index ix_tiquetes_reserva_pasajero_id on plugin_airline.tiquetes (tenant_id, reserva_pasajero_id);
create index ix_tiquetes_tramo_id on plugin_airline.tiquetes (tenant_id, tramo_id);
create index ix_equipajes_tiquete_id on plugin_airline.equipajes (tenant_id, tiquete_id);

-- -----------------------------------------------------------------------------
-- Comentarios: el diccionario de datos vive también dentro de la base
-- -----------------------------------------------------------------------------
comment on table platform.planes is 'Planes de suscripción y sus límites [referencia]';
comment on column platform.planes.id is 'Identificador único';
comment on column platform.planes.codigo is 'free, starter, pro, enterprise';
comment on column platform.planes.nombre is 'Nombre comercial';
comment on column platform.planes.precio_mensual is 'Precio mensual';
comment on column platform.planes.moneda is 'Moneda ISO 4217';
comment on column platform.planes.max_usuarios is 'Usuarios permitidos por tenant';
comment on column platform.planes.max_conversaciones_mes is 'Conversaciones de Eli por mes';
comment on column platform.planes.max_tokens_mes is 'Tokens de LLM por mes';
comment on column platform.planes.activo is 'Disponible para nuevos tenants';
comment on column platform.planes.creado_en is 'Fecha de creación';
comment on column platform.planes.actualizado_en is 'Fecha de la última modificación';
comment on table platform.tenants is 'Cada negocio cliente de Elius [entidad]';
comment on column platform.tenants.id is 'Identificador único';
comment on column platform.tenants.plan_id is 'Plan contratado';
comment on column platform.tenants.slug is 'Identificador corto único';
comment on column platform.tenants.nombre is 'Nombre comercial';
comment on column platform.tenants.vertical is 'veterinaria, restaurante, aerolinea, otro';
comment on column platform.tenants.estado is 'prueba, activo, suspendido, cancelado';
comment on column platform.tenants.fin_prueba is 'Último día del periodo de prueba';
comment on column platform.tenants.razon_social is 'Nombre legal';
comment on column platform.tenants.nit is 'Identificación tributaria';
comment on column platform.tenants.pais is 'País ISO 3166';
comment on column platform.tenants.zona_horaria is 'Ej. America/Bogota';
comment on column platform.tenants.moneda is 'Moneda de operación';
comment on column platform.tenants.eliminado_en is 'Borrado lógico';
comment on column platform.tenants.creado_en is 'Fecha de creación';
comment on column platform.tenants.actualizado_en is 'Fecha de la última modificación';
comment on table platform.roles is 'Los 6 roles generales y fijos [referencia]';
comment on column platform.roles.id is 'Identificador único';
comment on column platform.roles.codigo is 'super_admin, soporte, administrador, operador, analista, eli';
comment on column platform.roles.nombre is 'Nombre visible';
comment on column platform.roles.nivel is 'plataforma o tenant';
comment on column platform.roles.descripcion is 'Qué hace el rol';
comment on column platform.roles.orden is 'Orden de presentación';
comment on column platform.roles.creado_en is 'Fecha de creación';
comment on column platform.roles.actualizado_en is 'Fecha de la última modificación';
comment on table platform.plugins is 'Catálogo de plugins (microkernel) [referencia]';
comment on column platform.plugins.id is 'Identificador único';
comment on column platform.plugins.codigo is 'vet, restaurant, airline';
comment on column platform.plugins.nombre is 'Nombre visible';
comment on column platform.plugins.esquema is 'Esquema de la BD del plugin';
comment on column platform.plugins.version is 'Versión semántica';
comment on column platform.plugins.verticales is 'Verticales a las que se instala por defecto';
comment on column platform.plugins.manifiesto is 'Módulos, permisos y configuración que aporta';
comment on column platform.plugins.activo is 'Disponible para instalar';
comment on column platform.plugins.creado_en is 'Fecha de creación';
comment on column platform.plugins.actualizado_en is 'Fecha de la última modificación';
comment on table platform.permisos is 'Módulos y accesos que se pueden otorgar [referencia]';
comment on column platform.permisos.id is 'Identificador único';
comment on column platform.permisos.plugin_id is 'Plugin que lo aporta; vacío = núcleo';
comment on column platform.permisos.codigo is 'Ej. contactos, vet.historia_clinica';
comment on column platform.permisos.modulo is 'Módulo funcional';
comment on column platform.permisos.descripcion is 'Qué permite';
comment on column platform.permisos.es_acceso_especial is 'Se otorga por usuario con un interruptor';
comment on column platform.permisos.protege_dato_sensible is 'Da acceso a datos sensibles';
comment on column platform.permisos.creado_en is 'Fecha de creación';
comment on column platform.permisos.actualizado_en is 'Fecha de la última modificación';
comment on table platform.rol_permisos is 'Qué puede hacer cada rol en cada módulo [transicion]';
comment on column platform.rol_permisos.id is 'Identificador único';
comment on column platform.rol_permisos.rol_id is 'Rol';
comment on column platform.rol_permisos.permiso_id is 'Permiso';
comment on column platform.rol_permisos.nivel is 'lectura, escritura, total, con_autorizacion';
comment on column platform.rol_permisos.origen is 'nucleo o código del plugin que lo asignó';
comment on column platform.rol_permisos.creado_en is 'Fecha de creación';
comment on column platform.rol_permisos.actualizado_en is 'Fecha de la última modificación';
comment on table platform.membresias is 'Usuario dentro de un tenant con su rol (tenantUser) [transicion]';
comment on column platform.membresias.id is 'Identificador único';
comment on column platform.membresias.tenant_id is 'Tenant dueño del registro';
comment on column platform.membresias.usuario_id is 'Usuario';
comment on column platform.membresias.rol_id is 'Rol general dentro del tenant';
comment on column platform.membresias.estado is 'invitado, activo, inactivo';
comment on column platform.membresias.cargo is 'Etiqueta visible: Veterinario, Mesero… (no da permisos)';
comment on column platform.membresias.es_predeterminada is 'Tenant que se carga en el JWT al iniciar sesión';
comment on column platform.membresias.invitado_por is 'Quién lo invitó';
comment on column platform.membresias.fecha_ingreso is 'Cuándo aceptó';
comment on column platform.membresias.creado_en is 'Fecha de creación';
comment on column platform.membresias.actualizado_en is 'Fecha de la última modificación';
comment on table platform.accesos_especiales is 'Accesos especiales del plugin otorgados a un usuario (ej. historia clínica) [transicion]';
comment on column platform.accesos_especiales.id is 'Identificador único';
comment on column platform.accesos_especiales.tenant_id is 'Tenant dueño del registro';
comment on column platform.accesos_especiales.membresia_id is 'Usuario en el tenant';
comment on column platform.accesos_especiales.permiso_id is 'Acceso especial';
comment on column platform.accesos_especiales.otorgado_por is 'Administrador que lo activó';
comment on column platform.accesos_especiales.motivo is 'Justificación';
comment on column platform.accesos_especiales.vence_en is 'Vencimiento opcional';
comment on column platform.accesos_especiales.creado_en is 'Fecha de creación';
comment on column platform.accesos_especiales.actualizado_en is 'Fecha de la última modificación';
comment on table platform.asignaciones_plataforma is 'Roles de plataforma del equipo Elius (Super Admin, Soporte) [transicion]';
comment on column platform.asignaciones_plataforma.id is 'Identificador único';
comment on column platform.asignaciones_plataforma.usuario_id is 'Persona del equipo Elius';
comment on column platform.asignaciones_plataforma.rol_id is 'super_admin o soporte';
comment on column platform.asignaciones_plataforma.asignado_por is 'Quién lo asignó';
comment on column platform.asignaciones_plataforma.desde is 'Inicio';
comment on column platform.asignaciones_plataforma.hasta is 'Fin; vacío = vigente';
comment on column platform.asignaciones_plataforma.creado_en is 'Fecha de creación';
comment on column platform.asignaciones_plataforma.actualizado_en is 'Fecha de la última modificación';
comment on table platform.tenant_plugins is 'Plugins instalados en cada tenant [transicion]';
comment on column platform.tenant_plugins.id is 'Identificador único';
comment on column platform.tenant_plugins.tenant_id is 'Tenant dueño del registro';
comment on column platform.tenant_plugins.plugin_id is 'Plugin';
comment on column platform.tenant_plugins.habilitado is 'Activo para el tenant';
comment on column platform.tenant_plugins.configuracion is 'Configuración propia del tenant';
comment on column platform.tenant_plugins.version_instalada is 'Versión instalada';
comment on column platform.tenant_plugins.instalado_por is 'Quién lo instaló';
comment on column platform.tenant_plugins.creado_en is 'Fecha de creación';
comment on column platform.tenant_plugins.actualizado_en is 'Fecha de la última modificación';
comment on table platform.accesos_soporte is 'Autorización temporal del Administrador para que Soporte entre al tenant [transicion]';
comment on column platform.accesos_soporte.id is 'Identificador único';
comment on column platform.accesos_soporte.tenant_id is 'Tenant dueño del registro';
comment on column platform.accesos_soporte.usuario_soporte_id is 'Persona de soporte';
comment on column platform.accesos_soporte.autorizado_por is 'Administrador que autoriza';
comment on column platform.accesos_soporte.motivo is 'Para qué se necesita el acceso';
comment on column platform.accesos_soporte.inicio is 'Desde cuándo';
comment on column platform.accesos_soporte.vence_en is 'Vence solo';
comment on column platform.accesos_soporte.revocado_en is 'Revocación anticipada';
comment on column platform.accesos_soporte.creado_en is 'Fecha de creación';
comment on column platform.accesos_soporte.actualizado_en is 'Fecha de la última modificación';
comment on table platform.invitaciones is 'Invitaciones por correo a un tenant [entidad]';
comment on column platform.invitaciones.id is 'Identificador único';
comment on column platform.invitaciones.tenant_id is 'Tenant dueño del registro';
comment on column platform.invitaciones.rol_id is 'Rol que tendrá';
comment on column platform.invitaciones.invitado_por is 'Quién invita';
comment on column platform.invitaciones.email is 'Correo invitado [PERSONAL]';
comment on column platform.invitaciones.hash_token is 'Hash del token (nunca el token)';
comment on column platform.invitaciones.vence_en is '7 días después de creada';
comment on column platform.invitaciones.aceptada_en is 'Cuándo se aceptó';
comment on column platform.invitaciones.creado_en is 'Fecha de creación';
comment on column platform.invitaciones.actualizado_en is 'Fecha de la última modificación';
comment on table platform.llaves_api is 'Llaves de API por tenant (n8n, integraciones) [entidad]';
comment on column platform.llaves_api.id is 'Identificador único';
comment on column platform.llaves_api.tenant_id is 'Tenant dueño del registro';
comment on column platform.llaves_api.creado_por is 'Quién la creó';
comment on column platform.llaves_api.nombre is 'Nombre descriptivo';
comment on column platform.llaves_api.prefijo is 'Primeros caracteres visibles';
comment on column platform.llaves_api.hash_llave is 'Hash SHA-256 de la llave';
comment on column platform.llaves_api.alcances is 'Permisos de la llave';
comment on column platform.llaves_api.ultimo_uso is 'Último uso';
comment on column platform.llaves_api.vence_en is 'Vencimiento';
comment on column platform.llaves_api.revocada_en is 'Revocación';
comment on column platform.llaves_api.creado_en is 'Fecha de creación';
comment on column platform.llaves_api.actualizado_en is 'Fecha de la última modificación';
comment on table platform.consumos_periodo is 'Consumo por mes para límites del plan y cobro [entidad]';
comment on column platform.consumos_periodo.id is 'Identificador único';
comment on column platform.consumos_periodo.tenant_id is 'Tenant dueño del registro';
comment on column platform.consumos_periodo.periodo is 'Primer día del mes';
comment on column platform.consumos_periodo.metrica is 'conversaciones, mensajes, tokens_llm, almacenamiento_mb';
comment on column platform.consumos_periodo.valor is 'Cantidad acumulada';
comment on column platform.consumos_periodo.creado_en is 'Fecha de creación';
comment on column platform.consumos_periodo.actualizado_en is 'Fecha de la última modificación';
comment on table audit.registros_auditoria is 'Bitácora de cambios de todas las tablas [entidad]';
comment on column audit.registros_auditoria.id is 'Identificador único';
comment on column audit.registros_auditoria.tenant_id is 'Tenant afectado';
comment on column audit.registros_auditoria.usuario_id is 'Quién hizo el cambio';
comment on column audit.registros_auditoria.rol is 'Rol con el que actuó';
comment on column audit.registros_auditoria.origen is 'app, eli, soporte, sistema';
comment on column audit.registros_auditoria.esquema is 'Esquema de la tabla';
comment on column audit.registros_auditoria.tabla is 'Tabla afectada';
comment on column audit.registros_auditoria.registro_id is 'Fila afectada';
comment on column audit.registros_auditoria.operacion is 'INSERT, UPDATE, DELETE';
comment on column audit.registros_auditoria.datos_anteriores is 'Valores antes [RESTRINGIDO]';
comment on column audit.registros_auditoria.datos_nuevos is 'Valores después [RESTRINGIDO]';
comment on column audit.registros_auditoria.creado_en is 'Fecha de creación';
comment on column audit.registros_auditoria.actualizado_en is 'Fecha de la última modificación';
comment on table elius.contactos is 'Cliente final: propietario, comensal, pasajero o comprador [entidad]';
comment on column elius.contactos.id is 'Identificador único';
comment on column elius.contactos.tenant_id is 'Tenant dueño del registro';
comment on column elius.contactos.tipo is 'persona o empresa';
comment on column elius.contactos.nombres is 'Nombres [PERSONAL]';
comment on column elius.contactos.apellidos is 'Apellidos [PERSONAL]';
comment on column elius.contactos.email is 'Correo [PERSONAL]';
comment on column elius.contactos.telefono is 'Teléfono E.164 [PERSONAL]';
comment on column elius.contactos.tipo_documento is 'CC, CE, PA, NIT…';
comment on column elius.contactos.numero_documento is 'Número de documento [RESTRINGIDO, PERSONAL]';
comment on column elius.contactos.fecha_nacimiento is 'Fecha de nacimiento [RESTRINGIDO, PERSONAL]';
comment on column elius.contactos.etiquetas is 'Segmentación libre';
comment on column elius.contactos.origen is 'whatsapp, web, presencial, chrome…';
comment on column elius.contactos.eliminado_en is 'Borrado lógico';
comment on column elius.contactos.creado_en is 'Fecha de creación';
comment on column elius.contactos.actualizado_en is 'Fecha de la última modificación';
comment on table elius.direcciones is 'Direcciones de un contacto (domicilios) [entidad]';
comment on column elius.direcciones.id is 'Identificador único';
comment on column elius.direcciones.tenant_id is 'Tenant dueño del registro';
comment on column elius.direcciones.contacto_id is 'Contacto';
comment on column elius.direcciones.etiqueta is 'Casa, oficina…';
comment on column elius.direcciones.direccion is 'Dirección [PERSONAL]';
comment on column elius.direcciones.ciudad is 'Ciudad';
comment on column elius.direcciones.barrio is 'Barrio';
comment on column elius.direcciones.indicaciones is 'Cómo llegar [PERSONAL]';
comment on column elius.direcciones.latitud is 'Ubicación compartida por WhatsApp [PERSONAL]';
comment on column elius.direcciones.longitud is 'Ubicación compartida por WhatsApp [PERSONAL]';
comment on column elius.direcciones.es_principal is 'Dirección por defecto';
comment on column elius.direcciones.creado_en is 'Fecha de creación';
comment on column elius.direcciones.actualizado_en is 'Fecha de la última modificación';
comment on table elius.consentimientos is 'Autorizaciones de tratamiento de datos (Ley 1581, art. 9) [entidad]';
comment on column elius.consentimientos.id is 'Identificador único';
comment on column elius.consentimientos.tenant_id is 'Tenant dueño del registro';
comment on column elius.consentimientos.contacto_id is 'Titular';
comment on column elius.consentimientos.finalidad is 'Para qué se autoriza';
comment on column elius.consentimientos.canal is 'Por dónde se obtuvo';
comment on column elius.consentimientos.texto_aceptado is 'Texto exacto que aceptó';
comment on column elius.consentimientos.aceptado_en is 'Fecha de aceptación';
comment on column elius.consentimientos.revocado_en is 'Fecha de revocación';
comment on column elius.consentimientos.creado_en is 'Fecha de creación';
comment on column elius.consentimientos.actualizado_en is 'Fecha de la última modificación';
comment on table elius.agentes is 'Configuración de Eli por tenant [entidad]';
comment on column elius.agentes.id is 'Identificador único';
comment on column elius.agentes.tenant_id is 'Tenant dueño del registro';
comment on column elius.agentes.nombre is 'Nombre del agente';
comment on column elius.agentes.modelo_llm is 'Modelo de lenguaje';
comment on column elius.agentes.prompt_sistema is 'Instrucciones base';
comment on column elius.agentes.tono is 'Ej. empático, cercano, formal';
comment on column elius.agentes.temperatura is 'Creatividad del modelo';
comment on column elius.agentes.version is 'Versión de la configuración';
comment on column elius.agentes.activo is 'En uso';
comment on column elius.agentes.creado_en is 'Fecha de creación';
comment on column elius.agentes.actualizado_en is 'Fecha de la última modificación';
comment on table elius.canales is 'Canales del tenant: número de WhatsApp, widget web, extensión [entidad]';
comment on column elius.canales.id is 'Identificador único';
comment on column elius.canales.tenant_id is 'Tenant dueño del registro';
comment on column elius.canales.agente_id is 'Agente que atiende el canal';
comment on column elius.canales.tipo is 'whatsapp, web, chrome, api';
comment on column elius.canales.nombre is 'Nombre visible';
comment on column elius.canales.identificador_externo is 'Ej. phone_number_id de WhatsApp';
comment on column elius.canales.estado is 'activo, pausado, error';
comment on column elius.canales.referencia_secreto is 'Llave en Supabase Vault';
comment on column elius.canales.creado_en is 'Fecha de creación';
comment on column elius.canales.actualizado_en is 'Fecha de la última modificación';
comment on table elius.identidades_contacto is 'Cómo se identifica un contacto en cada canal [transicion]';
comment on column elius.identidades_contacto.id is 'Identificador único';
comment on column elius.identidades_contacto.tenant_id is 'Tenant dueño del registro';
comment on column elius.identidades_contacto.contacto_id is 'Contacto';
comment on column elius.identidades_contacto.canal_id is 'Canal';
comment on column elius.identidades_contacto.id_externo is 'Ej. número de WhatsApp [PERSONAL]';
comment on column elius.identidades_contacto.nombre_en_canal is 'Nombre que muestra el canal (perfil de WhatsApp) [PERSONAL]';
comment on column elius.identidades_contacto.verificado is 'Identidad confirmada';
comment on column elius.identidades_contacto.primer_contacto_en is 'Primera vez por este canal';
comment on column elius.identidades_contacto.ultimo_contacto_en is 'Última vez por este canal';
comment on column elius.identidades_contacto.creado_en is 'Fecha de creación';
comment on column elius.identidades_contacto.actualizado_en is 'Fecha de la última modificación';
comment on table elius.conversaciones is 'Conversación de un contacto con Eli por un canal [entidad]';
comment on column elius.conversaciones.id is 'Identificador único';
comment on column elius.conversaciones.tenant_id is 'Tenant dueño del registro';
comment on column elius.conversaciones.identidad_id is 'Contacto en el canal';
comment on column elius.conversaciones.asignado_a is 'Humano que la atiende';
comment on column elius.conversaciones.flujo is 'Flujo de Eli: ventas, reservas, menu_dia, carta…';
comment on column elius.conversaciones.estado is 'en_progreso, humano, pausa, cerrada';
comment on column elius.conversaciones.borrador is 'Pedido o reserva que Eli va armando antes de guardarlo';
comment on column elius.conversaciones.bloqueada_en is 'Un proceso la está atendiendo (evita respuestas dobles)';
comment on column elius.conversaciones.intencion is 'Intención detectada';
comment on column elius.conversaciones.sentimiento is 'positivo, neutro, negativo';
comment on column elius.conversaciones.resumen is 'Resumen generado por Eli';
comment on column elius.conversaciones.iniciada_en is 'Inicio';
comment on column elius.conversaciones.ultimo_mensaje_en is 'Último mensaje';
comment on column elius.conversaciones.cerrada_en is 'Cierre';
comment on column elius.conversaciones.creado_en is 'Fecha de creación';
comment on column elius.conversaciones.actualizado_en is 'Fecha de la última modificación';
comment on table elius.mensajes is 'Mensajes de cada conversación [entidad]';
comment on column elius.mensajes.id is 'Identificador único';
comment on column elius.mensajes.tenant_id is 'Tenant dueño del registro';
comment on column elius.mensajes.conversacion_id is 'Conversación';
comment on column elius.mensajes.emisor is 'cliente, eli, humano, sistema';
comment on column elius.mensajes.tipo_contenido is 'texto, imagen, audio, documento, plantilla';
comment on column elius.mensajes.contenido is 'Texto del mensaje [PERSONAL]';
comment on column elius.mensajes.url_adjunto is 'Archivo adjunto';
comment on column elius.mensajes.id_externo is 'Id del mensaje en WhatsApp';
comment on column elius.mensajes.estado_entrega is 'recibido, enviado, entregado, leido, fallido';
comment on column elius.mensajes.procesado is 'Eli ya lo procesó (agrupa mensajes seguidos)';
comment on column elius.mensajes.enviado_en is 'Hora del mensaje';
comment on column elius.mensajes.creado_en is 'Fecha de creación';
comment on column elius.mensajes.actualizado_en is 'Fecha de la última modificación';
comment on table elius.consumos_llm is 'Cada llamada a un modelo de lenguaje [entidad]';
comment on column elius.consumos_llm.id is 'Identificador único';
comment on column elius.consumos_llm.tenant_id is 'Tenant dueño del registro';
comment on column elius.consumos_llm.conversacion_id is 'Conversación';
comment on column elius.consumos_llm.mensaje_id is 'Mensaje que la originó';
comment on column elius.consumos_llm.proveedor is 'Proveedor del modelo';
comment on column elius.consumos_llm.modelo is 'Modelo usado';
comment on column elius.consumos_llm.tokens_entrada is 'Tokens enviados';
comment on column elius.consumos_llm.tokens_salida is 'Tokens recibidos';
comment on column elius.consumos_llm.tokens_cache is 'Tokens leídos de caché';
comment on column elius.consumos_llm.costo_usd is 'Costo estimado';
comment on column elius.consumos_llm.latencia_ms is 'Tiempo de respuesta';
comment on column elius.consumos_llm.creado_en is 'Fecha de creación';
comment on column elius.consumos_llm.actualizado_en is 'Fecha de la última modificación';
comment on table elius.categorias_catalogo is 'Categorías del catálogo: secciones del menú, tipos de servicio… [entidad]';
comment on column elius.categorias_catalogo.id is 'Identificador único';
comment on column elius.categorias_catalogo.tenant_id is 'Tenant dueño del registro';
comment on column elius.categorias_catalogo.nombre is 'Nombre';
comment on column elius.categorias_catalogo.descripcion is 'Descripción';
comment on column elius.categorias_catalogo.orden is 'Orden de presentación';
comment on column elius.categorias_catalogo.disponible_desde is 'Ej. desayunos desde 7:00';
comment on column elius.categorias_catalogo.disponible_hasta is 'Ej. desayunos hasta 11:00';
comment on column elius.categorias_catalogo.activa is 'Visible';
comment on column elius.categorias_catalogo.creado_en is 'Fecha de creación';
comment on column elius.categorias_catalogo.actualizado_en is 'Fecha de la última modificación';
comment on table elius.items_catalogo is 'Todo lo que se vende: platos, productos, servicios, vacunas, tarifas aéreas [entidad]';
comment on column elius.items_catalogo.id is 'Identificador único';
comment on column elius.items_catalogo.tenant_id is 'Tenant dueño del registro';
comment on column elius.items_catalogo.categoria_id is 'Categoría';
comment on column elius.items_catalogo.tipo is 'producto, servicio, paquete, adicional, tarifa';
comment on column elius.items_catalogo.sku is 'Código interno';
comment on column elius.items_catalogo.nombre is 'Nombre';
comment on column elius.items_catalogo.descripcion is 'Descripción';
comment on column elius.items_catalogo.incluye is 'Qué incluye un paquete';
comment on column elius.items_catalogo.precio is 'Precio base';
comment on column elius.items_catalogo.impuesto_pct is 'IVA o impoconsumo';
comment on column elius.items_catalogo.duracion_min is 'Duración, para servicios';
comment on column elius.items_catalogo.disponible is 'false = agotado';
comment on column elius.items_catalogo.atributos is 'Datos propios de la vertical';
comment on column elius.items_catalogo.eliminado_en is 'Borrado lógico';
comment on column elius.items_catalogo.creado_en is 'Fecha de creación';
comment on column elius.items_catalogo.actualizado_en is 'Fecha de la última modificación';
comment on table elius.recursos is 'Lo que se reserva: mesas, consultorios, salas [entidad]';
comment on column elius.recursos.id is 'Identificador único';
comment on column elius.recursos.tenant_id is 'Tenant dueño del registro';
comment on column elius.recursos.tipo is 'mesa, consultorio, sala, equipo';
comment on column elius.recursos.nombre is 'Ej. Mesa 12, Consultorio 2';
comment on column elius.recursos.capacidad is 'Personas o cupos';
comment on column elius.recursos.ubicacion is 'Zona: terraza, salón…';
comment on column elius.recursos.activo is 'Disponible';
comment on column elius.recursos.creado_en is 'Fecha de creación';
comment on column elius.recursos.actualizado_en is 'Fecha de la última modificación';
comment on table elius.horarios_atencion is 'Horario de atención del negocio o de un recurso [entidad]';
comment on column elius.horarios_atencion.id is 'Identificador único';
comment on column elius.horarios_atencion.tenant_id is 'Tenant dueño del registro';
comment on column elius.horarios_atencion.recurso_id is 'Vacío = horario general';
comment on column elius.horarios_atencion.dia_semana is '1 lunes … 7 domingo';
comment on column elius.horarios_atencion.abre is 'Hora de apertura';
comment on column elius.horarios_atencion.cierra is 'Hora de cierre';
comment on column elius.horarios_atencion.vigente_desde is 'Desde';
comment on column elius.horarios_atencion.vigente_hasta is 'Hasta';
comment on column elius.horarios_atencion.creado_en is 'Fecha de creación';
comment on column elius.horarios_atencion.actualizado_en is 'Fecha de la última modificación';
comment on table elius.reservas is 'Citas, reservas de mesa y reservas aéreas [entidad]';
comment on column elius.reservas.id is 'Identificador único';
comment on column elius.reservas.tenant_id is 'Tenant dueño del registro';
comment on column elius.reservas.contacto_id is 'Titular de la reserva';
comment on column elius.reservas.conversacion_id is 'Conversación donde se creó';
comment on column elius.reservas.codigo is 'Código o localizador visible al cliente';
comment on column elius.reservas.tipo is 'cita, mesa, vuelo';
comment on column elius.reservas.estado is 'pendiente_pago, confirmada, asistio, no_asistio, cancelada';
comment on column elius.reservas.inicio is 'Inicio';
comment on column elius.reservas.fin is 'Fin';
comment on column elius.reservas.personas is 'Número de personas';
comment on column elius.reservas.responsable_id is 'Quién la está gestionando';
comment on column elius.reservas.urgente is 'Marcada como urgente';
comment on column elius.reservas.visto is 'Ya la vio el equipo';
comment on column elius.reservas.llegada_en is 'Hora real de llegada';
comment on column elius.reservas.salida_en is 'Hora real de salida';
comment on column elius.reservas.novedades is 'Novedades de la visita';
comment on column elius.reservas.notas is 'Observaciones';
comment on column elius.reservas.creada_por_eli is 'La creó el agente';
comment on column elius.reservas.id_evento_calendario is 'Evento en Google Calendar';
comment on column elius.reservas.creado_en is 'Fecha de creación';
comment on column elius.reservas.actualizado_en is 'Fecha de la última modificación';
comment on table elius.asignaciones_recurso is 'Recursos ocupados por una reserva y en qué horario [transicion]';
comment on column elius.asignaciones_recurso.id is 'Identificador único';
comment on column elius.asignaciones_recurso.tenant_id is 'Tenant dueño del registro';
comment on column elius.asignaciones_recurso.reserva_id is 'Reserva';
comment on column elius.asignaciones_recurso.recurso_id is 'Recurso';
comment on column elius.asignaciones_recurso.inicio is 'Desde';
comment on column elius.asignaciones_recurso.fin is 'Hasta';
comment on column elius.asignaciones_recurso.estado is 'activa, liberada';
comment on column elius.asignaciones_recurso.notas is 'Ej. mesas unidas para grupo';
comment on column elius.asignaciones_recurso.creado_en is 'Fecha de creación';
comment on column elius.asignaciones_recurso.actualizado_en is 'Fecha de la última modificación';
comment on table elius.ordenes is 'Ventas: pedidos, compras de productos, tiquetes [entidad]';
comment on column elius.ordenes.id is 'Identificador único';
comment on column elius.ordenes.tenant_id is 'Tenant dueño del registro';
comment on column elius.ordenes.contacto_id is 'Cliente; vacío = venta de mostrador';
comment on column elius.ordenes.reserva_id is 'Reserva asociada';
comment on column elius.ordenes.conversacion_id is 'Conversación donde se tomó';
comment on column elius.ordenes.direccion_entrega_id is 'Para domicilios';
comment on column elius.ordenes.numero is 'Consecutivo por tenant';
comment on column elius.ordenes.canal_venta is 'presencial, whatsapp, web, app';
comment on column elius.ordenes.responsable_id is 'Quién la está gestionando';
comment on column elius.ordenes.tipo_entrega is 'sitio, recoger, domicilio, no_aplica';
comment on column elius.ordenes.estado is 'cotizando, esperando_pago, confirmada, en_preparacion, en_camino, entregada, cancelada';
comment on column elius.ordenes.urgente is 'Marcada como urgente';
comment on column elius.ordenes.visto is 'Ya la vio el equipo';
comment on column elius.ordenes.subtotal is 'Suma de líneas';
comment on column elius.ordenes.descuento is 'Descuentos';
comment on column elius.ordenes.impuestos is 'Impuestos';
comment on column elius.ordenes.total is 'Total calculado';
comment on column elius.ordenes.colocada_en is 'Hora del pedido';
comment on column elius.ordenes.creado_en is 'Fecha de creación';
comment on column elius.ordenes.actualizado_en is 'Fecha de la última modificación';
comment on table elius.orden_items is 'Líneas de una orden: qué ítems del catálogo y cuánto [transicion]';
comment on column elius.orden_items.id is 'Identificador único';
comment on column elius.orden_items.tenant_id is 'Tenant dueño del registro';
comment on column elius.orden_items.orden_id is 'Orden';
comment on column elius.orden_items.item_id is 'Ítem vendido';
comment on column elius.orden_items.cantidad is 'Cantidad';
comment on column elius.orden_items.precio_unitario is 'Precio al momento de la venta';
comment on column elius.orden_items.recargos is 'Recargos de opciones y adicionales (los suma el plugin)';
comment on column elius.orden_items.descuento is 'Descuento de la línea';
comment on column elius.orden_items.total_linea is 'Total de la línea';
comment on column elius.orden_items.notas is 'Ej. sin cebolla';
comment on column elius.orden_items.creado_en is 'Fecha de creación';
comment on column elius.orden_items.actualizado_en is 'Fecha de la última modificación';
comment on table elius.pagos is 'Pagos y reversos de una orden [entidad]';
comment on column elius.pagos.id is 'Identificador único';
comment on column elius.pagos.tenant_id is 'Tenant dueño del registro';
comment on column elius.pagos.orden_id is 'Orden';
comment on column elius.pagos.pago_original_id is 'Si es reverso, el pago que reversa';
comment on column elius.pagos.comprobante_id is 'Comprobante que lo respalda';
comment on column elius.pagos.recaudo_id is 'Recaudo de Factus Pay que lo respalda';
comment on column elius.pagos.metodo is 'efectivo, transferencia, breb_factus, nequi, daviplata, tarjeta, link';
comment on column elius.pagos.proveedor is 'Pasarela';
comment on column elius.pagos.referencia_externa is 'Id en la pasarela';
comment on column elius.pagos.monto is 'Monto (negativo en reversos)';
comment on column elius.pagos.estado is 'pendiente, aprobado, rechazado';
comment on column elius.pagos.pagado_en is 'Fecha del pago';
comment on column elius.pagos.creado_en is 'Fecha de creación';
comment on column elius.pagos.actualizado_en is 'Fecha de la última modificación';
comment on table elius.comprobantes_pago is 'Comprobantes de pago que el cliente envía por WhatsApp y Eli lee [entidad]';
comment on column elius.comprobantes_pago.id is 'Identificador único';
comment on column elius.comprobantes_pago.tenant_id is 'Tenant dueño del registro';
comment on column elius.comprobantes_pago.orden_id is 'Orden que paga, si ya se identificó';
comment on column elius.comprobantes_pago.conversacion_id is 'Conversación donde llegó';
comment on column elius.comprobantes_pago.decidido_por is 'Quién aprobó o rechazó';
comment on column elius.comprobantes_pago.monto_leido is 'Monto que Eli leyó en la imagen';
comment on column elius.comprobantes_pago.monto_esperado is 'Monto que debía pagar';
comment on column elius.comprobantes_pago.coincide is 'El monto leído coincide con el esperado';
comment on column elius.comprobantes_pago.remitente is 'Quién envía el dinero [PERSONAL]';
comment on column elius.comprobantes_pago.destinatario is 'A quién llegó el dinero';
comment on column elius.comprobantes_pago.app_origen is 'Nequi, Daviplata, Bancolombia, Bre-B…';
comment on column elius.comprobantes_pago.referencia is 'Número de la transacción';
comment on column elius.comprobantes_pago.fecha_texto is 'Fecha y hora como aparece en el comprobante';
comment on column elius.comprobantes_pago.hash_archivo is 'Huella del archivo para detectar repetidos';
comment on column elius.comprobantes_pago.url_archivo is 'Imagen en Supabase Storage';
comment on column elius.comprobantes_pago.media_id is 'Id del archivo en WhatsApp';
comment on column elius.comprobantes_pago.veredicto is 'pendiente, aprobado, rechazado';
comment on column elius.comprobantes_pago.motivo is 'Razón del veredicto o de la alerta';
comment on column elius.comprobantes_pago.decidido_en is 'Cuándo se decidió';
comment on column elius.comprobantes_pago.creado_en is 'Fecha de creación';
comment on column elius.comprobantes_pago.actualizado_en is 'Fecha de la última modificación';
comment on table elius.pasarelas_pago is 'Pasarelas de pago del negocio (Factus Pay con llave Bre-B) y su configuración [entidad]';
comment on column elius.pasarelas_pago.id is 'Identificador único';
comment on column elius.pasarelas_pago.tenant_id is 'Tenant dueño del registro';
comment on column elius.pasarelas_pago.proveedor is 'factus_pay';
comment on column elius.pasarelas_pago.ambiente is 'sandbox o produccion';
comment on column elius.pasarelas_pago.email_cuenta is 'Usuario de la cuenta en Factus Pay';
comment on column elius.pasarelas_pago.referencia_credenciales is 'Contraseña y token guardados en Supabase Vault';
comment on column elius.pasarelas_pago.referencia_clave_webhook is 'Clave secreta del webhook (?key=) en Supabase Vault';
comment on column elius.pasarelas_pago.monto_minimo is 'Factus: 1.000 COP';
comment on column elius.pasarelas_pago.monto_maximo is 'Factus: 12.100.000 COP';
comment on column elius.pasarelas_pago.expiracion_segundos is 'Vigencia del QR y la llave; Factus por defecto 86.400 (24 h)';
comment on column elius.pasarelas_pago.activa is 'Si está activa se cobra por llave; si no, por comprobante';
comment on column elius.pasarelas_pago.creado_en is 'Fecha de creación';
comment on column elius.pasarelas_pago.actualizado_en is 'Fecha de la última modificación';
comment on table elius.recaudos is 'Cobros creados en la pasarela: llave Bre-B y QR por el monto exacto [entidad]';
comment on column elius.recaudos.id is 'Identificador único';
comment on column elius.recaudos.tenant_id is 'Tenant dueño del registro';
comment on column elius.recaudos.orden_id is 'Orden que se cobra';
comment on column elius.recaudos.pasarela_id is 'Pasarela usada';
comment on column elius.recaudos.codigo_referencia is 'reference_code enviado a Factus (único por empresa)';
comment on column elius.recaudos.monto is 'Monto exacto: Factus no acepta parciales ni montos distintos';
comment on column elius.recaudos.llave_breb is 'breb_key que Eli envía al cliente';
comment on column elius.recaudos.url_qr is 'Imagen del QR en Supabase Storage';
comment on column elius.recaudos.expira_en is 'qr_expires_at';
comment on column elius.recaudos.estado is 'listo, pagado, vencido, anulado';
comment on column elius.recaudos.cobrado_en is 'collected_at';
comment on column elius.recaudos.pagador_nombre is 'payer.name del webhook [PERSONAL]';
comment on column elius.recaudos.pagador_documento is 'payer.document_type y document_number [PERSONAL]';
comment on column elius.recaudos.confirmado_por_api is 'Se verificó con GET /v1/collections/{reference}';
comment on column elius.recaudos.renovaciones is 'Veces que se renovó la expiración';
comment on column elius.recaudos.creado_en is 'Fecha de creación';
comment on column elius.recaudos.actualizado_en is 'Fecha de la última modificación';
comment on table elius.notificaciones_pasarela is 'Bandeja de webhooks recibidos de la pasarela (se guardan antes de responder 2xx) [entidad]';
comment on column elius.notificaciones_pasarela.id is 'Identificador único';
comment on column elius.notificaciones_pasarela.tenant_id is 'Tenant dueño del registro';
comment on column elius.notificaciones_pasarela.pasarela_id is 'Pasarela que envía';
comment on column elius.notificaciones_pasarela.recaudo_id is 'Recaudo identificado';
comment on column elius.notificaciones_pasarela.codigo_referencia is 'reference_code recibido';
comment on column elius.notificaciones_pasarela.carga is 'Cuerpo completo del webhook';
comment on column elius.notificaciones_pasarela.clave_valida is 'La clave ?key= coincidió (comparación de tiempo constante)';
comment on column elius.notificaciones_pasarela.recibida_en is 'Hora de llegada';
comment on column elius.notificaciones_pasarela.procesada_en is 'Cuándo se aplicó';
comment on column elius.notificaciones_pasarela.resultado is 'aplicado, duplicado, rechazado, sin_recaudo';
comment on column elius.notificaciones_pasarela.creado_en is 'Fecha de creación';
comment on column elius.notificaciones_pasarela.actualizado_en is 'Fecha de la última modificación';
comment on table elius.entregas is 'Domicilios: quién lleva la orden y cómo va [entidad]';
comment on column elius.entregas.id is 'Identificador único';
comment on column elius.entregas.tenant_id is 'Tenant dueño del registro';
comment on column elius.entregas.orden_id is 'Orden';
comment on column elius.entregas.repartidor_id is 'Domiciliario';
comment on column elius.entregas.estado is 'pendiente, en_camino, entregada, fallida';
comment on column elius.entregas.cobro_contra_entrega is 'Saldo que se cobra en efectivo al entregar';
comment on column elius.entregas.tomada_en is 'Cuándo la tomó el domiciliario';
comment on column elius.entregas.entregada_en is 'Cuándo se entregó';
comment on column elius.entregas.notas is 'Novedades de la entrega';
comment on column elius.entregas.creado_en is 'Fecha de creación';
comment on column elius.entregas.actualizado_en is 'Fecha de la última modificación';
comment on table elius.item_adicionales is 'Adicionales que se pueden sumar a cada producto o paquete [transicion]';
comment on column elius.item_adicionales.id is 'Identificador único';
comment on column elius.item_adicionales.tenant_id is 'Tenant dueño del registro';
comment on column elius.item_adicionales.item_id is 'Producto o paquete principal';
comment on column elius.item_adicionales.adicional_id is 'Ítem adicional (tipo adicional)';
comment on column elius.item_adicionales.precio_especial is 'Precio del adicional con este producto';
comment on column elius.item_adicionales.cantidad_maxima is 'Máximo que se puede agregar';
comment on column elius.item_adicionales.orden is 'Orden de presentación';
comment on column elius.item_adicionales.creado_en is 'Fecha de creación';
comment on column elius.item_adicionales.actualizado_en is 'Fecha de la última modificación';
comment on table elius.medios_item is 'Fotos y videos de cada ítem que Eli envía al cliente [entidad]';
comment on column elius.medios_item.id is 'Identificador único';
comment on column elius.medios_item.tenant_id is 'Tenant dueño del registro';
comment on column elius.medios_item.item_id is 'Ítem';
comment on column elius.medios_item.tipo_archivo is 'foto, video';
comment on column elius.medios_item.url is 'Archivo';
comment on column elius.medios_item.descripcion is 'Texto que acompaña el envío';
comment on column elius.medios_item.orden is 'Orden de envío';
comment on column elius.medios_item.activo is 'Se envía';
comment on column elius.medios_item.creado_en is 'Fecha de creación';
comment on column elius.medios_item.actualizado_en is 'Fecha de la última modificación';
comment on table elius.escalamientos is 'Casos que Eli pasa a una persona (pendientes) [entidad]';
comment on column elius.escalamientos.id is 'Identificador único';
comment on column elius.escalamientos.tenant_id is 'Tenant dueño del registro';
comment on column elius.escalamientos.conversacion_id is 'Conversación';
comment on column elius.escalamientos.asignado_a is 'Operador asignado por turnos';
comment on column elius.escalamientos.resuelto_por is 'Quién lo resolvió';
comment on column elius.escalamientos.motivo is 'Por qué Eli lo escaló';
comment on column elius.escalamientos.mensaje_cliente is 'Mensaje que lo disparó [PERSONAL]';
comment on column elius.escalamientos.resumen is 'Resumen de Eli para el humano';
comment on column elius.escalamientos.resuelto_en is 'Cuándo se resolvió';
comment on column elius.escalamientos.creado_en is 'Fecha de creación';
comment on column elius.escalamientos.actualizado_en is 'Fecha de la última modificación';
comment on table elius.eventos_embudo is 'Fases por las que pasa cada conversación (métricas de conversión) [entidad]';
comment on column elius.eventos_embudo.id is 'Identificador único';
comment on column elius.eventos_embudo.tenant_id is 'Tenant dueño del registro';
comment on column elius.eventos_embudo.conversacion_id is 'Conversación';
comment on column elius.eventos_embudo.fase is 'mensaje_recibido, cotizo, pedido_guardado, pago_enviado, escalado…';
comment on column elius.eventos_embudo.detalle is 'Datos de la fase';
comment on column elius.eventos_embudo.ocurrido_en is 'Cuándo';
comment on column elius.eventos_embudo.creado_en is 'Fecha de creación';
comment on column elius.eventos_embudo.actualizado_en is 'Fecha de la última modificación';
comment on table elius.errores_agente is 'Errores de Eli o de los flujos de n8n, para Soporte [entidad]';
comment on column elius.errores_agente.id is 'Identificador único';
comment on column elius.errores_agente.tenant_id is 'Tenant dueño del registro';
comment on column elius.errores_agente.conversacion_id is 'Conversación afectada';
comment on column elius.errores_agente.resuelto_por is 'Quién lo resolvió (Soporte)';
comment on column elius.errores_agente.origen is 'Nodo o paso donde ocurrió';
comment on column elius.errores_agente.mensaje is 'Mensaje de error';
comment on column elius.errores_agente.detalle is 'Datos técnicos';
comment on column elius.errores_agente.resuelto_en is 'Cuándo se resolvió';
comment on column elius.errores_agente.notas is 'Notas de Soporte';
comment on column elius.errores_agente.creado_en is 'Fecha de creación';
comment on column elius.errores_agente.actualizado_en is 'Fecha de la última modificación';
comment on table elius.parametros_negocio is 'Reglas configurables del negocio (umbral de grupo, tolerancia, cuentas de pago…) [entidad]';
comment on column elius.parametros_negocio.id is 'Identificador único';
comment on column elius.parametros_negocio.tenant_id is 'Tenant dueño del registro';
comment on column elius.parametros_negocio.clave is 'Ej. umbral_grupo_grande, tolerancia_minutos_llegada';
comment on column elius.parametros_negocio.valor is 'Valor actual';
comment on column elius.parametros_negocio.tipo_dato is 'numero, texto, booleano, porcentaje';
comment on column elius.parametros_negocio.descripcion is 'Qué controla, en palabras del dueño';
comment on column elius.parametros_negocio.creado_en is 'Fecha de creación';
comment on column elius.parametros_negocio.actualizado_en is 'Fecha de la última modificación';
comment on table elius.suscripciones_push is 'Dispositivos que reciben notificaciones push [entidad]';
comment on column elius.suscripciones_push.id is 'Identificador único';
comment on column elius.suscripciones_push.tenant_id is 'Tenant dueño del registro';
comment on column elius.suscripciones_push.membresia_id is 'Usuario que las recibe';
comment on column elius.suscripciones_push.endpoint is 'Endpoint del navegador';
comment on column elius.suscripciones_push.p256dh is 'Llave pública del navegador';
comment on column elius.suscripciones_push.auth is 'Secreto de autenticación del navegador';
comment on column elius.suscripciones_push.dispositivo is 'Celular, computador…';
comment on column elius.suscripciones_push.activa is 'Recibe notificaciones';
comment on column elius.suscripciones_push.creado_en is 'Fecha de creación';
comment on column elius.suscripciones_push.actualizado_en is 'Fecha de la última modificación';
comment on table elius.documentos_conocimiento is 'Documentos que Eli usa para responder (RAG) [entidad]';
comment on column elius.documentos_conocimiento.id is 'Identificador único';
comment on column elius.documentos_conocimiento.tenant_id is 'Tenant dueño del registro';
comment on column elius.documentos_conocimiento.titulo is 'Título';
comment on column elius.documentos_conocimiento.tipo_fuente is 'archivo, url, faq, manual';
comment on column elius.documentos_conocimiento.url_fuente is 'Origen';
comment on column elius.documentos_conocimiento.ruta_archivo is 'Ruta en Supabase Storage';
comment on column elius.documentos_conocimiento.estado is 'procesando, listo, error';
comment on column elius.documentos_conocimiento.creado_en is 'Fecha de creación';
comment on column elius.documentos_conocimiento.actualizado_en is 'Fecha de la última modificación';
comment on table elius.fragmentos_conocimiento is 'Fragmentos de los documentos con su embedding [entidad]';
comment on column elius.fragmentos_conocimiento.id is 'Identificador único';
comment on column elius.fragmentos_conocimiento.tenant_id is 'Tenant dueño del registro';
comment on column elius.fragmentos_conocimiento.documento_id is 'Documento';
comment on column elius.fragmentos_conocimiento.orden is 'Posición en el documento';
comment on column elius.fragmentos_conocimiento.contenido is 'Texto del fragmento';
comment on column elius.fragmentos_conocimiento.tokens is 'Tamaño en tokens';
comment on column elius.fragmentos_conocimiento.embedding is 'Vector para búsqueda semántica';
comment on column elius.fragmentos_conocimiento.creado_en is 'Fecha de creación';
comment on column elius.fragmentos_conocimiento.actualizado_en is 'Fecha de la última modificación';
comment on table elius.eventos_salida is 'Eventos para n8n: reserva creada, vuelo cancelado… [entidad]';
comment on column elius.eventos_salida.id is 'Identificador único';
comment on column elius.eventos_salida.tenant_id is 'Tenant dueño del registro';
comment on column elius.eventos_salida.tipo_evento is 'Ej. reserva.creada';
comment on column elius.eventos_salida.entidad is 'Tabla de origen';
comment on column elius.eventos_salida.entidad_id is 'Fila de origen';
comment on column elius.eventos_salida.carga is 'Datos del evento';
comment on column elius.eventos_salida.estado is 'pendiente, enviado, fallido';
comment on column elius.eventos_salida.intentos is 'Reintentos';
comment on column elius.eventos_salida.procesado_en is 'Cuándo se envió';
comment on column elius.eventos_salida.creado_en is 'Fecha de creación';
comment on column elius.eventos_salida.actualizado_en is 'Fecha de la última modificación';
comment on table ext.instalaciones_extension is 'Extensión instalada por un usuario del tenant [entidad]';
comment on column ext.instalaciones_extension.id is 'Identificador único';
comment on column ext.instalaciones_extension.tenant_id is 'Tenant dueño del registro';
comment on column ext.instalaciones_extension.membresia_id is 'Usuario en el tenant';
comment on column ext.instalaciones_extension.navegador is 'Chrome, Edge…';
comment on column ext.instalaciones_extension.version_extension is 'Versión';
comment on column ext.instalaciones_extension.ultimo_uso_en is 'Última actividad';
comment on column ext.instalaciones_extension.activa is 'En uso';
comment on column ext.instalaciones_extension.creado_en is 'Fecha de creación';
comment on column ext.instalaciones_extension.actualizado_en is 'Fecha de la última modificación';
comment on table ext.sitios_autorizados is 'Sitios donde el tenant permite capturar (RN-E03) [entidad]';
comment on column ext.sitios_autorizados.id is 'Identificador único';
comment on column ext.sitios_autorizados.tenant_id is 'Tenant dueño del registro';
comment on column ext.sitios_autorizados.autorizado_por is 'Administrador';
comment on column ext.sitios_autorizados.dominio is 'Ej. web.whatsapp.com';
comment on column ext.sitios_autorizados.nombre is 'Nombre visible';
comment on column ext.sitios_autorizados.activo is 'Vigente';
comment on column ext.sitios_autorizados.creado_en is 'Fecha de creación';
comment on column ext.sitios_autorizados.actualizado_en is 'Fecha de la última modificación';
comment on table ext.conversaciones_capturadas is 'Conversaciones capturadas desde el navegador [entidad]';
comment on column ext.conversaciones_capturadas.id is 'Identificador único';
comment on column ext.conversaciones_capturadas.tenant_id is 'Tenant dueño del registro';
comment on column ext.conversaciones_capturadas.instalacion_id is 'Quién la capturó';
comment on column ext.conversaciones_capturadas.sitio_id is 'Dónde';
comment on column ext.conversaciones_capturadas.contacto_id is 'Contacto reconocido';
comment on column ext.conversaciones_capturadas.id_hilo_externo is 'Id del chat en el sitio';
comment on column ext.conversaciones_capturadas.titulo is 'Título del hilo';
comment on column ext.conversaciones_capturadas.capturada_en is 'Fecha de captura';
comment on column ext.conversaciones_capturadas.creado_en is 'Fecha de creación';
comment on column ext.conversaciones_capturadas.actualizado_en is 'Fecha de la última modificación';
comment on table ext.mensajes_capturados is 'Mensajes de una conversación capturada [entidad]';
comment on column ext.mensajes_capturados.id is 'Identificador único';
comment on column ext.mensajes_capturados.tenant_id is 'Tenant dueño del registro';
comment on column ext.mensajes_capturados.conversacion_id is 'Conversación';
comment on column ext.mensajes_capturados.autor_rol is 'cliente, agente, desconocido';
comment on column ext.mensajes_capturados.autor_nombre is 'Nombre del autor [PERSONAL]';
comment on column ext.mensajes_capturados.contenido is 'Texto [PERSONAL]';
comment on column ext.mensajes_capturados.enviado_en is 'Hora del mensaje';
comment on column ext.mensajes_capturados.embedding is 'Vector para detectar patrones';
comment on column ext.mensajes_capturados.creado_en is 'Fecha de creación';
comment on column ext.mensajes_capturados.actualizado_en is 'Fecha de la última modificación';
comment on table ext.patrones is 'Patrones detectados: preguntas frecuentes, objeciones, intenciones [entidad]';
comment on column ext.patrones.id is 'Identificador único';
comment on column ext.patrones.tenant_id is 'Tenant dueño del registro';
comment on column ext.patrones.aprobado_por is 'Quién lo aprobó';
comment on column ext.patrones.tipo is 'faq, objecion, intencion, plantilla';
comment on column ext.patrones.nombre is 'Nombre';
comment on column ext.patrones.descripcion is 'Descripción';
comment on column ext.patrones.respuesta_sugerida is 'Respuesta para Eli';
comment on column ext.patrones.frecuencia is 'Veces observado';
comment on column ext.patrones.confianza is '0 a 1';
comment on column ext.patrones.estado is 'sugerido, aprobado, rechazado';
comment on column ext.patrones.embedding is 'Vector del patrón';
comment on column ext.patrones.creado_en is 'Fecha de creación';
comment on column ext.patrones.actualizado_en is 'Fecha de la última modificación';
comment on table ext.evidencias_patron is 'Mensajes que respaldan cada patrón [transicion]';
comment on column ext.evidencias_patron.id is 'Identificador único';
comment on column ext.evidencias_patron.tenant_id is 'Tenant dueño del registro';
comment on column ext.evidencias_patron.patron_id is 'Patrón';
comment on column ext.evidencias_patron.mensaje_id is 'Mensaje';
comment on column ext.evidencias_patron.relevancia is 'Qué tanto lo respalda, 0 a 1';
comment on column ext.evidencias_patron.fragmento is 'Parte del mensaje que lo evidencia';
comment on column ext.evidencias_patron.detectado_en is 'Cuándo se asoció';
comment on column ext.evidencias_patron.creado_en is 'Fecha de creación';
comment on column ext.evidencias_patron.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_vet.mascotas is 'Pacientes de la clínica [entidad]';
comment on column plugin_vet.mascotas.id is 'Identificador único';
comment on column plugin_vet.mascotas.tenant_id is 'Tenant dueño del registro';
comment on column plugin_vet.mascotas.nombre is 'Nombre';
comment on column plugin_vet.mascotas.especie is 'perro, gato, ave, exótico, otro';
comment on column plugin_vet.mascotas.raza is 'Raza';
comment on column plugin_vet.mascotas.sexo is 'macho, hembra';
comment on column plugin_vet.mascotas.fecha_nacimiento is 'Nacimiento aproximado';
comment on column plugin_vet.mascotas.peso_kg is 'Último peso';
comment on column plugin_vet.mascotas.microchip is 'Número de microchip';
comment on column plugin_vet.mascotas.esterilizada is 'Esterilizada';
comment on column plugin_vet.mascotas.alergias is 'Alergias conocidas [RESTRINGIDO]';
comment on column plugin_vet.mascotas.fallecida_en is 'Fecha de fallecimiento';
comment on column plugin_vet.mascotas.creado_en is 'Fecha de creación';
comment on column plugin_vet.mascotas.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_vet.propietarios_mascota is 'Personas responsables de cada mascota [transicion]';
comment on column plugin_vet.propietarios_mascota.id is 'Identificador único';
comment on column plugin_vet.propietarios_mascota.tenant_id is 'Tenant dueño del registro';
comment on column plugin_vet.propietarios_mascota.contacto_id is 'Propietario';
comment on column plugin_vet.propietarios_mascota.mascota_id is 'Mascota';
comment on column plugin_vet.propietarios_mascota.tipo is 'principal, secundario';
comment on column plugin_vet.propietarios_mascota.puede_autorizar is 'Puede autorizar procedimientos';
comment on column plugin_vet.propietarios_mascota.desde is 'Desde cuándo es responsable';
comment on column plugin_vet.propietarios_mascota.creado_en is 'Fecha de creación';
comment on column plugin_vet.propietarios_mascota.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_vet.atenciones is 'Atención de una mascota dentro de una cita [transicion]';
comment on column plugin_vet.atenciones.id is 'Identificador único';
comment on column plugin_vet.atenciones.tenant_id is 'Tenant dueño del registro';
comment on column plugin_vet.atenciones.reserva_id is 'Cita';
comment on column plugin_vet.atenciones.mascota_id is 'Mascota atendida';
comment on column plugin_vet.atenciones.servicio_id is 'Servicio del catálogo';
comment on column plugin_vet.atenciones.profesional_id is 'Veterinario que atiende';
comment on column plugin_vet.atenciones.motivo is 'Motivo de consulta';
comment on column plugin_vet.atenciones.estado is 'programada, en_curso, finalizada';
comment on column plugin_vet.atenciones.peso_kg is 'Peso en la atención';
comment on column plugin_vet.atenciones.temperatura_c is 'Temperatura [RESTRINGIDO]';
comment on column plugin_vet.atenciones.creado_en is 'Fecha de creación';
comment on column plugin_vet.atenciones.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_vet.registros_clinicos is 'Historia clínica: anotaciones de cada atención [entidad]';
comment on column plugin_vet.registros_clinicos.id is 'Identificador único';
comment on column plugin_vet.registros_clinicos.tenant_id is 'Tenant dueño del registro';
comment on column plugin_vet.registros_clinicos.atencion_id is 'Atención';
comment on column plugin_vet.registros_clinicos.autor_id is 'Veterinario';
comment on column plugin_vet.registros_clinicos.corrige_a is 'Registro que corrige (RN-V04)';
comment on column plugin_vet.registros_clinicos.tipo is 'anamnesis, examen, diagnostico, tratamiento, correccion';
comment on column plugin_vet.registros_clinicos.contenido is 'Texto clínico [RESTRINGIDO]';
comment on column plugin_vet.registros_clinicos.registrado_en is 'Fecha del registro';
comment on column plugin_vet.registros_clinicos.creado_en is 'Fecha de creación';
comment on column plugin_vet.registros_clinicos.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_vet.aplicaciones_vacuna is 'Vacunas aplicadas a cada mascota [transicion]';
comment on column plugin_vet.aplicaciones_vacuna.id is 'Identificador único';
comment on column plugin_vet.aplicaciones_vacuna.tenant_id is 'Tenant dueño del registro';
comment on column plugin_vet.aplicaciones_vacuna.mascota_id is 'Mascota';
comment on column plugin_vet.aplicaciones_vacuna.vacuna_id is 'Vacuna del catálogo';
comment on column plugin_vet.aplicaciones_vacuna.atencion_id is 'Atención en que se aplicó';
comment on column plugin_vet.aplicaciones_vacuna.aplicada_por is 'Quién la aplicó';
comment on column plugin_vet.aplicaciones_vacuna.lote is 'Lote del biológico';
comment on column plugin_vet.aplicaciones_vacuna.aplicada_en is 'Fecha de aplicación';
comment on column plugin_vet.aplicaciones_vacuna.proxima_dosis_en is 'Próxima dosis (RN-V05)';
comment on column plugin_vet.aplicaciones_vacuna.creado_en is 'Fecha de creación';
comment on column plugin_vet.aplicaciones_vacuna.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.alergenos is 'Alérgenos que el restaurante informa [entidad]';
comment on column plugin_restaurant.alergenos.id is 'Identificador único';
comment on column plugin_restaurant.alergenos.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.alergenos.nombre is 'Ej. maní, gluten, lácteos';
comment on column plugin_restaurant.alergenos.descripcion is 'Descripción';
comment on column plugin_restaurant.alergenos.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.alergenos.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.item_alergenos is 'Alérgenos de cada plato [transicion]';
comment on column plugin_restaurant.item_alergenos.id is 'Identificador único';
comment on column plugin_restaurant.item_alergenos.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.item_alergenos.item_id is 'Plato';
comment on column plugin_restaurant.item_alergenos.alergeno_id is 'Alérgeno';
comment on column plugin_restaurant.item_alergenos.nivel is 'contiene, trazas';
comment on column plugin_restaurant.item_alergenos.nota is 'Aclaración';
comment on column plugin_restaurant.item_alergenos.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.item_alergenos.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.grupos_modificador is 'Grupos de opciones: término de la carne, acompañante… [entidad]';
comment on column plugin_restaurant.grupos_modificador.id is 'Identificador único';
comment on column plugin_restaurant.grupos_modificador.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.grupos_modificador.nombre is 'Nombre';
comment on column plugin_restaurant.grupos_modificador.descripcion is 'Descripción';
comment on column plugin_restaurant.grupos_modificador.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.grupos_modificador.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.opciones_modificador is 'Opciones de un grupo: término medio, papas… [entidad]';
comment on column plugin_restaurant.opciones_modificador.id is 'Identificador único';
comment on column plugin_restaurant.opciones_modificador.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.opciones_modificador.grupo_id is 'Grupo';
comment on column plugin_restaurant.opciones_modificador.nombre is 'Nombre';
comment on column plugin_restaurant.opciones_modificador.precio_adicional is 'Recargo';
comment on column plugin_restaurant.opciones_modificador.disponible is 'false = agotado';
comment on column plugin_restaurant.opciones_modificador.orden is 'Orden de presentación';
comment on column plugin_restaurant.opciones_modificador.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.opciones_modificador.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.item_grupos_modificador is 'Qué grupos de opciones aplica cada plato [transicion]';
comment on column plugin_restaurant.item_grupos_modificador.id is 'Identificador único';
comment on column plugin_restaurant.item_grupos_modificador.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.item_grupos_modificador.item_id is 'Plato';
comment on column plugin_restaurant.item_grupos_modificador.grupo_id is 'Grupo';
comment on column plugin_restaurant.item_grupos_modificador.minimo is 'Mínimo de opciones (RN-R04)';
comment on column plugin_restaurant.item_grupos_modificador.maximo is 'Máximo de opciones (RN-R04)';
comment on column plugin_restaurant.item_grupos_modificador.orden is 'Orden en pantalla';
comment on column plugin_restaurant.item_grupos_modificador.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.item_grupos_modificador.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.orden_item_opciones is 'Opciones elegidas en cada línea del pedido [transicion]';
comment on column plugin_restaurant.orden_item_opciones.id is 'Identificador único';
comment on column plugin_restaurant.orden_item_opciones.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.orden_item_opciones.orden_item_id is 'Línea del pedido';
comment on column plugin_restaurant.orden_item_opciones.opcion_id is 'Opción';
comment on column plugin_restaurant.orden_item_opciones.cantidad is 'Cantidad';
comment on column plugin_restaurant.orden_item_opciones.precio_aplicado is 'Recargo cobrado';
comment on column plugin_restaurant.orden_item_opciones.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.orden_item_opciones.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.estaciones_cocina is 'Estaciones de producción: parrilla, bar, fríos [entidad]';
comment on column plugin_restaurant.estaciones_cocina.id is 'Identificador único';
comment on column plugin_restaurant.estaciones_cocina.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.estaciones_cocina.nombre is 'Nombre';
comment on column plugin_restaurant.estaciones_cocina.tiempo_objetivo_min is 'Tiempo objetivo de preparación';
comment on column plugin_restaurant.estaciones_cocina.activa is 'En uso';
comment on column plugin_restaurant.estaciones_cocina.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.estaciones_cocina.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.comandas is 'Envíos de un pedido a cocina, por estación y por ronda [entidad]';
comment on column plugin_restaurant.comandas.id is 'Identificador único';
comment on column plugin_restaurant.comandas.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.comandas.orden_id is 'Pedido';
comment on column plugin_restaurant.comandas.estacion_id is 'Estación';
comment on column plugin_restaurant.comandas.ronda is '1, 2, 3… en la misma mesa';
comment on column plugin_restaurant.comandas.estado is 'recibida, en_preparacion, lista, entregada';
comment on column plugin_restaurant.comandas.enviada_en is 'Cuándo se envió';
comment on column plugin_restaurant.comandas.lista_en is 'Cuándo quedó lista';
comment on column plugin_restaurant.comandas.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.comandas.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.comanda_items is 'Qué líneas del pedido van en cada comanda [transicion]';
comment on column plugin_restaurant.comanda_items.id is 'Identificador único';
comment on column plugin_restaurant.comanda_items.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.comanda_items.comanda_id is 'Comanda';
comment on column plugin_restaurant.comanda_items.orden_item_id is 'Línea del pedido';
comment on column plugin_restaurant.comanda_items.cantidad is 'Cantidad enviada en esta comanda';
comment on column plugin_restaurant.comanda_items.estado is 'pendiente, preparando, listo';
comment on column plugin_restaurant.comanda_items.nota_cocina is 'Indicación para cocina';
comment on column plugin_restaurant.comanda_items.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.comanda_items.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.menus_dia is 'Menú del día: uno por fecha, confirmado por el dueño [entidad]';
comment on column plugin_restaurant.menus_dia.id is 'Identificador único';
comment on column plugin_restaurant.menus_dia.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.menus_dia.confirmado_por is 'Quién lo confirmó';
comment on column plugin_restaurant.menus_dia.fecha is 'Día del menú';
comment on column plugin_restaurant.menus_dia.precio_base is 'Precio del menú';
comment on column plugin_restaurant.menus_dia.url_foto is 'Foto del menú que Eli envía';
comment on column plugin_restaurant.menus_dia.confirmado_en is 'Eli solo lo ofrece si está confirmado';
comment on column plugin_restaurant.menus_dia.activo is 'Disponible ese día';
comment on column plugin_restaurant.menus_dia.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.menus_dia.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.menu_dia_items is 'Platos que componen el menú de cada día [transicion]';
comment on column plugin_restaurant.menu_dia_items.id is 'Identificador único';
comment on column plugin_restaurant.menu_dia_items.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.menu_dia_items.menu_id is 'Menú del día';
comment on column plugin_restaurant.menu_dia_items.item_id is 'Plato';
comment on column plugin_restaurant.menu_dia_items.seccion is 'entrada, principal, bebida, postre';
comment on column plugin_restaurant.menu_dia_items.posicion is 'Posición en la sección (Eli lee en este orden)';
comment on column plugin_restaurant.menu_dia_items.disponible is 'false = se acabó hoy';
comment on column plugin_restaurant.menu_dia_items.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.menu_dia_items.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_restaurant.celebraciones is 'Celebraciones dentro de una reserva (cumpleaños, aniversarios) [entidad]';
comment on column plugin_restaurant.celebraciones.id is 'Identificador único';
comment on column plugin_restaurant.celebraciones.tenant_id is 'Tenant dueño del registro';
comment on column plugin_restaurant.celebraciones.reserva_id is 'Reserva';
comment on column plugin_restaurant.celebraciones.tipo_celebracion is 'cumpleaños, aniversario, grado…';
comment on column plugin_restaurant.celebraciones.festejado is 'Nombre del festejado [PERSONAL]';
comment on column plugin_restaurant.celebraciones.decoracion is 'Decoración solicitada';
comment on column plugin_restaurant.celebraciones.notas is 'Indicaciones';
comment on column plugin_restaurant.celebraciones.creado_en is 'Fecha de creación';
comment on column plugin_restaurant.celebraciones.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.aeropuertos is 'Aeropuertos con código IATA, comunes a todos los tenants [referencia]';
comment on column plugin_airline.aeropuertos.id is 'Identificador único';
comment on column plugin_airline.aeropuertos.codigo_iata is 'Ej. BOG';
comment on column plugin_airline.aeropuertos.nombre is 'Nombre';
comment on column plugin_airline.aeropuertos.ciudad is 'Ciudad';
comment on column plugin_airline.aeropuertos.pais is 'País ISO 3166';
comment on column plugin_airline.aeropuertos.zona_horaria is 'Zona horaria';
comment on column plugin_airline.aeropuertos.creado_en is 'Fecha de creación';
comment on column plugin_airline.aeropuertos.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.aeronaves is 'Flota de la aerolínea [entidad]';
comment on column plugin_airline.aeronaves.id is 'Identificador único';
comment on column plugin_airline.aeronaves.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.aeronaves.matricula is 'Matrícula';
comment on column plugin_airline.aeronaves.modelo is 'Ej. A320';
comment on column plugin_airline.aeronaves.capacidad is 'Sillas totales (RN-A04)';
comment on column plugin_airline.aeronaves.mapa_sillas is 'Distribución de sillas';
comment on column plugin_airline.aeronaves.activa is 'En servicio';
comment on column plugin_airline.aeronaves.creado_en is 'Fecha de creación';
comment on column plugin_airline.aeronaves.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.rutas is 'Rutas entre dos aeropuertos [transicion]';
comment on column plugin_airline.rutas.id is 'Identificador único';
comment on column plugin_airline.rutas.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.rutas.origen_id is 'Aeropuerto de origen';
comment on column plugin_airline.rutas.destino_id is 'Aeropuerto de destino (RN-A02)';
comment on column plugin_airline.rutas.distancia_km is 'Distancia';
comment on column plugin_airline.rutas.duracion_min is 'Duración estimada';
comment on column plugin_airline.rutas.activa is 'En operación';
comment on column plugin_airline.rutas.creado_en is 'Fecha de creación';
comment on column plugin_airline.rutas.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.vuelos is 'Vuelos programados [entidad]';
comment on column plugin_airline.vuelos.id is 'Identificador único';
comment on column plugin_airline.vuelos.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.vuelos.ruta_id is 'Ruta';
comment on column plugin_airline.vuelos.aeronave_id is 'Aeronave';
comment on column plugin_airline.vuelos.numero_vuelo is 'Ej. EL123';
comment on column plugin_airline.vuelos.salida_programada is 'Salida';
comment on column plugin_airline.vuelos.llegada_programada is 'Llegada (RN-A03)';
comment on column plugin_airline.vuelos.estado is 'programado, abordando, salio, llego, retrasado, cancelado';
comment on column plugin_airline.vuelos.puerta is 'Puerta';
comment on column plugin_airline.vuelos.creado_en is 'Fecha de creación';
comment on column plugin_airline.vuelos.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.tarifas_vuelo is 'Precio y cupos de cada tarifa del catálogo en cada vuelo [transicion]';
comment on column plugin_airline.tarifas_vuelo.id is 'Identificador único';
comment on column plugin_airline.tarifas_vuelo.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.tarifas_vuelo.vuelo_id is 'Vuelo';
comment on column plugin_airline.tarifas_vuelo.tarifa_id is 'Tarifa (ítem del catálogo)';
comment on column plugin_airline.tarifas_vuelo.precio is 'Precio en este vuelo';
comment on column plugin_airline.tarifas_vuelo.cupos_totales is 'Cupos asignados';
comment on column plugin_airline.tarifas_vuelo.cupos_vendidos is 'Cupos vendidos';
comment on column plugin_airline.tarifas_vuelo.creado_en is 'Fecha de creación';
comment on column plugin_airline.tarifas_vuelo.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.reserva_pasajeros is 'Pasajeros de cada reserva aérea [transicion]';
comment on column plugin_airline.reserva_pasajeros.id is 'Identificador único';
comment on column plugin_airline.reserva_pasajeros.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.reserva_pasajeros.reserva_id is 'Reserva';
comment on column plugin_airline.reserva_pasajeros.contacto_id is 'Pasajero';
comment on column plugin_airline.reserva_pasajeros.tipo_pasajero is 'ADT adulto, CHD niño, INF infante (RN-A06)';
comment on column plugin_airline.reserva_pasajeros.necesidades_especiales is 'Asistencia o condición de salud [SENSIBLE]';
comment on column plugin_airline.reserva_pasajeros.creado_en is 'Fecha de creación';
comment on column plugin_airline.reserva_pasajeros.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.tramos_reserva is 'Vuelos que componen una reserva, en orden [transicion]';
comment on column plugin_airline.tramos_reserva.id is 'Identificador único';
comment on column plugin_airline.tramos_reserva.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.tramos_reserva.reserva_id is 'Reserva';
comment on column plugin_airline.tramos_reserva.tarifa_vuelo_id is 'Vuelo y tarifa';
comment on column plugin_airline.tramos_reserva.orden_tramo is '1 = ida, 2 = regreso…';
comment on column plugin_airline.tramos_reserva.estado is 'confirmado, cambiado, cancelado';
comment on column plugin_airline.tramos_reserva.creado_en is 'Fecha de creación';
comment on column plugin_airline.tramos_reserva.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.tiquetes is 'Tiquete de un pasajero en un tramo [transicion]';
comment on column plugin_airline.tiquetes.id is 'Identificador único';
comment on column plugin_airline.tiquetes.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.tiquetes.reserva_pasajero_id is 'Pasajero';
comment on column plugin_airline.tiquetes.tramo_id is 'Tramo';
comment on column plugin_airline.tiquetes.numero_tiquete is 'Número de tiquete';
comment on column plugin_airline.tiquetes.silla is 'Silla asignada (RN-A07)';
comment on column plugin_airline.tiquetes.estado is 'emitido, usado, anulado';
comment on column plugin_airline.tiquetes.checkin_en is 'Hora de check-in (RN-A08)';
comment on column plugin_airline.tiquetes.creado_en is 'Fecha de creación';
comment on column plugin_airline.tiquetes.actualizado_en is 'Fecha de la última modificación';
comment on table plugin_airline.equipajes is 'Equipaje registrado en un tiquete [entidad]';
comment on column plugin_airline.equipajes.id is 'Identificador único';
comment on column plugin_airline.equipajes.tenant_id is 'Tenant dueño del registro';
comment on column plugin_airline.equipajes.tiquete_id is 'Tiquete';
comment on column plugin_airline.equipajes.tipo is 'mano, bodega, especial';
comment on column plugin_airline.equipajes.peso_kg is 'Peso';
comment on column plugin_airline.equipajes.etiqueta is 'Número de etiqueta';
comment on column plugin_airline.equipajes.estado is 'registrado, cargado, entregado, perdido';
comment on column plugin_airline.equipajes.creado_en is 'Fecha de creación';
comment on column plugin_airline.equipajes.actualizado_en is 'Fecha de la última modificación';
