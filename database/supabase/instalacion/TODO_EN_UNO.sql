-- =============================================================================
-- ELIUS · Migración 0100 · Extensiones, esquemas, roles de base de datos y utilidades
-- Modelo multi-tenant POOL: una base, tablas compartidas, tenant_id + RLS.
-- =============================================================================
--
--   MODELO GENERAL                         PLUGINS (uno por vertical)
--   platform  lógica del tenant (SaaS)     plugin_vet         veterinaria
--   elius     núcleo de negocio            plugin_restaurant  restaurante
--   ext       extensión de Chrome          plugin_airline     aerolínea
--   audit     bitácora de cambios
--   app       funciones internas de seguridad (no se expone en la API)
--   reportes  vistas agregadas para el usuario de consulta (no se expone en la API)
-- =============================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto   with schema extensions;  -- digest(): huellas de comprobantes
create extension if not exists vector     with schema extensions;  -- pgvector: embeddings (DT-15)
create extension if not exists pg_trgm    with schema extensions;  -- búsqueda difusa de nombres
create extension if not exists btree_gist with schema extensions;  -- exclusión de reservas cruzadas (DT-08)
-- En Supabase el esquema extensions ya es utilizable por los roles de la API
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    grant usage on schema extensions to authenticated, service_role;
  end if;
end $$;

create schema if not exists platform;
create schema if not exists elius;
create schema if not exists ext;
create schema if not exists audit;
create schema if not exists app;
create schema if not exists reportes;
create schema if not exists plugin_vet;
create schema if not exists plugin_restaurant;
create schema if not exists plugin_airline;

comment on schema platform          is 'Modelo general · lógica del tenant: tenants, planes, membresías, roles, permisos, plugins';
comment on schema elius             is 'Modelo general · núcleo de negocio común a todas las verticales';
comment on schema ext               is 'Modelo general · extensión de Chrome';
comment on schema audit             is 'Modelo general · bitácora de cambios';
comment on schema app               is 'Funciones internas de seguridad multi-tenant (no expuesto)';
comment on schema reportes          is 'Vistas agregadas y anónimas para el usuario elius_consulta (no expuesto)';
comment on schema plugin_vet        is 'Plugin · veterinaria';
comment on schema plugin_restaurant is 'Plugin · restaurante';
comment on schema plugin_airline    is 'Plugin · aerolínea';

-- -----------------------------------------------------------------------------
-- Roles de conexión a PostgreSQL (DT-13). Ninguno es superusuario ni salta RLS.
-- Se crean sin LOGIN: la contraseña se asigna fuera del repositorio, por ejemplo
--   alter role elius_app login password '...';
-- Sus permisos (GRANT) están en la migración 0800.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'elius_admin') then
    create role elius_admin nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'elius_app') then
    create role elius_app nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'elius_consulta') then
    create role elius_consulta nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls;
  end if;
end $$;

comment on role elius_admin    is 'Administrador del esquema: crea y modifica objetos. No es superusuario.';
comment on role elius_app      is 'Backend de confianza con privilegios de lectura y escritura. Siempre sujeto a RLS.';
comment on role elius_consulta is 'Consulta: solo lee las vistas agregadas del esquema reportes.';
grant usage on schema extensions to elius_admin, elius_app;

-- -----------------------------------------------------------------------------
-- Utilidades genéricas
-- -----------------------------------------------------------------------------
create or replace function app.set_actualizado_en()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

create or replace function app.codigo_aleatorio(p_largo int default 6)
returns text language sql volatile set search_path = '' as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
  from generate_series(1, p_largo);
$$;

create or replace function app.es_uuid(p text)
returns boolean language sql immutable set search_path = '' as $$
  select p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
$$;

-- -----------------------------------------------------------------------------
-- app.current_tenant_id(): de qué tenant es la petición actual (DT-04).
--   1. Backend de confianza (service_role, elius_app) sin usuario: usa app.tenant_id
--      fijado con set_config. Así una Edge Function o un webhook trabaja en un solo tenant.
--   2. Usuario autenticado: encabezado X-Tenant-ID o claim tenant_id del JWT.
--      Solo se acepta si el usuario es miembro activo o Soporte autorizado.
-- Si no hay un tenant válido devuelve NULL y las políticas RLS no muestran nada.
-- Se define aquí (plpgsql) para poder usarlo como DEFAULT de tenant_id en las tablas.
-- -----------------------------------------------------------------------------
create or replace function app.current_tenant_id()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid    uuid  := auth.uid();
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_txt    text;
  v_hdr    text;
begin
  if v_uid is null then
    if v_claims ->> 'role' = 'service_role'
       or session_user in ('elius_app', 'elius_admin', 'postgres', 'supabase_admin') then
      v_txt := nullif(current_setting('app.tenant_id', true), '');
      return case when app.es_uuid(v_txt) then v_txt::uuid end;
    end if;
    return null;
  end if;

  v_hdr := nullif(current_setting('request.headers', true), '');
  if v_hdr is not null then
    v_txt := v_hdr::jsonb ->> 'x-tenant-id';
  end if;
  v_txt := coalesce(v_txt, v_claims ->> 'tenant_id');
  if not app.es_uuid(v_txt) then
    return null;
  end if;
  if app.tiene_acceso_tenant(v_uid, v_txt::uuid) then
    return v_txt::uuid;
  end if;
  return null;
end $$;

comment on function app.current_tenant_id() is
  'Tenant de la petición: JWT/X-Tenant-ID validado contra la membresía, o app.tenant_id para el backend de confianza';
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
-- =============================================================================
-- ELIUS · Migración 0300 · Restricciones de reglas de negocio
-- Reglas que se pueden expresar de forma declarativa (CHECK, UNIQUE, EXCLUDE).
-- Las que necesitan consultar otras tablas van como triggers en la 0500.
-- Cada restricción lleva el código de la regla que garantiza (sección 9 del levantamiento).
-- =============================================================================

-- ---------- platform ---------------------------------------------------------
alter table platform.tenants
  add constraint ck_tenants_slug_formato check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$');            -- RN-P05
alter table platform.planes
  add constraint ck_planes_limites check (max_usuarios > 0 and max_conversaciones_mes > 0 and max_tokens_mes > 0 and precio_mensual >= 0);
alter table platform.accesos_soporte
  add constraint ck_accesos_soporte_vigencia check (vence_en > inicio and vence_en <= inicio + interval '7 days'); -- RN-P16
alter table platform.asignaciones_plataforma
  add constraint ck_asignaciones_plataforma_vigencia check (hasta is null or hasta > desde);
alter table platform.invitaciones
  add constraint ck_invitaciones_email check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$');
-- Solo una membresía predeterminada por usuario (es el tenant que va en el JWT)
create unique index uq_membresias_predeterminada on platform.membresias (usuario_id) where es_predeterminada;
-- Una sola invitación pendiente por correo y tenant
create unique index uq_invitaciones_pendiente on platform.invitaciones (tenant_id, lower(email)) where aceptada_en is null;

-- ---------- elius: contactos y conversaciones --------------------------------
alter table elius.contactos
  add constraint ck_contactos_telefono_e164 check (telefono is null or telefono ~ '^\+[1-9][0-9]{6,14}$'),  -- RN-C02
  add constraint ck_contactos_email check (email is null or email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  add constraint ck_contactos_identificable check (telefono is not null or email is not null);              -- RN-C01
create index ix_contactos_nombre_trgm on elius.contactos using gin (nombres extensions.gin_trgm_ops);
-- Una sola conversación abierta por identidad y flujo
create unique index uq_conversaciones_abierta on elius.conversaciones (tenant_id, identidad_id, flujo) where estado <> 'cerrada';
create index ix_mensajes_conversacion_fecha on elius.mensajes (tenant_id, conversacion_id, enviado_en desc);
create index ix_mensajes_sin_procesar on elius.mensajes (tenant_id, conversacion_id) where not procesado;  -- RN-C21
alter table elius.agentes
  add constraint ck_agentes_temperatura check (temperatura between 0 and 2);
-- Solo un agente activo por tenant
create unique index uq_agentes_activo on elius.agentes (tenant_id) where activo;
alter table elius.consumos_llm
  add constraint ck_consumos_llm_positivos check (tokens_entrada >= 0 and tokens_salida >= 0 and tokens_cache >= 0 and costo_usd >= 0 and latencia_ms >= 0);

-- ---------- elius: catálogo ----------------------------------------------------
alter table elius.items_catalogo
  add constraint ck_items_precio check (precio >= 0),
  add constraint ck_items_impuesto check (impuesto_pct between 0 and 100),
  add constraint ck_items_duracion check (duracion_min is null or duracion_min > 0);
alter table elius.item_adicionales
  add constraint ck_item_adicionales_distintos check (item_id <> adicional_id),
  add constraint ck_item_adicionales_cantidad check (cantidad_maxima is null or cantidad_maxima > 0);
alter table elius.categorias_catalogo
  add constraint ck_categorias_horario check (disponible_desde is null or disponible_hasta is null or disponible_desde < disponible_hasta);

-- ---------- elius: reservas y recursos ------------------------------------------
alter table elius.recursos
  add constraint ck_recursos_capacidad check (capacidad > 0);
alter table elius.horarios_atencion
  add constraint ck_horarios_dia check (dia_semana between 1 and 7),
  add constraint ck_horarios_horas check (abre < cierra);
alter table elius.reservas
  add constraint ck_reservas_fin check (fin is null or fin > inicio),                                       -- RN-C08
  add constraint ck_reservas_personas check (personas > 0),
  add constraint ck_reservas_llegada check (salida_en is null or llegada_en is not null and salida_en >= llegada_en);
alter table elius.asignaciones_recurso
  add constraint ck_asignaciones_fin check (fin > inicio),
  -- RN-C07: un recurso no puede tener dos asignaciones activas que se crucen en el tiempo (DT-08)
  add constraint ex_asignaciones_sin_cruce exclude using gist (
    tenant_id with =, recurso_id with =, tstzrange(inicio, fin, '[)') with &&
  ) where (estado = 'activa');
create index ix_reservas_agenda on elius.reservas (tenant_id, inicio) where estado in ('pendiente_pago', 'confirmada');

-- ---------- elius: órdenes, pagos y cobros --------------------------------------
alter table elius.ordenes
  add constraint ck_ordenes_montos check (subtotal >= 0 and descuento >= 0 and impuestos >= 0 and total >= 0),
  -- RN-R05: un domicilio confirmado exige dirección
  add constraint ck_ordenes_domicilio_direccion check (
    tipo_entrega <> 'domicilio' or estado in ('cotizando', 'cancelada') or direccion_entrega_id is not null);
alter table elius.orden_items
  add constraint ck_orden_items_cantidad check (cantidad > 0),
  add constraint ck_orden_items_montos check (precio_unitario >= 0 and descuento >= 0 and total_linea >= 0);
alter table elius.pagos
  -- un reverso es negativo y apunta al pago original; un pago normal es positivo (RN-C12)
  add constraint ck_pagos_reverso check ((pago_original_id is null and monto > 0) or (pago_original_id is not null and monto < 0)),
  -- un pago con Factus siempre viene de un recaudo (RN-C22)
  add constraint ck_pagos_factus_recaudo check (metodo <> 'breb_factus' or recaudo_id is not null);
alter table elius.comprobantes_pago
  add constraint ck_comprobantes_decision check ((veredicto = 'pendiente') = (decidido_en is null));
-- RN-C16: el mismo archivo no se acepta dos veces en el mismo tenant
create index ix_comprobantes_hash on elius.comprobantes_pago (tenant_id, hash_archivo) where hash_archivo is not null;
create index ix_comprobantes_referencia on elius.comprobantes_pago (tenant_id, app_origen, referencia) where referencia is not null;
alter table elius.pasarelas_pago
  add constraint ck_pasarelas_montos check (monto_minimo >= 1000 and monto_maximo <= 12100000 and monto_minimo < monto_maximo), -- RN-C23
  add constraint ck_pasarelas_expiracion check (expiracion_segundos between 60 and 604800);
alter table elius.recaudos
  add constraint ck_recaudos_monto check (monto >= 1000 and monto <= 12100000),                               -- RN-C23
  add constraint ck_recaudos_referencia check (length(codigo_referencia) between 1 and 100),
  add constraint ck_recaudos_pagado check ((estado = 'pagado') = (cobrado_en is not null));
-- Un solo recaudo listo por orden a la vez
create unique index uq_recaudos_listo_por_orden on elius.recaudos (tenant_id, orden_id) where estado = 'listo';
create index ix_notificaciones_referencia on elius.notificaciones_pasarela (tenant_id, codigo_referencia);
alter table elius.entregas
  add constraint ck_entregas_cobro check (cobro_contra_entrega >= 0);

-- ---------- elius: conocimiento, eventos, parámetros -----------------------------
create index ix_fragmentos_embedding on elius.fragmentos_conocimiento
  using hnsw (embedding extensions.vector_cosine_ops);                                                       -- DT-15
create index ix_eventos_salida_pendientes on elius.eventos_salida (estado, creado_en) where estado = 'pendiente';
alter table elius.parametros_negocio
  add constraint ck_parametros_clave check (clave ~ '^[a-z][a-z0-9_]{2,62}$');
alter table elius.consentimientos
  add constraint ck_consentimientos_revocacion check (revocado_en is null or revocado_en >= aceptado_en);

-- ---------- ext ----------------------------------------------------------------
alter table ext.patrones
  add constraint ck_patrones_confianza check (confianza between 0 and 1),
  add constraint ck_patrones_aprobacion check (estado <> 'aprobado' or aprobado_por is not null);           -- RN-E02
alter table ext.evidencias_patron
  add constraint ck_evidencias_relevancia check (relevancia between 0 and 1);
alter table ext.sitios_autorizados
  add constraint ck_sitios_dominio check (dominio ~ '^[a-z0-9.-]+\.[a-z]{2,}$');

-- ---------- plugin_vet ------------------------------------------------------------
alter table plugin_vet.mascotas
  add constraint ck_mascotas_peso check (peso_kg is null or peso_kg > 0);
alter table plugin_vet.atenciones
  add constraint ck_atenciones_signos check ((peso_kg is null or peso_kg > 0) and (temperatura_c is null or temperatura_c between 30 and 45));
alter table plugin_vet.aplicaciones_vacuna
  add constraint ck_vacunas_proxima check (proxima_dosis_en is null or proxima_dosis_en > aplicada_en);
alter table plugin_vet.registros_clinicos
  add constraint ck_registros_correccion check ((tipo = 'correccion') = (corrige_a is not null));            -- RN-V04
-- Solo un propietario principal por mascota
create unique index uq_propietario_principal on plugin_vet.propietarios_mascota (mascota_id) where tipo = 'principal';

-- ---------- plugin_restaurant ---------------------------------------------------
alter table plugin_restaurant.item_grupos_modificador
  add constraint ck_modificador_rango check (minimo >= 0 and maximo >= 1 and minimo <= maximo);            -- RN-R04
alter table plugin_restaurant.opciones_modificador
  add constraint ck_opciones_precio check (precio_adicional >= 0);
alter table plugin_restaurant.comanda_items
  add constraint ck_comanda_items_cantidad check (cantidad > 0);
alter table plugin_restaurant.menus_dia
  add constraint ck_menus_dia_confirmacion check ((confirmado_en is null) = (confirmado_por is null));
create unique index uq_menu_dia_posicion on plugin_restaurant.menu_dia_items (menu_id, seccion, posicion);

-- ---------- plugin_airline --------------------------------------------------------
alter table plugin_airline.aeropuertos
  add constraint ck_aeropuertos_iata check (codigo_iata ~ '^[A-Z]{3}$');
alter table plugin_airline.rutas
  add constraint ck_rutas_distintas check (origen_id <> destino_id);                                          -- RN-A02
alter table plugin_airline.vuelos
  add constraint ck_vuelos_horario check (llegada_programada > salida_programada);                            -- RN-A03
alter table plugin_airline.aeronaves
  add constraint ck_aeronaves_capacidad check (capacidad > 0);
alter table plugin_airline.tarifas_vuelo
  add constraint ck_tarifas_cupos check (cupos_totales >= 0 and cupos_vendidos between 0 and cupos_totales);  -- RN-A04
alter table plugin_airline.equipajes
  add constraint ck_equipajes_peso check (peso_kg > 0 and peso_kg <= 100);
alter table plugin_airline.tiquetes
  add constraint ck_tiquetes_checkin check (estado <> 'usado' or checkin_en is not null);
create unique index uq_vuelos_numero_salida on plugin_airline.vuelos (tenant_id, numero_vuelo, salida_programada);
-- =============================================================================
-- ELIUS · Migración 0400 · Seguridad: tenant, permisos, JWT y RLS
-- DT-02 (RLS), DT-04 (JWT con tenant), DT-05 (roles generales), DT-06 (rendimiento)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. ¿El usuario puede entrar a este tenant?
--    Miembro activo de un tenant activo, o Soporte con autorización vigente (RN-P16).
-- -----------------------------------------------------------------------------
create or replace function app.soporte_autorizado(p_usuario uuid, p_tenant uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from platform.accesos_soporte a
    join platform.asignaciones_plataforma ap on ap.usuario_id = a.usuario_soporte_id
    join platform.roles r on r.id = ap.rol_id and r.codigo = 'soporte'
    where a.usuario_soporte_id = p_usuario and a.tenant_id = p_tenant
      and now() >= a.inicio and now() < a.vence_en and a.revocado_en is null
      and now() >= ap.desde and (ap.hasta is null or now() < ap.hasta));
$$;

create or replace function app.tiene_acceso_tenant(p_usuario uuid, p_tenant uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
           select 1
           from platform.membresias m
           join platform.tenants t on t.id = m.tenant_id
           where m.usuario_id = p_usuario and m.tenant_id = p_tenant
             and m.estado = 'activo' and t.estado in ('prueba', 'activo') and t.eliminado_en is null)
      or app.soporte_autorizado(p_usuario, p_tenant);
$$;

create or replace function app.es_super_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from platform.asignaciones_plataforma ap
    join platform.roles r on r.id = ap.rol_id and r.codigo = 'super_admin'
    where ap.usuario_id = auth.uid() and now() >= ap.desde and (ap.hasta is null or now() < ap.hasta));
$$;

-- Membresía del usuario en el tenant actual (NULL si no tiene)
create or replace function app.mi_membresia()
returns uuid language sql stable security definer set search_path = '' as $$
  select m.id from platform.membresias m
  where m.tenant_id = app.current_tenant_id() and m.usuario_id = auth.uid() and m.estado = 'activo';
$$;

create or replace function app.mi_rol()
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select r.codigo from platform.membresias m join platform.roles r on r.id = m.rol_id
      where m.tenant_id = app.current_tenant_id() and m.usuario_id = auth.uid() and m.estado = 'activo'),
    case when app.soporte_autorizado(auth.uid(), app.current_tenant_id()) then 'soporte' end,
    case when auth.uid() is null and app.current_tenant_id() is not null then 'backend' end);
$$;

create or replace function app.plugin_habilitado(p_codigo text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from platform.tenant_plugins tp join platform.plugins p on p.id = tp.plugin_id
    where tp.tenant_id = app.current_tenant_id() and p.codigo = p_codigo and tp.habilitado and p.activo);
$$;

-- -----------------------------------------------------------------------------
-- 2. Nivel de permiso del usuario actual sobre un módulo: 0 nada, 1 lectura,
--    2 escritura, 3 total. Suma tres fuentes y toma la mayor:
--      a) el rol general de su membresía (platform.rol_permisos)
--      b) los accesos especiales que le activó el Administrador (escritura)
--      c) Soporte con autorización vigente: 'con_autorizacion' equivale a total
--    El backend de confianza (sin usuario, tenant fijado) tiene nivel total.
--    Si el permiso es de un plugin que el tenant no tiene habilitado: 0 (RN-P09).
-- -----------------------------------------------------------------------------
create or replace function app.nivel_permiso(p_codigo text)
returns int language plpgsql stable security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_uid    uuid := auth.uid();
  v_perm   record;
  v_nivel  int := 0;
begin
  if v_tenant is null then
    return 0;
  end if;
  select p.id, p.plugin_id, pl.codigo as plugin_codigo into v_perm
  from platform.permisos p left join platform.plugins pl on pl.id = p.plugin_id
  where p.codigo = p_codigo;
  if not found then
    return 0;
  end if;
  if v_perm.plugin_id is not null and not app.plugin_habilitado(v_perm.plugin_codigo) then
    return 0;
  end if;
  if v_uid is null then
    return 3;  -- backend de confianza (service_role / elius_app) dentro de un solo tenant
  end if;

  select coalesce(max(case rp.nivel when 'lectura' then 1 when 'escritura' then 2 when 'total' then 3 else 0 end), 0)
    into v_nivel
  from platform.membresias m
  join platform.rol_permisos rp on rp.rol_id = m.rol_id and rp.permiso_id = v_perm.id
  where m.tenant_id = v_tenant and m.usuario_id = v_uid and m.estado = 'activo';

  if v_nivel < 2 and exists (
       select 1 from platform.membresias m
       join platform.accesos_especiales ae on ae.membresia_id = m.id and ae.permiso_id = v_perm.id
       where m.tenant_id = v_tenant and m.usuario_id = v_uid and m.estado = 'activo'
         and (ae.vence_en is null or ae.vence_en > now())) then
    v_nivel := 2;
  end if;

  if v_nivel < 3 and app.soporte_autorizado(v_uid, v_tenant) and exists (
       select 1 from platform.rol_permisos rp join platform.roles r on r.id = rp.rol_id
       where r.codigo = 'soporte' and rp.permiso_id = v_perm.id and rp.nivel = 'con_autorizacion') then
    v_nivel := 3;
  end if;
  return v_nivel;
end $$;

create or replace function app.puede(p_codigo text, p_nivel text)
returns boolean language sql stable security definer set search_path = '' as $$
  select app.nivel_permiso(p_codigo) >= case p_nivel when 'lectura' then 1 when 'escritura' then 2 when 'total' then 3 else 99 end;
$$;

comment on function app.puede(text, text) is 'true si el usuario actual tiene al menos ese nivel (lectura, escritura, total) en el módulo';

-- -----------------------------------------------------------------------------
-- 3. Hook de Supabase Auth: agrega al JWT el tenant activo y el rol (DT-04)
--    Se activa en Supabase: Authentication → Hooks → Custom Access Token.
-- -----------------------------------------------------------------------------
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid    uuid  := (event ->> 'user_id')::uuid;
  v_claims jsonb := coalesce(event -> 'claims', '{}'::jsonb);
  v_tenant uuid;
  v_rol    text;
begin
  select m.tenant_id, r.codigo into v_tenant, v_rol
  from platform.membresias m
  join platform.roles r on r.id = m.rol_id
  join platform.tenants t on t.id = m.tenant_id
  where m.usuario_id = v_uid and m.estado = 'activo' and t.estado in ('prueba', 'activo')
  order by m.es_predeterminada desc, m.fecha_ingreso
  limit 1;

  if v_tenant is not null then
    v_claims := v_claims || jsonb_build_object('tenant_id', v_tenant, 'tenant_rol', v_rol);
  else
    v_claims := v_claims - 'tenant_id' - 'tenant_rol';
  end if;
  return jsonb_set(event, '{claims}', v_claims);
end $$;

revoke execute on function public.custom_access_token_hook(jsonb) from public, anon, authenticated;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- -----------------------------------------------------------------------------
-- 4. Plantilla de políticas para tablas de negocio (modelo general y plugins)
--    select: lectura · insert/update: escritura · delete: total
--    (select …) hace que Postgres calcule la función una sola vez por consulta (DT-06)
-- -----------------------------------------------------------------------------
create or replace function app.aplicar_rls(p_tabla regclass, p_permiso text)
returns void language plpgsql set search_path = '' as $$
declare
  v_t text := p_tabla::text;
  v_n text := replace(split_part(v_t, '.', 2), '"', '');
  v_cond text := format('tenant_id = (select app.current_tenant_id())');
begin
  execute format('alter table %s enable row level security', v_t);
  execute format('create policy %I on %s for select using (%s and (select app.puede(%L, ''lectura'')))',
                 'sel_' || v_n, v_t, v_cond, p_permiso);
  execute format('create policy %I on %s for insert with check (%s and (select app.puede(%L, ''escritura'')))',
                 'ins_' || v_n, v_t, v_cond, p_permiso);
  execute format('create policy %I on %s for update using (%s and (select app.puede(%L, ''escritura''))) with check (%s)',
                 'upd_' || v_n, v_t, v_cond, p_permiso, v_cond);
  execute format('create policy %I on %s for delete using (%s and (select app.puede(%L, ''total'')))',
                 'del_' || v_n, v_t, v_cond, p_permiso);
end $$;

-- Tabla → permiso (módulo). Las tablas de plugin usan permisos del plugin, así que
-- además exigen que el plugin esté habilitado para el tenant (RN-P09).
do $$
declare
  r record;
begin
  for r in select * from (values
    -- elius: contactos y conversaciones
    ('elius.contactos', 'contactos'), ('elius.direcciones', 'contactos'), ('elius.consentimientos', 'contactos'),
    ('elius.identidades_contacto', 'conversaciones'), ('elius.conversaciones', 'conversaciones'),
    ('elius.mensajes', 'conversaciones'), ('elius.escalamientos', 'conversaciones'),
    ('elius.consumos_llm', 'reportes'), ('elius.eventos_embudo', 'reportes'),
    -- elius: configuración del negocio y de Eli
    ('elius.agentes', 'configuracion'), ('elius.canales', 'configuracion'), ('elius.parametros_negocio', 'configuracion'),
    ('elius.errores_agente', 'configuracion'), ('elius.eventos_salida', 'configuracion'),
    ('elius.pasarelas_pago', 'configuracion'),
    -- elius: catálogo
    ('elius.categorias_catalogo', 'catalogo'), ('elius.items_catalogo', 'catalogo'),
    ('elius.item_adicionales', 'catalogo'), ('elius.medios_item', 'catalogo'),
    -- elius: reservas
    ('elius.recursos', 'reservas'), ('elius.horarios_atencion', 'reservas'),
    ('elius.reservas', 'reservas'), ('elius.asignaciones_recurso', 'reservas'),
    -- elius: órdenes y pagos
    ('elius.ordenes', 'ordenes'), ('elius.orden_items', 'ordenes'), ('elius.entregas', 'ordenes'),
    ('elius.pagos', 'pagos'), ('elius.comprobantes_pago', 'pagos'), ('elius.recaudos', 'pagos'),
    ('elius.notificaciones_pasarela', 'pagos'),
    -- elius: conocimiento de Eli
    ('elius.documentos_conocimiento', 'conocimiento'), ('elius.fragmentos_conocimiento', 'conocimiento'),
    -- ext
    ('ext.instalaciones_extension', 'ext'), ('ext.sitios_autorizados', 'ext'),
    ('ext.conversaciones_capturadas', 'ext'), ('ext.mensajes_capturados', 'ext'),
    ('ext.patrones', 'ext'), ('ext.evidencias_patron', 'ext'),
    -- plugin veterinaria
    ('plugin_vet.mascotas', 'vet.pacientes'), ('plugin_vet.propietarios_mascota', 'vet.pacientes'),
    ('plugin_vet.atenciones', 'vet.pacientes'), ('plugin_vet.aplicaciones_vacuna', 'vet.pacientes'),
    ('plugin_vet.registros_clinicos', 'vet.historia_clinica'),
    -- plugin restaurante
    ('plugin_restaurant.alergenos', 'restaurant.menu'), ('plugin_restaurant.item_alergenos', 'restaurant.menu'),
    ('plugin_restaurant.grupos_modificador', 'restaurant.menu'), ('plugin_restaurant.opciones_modificador', 'restaurant.menu'),
    ('plugin_restaurant.item_grupos_modificador', 'restaurant.menu'),
    ('plugin_restaurant.menus_dia', 'restaurant.menu'), ('plugin_restaurant.menu_dia_items', 'restaurant.menu'),
    ('plugin_restaurant.orden_item_opciones', 'restaurant.cocina'), ('plugin_restaurant.estaciones_cocina', 'restaurant.cocina'),
    ('plugin_restaurant.comandas', 'restaurant.cocina'), ('plugin_restaurant.comanda_items', 'restaurant.cocina'),
    ('plugin_restaurant.celebraciones', 'restaurant.cocina'),
    -- plugin aerolínea
    ('plugin_airline.aeronaves', 'airline.vuelos'), ('plugin_airline.rutas', 'airline.vuelos'),
    ('plugin_airline.vuelos', 'airline.vuelos'), ('plugin_airline.tarifas_vuelo', 'airline.vuelos'),
    ('plugin_airline.reserva_pasajeros', 'airline.reservas'), ('plugin_airline.tramos_reserva', 'airline.reservas'),
    ('plugin_airline.tiquetes', 'airline.reservas'), ('plugin_airline.equipajes', 'airline.reservas')
  ) as t(tabla, permiso)
  loop
    perform app.aplicar_rls(r.tabla::regclass, r.permiso);
  end loop;
end $$;

-- Notificaciones push: cada usuario solo administra las de sus dispositivos
alter table elius.suscripciones_push enable row level security;
create policy push_propias on elius.suscripciones_push for all
  using (tenant_id = (select app.current_tenant_id()) and membresia_id = (select app.mi_membresia()))
  with check (tenant_id = (select app.current_tenant_id()) and membresia_id = (select app.mi_membresia()));
create policy push_backend on elius.suscripciones_push for select
  using (auth.uid() is null and tenant_id = (select app.current_tenant_id()));

-- RN-E01: lo capturado por la extensión solo lo ve quien lo capturó, salvo nivel total
-- (política RESTRICTIVA: se suma con AND a las políticas anteriores)
create policy solo_quien_captura on ext.conversaciones_capturadas as restrictive for select
  using (
    (select app.puede('ext', 'total'))
    or instalacion_id in (select i.id from ext.instalaciones_extension i where i.membresia_id = (select app.mi_membresia()))
  );
create policy solo_quien_captura on ext.mensajes_capturados as restrictive for select
  using (
    (select app.puede('ext', 'total'))
    or conversacion_id in (
      select c.id from ext.conversaciones_capturadas c
      join ext.instalaciones_extension i on i.id = c.instalacion_id
      where i.membresia_id = (select app.mi_membresia()))
  );

-- Aeropuertos: catálogo global de solo lectura (RN-A01)
alter table plugin_airline.aeropuertos enable row level security;
create policy aeropuertos_lectura on plugin_airline.aeropuertos for select using (auth.uid() is not null or auth.role() = 'service_role' or session_user = 'elius_app');
create policy aeropuertos_admin on plugin_airline.aeropuertos for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

-- -----------------------------------------------------------------------------
-- 5. Políticas del esquema platform (lógica del tenant)
-- -----------------------------------------------------------------------------
alter table platform.planes                  enable row level security;
alter table platform.tenants                 enable row level security;
alter table platform.roles                   enable row level security;
alter table platform.permisos                enable row level security;
alter table platform.plugins                 enable row level security;
alter table platform.rol_permisos            enable row level security;
alter table platform.membresias              enable row level security;
alter table platform.accesos_especiales      enable row level security;
alter table platform.asignaciones_plataforma enable row level security;
alter table platform.tenant_plugins          enable row level security;
alter table platform.accesos_soporte         enable row level security;
alter table platform.invitaciones            enable row level security;
alter table platform.llaves_api              enable row level security;
alter table platform.consumos_periodo        enable row level security;
alter table audit.registros_auditoria        enable row level security;

-- Catálogos globales: todos los autenticados leen; solo el Super Admin cambia
create policy planes_lectura   on platform.planes       for select using (auth.uid() is not null);
create policy planes_admin     on platform.planes       for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy roles_lectura    on platform.roles        for select using (auth.uid() is not null);
create policy roles_admin      on platform.roles        for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy permisos_lectura on platform.permisos     for select using (auth.uid() is not null);
create policy permisos_admin   on platform.permisos     for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy plugins_lectura  on platform.plugins      for select using (auth.uid() is not null);
create policy plugins_admin    on platform.plugins      for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));
create policy rol_permisos_lectura on platform.rol_permisos for select using (auth.uid() is not null);
create policy rol_permisos_admin   on platform.rol_permisos for all using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

-- Tenants: cada usuario ve los suyos (para cambiar de tenant); el Administrador edita el actual
create policy tenants_mios on platform.tenants for select
  using (id in (select m.tenant_id from platform.membresias m where m.usuario_id = auth.uid() and m.estado = 'activo')
         or id = (select app.current_tenant_id()) or (select app.es_super_admin()));
create policy tenants_editar on platform.tenants for update
  using (id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')))
  with check (id = (select app.current_tenant_id()));
create policy tenants_super_admin on platform.tenants for all
  using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

-- Membresías: el usuario ve las suyas; quien tiene permiso de usuarios ve y gestiona las del tenant
create policy membresias_propias on platform.membresias for select using (usuario_id = auth.uid());
create policy membresias_tenant on platform.membresias for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'lectura')));
create policy membresias_gestion on platform.membresias for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')));

create policy accesos_especiales_tenant on platform.accesos_especiales for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'lectura')));
create policy accesos_especiales_gestion on platform.accesos_especiales for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')));

create policy asignaciones_propias on platform.asignaciones_plataforma for select
  using (usuario_id = auth.uid() or (select app.es_super_admin()));
create policy asignaciones_admin on platform.asignaciones_plataforma for all
  using ((select app.es_super_admin())) with check ((select app.es_super_admin()));

create policy tenant_plugins_lectura on platform.tenant_plugins for select
  using (tenant_id = (select app.current_tenant_id()) or (select app.es_super_admin()));
create policy tenant_plugins_gestion on platform.tenant_plugins for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')));

-- Accesos de soporte: los autoriza el Administrador; Soporte ve los que le dieron
create policy accesos_soporte_propios on platform.accesos_soporte for select using (usuario_soporte_id = auth.uid());
create policy accesos_soporte_gestion on platform.accesos_soporte for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total'))
              and autorizado_por = auth.uid());

create policy invitaciones_gestion on platform.invitaciones for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('usuarios', 'total')));

create policy llaves_api_gestion on platform.llaves_api for all
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')))
  with check (tenant_id = (select app.current_tenant_id()) and (select app.puede('configuracion', 'total')));

create policy consumos_lectura on platform.consumos_periodo for select
  using ((tenant_id = (select app.current_tenant_id()) and (select app.puede('reportes', 'lectura'))) or (select app.es_super_admin()));
create policy consumos_backend on platform.consumos_periodo for all
  using (auth.uid() is null and tenant_id = (select app.current_tenant_id()))
  with check (auth.uid() is null and tenant_id = (select app.current_tenant_id()));

-- Auditoría: solo lectura. La escriben los triggers (security definer), nunca un usuario.
create policy auditoria_tenant on audit.registros_auditoria for select
  using (tenant_id = (select app.current_tenant_id()) and (select app.puede('auditoria', 'lectura')));
create policy auditoria_plataforma on audit.registros_auditoria for select
  using ((select app.es_super_admin()));

-- -----------------------------------------------------------------------------
-- 6. Permisos de los roles de la API de Supabase (las políticas RLS hacen el filtro)
-- -----------------------------------------------------------------------------
grant usage on schema platform, elius, ext, audit, app, plugin_vet, plugin_restaurant, plugin_airline
  to authenticated, service_role, elius_app;
grant select, insert, update, delete on all tables in schema platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline
  to authenticated, service_role, elius_app;
grant select on audit.registros_auditoria to authenticated, service_role, elius_app;
grant execute on all functions in schema app to authenticated, service_role, elius_app;
revoke execute on function app.aplicar_rls(regclass, text) from public, anon, authenticated, service_role, elius_app;
revoke all on schema reportes from public;
-- anon (sin iniciar sesión) no recibe ningún permiso sobre datos
-- =============================================================================
-- ELIUS · Migración 0500 · Triggers
-- Cada trigger hace cumplir una regla de negocio (código RN-…) que no se puede
-- expresar con CHECK porque consulta otras filas o tablas.
-- Las funciones de trigger son SECURITY DEFINER solo cuando deben escribir en
-- tablas que el usuario no puede tocar (auditoría, eventos, contadores).
-- Los triggers de los plugins viven en el esquema del plugin: el modelo general
-- nunca depende de un plugin.
-- =============================================================================

-- =============================================================================
-- T01 · actualizado_en en todas las tablas que lo tienen
-- =============================================================================
do $$
declare r record;
begin
  for r in
    select c.table_schema, c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
    where c.column_name = 'actualizado_en'
      and c.table_schema in ('platform', 'elius', 'ext', 'plugin_vet', 'plugin_restaurant', 'plugin_airline')
  loop
    execute format('create trigger t01_actualizado_en before update on %I.%I for each row execute function app.set_actualizado_en()',
                   r.table_schema, r.table_name);
  end loop;
end $$;

-- =============================================================================
-- T02 · Auditoría (RN-P15, RNF-06, DT-12)
-- Guarda quién, con qué rol, desde dónde, qué tabla, qué fila, y el antes y el después.
-- =============================================================================
create or replace function app.auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_fila   jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_rol    text  := app.mi_rol();
  v_tenant uuid  := nullif(v_fila ->> 'tenant_id', '')::uuid;
begin
  insert into audit.registros_auditoria
    (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_anteriores, datos_nuevos)
  values (
    v_tenant, auth.uid(), coalesce(v_rol, 'sistema'),
    case when v_rol = 'eli' then 'eli' when v_rol = 'soporte' then 'soporte'
         when auth.uid() is null then 'sistema' else 'app' end,
    tg_table_schema, tg_table_name, (v_fila ->> 'id')::uuid, tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return null;
end $$;

-- Se audita todo menos las tablas de alto volumen o técnicas
do $$
declare r record;
begin
  for r in
    select t.table_schema, t.table_name from information_schema.tables t
    where t.table_type = 'BASE TABLE'
      and t.table_schema in ('platform', 'elius', 'ext', 'plugin_vet', 'plugin_restaurant', 'plugin_airline')
      and (t.table_schema || '.' || t.table_name) not in (
        'elius.mensajes', 'elius.consumos_llm', 'elius.eventos_embudo', 'elius.eventos_salida',
        'elius.fragmentos_conocimiento', 'elius.notificaciones_pasarela', 'elius.suscripciones_push',
        'ext.mensajes_capturados', 'ext.evidencias_patron', 'platform.consumos_periodo')
  loop
    execute format('create trigger t02_auditoria after insert or update or delete on %I.%I for each row execute function app.auditar()',
                   r.table_schema, r.table_name);
  end loop;
end $$;

-- =============================================================================
-- T03 · Eventos de salida para n8n (DT-16): una tabla que n8n lee o un webhook de BD
-- =============================================================================
create or replace function app.emitir_evento(p_tenant uuid, p_tipo text, p_entidad text, p_id uuid, p_carga jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into elius.eventos_salida (tenant_id, tipo_evento, entidad, entidad_id, carga)
  values (p_tenant, p_tipo, p_entidad, p_id, coalesce(p_carga, '{}'::jsonb));
$$;

create or replace function app.parametro(p_tenant uuid, p_clave text)
returns text language sql stable security definer set search_path = '' as $$
  select valor from elius.parametros_negocio where tenant_id = p_tenant and clave = p_clave;
$$;

-- =============================================================================
-- PLATFORM
-- =============================================================================
-- T10 · RN-P13: el rol de una membresía es de nivel tenant; el de plataforma, de nivel plataforma
create or replace function app.validar_nivel_rol()
returns trigger language plpgsql set search_path = '' as $$
declare v_nivel text;
begin
  select nivel into v_nivel from platform.roles where id = new.rol_id;
  if tg_table_name = 'membresias' and v_nivel <> 'tenant' then
    raise exception 'RN-P13: el rol de una membresía debe ser de nivel tenant' using errcode = '23514';
  elsif tg_table_name = 'asignaciones_plataforma' and v_nivel <> 'plataforma' then
    raise exception 'RN-P13: solo Super Admin y Soporte se asignan a nivel plataforma' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t10_nivel_rol before insert or update of rol_id on platform.membresias
  for each row execute function app.validar_nivel_rol();
create trigger t10_nivel_rol before insert or update of rol_id on platform.asignaciones_plataforma
  for each row execute function app.validar_nivel_rol();

-- T11 · RN-P04: el último Administrador activo no se elimina, no se desactiva ni cambia de rol
create or replace function app.proteger_ultimo_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_admin uuid;
begin
  select id into v_admin from platform.roles where codigo = 'administrador';
  if old.rol_id = v_admin and old.estado = 'activo'
     and (tg_op = 'DELETE' or new.rol_id <> v_admin or new.estado <> 'activo')
     and not exists (select 1 from platform.membresias m
                     where m.tenant_id = old.tenant_id and m.id <> old.id and m.rol_id = v_admin and m.estado = 'activo')
     and exists (select 1 from platform.tenants t where t.id = old.tenant_id) then
    raise exception 'RN-P04: el tenant debe conservar al menos un Administrador activo' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger t11_ultimo_admin before update or delete on platform.membresias
  for each row execute function app.proteger_ultimo_admin();

-- T12 · RN-P10: no superar los usuarios del plan
create or replace function app.validar_limite_usuarios()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_max int; v_actual int;
begin
  select p.max_usuarios into v_max from platform.tenants t join platform.planes p on p.id = t.plan_id where t.id = new.tenant_id;
  select count(*) into v_actual from platform.membresias where tenant_id = new.tenant_id and estado <> 'inactivo';
  if v_actual >= v_max then
    raise exception 'RN-P10: el plan permite máximo % usuarios', v_max using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t12_limite_usuarios before insert on platform.membresias
  for each row execute function app.validar_limite_usuarios();

-- =============================================================================
-- ELIUS · conversaciones (RN-C06, RN-C18, RN-C19, RN-C20)
-- =============================================================================
-- T20 · Antes de guardar un mensaje: Eli no habla si la conversación es de un humano
--       o si está apagada; un mensaje del cliente reabre una conversación cerrada.
create or replace function app.antes_de_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_estado text; v_agente_activo boolean;
begin
  select c.estado, coalesce(a.activo, false) into v_estado, v_agente_activo
  from elius.conversaciones c
  join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
  join elius.canales ca on ca.tenant_id = i.tenant_id and ca.id = i.canal_id
  left join elius.agentes a on a.tenant_id = ca.tenant_id and a.id = ca.agente_id
  where c.tenant_id = new.tenant_id and c.id = new.conversacion_id;

  if new.emisor = 'eli' and v_estado in ('humano', 'pausa') then
    raise exception 'RN-C19: la conversación la atiende una persona; Eli no responde' using errcode = '23514';
  end if;
  if new.emisor = 'eli' and not v_agente_activo then
    raise exception 'RN-C20: Eli está apagado para este negocio' using errcode = '23514';
  end if;
  if new.emisor = 'cliente' and v_estado = 'cerrada' then
    update elius.conversaciones set estado = 'en_progreso', cerrada_en = null
    where tenant_id = new.tenant_id and id = new.conversacion_id;
  end if;
  return new;
end $$;
create trigger t20_antes_de_mensaje before insert on elius.mensajes
  for each row execute function app.antes_de_mensaje();

create or replace function app.despues_de_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update elius.conversaciones set ultimo_mensaje_en = new.enviado_en
  where tenant_id = new.tenant_id and id = new.conversacion_id and ultimo_mensaje_en < new.enviado_en;
  update elius.identidades_contacto i set ultimo_contacto_en = new.enviado_en
  from elius.conversaciones c
  where c.tenant_id = new.tenant_id and c.id = new.conversacion_id and i.tenant_id = c.tenant_id and i.id = c.identidad_id
    and new.emisor = 'cliente';
  return null;
end $$;
create trigger t21_despues_de_mensaje after insert on elius.mensajes
  for each row execute function app.despues_de_mensaje();

-- T22 · RN-C18: los escalamientos se reparten por turnos entre los Operadores activos
--       (al que tenga menos casos abiertos; empate: al que hace más tiempo no recibe uno)
create or replace function app.asignar_escalamiento()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.asignado_a is null then
    select m.id into new.asignado_a
    from platform.membresias m
    join platform.roles r on r.id = m.rol_id and r.codigo = 'operador'
    where m.tenant_id = new.tenant_id and m.estado = 'activo'
    order by (select count(*) from elius.escalamientos e
              where e.tenant_id = m.tenant_id and e.asignado_a = m.id and e.resuelto_en is null),
             (select max(e.creado_en) from elius.escalamientos e
              where e.tenant_id = m.tenant_id and e.asignado_a = m.id) nulls first,
             m.fecha_ingreso
    limit 1;
  end if;
  return new;
end $$;
create trigger t22_asignar_escalamiento before insert on elius.escalamientos
  for each row execute function app.asignar_escalamiento();

-- T23 · RN-C19: al escalar, la conversación pasa a humano; al resolver el último, queda libre
create or replace function app.despues_de_escalamiento()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    update elius.conversaciones set estado = 'humano', asignado_a = new.asignado_a
    where tenant_id = new.tenant_id and id = new.conversacion_id;
    perform app.emitir_evento(new.tenant_id, 'escalamiento.creado', 'escalamientos', new.id,
                              jsonb_build_object('motivo', new.motivo, 'asignado_a', new.asignado_a));
  elsif new.resuelto_en is not null and old.resuelto_en is null
        and not exists (select 1 from elius.escalamientos e
                        where e.tenant_id = new.tenant_id and e.conversacion_id = new.conversacion_id
                          and e.resuelto_en is null and e.id <> new.id) then
    update elius.conversaciones set asignado_a = null
    where tenant_id = new.tenant_id and id = new.conversacion_id;
  end if;
  return null;
end $$;
create trigger t23_despues_de_escalamiento after insert or update of resuelto_en on elius.escalamientos
  for each row execute function app.despues_de_escalamiento();

-- =============================================================================
-- ELIUS · reservas (RN-C08, RN-C09, RN-R08, RN-R10)
-- =============================================================================
-- T30 · Código visible de la reserva (localizador) único por tenant
create or replace function app.codigo_reserva()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.codigo is null then
    loop
      new.codigo := app.codigo_aleatorio(6);
      exit when not exists (select 1 from elius.reservas where tenant_id = new.tenant_id and codigo = new.codigo);
    end loop;
  end if;
  return new;
end $$;
create trigger t30_codigo_reserva before insert on elius.reservas
  for each row execute function app.codigo_reserva();

-- T31 · RN-C08 y RN-R10: no reservar en el pasado ni más allá de la anticipación máxima
create or replace function app.validar_fecha_reserva()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_dias int := coalesce(app.parametro(new.tenant_id, 'dias_anticipacion_max')::int, 365);
begin
  if new.inicio < now() - interval '5 minutes' then
    raise exception 'RN-C08: no se puede reservar en el pasado' using errcode = '23514';
  end if;
  if new.inicio > now() + make_interval(days => v_dias) then
    raise exception 'RN-R10: solo se reserva con máximo % días de anticipación', v_dias using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t31_fecha_reserva before insert or update of inicio on elius.reservas
  for each row execute function app.validar_fecha_reserva();

-- T32 · RN-C09: solo transiciones de estado válidas
create or replace function app.validar_transicion_reserva()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.estado is distinct from old.estado and not (
       (old.estado = 'pendiente_pago' and new.estado in ('confirmada', 'cancelada'))
    or (old.estado = 'confirmada'     and new.estado in ('asistio', 'no_asistio', 'cancelada'))) then
    raise exception 'RN-C09: una reserva no puede pasar de % a %', old.estado, new.estado using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t32_transicion_reserva before update of estado on elius.reservas
  for each row execute function app.validar_transicion_reserva();

-- T33 · Eventos de reservas para n8n (aviso al equipo, calendario) y RN-R08 grupo grande
create or replace function app.eventos_reserva()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_umbral int := app.parametro(new.tenant_id, 'umbral_grupo_grande')::int;
begin
  if tg_op = 'INSERT' then
    perform app.emitir_evento(new.tenant_id, 'reserva.creada', 'reservas', new.id,
                              jsonb_build_object('codigo', new.codigo, 'inicio', new.inicio, 'personas', new.personas));
    if v_umbral is not null and new.personas >= v_umbral then
      perform app.emitir_evento(new.tenant_id, 'reserva.grupo_grande', 'reservas', new.id,
                                jsonb_build_object('personas', new.personas, 'umbral', v_umbral));
    end if;
  elsif new.estado is distinct from old.estado then
    perform app.emitir_evento(new.tenant_id, 'reserva.' || new.estado, 'reservas', new.id,
                              jsonb_build_object('codigo', new.codigo));
  end if;
  return null;
end $$;
create trigger t33_eventos_reserva after insert or update of estado on elius.reservas
  for each row execute function app.eventos_reserva();

-- =============================================================================
-- ELIUS · órdenes (RN-C10, RN-C11, RN-C12, RN-R03)
-- =============================================================================
-- T40 · RN-C10: consecutivo de orden por tenant (bloqueo por tenant para evitar repetidos)
create or replace function app.numero_orden()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.numero is null then
    perform pg_advisory_xact_lock(hashtext('ordenes:' || new.tenant_id::text));
    select coalesce(max(numero), 0) + 1 into new.numero from elius.ordenes where tenant_id = new.tenant_id;
  end if;
  return new;
end $$;
create trigger t40_numero_orden before insert on elius.ordenes
  for each row execute function app.numero_orden();

-- T41 · Línea de orden: precio desde el catálogo, total de línea, ítem disponible y orden abierta
create or replace function app.antes_de_linea()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_estado text; v_disponible boolean; v_precio numeric;
begin
  select estado into v_estado from elius.ordenes
  where tenant_id = coalesce(new.tenant_id, old.tenant_id) and id = coalesce(new.orden_id, old.orden_id);
  if v_estado not in ('cotizando', 'esperando_pago') then
    raise exception 'RN-C12: la orden ya está % y no se puede modificar', v_estado using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  select disponible, precio into v_disponible, v_precio from elius.items_catalogo
  where tenant_id = new.tenant_id and id = new.item_id and eliminado_en is null;
  if not coalesce(v_disponible, false) then
    raise exception 'RN-R03: el ítem está agotado o no existe' using errcode = '23514';
  end if;
  new.precio_unitario := coalesce(new.precio_unitario, v_precio);
  new.total_linea := round(new.cantidad * new.precio_unitario + new.recargos - new.descuento, 2);
  if new.total_linea < 0 then
    raise exception 'El descuento no puede superar el valor de la línea' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t41_antes_de_linea before insert or update or delete on elius.orden_items
  for each row execute function app.antes_de_linea();

-- T42 · RN-C11: el total de la orden siempre se calcula desde sus líneas
create or replace function app.recalcular_orden(p_tenant uuid, p_orden uuid)
returns void language sql security definer set search_path = '' as $$
  update elius.ordenes o set
    subtotal  = coalesce(l.subtotal, 0),
    impuestos = coalesce(l.impuestos, 0),
    total     = greatest(coalesce(l.subtotal, 0) - o.descuento + coalesce(l.impuestos, 0), 0)
  from (select sum(oi.total_linea) as subtotal,
               round(sum(oi.total_linea * ic.impuesto_pct / 100), 2) as impuestos
        from elius.orden_items oi
        join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
        where oi.tenant_id = p_tenant and oi.orden_id = p_orden) l
  where o.tenant_id = p_tenant and o.id = p_orden;
$$;

create or replace function app.despues_de_linea()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app.recalcular_orden(coalesce(new.tenant_id, old.tenant_id), coalesce(new.orden_id, old.orden_id));
  return null;
end $$;
create trigger t42_recalcular_orden after insert or update or delete on elius.orden_items
  for each row execute function app.despues_de_linea();

-- T43 · RN-C11: los montos de la orden no se escriben a mano
create or replace function app.proteger_totales_orden()
returns trigger language plpgsql set search_path = '' as $$
begin
  if pg_trigger_depth() = 1 and (new.subtotal, new.impuestos, new.total) is distinct from (old.subtotal, old.impuestos, old.total) then
    raise exception 'RN-C11: los totales se calculan desde las líneas de la orden' using errcode = '23514';
  end if;
  if new.descuento is distinct from old.descuento then
    new.total := greatest(new.subtotal - new.descuento + new.impuestos, 0);
  end if;
  return new;
end $$;
create trigger t43_proteger_totales before update on elius.ordenes
  for each row execute function app.proteger_totales_orden();

-- T44 · Evento cuando una orden cambia de estado (cocina, domiciliario, cliente)
create or replace function app.eventos_orden()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado is distinct from old.estado then
    perform app.emitir_evento(new.tenant_id, 'orden.' || new.estado, 'ordenes', new.id,
                              jsonb_build_object('numero', new.numero, 'total', new.total, 'tipo_entrega', new.tipo_entrega));
  end if;
  return null;
end $$;
create trigger t44_eventos_orden after update of estado on elius.ordenes
  for each row execute function app.eventos_orden();

-- =============================================================================
-- ELIUS · pagos, comprobantes y Factus Pay (RN-C12, RN-C16, RN-C17, RN-C22)
-- =============================================================================
-- T50 · RN-C12: un pago aprobado no se modifica ni se borra; se reversa con otro pago negativo
create or replace function app.proteger_pago()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.estado = 'aprobado' then
    raise exception 'RN-C12: un pago aprobado no se modifica; registre un reverso' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger t50_proteger_pago before update or delete on elius.pagos
  for each row execute function app.proteger_pago();

-- T51 · RN-C17: cuando lo pagado cubre el total, la orden (y su reserva) quedan confirmadas
create or replace function app.aplicar_pago()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_total numeric; v_pagado numeric; v_estado text; v_reserva uuid; v_contra numeric;
begin
  if new.estado <> 'aprobado' then
    return null;
  end if;
  select total, estado, reserva_id into v_total, v_estado, v_reserva
  from elius.ordenes where tenant_id = new.tenant_id and id = new.orden_id for update;
  select coalesce(sum(monto), 0) into v_pagado from elius.pagos
  where tenant_id = new.tenant_id and orden_id = new.orden_id and estado = 'aprobado';
  select coalesce(sum(cobro_contra_entrega), 0) into v_contra from elius.entregas
  where tenant_id = new.tenant_id and orden_id = new.orden_id and estado <> 'fallida';

  if v_estado in ('cotizando', 'esperando_pago') and v_pagado + v_contra >= v_total and v_total > 0 then
    update elius.ordenes set estado = 'confirmada' where tenant_id = new.tenant_id and id = new.orden_id;
    if v_reserva is not null then
      update elius.reservas set estado = 'confirmada'
      where tenant_id = new.tenant_id and id = v_reserva and estado = 'pendiente_pago';
    end if;
  elsif v_estado = 'cotizando' then
    update elius.ordenes set estado = 'esperando_pago' where tenant_id = new.tenant_id and id = new.orden_id;
  end if;
  return null;
end $$;
create trigger t51_aplicar_pago after insert or update of estado on elius.pagos
  for each row execute function app.aplicar_pago();

-- T52 · RN-C16: alertas del comprobante (repetido, monto distinto, destinatario raro)
create or replace function app.revisar_comprobante()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_alertas text[] := '{}';
  v_cuentas text := app.parametro(new.tenant_id, 'cuentas_pago');
begin
  if exists (select 1 from elius.comprobantes_pago c
             where c.tenant_id = new.tenant_id and c.id <> new.id
               and ((new.hash_archivo is not null and c.hash_archivo = new.hash_archivo)
                 or (new.referencia is not null and c.app_origen is not distinct from new.app_origen and c.referencia = new.referencia))) then
    v_alertas := array_append(v_alertas, 'comprobante repetido');
  end if;
  if new.monto_leido is not null and new.monto_esperado is not null then
    new.coincide := new.monto_leido = new.monto_esperado;
    if not new.coincide then
      v_alertas := array_append(v_alertas, format('monto %s distinto al esperado %s', new.monto_leido, new.monto_esperado));
    end if;
  end if;
  if v_cuentas is not null and new.destinatario is not null
     and position(lower(new.destinatario) in lower(v_cuentas)) = 0 then
    v_alertas := array_append(v_alertas, 'destinatario distinto a las cuentas del negocio');
  end if;
  if array_length(v_alertas, 1) > 0 then
    new.motivo := 'ALERTA: ' || array_to_string(v_alertas, '; ');
  end if;
  return new;
end $$;
create trigger t52_revisar_comprobante before insert on elius.comprobantes_pago
  for each row execute function app.revisar_comprobante();

create or replace function app.evento_comprobante()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app.emitir_evento(new.tenant_id, 'comprobante.recibido', 'comprobantes_pago', new.id,
                            jsonb_build_object('monto', new.monto_leido, 'alerta', new.motivo));
  return null;
end $$;
create trigger t53_evento_comprobante after insert on elius.comprobantes_pago
  for each row execute function app.evento_comprobante();

-- T54 · RN-C22: un recaudo de Factus pagado crea su pago aprobado (una sola vez)
create or replace function app.recaudo_pagado()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'pagado' and old.estado is distinct from 'pagado'
     and not exists (select 1 from elius.pagos p where p.tenant_id = new.tenant_id and p.recaudo_id = new.id) then
    insert into elius.pagos (tenant_id, orden_id, recaudo_id, metodo, proveedor, referencia_externa, monto, estado, pagado_en)
    values (new.tenant_id, new.orden_id, new.id, 'breb_factus', 'factus_pay', new.codigo_referencia,
            new.monto, 'aprobado', new.cobrado_en);
  end if;
  return null;
end $$;
create trigger t54_recaudo_pagado after update of estado on elius.recaudos
  for each row execute function app.recaudo_pagado();

-- =============================================================================
-- PLUGIN VETERINARIA (RN-V04, RN-V06)
-- =============================================================================
create or replace function plugin_vet.no_atender_fallecida()
returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from plugin_vet.mascotas m
             where m.tenant_id = new.tenant_id and m.id = new.mascota_id and m.fallecida_en is not null) then
    raise exception 'RN-V06: la mascota está registrada como fallecida' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger tv1_no_atender_fallecida before insert on plugin_vet.atenciones
  for each row execute function plugin_vet.no_atender_fallecida();

create or replace function plugin_vet.historia_inmutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.registrado_en < now() - interval '24 hours' then
    raise exception 'RN-V04: la historia clínica no se edita después de 24 horas; agregue una corrección' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger tv2_historia_inmutable before update or delete on plugin_vet.registros_clinicos
  for each row execute function plugin_vet.historia_inmutable();

-- =============================================================================
-- PLUGIN RESTAURANTE (RN-R04 recargos de opciones)
-- =============================================================================
-- Las opciones elegidas suman su recargo a la línea del núcleo (orden_items.recargos)
create or replace function plugin_restaurant.sumar_recargos()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_linea uuid := coalesce(new.orden_item_id, old.orden_item_id);
        v_tenant uuid := coalesce(new.tenant_id, old.tenant_id);
begin
  update elius.orden_items oi set recargos = coalesce((
    select sum(o.cantidad * o.precio_aplicado) from plugin_restaurant.orden_item_opciones o
    where o.tenant_id = v_tenant and o.orden_item_id = v_linea), 0)
  where oi.tenant_id = v_tenant and oi.id = v_linea;
  return null;
end $$;
create trigger tr1_sumar_recargos after insert or update or delete on plugin_restaurant.orden_item_opciones
  for each row execute function plugin_restaurant.sumar_recargos();

create or replace function plugin_restaurant.precio_opcion()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.precio_aplicado = 0 then
    select precio_adicional into new.precio_aplicado from plugin_restaurant.opciones_modificador
    where tenant_id = new.tenant_id and id = new.opcion_id;
  end if;
  return new;
end $$;
create trigger tr0_precio_opcion before insert on plugin_restaurant.orden_item_opciones
  for each row execute function plugin_restaurant.precio_opcion();

-- =============================================================================
-- PLUGIN AEROLÍNEA (RN-A04, RN-A06, RN-A07, RN-A09)
-- =============================================================================
-- RN-A04: los cupos de las tarifas de un vuelo no superan la capacidad de la aeronave
create or replace function plugin_airline.validar_capacidad()
returns trigger language plpgsql set search_path = '' as $$
declare v_cap int; v_cupos int;
begin
  select a.capacidad into v_cap from plugin_airline.vuelos v
  join plugin_airline.aeronaves a on a.tenant_id = v.tenant_id and a.id = v.aeronave_id
  where v.tenant_id = new.tenant_id and v.id = new.vuelo_id;
  select coalesce(sum(cupos_totales), 0) into v_cupos from plugin_airline.tarifas_vuelo
  where tenant_id = new.tenant_id and vuelo_id = new.vuelo_id and id <> new.id;
  if v_cupos + new.cupos_totales > v_cap then
    raise exception 'RN-A04: los cupos (%) superan la capacidad de la aeronave (%)', v_cupos + new.cupos_totales, v_cap
      using errcode = '23514';
  end if;
  return new;
end $$;
create trigger ta1_capacidad before insert or update of cupos_totales on plugin_airline.tarifas_vuelo
  for each row execute function plugin_airline.validar_capacidad();

-- RN-A04: cada tramo reservado ocupa un cupo por pasajero de la reserva
create or replace function plugin_airline.ocupar_cupo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_pax int;
begin
  select greatest(count(*) filter (where tipo_pasajero <> 'INF'), 1) into v_pax
  from plugin_airline.reserva_pasajeros where tenant_id = new.tenant_id and reserva_id = new.reserva_id;
  update plugin_airline.tarifas_vuelo set cupos_vendidos = cupos_vendidos + v_pax
  where tenant_id = new.tenant_id and id = new.tarifa_vuelo_id;   -- el CHECK de cupos impide sobreventa
  return new;
end $$;
create trigger ta2_ocupar_cupo before insert on plugin_airline.tramos_reserva
  for each row execute function plugin_airline.ocupar_cupo();

-- RN-A06: en cada reserva los infantes no superan a los adultos (se revisa al final de la transacción)
create or replace function plugin_airline.validar_infantes()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select count(*) filter (where tipo_pasajero = 'INF') > count(*) filter (where tipo_pasajero = 'ADT')
      from plugin_airline.reserva_pasajeros where tenant_id = new.tenant_id and reserva_id = new.reserva_id) then
    raise exception 'RN-A06: cada infante debe viajar con un adulto' using errcode = '23514';
  end if;
  return null;
end $$;
create constraint trigger ta3_infantes after insert or update on plugin_airline.reserva_pasajeros
  deferrable initially deferred for each row execute function plugin_airline.validar_infantes();

-- RN-A07: una silla no se asigna a dos pasajeros del mismo vuelo
create or replace function plugin_airline.validar_silla()
returns trigger language plpgsql set search_path = '' as $$
declare v_vuelo uuid;
begin
  if new.silla is null then
    return new;
  end if;
  select tv.vuelo_id into v_vuelo from plugin_airline.tramos_reserva tr
  join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
  where tr.tenant_id = new.tenant_id and tr.id = new.tramo_id;
  if exists (select 1 from plugin_airline.tiquetes t
             join plugin_airline.tramos_reserva tr on tr.tenant_id = t.tenant_id and tr.id = t.tramo_id
             join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
             where t.tenant_id = new.tenant_id and tv.vuelo_id = v_vuelo and t.silla = new.silla
               and t.id <> new.id and t.estado <> 'anulado') then
    raise exception 'RN-A07: la silla % ya está asignada en este vuelo', new.silla using errcode = '23505';
  end if;
  return new;
end $$;
create trigger ta4_silla before insert or update of silla on plugin_airline.tiquetes
  for each row execute function plugin_airline.validar_silla();

-- RN-A09: si un vuelo se cancela o se retrasa se avisa a sus pasajeros (evento para n8n)
create or replace function plugin_airline.evento_vuelo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado in ('cancelado', 'retrasado') and new.estado is distinct from old.estado then
    perform app.emitir_evento(new.tenant_id, 'vuelo.' || new.estado, 'vuelos', new.id,
                              jsonb_build_object('numero_vuelo', new.numero_vuelo, 'salida', new.salida_programada));
  end if;
  return null;
end $$;
create trigger ta5_evento_vuelo after update of estado on plugin_airline.vuelos
  for each row execute function plugin_airline.evento_vuelo();
-- =============================================================================
-- ELIUS · Migración 0600 · Vistas
-- Dos familias:
--  1. Vistas de negocio (elius y plugins) con security_invoker = true (DT-14):
--     aplican el RLS de quien consulta, así cada usuario solo ve su tenant y lo
--     que su rol le permite. Son las que usan los paneles y el rol Analista.
--  2. Vistas del esquema reportes: agregadas y sin datos personales, para el
--     usuario de base de datos elius_consulta y el Super Admin. No se exponen en la API.
-- =============================================================================

-- ---------- 1. Modelo general ----------------------------------------------------

-- Agenda del día: reservas de hoy con cliente y recursos asignados
create view elius.v_agenda_dia with (security_invoker = true) as
select r.tenant_id, r.id as reserva_id, r.codigo, r.tipo, r.estado, r.inicio, r.fin, r.personas,
       r.urgente, r.visto, r.llegada_en,
       c.nombres || coalesce(' ' || c.apellidos, '') as cliente, c.telefono,
       string_agg(rc.nombre, ', ' order by rc.nombre) as recursos,
       m.cargo as responsable_cargo
from elius.reservas r
join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
left join elius.asignaciones_recurso ar on ar.tenant_id = r.tenant_id and ar.reserva_id = r.id and ar.estado = 'activa'
left join elius.recursos rc on rc.tenant_id = ar.tenant_id and rc.id = ar.recurso_id
left join platform.membresias m on m.tenant_id = r.tenant_id and m.id = r.responsable_id
where r.inicio >= date_trunc('day', now()) and r.inicio < date_trunc('day', now()) + interval '1 day'
  and r.estado in ('pendiente_pago', 'confirmada', 'asistio')
group by r.tenant_id, r.id, c.nombres, c.apellidos, c.telefono, m.cargo;
comment on view elius.v_agenda_dia is 'Reservas de hoy con cliente y recursos (panel Operador)';

-- Saldo de cada orden: total, pagado, contra entrega y pendiente (RN-C17)
create view elius.v_saldo_ordenes with (security_invoker = true) as
select o.tenant_id, o.id as orden_id, o.numero, o.estado, o.total,
       coalesce(p.pagado, 0) as pagado,
       coalesce(e.contra_entrega, 0) as contra_entrega,
       greatest(o.total - coalesce(p.pagado, 0) - coalesce(e.contra_entrega, 0), 0) as saldo_pendiente
from elius.ordenes o
left join (select tenant_id, orden_id, sum(monto) as pagado from elius.pagos where estado = 'aprobado'
           group by tenant_id, orden_id) p on p.tenant_id = o.tenant_id and p.orden_id = o.id
left join (select tenant_id, orden_id, sum(cobro_contra_entrega) as contra_entrega from elius.entregas
           where estado <> 'fallida' group by tenant_id, orden_id) e on e.tenant_id = o.tenant_id and e.orden_id = o.id;
comment on view elius.v_saldo_ordenes is 'Total, pagado y saldo de cada orden (RN-C17)';

-- Comprobantes por revisar, primero los que tienen alerta (RN-C16)
create view elius.v_comprobantes_pendientes with (security_invoker = true) as
select cp.tenant_id, cp.id as comprobante_id, cp.creado_en, cp.monto_leido, cp.monto_esperado, cp.coincide,
       cp.app_origen, cp.referencia, cp.destinatario, cp.motivo,
       cp.motivo like 'ALERTA:%' as tiene_alerta,
       o.numero as orden_numero, c.nombres as cliente
from elius.comprobantes_pago cp
join elius.conversaciones cv on cv.tenant_id = cp.tenant_id and cv.id = cp.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join elius.ordenes o on o.tenant_id = cp.tenant_id and o.id = cp.orden_id
where cp.veredicto = 'pendiente';
comment on view elius.v_comprobantes_pendientes is 'Comprobantes por aprobar, con alertas (RN-C16)';

-- Recaudos de Factus Pay que siguen abiertos o ya vencieron
create view elius.v_recaudos_abiertos with (security_invoker = true) as
select r.tenant_id, r.id as recaudo_id, r.codigo_referencia, r.monto, r.estado, r.expira_en, r.llave_breb,
       r.expira_en < now() as vencido, o.numero as orden_numero
from elius.recaudos r
join elius.ordenes o on o.tenant_id = r.tenant_id and o.id = r.orden_id
where r.estado = 'listo';
comment on view elius.v_recaudos_abiertos is 'Cobros por llave Bre-B pendientes de pago (RN-C22)';

-- Pendientes del equipo: escalamientos abiertos con su antigüedad
create view elius.v_escalamientos_abiertos with (security_invoker = true) as
select e.tenant_id, e.id as escalamiento_id, e.creado_en, now() - e.creado_en as antiguedad,
       e.motivo, e.resumen, e.asignado_a, m.cargo as asignado_cargo,
       c.nombres as cliente, i.id_externo as numero_cliente
from elius.escalamientos e
join elius.conversaciones cv on cv.tenant_id = e.tenant_id and cv.id = e.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join platform.membresias m on m.tenant_id = e.tenant_id and m.id = e.asignado_a
where e.resuelto_en is null;
comment on view elius.v_escalamientos_abiertos is 'Casos que Eli pasó a una persona y siguen abiertos (RN-C18)';

-- Embudo: última fase de cada conversación
create view elius.v_embudo_ultima_fase with (security_invoker = true) as
select distinct on (ee.tenant_id, ee.conversacion_id)
       ee.tenant_id, ee.conversacion_id, ee.fase, ee.ocurrido_en
from elius.eventos_embudo ee
order by ee.tenant_id, ee.conversacion_id, ee.ocurrido_en desc;
comment on view elius.v_embudo_ultima_fase is 'Fase más reciente de cada conversación (métricas de conversión)';

-- Embudo agregado por día y fase (panel Analista)
create view elius.v_embudo_diario with (security_invoker = true) as
select tenant_id, date_trunc('day', ocurrido_en)::date as dia, fase, count(distinct conversacion_id) as conversaciones
from elius.eventos_embudo
group by tenant_id, 2, fase;

-- Ventas por día y canal (panel Analista)
create view elius.v_ventas_diarias with (security_invoker = true) as
select tenant_id, date_trunc('day', colocada_en)::date as dia, canal_venta, tipo_entrega,
       count(*) as ordenes, sum(total) as ventas, round(avg(total), 2) as ticket_promedio
from elius.ordenes
where estado not in ('cotizando', 'cancelada')
group by tenant_id, 2, canal_venta, tipo_entrega;
comment on view elius.v_ventas_diarias is 'Ventas confirmadas por día, canal y tipo de entrega';

-- Ítems más vendidos (panel Analista)
create view elius.v_items_mas_vendidos with (security_invoker = true) as
select oi.tenant_id, ic.id as item_id, ic.nombre, ic.tipo,
       sum(oi.cantidad) as unidades, sum(oi.total_linea) as ventas
from elius.orden_items oi
join elius.ordenes o on o.tenant_id = oi.tenant_id and o.id = oi.orden_id and o.estado not in ('cotizando', 'cancelada')
join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
group by oi.tenant_id, ic.id, ic.nombre, ic.tipo;

-- Conversaciones: cuántas atiende Eli sola y cuántas escala (panel Analista)
create view elius.v_metricas_conversaciones with (security_invoker = true) as
select cv.tenant_id, date_trunc('day', cv.iniciada_en)::date as dia,
       count(*) as conversaciones,
       count(*) filter (where exists (select 1 from elius.escalamientos e
                                      where e.tenant_id = cv.tenant_id and e.conversacion_id = cv.id)) as escaladas,
       round(100.0 * count(*) filter (where not exists (select 1 from elius.escalamientos e
                                      where e.tenant_id = cv.tenant_id and e.conversacion_id = cv.id)) / count(*), 1)
         as pct_resueltas_por_eli
from elius.conversaciones cv
group by cv.tenant_id, 2;

-- Consumo de IA por mes: tokens, costo y latencia
create view elius.v_consumo_ia_mensual with (security_invoker = true) as
select tenant_id, date_trunc('month', creado_en)::date as mes, modelo,
       count(*) as llamadas, sum(tokens_entrada) as tokens_entrada, sum(tokens_salida) as tokens_salida,
       sum(tokens_cache) as tokens_cache, sum(costo_usd) as costo_usd,
       round(avg(latencia_ms)) as latencia_promedio_ms,
       percentile_cont(0.95) within group (order by latencia_ms) as latencia_p95_ms
from elius.consumos_llm
group by tenant_id, 2, modelo;

-- ---------- 2. Plugins ------------------------------------------------------------

-- Veterinaria: vacunas que vencen en los próximos 30 días (RN-V05, recordatorios de Eli)
create view plugin_vet.v_vacunas_por_vencer with (security_invoker = true) as
select av.tenant_id, m.id as mascota_id, m.nombre as mascota, m.especie,
       ic.nombre as vacuna, av.aplicada_en, av.proxima_dosis_en,
       c.nombres as propietario, c.telefono
from plugin_vet.aplicaciones_vacuna av
join plugin_vet.mascotas m on m.tenant_id = av.tenant_id and m.id = av.mascota_id and m.fallecida_en is null
join elius.items_catalogo ic on ic.tenant_id = av.tenant_id and ic.id = av.vacuna_id
join plugin_vet.propietarios_mascota pm on pm.tenant_id = m.tenant_id and pm.mascota_id = m.id and pm.tipo = 'principal'
join elius.contactos c on c.tenant_id = pm.tenant_id and c.id = pm.contacto_id
where av.proxima_dosis_en between current_date and current_date + 30
  and not exists (select 1 from plugin_vet.aplicaciones_vacuna x
                  where x.tenant_id = av.tenant_id and x.mascota_id = av.mascota_id
                    and x.vacuna_id = av.vacuna_id and x.aplicada_en > av.aplicada_en);

-- Veterinaria: historia clínica completa por mascota (RLS: solo con acceso especial, RN-V03)
create view plugin_vet.v_historia_clinica with (security_invoker = true) as
select rc.tenant_id, a.mascota_id, m.nombre as mascota, a.id as atencion_id, r.inicio as fecha_cita,
       a.motivo, rc.tipo, rc.contenido, rc.registrado_en, rc.corrige_a, mb.cargo as autor_cargo
from plugin_vet.registros_clinicos rc
join plugin_vet.atenciones a on a.tenant_id = rc.tenant_id and a.id = rc.atencion_id
join plugin_vet.mascotas m on m.tenant_id = a.tenant_id and m.id = a.mascota_id
join elius.reservas r on r.tenant_id = a.tenant_id and r.id = a.reserva_id
join platform.membresias mb on mb.tenant_id = rc.tenant_id and mb.id = rc.autor_id;

-- Restaurante: menú del día vigente, solo si el dueño lo confirmó (RN-R11)
create view plugin_restaurant.v_menu_vigente with (security_invoker = true) as
select md.tenant_id, md.fecha, md.precio_base, md.url_foto,
       mi.seccion, mi.posicion, ic.nombre as plato, mi.disponible
from plugin_restaurant.menus_dia md
join plugin_restaurant.menu_dia_items mi on mi.tenant_id = md.tenant_id and mi.menu_id = md.id
join elius.items_catalogo ic on ic.tenant_id = mi.tenant_id and ic.id = mi.item_id
where md.fecha = current_date and md.activo and md.confirmado_en is not null;

-- Restaurante: lo que la cocina tiene pendiente, por estación
create view plugin_restaurant.v_cocina_pendiente with (security_invoker = true) as
select co.tenant_id, ec.nombre as estacion, co.id as comanda_id, o.numero as orden_numero, o.tipo_entrega,
       co.ronda, co.estado, co.enviada_en, now() - co.enviada_en as espera,
       ic.nombre as plato, ci.cantidad, ci.nota_cocina, ci.estado as estado_plato
from plugin_restaurant.comandas co
join plugin_restaurant.estaciones_cocina ec on ec.tenant_id = co.tenant_id and ec.id = co.estacion_id
join elius.ordenes o on o.tenant_id = co.tenant_id and o.id = co.orden_id
join plugin_restaurant.comanda_items ci on ci.tenant_id = co.tenant_id and ci.comanda_id = co.id
join elius.orden_items oi on oi.tenant_id = ci.tenant_id and oi.id = ci.orden_item_id
join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
where co.estado in ('recibida', 'en_preparacion');

-- Aerolínea: ocupación de cada vuelo
create view plugin_airline.v_ocupacion_vuelos with (security_invoker = true) as
select v.tenant_id, v.id as vuelo_id, v.numero_vuelo, v.salida_programada, v.estado,
       ao.codigo_iata as origen, ad.codigo_iata as destino, an.capacidad,
       coalesce(sum(tv.cupos_vendidos), 0) as vendidos,
       round(100.0 * coalesce(sum(tv.cupos_vendidos), 0) / an.capacidad, 1) as pct_ocupacion
from plugin_airline.vuelos v
join plugin_airline.rutas ru on ru.tenant_id = v.tenant_id and ru.id = v.ruta_id
join plugin_airline.aeropuertos ao on ao.id = ru.origen_id
join plugin_airline.aeropuertos ad on ad.id = ru.destino_id
join plugin_airline.aeronaves an on an.tenant_id = v.tenant_id and an.id = v.aeronave_id
left join plugin_airline.tarifas_vuelo tv on tv.tenant_id = v.tenant_id and tv.vuelo_id = v.id
group by v.tenant_id, v.id, ao.codigo_iata, ad.codigo_iata, an.capacidad;

-- Aerolínea: manifiesto de pasajeros por vuelo
create view plugin_airline.v_manifiesto with (security_invoker = true) as
select tv.tenant_id, tv.vuelo_id, v.numero_vuelo, v.salida_programada,
       c.nombres || coalesce(' ' || c.apellidos, '') as pasajero, rp.tipo_pasajero,
       t.numero_tiquete, t.silla, t.estado as estado_tiquete, t.checkin_en, r.codigo as localizador
from plugin_airline.tiquetes t
join plugin_airline.reserva_pasajeros rp on rp.tenant_id = t.tenant_id and rp.id = t.reserva_pasajero_id
join elius.contactos c on c.tenant_id = rp.tenant_id and c.id = rp.contacto_id
join elius.reservas r on r.tenant_id = rp.tenant_id and r.id = rp.reserva_id
join plugin_airline.tramos_reserva tr on tr.tenant_id = t.tenant_id and tr.id = t.tramo_id
join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
join plugin_airline.vuelos v on v.tenant_id = tv.tenant_id and v.id = tv.vuelo_id
where t.estado <> 'anulado';

grant select on all tables in schema elius, plugin_vet, plugin_restaurant, plugin_airline to authenticated, service_role, elius_app;

-- ---------- 3. Reportes agregados (usuario elius_consulta y Super Admin) ----------
-- Sin nombres, teléfonos ni contenidos: solo conteos y montos por tenant y mes.
create view reportes.v_uso_por_tenant as
select t.id as tenant_id, t.slug, t.vertical, t.estado, p.codigo as plan, m.mes,
       coalesce(m.conversaciones, 0) as conversaciones, coalesce(m.tokens, 0) as tokens,
       coalesce(m.costo_ia_usd, 0) as costo_ia_usd
from platform.tenants t
join platform.planes p on p.id = t.plan_id
left join (
  select cv.tenant_id, date_trunc('month', cv.iniciada_en)::date as mes, count(*) as conversaciones,
         sum(ll.tokens) as tokens, sum(ll.costo) as costo_ia_usd
  from elius.conversaciones cv
  left join (select tenant_id, conversacion_id, sum(tokens_entrada + tokens_salida) as tokens, sum(costo_usd) as costo
             from elius.consumos_llm group by tenant_id, conversacion_id) ll
    on ll.tenant_id = cv.tenant_id and ll.conversacion_id = cv.id
  group by cv.tenant_id, 2
) m on m.tenant_id = t.id;
comment on view reportes.v_uso_por_tenant is 'Uso mensual por tenant, sin datos personales';

create view reportes.v_ventas_por_tenant as
select o.tenant_id, t.slug, t.vertical, date_trunc('month', o.colocada_en)::date as mes,
       count(*) as ordenes, sum(o.total) as ventas
from elius.ordenes o join platform.tenants t on t.id = o.tenant_id
where o.estado not in ('cotizando', 'cancelada')
group by o.tenant_id, t.slug, t.vertical, 4;

create view reportes.v_resumen_tenants as
select t.id as tenant_id, t.slug, t.vertical, t.estado, p.codigo as plan,
       (select count(*) from platform.membresias m where m.tenant_id = t.id and m.estado = 'activo') as usuarios_activos,
       (select string_agg(pl.codigo, ', ') from platform.tenant_plugins tp join platform.plugins pl on pl.id = tp.plugin_id
         where tp.tenant_id = t.id and tp.habilitado) as plugins,
       t.creado_en
from platform.tenants t join platform.planes p on p.id = t.plan_id;
-- =============================================================================
-- ELIUS · Migración 0700 · Procedimientos (funciones RPC)
-- Operaciones de negocio que cambian varias tablas a la vez y deben ser atómicas.
-- Se llaman desde los paneles, Eli o las Edge Functions con supabase.rpc('nombre', {...}).
--
-- SECURITY INVOKER (por defecto): corren con los permisos de quien llama, así que
-- RLS sigue aplicando. Solo son SECURITY DEFINER los que necesitan crear filas que
-- el usuario aún no puede ver (crear un tenant, aceptar una invitación) o los que
-- solo puede ejecutar el backend (webhook de Factus, tareas programadas).
-- =============================================================================

-- =============================================================================
-- PLATFORM
-- =============================================================================

-- Crea un negocio: tenant, su Administrador, el plugin de su vertical, Eli y parámetros base (RN-P08)
create or replace function platform.crear_tenant(p_nombre text, p_slug text, p_vertical text, p_plan text default 'free')
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_tenant uuid;
  v_admin uuid;
begin
  if v_uid is null then
    raise exception 'Debe iniciar sesión para crear un negocio' using errcode = '42501';
  end if;
  insert into platform.tenants (plan_id, slug, nombre, vertical, fin_prueba)
  select id, lower(p_slug), p_nombre, p_vertical, current_date + 14 from platform.planes where codigo = p_plan and activo
  returning id into v_tenant;
  if v_tenant is null then
    raise exception 'El plan % no existe', p_plan;
  end if;

  select id into v_admin from platform.roles where codigo = 'administrador';
  insert into platform.membresias (tenant_id, usuario_id, rol_id, cargo, es_predeterminada)
  values (v_tenant, v_uid, v_admin, 'Dueño',
          not exists (select 1 from platform.membresias where usuario_id = v_uid and es_predeterminada));

  insert into platform.tenant_plugins (tenant_id, plugin_id, instalado_por, version_instalada)
  select v_tenant, p.id, v_uid, p.version from platform.plugins p where p_vertical = any (p.verticales) and p.activo;

  insert into elius.agentes (tenant_id, nombre, modelo_llm, prompt_sistema, tono, activo)
  values (v_tenant, 'Eli', 'por-definir', 'Eres Eli, el asistente de ' || p_nombre || '.',
          case p_vertical when 'veterinaria' then 'empatico' else 'cercano' end, true);

  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
  select v_tenant, x.clave, x.valor, x.tipo, x.descr from (values
    ('dias_anticipacion_max', case p_vertical when 'restaurante' then '120' else '365' end, 'numero', 'Días máximos para reservar con anticipación'),
    ('tolerancia_minutos_llegada', '20', 'numero', 'Minutos de espera antes de marcar no asistió'),
    ('umbral_grupo_grande', '20', 'numero', 'Personas a partir de las cuales se avisa al Administrador'),
    ('porcentaje_minimo_grupo', '80', 'porcentaje', 'Porcentaje del grupo que debe llegar'),
    ('politica_consignacion', 'No reembolsable; se puede reagendar según disponibilidad', 'texto', 'Política de la consignación de reservas')
  ) as x(clave, valor, tipo, descr);
  return v_tenant;
end $$;

-- Cambia el tenant que va en el JWT; el cliente debe refrescar la sesión después
create or replace function platform.cambiar_tenant(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not app.tiene_acceso_tenant(auth.uid(), p_tenant) then
    raise exception 'No pertenece a ese negocio' using errcode = '42501';
  end if;
  update platform.membresias set es_predeterminada = false where usuario_id = auth.uid() and es_predeterminada;
  update platform.membresias set es_predeterminada = true where usuario_id = auth.uid() and tenant_id = p_tenant;
end $$;

-- Invita a un usuario con un rol general. Devuelve el token una sola vez; se guarda su hash.
create or replace function platform.invitar_usuario(p_email text, p_rol text)
returns text language plpgsql set search_path = '' as $$
declare v_token text := encode(extensions.gen_random_bytes(24), 'hex');
begin
  insert into platform.invitaciones (tenant_id, rol_id, invitado_por, email, hash_token)
  select app.current_tenant_id(), r.id, auth.uid(), lower(p_email), encode(extensions.digest(v_token, 'sha256'), 'hex')
  from platform.roles r where r.codigo = p_rol and r.nivel = 'tenant';
  if not found then
    raise exception 'Rol % no válido para un negocio', p_rol;
  end if;
  return v_token;
end $$;

create or replace function platform.aceptar_invitacion(p_token text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_inv record; v_email text;
begin
  select email into v_email from auth.users where id = auth.uid();
  select * into v_inv from platform.invitaciones
  where hash_token = encode(extensions.digest(p_token, 'sha256'), 'hex') and aceptada_en is null and vence_en > now()
  for update;
  if not found or lower(v_inv.email) <> lower(v_email) then
    raise exception 'RN-P12: invitación inválida, vencida o de otro correo' using errcode = '42501';
  end if;
  insert into platform.membresias (tenant_id, usuario_id, rol_id, invitado_por, es_predeterminada)
  values (v_inv.tenant_id, auth.uid(), v_inv.rol_id, v_inv.invitado_por,
          not exists (select 1 from platform.membresias where usuario_id = auth.uid() and es_predeterminada));
  update platform.invitaciones set aceptada_en = now() where id = v_inv.id;
  return v_inv.tenant_id;
end $$;

-- Activa un acceso especial del plugin para un usuario (ej. historia clínica) — sección 10.2
create or replace function platform.otorgar_acceso_especial(p_membresia uuid, p_permiso text, p_motivo text default null,
                                                            p_vence timestamptz default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into platform.accesos_especiales (tenant_id, membresia_id, permiso_id, otorgado_por, motivo, vence_en)
  select app.current_tenant_id(), p_membresia, p.id, auth.uid(), p_motivo, p_vence
  from platform.permisos p where p.codigo = p_permiso and p.es_acceso_especial
  returning id into v_id;
  if v_id is null then
    raise exception '% no es un acceso especial', p_permiso;
  end if;
  return v_id;
end $$;

-- El Administrador autoriza a Soporte por unas horas (RN-P16)
create or replace function platform.autorizar_soporte(p_usuario_soporte uuid, p_motivo text, p_horas int default 24)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into platform.accesos_soporte (tenant_id, usuario_soporte_id, autorizado_por, motivo, vence_en)
  values (app.current_tenant_id(), p_usuario_soporte, auth.uid(), p_motivo, now() + make_interval(hours => p_horas))
  returning id into v_id;
  return v_id;
end $$;

-- =============================================================================
-- ELIUS · conversaciones
-- =============================================================================

-- RN-C21: solo un proceso atiende la conversación a la vez (bloqueo con vencimiento)
create or replace function elius.tomar_bloqueo(p_conversacion uuid, p_segundos int default 60)
returns boolean language sql set search_path = '' as $$
  with t as (
    update elius.conversaciones set bloqueada_en = now()
    where id = p_conversacion and tenant_id = app.current_tenant_id()
      and (bloqueada_en is null or bloqueada_en < now() - make_interval(secs => p_segundos))
    returning 1)
  select exists (select 1 from t);
$$;

create or replace function elius.soltar_bloqueo(p_conversacion uuid)
returns void language sql set search_path = '' as $$
  update elius.conversaciones set bloqueada_en = null where id = p_conversacion and tenant_id = app.current_tenant_id();
$$;

-- Eli pasa la conversación a una persona (RN-C18: el trigger asigna por turnos)
create or replace function elius.escalar_conversacion(p_conversacion uuid, p_motivo text, p_mensaje text default null,
                                                      p_resumen text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into elius.escalamientos (conversacion_id, motivo, mensaje_cliente, resumen)
  values (p_conversacion, p_motivo, p_mensaje, p_resumen) returning id into v_id;
  return v_id;
end $$;

-- Un Operador toma la conversación: Eli deja de responder (RN-C19)
create or replace function elius.tomar_conversacion(p_conversacion uuid)
returns void language plpgsql set search_path = '' as $$
begin
  update elius.conversaciones set estado = 'humano', asignado_a = app.mi_membresia()
  where id = p_conversacion and tenant_id = app.current_tenant_id();
  if not found then
    raise exception 'Conversación no encontrada' using errcode = 'P0002';
  end if;
end $$;

-- Devuelve la conversación a Eli y cierra sus escalamientos abiertos
create or replace function elius.devolver_a_eli(p_conversacion uuid)
returns void language plpgsql set search_path = '' as $$
begin
  update elius.escalamientos set resuelto_en = now(), resuelto_por = app.mi_membresia()
  where conversacion_id = p_conversacion and tenant_id = app.current_tenant_id() and resuelto_en is null;
  update elius.conversaciones set estado = 'en_progreso', asignado_a = null
  where id = p_conversacion and tenant_id = app.current_tenant_id();
end $$;

create or replace function elius.resolver_escalamiento(p_escalamiento uuid)
returns void language sql set search_path = '' as $$
  update elius.escalamientos set resuelto_en = now(), resuelto_por = app.mi_membresia()
  where id = p_escalamiento and tenant_id = app.current_tenant_id() and resuelto_en is null;
$$;

-- RN-C20: interruptor de emergencia de Eli
create or replace function elius.encender_eli(p_activo boolean)
returns void language plpgsql set search_path = '' as $$
begin
  if not app.puede('configuracion', 'total') then
    raise exception 'RN-C20: solo el Administrador o Soporte pueden apagar o encender a Eli' using errcode = '42501';
  end if;
  update elius.agentes set activo = p_activo
  where tenant_id = app.current_tenant_id()
    and id = (select id from elius.agentes where tenant_id = app.current_tenant_id() order by version desc limit 1);
end $$;

-- =============================================================================
-- ELIUS · reservas
-- =============================================================================

-- Agenda una reserva y ocupa sus recursos. Valida horario (RN-R02) y capacidad (RN-R01).
-- Los cruces los impide la restricción de exclusión (RN-C07).
create or replace function elius.agendar_reserva(p_contacto uuid, p_tipo text, p_inicio timestamptz, p_fin timestamptz,
                                                 p_personas int default 1, p_recursos uuid[] default '{}',
                                                 p_notas text default null, p_conversacion uuid default null)
returns uuid language plpgsql set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_id uuid;
  v_capacidad int;
  v_zona text;
  v_dia int := extract(isodow from p_inicio at time zone 'America/Bogota');
begin
  select t.zona_horaria into v_zona from platform.tenants t where t.id = v_tenant;
  v_dia := extract(isodow from p_inicio at time zone coalesce(v_zona, 'America/Bogota'));
  if exists (select 1 from elius.horarios_atencion h where h.tenant_id = v_tenant and h.recurso_id is null)
     and not exists (
       select 1 from elius.horarios_atencion h
       where h.tenant_id = v_tenant and h.recurso_id is null and h.dia_semana = v_dia
         and (p_inicio at time zone coalesce(v_zona, 'America/Bogota'))::time >= h.abre
         and (p_fin at time zone coalesce(v_zona, 'America/Bogota'))::time <= h.cierra
         and current_date >= h.vigente_desde and (h.vigente_hasta is null or current_date <= h.vigente_hasta)) then
    raise exception 'RN-R02: el negocio no atiende en ese horario' using errcode = '23514';
  end if;

  if cardinality(p_recursos) > 0 and p_tipo = 'mesa' then
    select coalesce(sum(capacidad), 0) into v_capacidad from elius.recursos
    where tenant_id = v_tenant and id = any (p_recursos) and activo;
    if v_capacidad < p_personas then
      raise exception 'RN-R01: las mesas elegidas tienen capacidad para % y la reserva es de %', v_capacidad, p_personas
        using errcode = '23514';
    end if;
  end if;

  insert into elius.reservas (contacto_id, conversacion_id, tipo, inicio, fin, personas, notas, creada_por_eli)
  values (p_contacto, p_conversacion, p_tipo, p_inicio, p_fin, p_personas, p_notas, app.mi_rol() = 'eli')
  returning id into v_id;

  insert into elius.asignaciones_recurso (reserva_id, recurso_id, inicio, fin)
  select v_id, r, p_inicio, p_fin from unnest(p_recursos) r;
  return v_id;
end $$;

-- Registra la llegada del cliente (operación del día)
create or replace function elius.marcar_llegada(p_reserva uuid)
returns void language sql set search_path = '' as $$
  update elius.reservas set llegada_en = now(), estado = 'asistio', visto = true
  where id = p_reserva and tenant_id = app.current_tenant_id() and estado = 'confirmada';
$$;

-- RN-R07: tarea programada. Marca no asistió después de la tolerancia y libera los recursos.
-- Solo para el backend (cron de Supabase o n8n), en el tenant fijado con app.tenant_id.
create or replace function elius.marcar_no_asistidas()
returns int language plpgsql set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_n int;
        v_tol int := coalesce(app.parametro(v_tenant, 'tolerancia_minutos_llegada')::int, 20);
begin
  with r as (
    update elius.reservas set estado = 'no_asistio'
    where tenant_id = v_tenant and estado = 'confirmada' and llegada_en is null
      and inicio < now() - make_interval(mins => v_tol)
    returning id)
  update elius.asignaciones_recurso a set estado = 'liberada'
  from r where a.tenant_id = v_tenant and a.reserva_id = r.id;
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- =============================================================================
-- ELIUS · órdenes y pagos
-- =============================================================================

create or replace function elius.crear_orden(p_contacto uuid, p_canal text default 'whatsapp', p_tipo_entrega text default 'recoger',
                                             p_reserva uuid default null, p_conversacion uuid default null,
                                             p_direccion uuid default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into elius.ordenes (contacto_id, canal_venta, tipo_entrega, reserva_id, conversacion_id, direccion_entrega_id)
  values (p_contacto, p_canal, p_tipo_entrega, p_reserva, p_conversacion, p_direccion)
  returning id into v_id;
  return v_id;
end $$;

create or replace function elius.agregar_item(p_orden uuid, p_item uuid, p_cantidad numeric default 1, p_notas text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid;
begin
  insert into elius.orden_items (orden_id, item_id, cantidad, notas)
  values (p_orden, p_item, p_cantidad, p_notas) returning id into v_id;   -- precio y total los pone el trigger T41
  return v_id;
end $$;

-- Eli registra el comprobante que mandó el cliente; el monto esperado es el saldo de la orden
create or replace function elius.registrar_comprobante(p_conversacion uuid, p_orden uuid, p_monto_leido numeric,
       p_remitente text default null, p_destinatario text default null, p_app text default null,
       p_referencia text default null, p_fecha_texto text default null, p_hash text default null,
       p_url text default null, p_media_id text default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid; v_esperado numeric;
begin
  select saldo_pendiente into v_esperado from elius.v_saldo_ordenes
  where orden_id = p_orden and tenant_id = app.current_tenant_id();
  insert into elius.comprobantes_pago (orden_id, conversacion_id, monto_leido, monto_esperado, remitente, destinatario,
                                       app_origen, referencia, fecha_texto, hash_archivo, url_archivo, media_id)
  values (p_orden, p_conversacion, p_monto_leido, v_esperado, p_remitente, p_destinatario,
          p_app, p_referencia, p_fecha_texto, p_hash, p_url, p_media_id)
  returning id into v_id;
  return v_id;
end $$;

-- Una persona aprueba el comprobante. Atómico (DT corrige el problema 11 de Potrillos):
-- crea el pago, deja el resto contra entrega si se pide, y el trigger T51 confirma la orden.
create or replace function elius.aprobar_comprobante(p_comprobante uuid, p_resto_contra_entrega boolean default false)
returns text language plpgsql set search_path = '' as $$
declare
  v_c record;
  v_saldo numeric;
  v_tenant uuid := app.current_tenant_id();
begin
  if not app.puede('pagos', 'escritura') then
    raise exception 'No tiene permiso para aprobar pagos' using errcode = '42501';
  end if;
  select * into v_c from elius.comprobantes_pago where id = p_comprobante and tenant_id = v_tenant for update;
  if not found or v_c.veredicto <> 'pendiente' then
    raise exception 'El comprobante no existe o ya fue decidido' using errcode = '23514';
  end if;
  if v_c.orden_id is null then
    raise exception 'Asocie el comprobante a una orden antes de aprobarlo' using errcode = '23514';
  end if;

  update elius.comprobantes_pago set veredicto = 'aprobado', decidido_por = app.mi_membresia(), decidido_en = now()
  where id = p_comprobante;

  select saldo_pendiente into v_saldo from elius.v_saldo_ordenes where orden_id = v_c.orden_id and tenant_id = v_tenant;
  if v_saldo <= 0 then
    return 'ya_pagada';   -- comprobante repetido del mismo pago: no se cobra dos veces
  end if;

  if p_resto_contra_entrega and coalesce(v_c.monto_leido, 0) < v_saldo then
    insert into elius.entregas (orden_id, cobro_contra_entrega)
    values (v_c.orden_id, v_saldo - coalesce(v_c.monto_leido, 0));
  end if;

  insert into elius.pagos (orden_id, comprobante_id, metodo, proveedor, referencia_externa, monto, estado)
  values (v_c.orden_id, p_comprobante, 'transferencia', v_c.app_origen, v_c.referencia,
          least(coalesce(v_c.monto_leido, v_saldo), v_saldo), 'aprobado');

  select saldo_pendiente into v_saldo from elius.v_saldo_ordenes where orden_id = v_c.orden_id and tenant_id = v_tenant;
  return case when v_saldo > 0 then 'pago_parcial' else 'pagada' end;
end $$;

create or replace function elius.rechazar_comprobante(p_comprobante uuid, p_motivo text)
returns void language plpgsql set search_path = '' as $$
begin
  update elius.comprobantes_pago set veredicto = 'rechazado', motivo = p_motivo,
         decidido_por = app.mi_membresia(), decidido_en = now()
  where id = p_comprobante and tenant_id = app.current_tenant_id() and veredicto = 'pendiente';
  if not found then
    raise exception 'El comprobante no existe o ya fue decidido' using errcode = '23514';
  end if;
end $$;

-- ---------- Factus Pay (DT-18) ----------------------------------------------------
-- Decide la estrategia de cobro de una orden: llave Bre-B con Factus si el negocio
-- la tiene activa y el monto cabe en sus límites; si no, comprobante tradicional.
create or replace function elius.estrategia_cobro(p_monto numeric)
returns text language sql stable set search_path = '' as $$
  select case when exists (
           select 1 from elius.pasarelas_pago p
           where p.tenant_id = app.current_tenant_id() and p.activa and p.proveedor = 'factus_pay'
             and p_monto between p.monto_minimo and p.monto_maximo)
         then 'llave_breb_factus' else 'comprobante' end;
$$;

-- La Edge Function llama a POST /v1/collections y guarda aquí lo que respondió Factus
create or replace function elius.registrar_recaudo(p_orden uuid, p_codigo text, p_monto numeric, p_llave text,
                                                   p_url_qr text, p_expira timestamptz)
returns uuid language plpgsql set search_path = '' as $$
declare v_pasarela uuid; v_id uuid;
begin
  select id into v_pasarela from elius.pasarelas_pago
  where tenant_id = app.current_tenant_id() and activa and proveedor = 'factus_pay'
    and p_monto between monto_minimo and monto_maximo
  order by ambiente desc limit 1;
  if v_pasarela is null then
    raise exception 'RN-C23: sin pasarela activa para este monto; use el comprobante tradicional' using errcode = '23514';
  end if;
  insert into elius.recaudos (orden_id, pasarela_id, codigo_referencia, monto, llave_breb, url_qr, expira_en)
  values (p_orden, v_pasarela, p_codigo, p_monto, p_llave, p_url_qr, p_expira)
  on conflict (pasarela_id, codigo_referencia) do update
    set expira_en = excluded.expira_en, llave_breb = excluded.llave_breb, url_qr = excluded.url_qr,
        estado = case when elius.recaudos.estado = 'vencido' then 'listo' else elius.recaudos.estado end,
        renovaciones = elius.recaudos.renovaciones + 1
  returning id into v_id;
  update elius.ordenes set estado = 'esperando_pago'
  where tenant_id = app.current_tenant_id() and id = p_orden and estado = 'cotizando';
  return v_id;
end $$;

-- Webhook de Factus (RN-C24). Lo llama SOLO la Edge Function, con el tenant fijado.
-- La Edge Function compara ?key= en tiempo constante y pasa el resultado en p_clave_valida.
-- Primero se guarda la notificación (para poder responder 2xx), luego se aplica. Idempotente.
create or replace function elius.procesar_webhook_factus(p_pasarela uuid, p_clave_valida boolean, p_carga jsonb)
returns text language plpgsql set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_ref text := p_carga -> 'data' ->> 'reference_code';
  v_monto numeric := (p_carga -> 'data' ->> 'amount')::numeric;
  v_notif uuid;
  v_rec record;
  v_recaudo uuid;
  v_resultado text;
begin
  if auth.uid() is not null then
    raise exception 'Solo el backend procesa webhooks' using errcode = '42501';
  end if;
  insert into elius.notificaciones_pasarela (pasarela_id, codigo_referencia, carga, clave_valida)
  values (p_pasarela, coalesce(v_ref, ''), p_carga, p_clave_valida) returning id into v_notif;

  if not p_clave_valida or p_carga -> 'data' ->> 'status' is distinct from 'paid' then
    v_resultado := 'rechazado';
  else
    select * into v_rec from elius.recaudos
    where tenant_id = v_tenant and pasarela_id = p_pasarela and codigo_referencia = v_ref for update;
    v_recaudo := v_rec.id;
    if not found then
      v_resultado := 'sin_recaudo';
    elsif v_rec.estado = 'pagado' then
      v_resultado := 'duplicado';
    elsif v_monto is distinct from v_rec.monto then
      v_resultado := 'rechazado';   -- Factus solo acepta el monto exacto: si no coincide, no se aplica
    else
      update elius.recaudos set estado = 'pagado', cobrado_en = now(),
             pagador_nombre = p_carga -> 'data' -> 'payer' ->> 'name',
             pagador_documento = nullif(concat_ws(' ', p_carga -> 'data' -> 'payer' ->> 'document_type',
                                                       p_carga -> 'data' -> 'payer' ->> 'document_number'), '')
      where id = v_rec.id;          -- T54 crea el pago y T51 confirma la orden
      v_resultado := 'aplicado';
    end if;
  end if;
  update elius.notificaciones_pasarela set procesada_en = now(), resultado = v_resultado, recaudo_id = v_recaudo
  where id = v_notif;
  return v_resultado;
end $$;

-- =============================================================================
-- PLUGINS
-- =============================================================================

-- Restaurante: el dueño confirma el menú del día; sin confirmar, Eli no lo ofrece (RN-R11)
create or replace function plugin_restaurant.confirmar_menu_dia(p_menu uuid)
returns void language sql set search_path = '' as $$
  update plugin_restaurant.menus_dia set confirmado_por = app.mi_membresia(), confirmado_en = now()
  where id = p_menu and tenant_id = app.current_tenant_id();
$$;

-- Restaurante: agrega una opción a una línea respetando el máximo del grupo (RN-R04)
create or replace function plugin_restaurant.agregar_opcion(p_linea uuid, p_opcion uuid, p_cantidad int default 1)
returns uuid language plpgsql set search_path = '' as $$
declare v_grupo uuid; v_max int; v_actual int; v_id uuid; v_item uuid;
begin
  select grupo_id into v_grupo from plugin_restaurant.opciones_modificador where id = p_opcion and disponible;
  select item_id into v_item from elius.orden_items where id = p_linea;
  select maximo into v_max from plugin_restaurant.item_grupos_modificador where item_id = v_item and grupo_id = v_grupo;
  if v_max is null then
    raise exception 'RN-R04: esa opción no aplica a este plato' using errcode = '23514';
  end if;
  select coalesce(sum(o.cantidad), 0) into v_actual from plugin_restaurant.orden_item_opciones o
  join plugin_restaurant.opciones_modificador om on om.id = o.opcion_id
  where o.orden_item_id = p_linea and om.grupo_id = v_grupo;
  if v_actual + p_cantidad > v_max then
    raise exception 'RN-R04: máximo % opciones de este grupo', v_max using errcode = '23514';
  end if;
  insert into plugin_restaurant.orden_item_opciones (orden_item_id, opcion_id, cantidad)
  values (p_linea, p_opcion, p_cantidad) returning id into v_id;
  return v_id;
end $$;

-- Veterinaria: registra una vacuna y calcula la próxima dosis (RN-V05)
-- La vacuna del catálogo puede traer en atributos {"refuerzo_dias": 365}
create or replace function plugin_vet.registrar_vacuna(p_mascota uuid, p_vacuna uuid, p_lote text,
                                                       p_atencion uuid default null, p_proxima date default null)
returns uuid language plpgsql set search_path = '' as $$
declare v_id uuid; v_dias int;
begin
  select (atributos ->> 'refuerzo_dias')::int into v_dias from elius.items_catalogo where id = p_vacuna;
  insert into plugin_vet.aplicaciones_vacuna (mascota_id, vacuna_id, atencion_id, aplicada_por, lote, proxima_dosis_en)
  values (p_mascota, p_vacuna, p_atencion, app.mi_membresia(), p_lote,
          coalesce(p_proxima, current_date + v_dias))
  returning id into v_id;
  return v_id;
end $$;

-- Aerolínea: check-in entre 48 h y 1 h antes de la salida (RN-A08)
create or replace function plugin_airline.hacer_checkin(p_tiquete uuid, p_silla text)
returns void language plpgsql set search_path = '' as $$
declare v_salida timestamptz;
begin
  select v.salida_programada into v_salida
  from plugin_airline.tiquetes t
  join plugin_airline.tramos_reserva tr on tr.id = t.tramo_id
  join plugin_airline.tarifas_vuelo tv on tv.id = tr.tarifa_vuelo_id
  join plugin_airline.vuelos v on v.id = tv.vuelo_id
  where t.id = p_tiquete and t.estado = 'emitido';
  if v_salida is null then
    raise exception 'Tiquete no encontrado o no emitido' using errcode = 'P0002';
  end if;
  if now() < v_salida - interval '48 hours' or now() > v_salida - interval '1 hour' then
    raise exception 'RN-A08: el check-in abre 48 h y cierra 1 h antes de la salida' using errcode = '23514';
  end if;
  update plugin_airline.tiquetes set silla = p_silla, checkin_en = now() where id = p_tiquete;
end $$;

-- ---------- Permisos de ejecución ----------
grant execute on all functions in schema platform, elius, plugin_vet, plugin_restaurant, plugin_airline
  to authenticated, service_role, elius_app;
-- En PostgreSQL toda función nace ejecutable por PUBLIC: hay que quitárselo explícitamente
revoke execute on function elius.procesar_webhook_factus(uuid, boolean, jsonb) from public, anon, authenticated;
revoke execute on function elius.marcar_no_asistidas() from public, anon, authenticated;
grant execute on function elius.procesar_webhook_factus(uuid, boolean, jsonb) to service_role, elius_app;
grant execute on function elius.marcar_no_asistidas() to service_role, elius_app;
-- =============================================================================
-- ELIUS · Migración 0800 · Usuarios de conexión a PostgreSQL y sus permisos
-- "Conexión con usuarios: Admin, Privilegios, Consulting (non Super Admin)"
-- Sección 10.3 del levantamiento y DT-13.
--
--   Usuario         Puede                                            No puede
--   elius_admin     crear objetos, leer/escribir todo, otorgar       ser superusuario, saltarse RLS,
--                   permisos (WITH GRANT OPTION)                     ver varios tenants a la vez
--   elius_app       leer, insertar, actualizar, borrar en tablas     cambiar la estructura, leer la
--                   de negocio y ejecutar procedimientos             auditoría completa, saltarse RLS
--   elius_consulta  leer las vistas agregadas del esquema reportes   escribir, leer tablas, ver datos
--                                                                    personales
--
-- Ninguno tiene SUPERUSER ni BYPASSRLS (ver migración 0100). Como no son dueños de las
-- tablas, RLS les aplica: para trabajar fijan el tenant con
--   select set_config('app.tenant_id', '<uuid>', false);
-- y solo ven ese tenant.
-- =============================================================================

-- ---------- elius_admin: administrador del esquema --------------------------------
grant usage, create on schema platform, elius, ext, audit, app, reportes, plugin_vet, plugin_restaurant, plugin_airline
  to elius_admin;
grant all privileges on all tables in schema platform, elius, ext, audit, plugin_vet, plugin_restaurant, plugin_airline, reportes
  to elius_admin with grant option;
grant all privileges on all sequences in schema platform, elius, ext, audit, plugin_vet, plugin_restaurant, plugin_airline
  to elius_admin with grant option;
grant execute on all functions in schema app, platform, elius, plugin_vet, plugin_restaurant, plugin_airline
  to elius_admin with grant option;
grant usage on schema auth to elius_admin;

-- ---------- elius_app: privilegios de la aplicación ---------------------------------
-- (los GRANT de tablas y funciones de negocio se dieron en 0400 y 0700)
revoke truncate, references, trigger on all tables in schema platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline
  from elius_app;
revoke all on audit.registros_auditoria from elius_app;
grant select on audit.registros_auditoria to elius_app;           -- RLS: solo su tenant y con permiso de auditoría
revoke insert, update, delete on platform.planes, platform.roles, platform.permisos, platform.plugins, platform.rol_permisos
  from elius_app;                                                  -- catálogos globales: solo lectura
grant usage on schema auth to elius_app;

-- ---------- elius_consulta: solo vistas agregadas (consultoría) ---------------------
revoke all on all tables in schema platform, elius, ext, audit, plugin_vet, plugin_restaurant, plugin_airline
  from elius_consulta;
grant usage on schema reportes to elius_consulta;
grant select on all tables in schema reportes to elius_consulta;
-- Las vistas de reportes corren con los permisos de su dueño y solo devuelven conteos
-- y montos por tenant y mes, sin nombres, teléfonos ni contenidos.

-- ---------- Nada para anon ni para PUBLIC ------------------------------------------
revoke all on all tables in schema platform, elius, ext, audit, reportes, plugin_vet, plugin_restaurant, plugin_airline
  from anon, public;
revoke create on schema public from public;

-- ---------- Objetos futuros heredan los mismos permisos ------------------------------
alter default privileges in schema platform, elius, ext, plugin_vet, plugin_restaurant, plugin_airline
  grant select, insert, update, delete on tables to authenticated, service_role, elius_app;
alter default privileges in schema reportes grant select on tables to elius_consulta;
-- =============================================================================
-- ELIUS · Migración 0900 · Datos base
-- Planes, los 6 roles generales, plugins, catálogo de permisos y la matriz
-- rol → permiso → nivel (sección 10.1 del levantamiento), y aeropuertos de referencia.
-- =============================================================================

insert into platform.planes (codigo, nombre, precio_mensual, moneda, max_usuarios, max_conversaciones_mes, max_tokens_mes) values
  ('free',       'Prueba',     0,   'USD',  3,    300,   1000000),
  ('starter',    'Emprende',   29,  'USD',  5,   2000,   5000000),
  ('pro',        'Crece',      79,  'USD', 15,  10000,  25000000),
  ('enterprise', 'Empresa',    249, 'USD', 100, 100000, 250000000);

-- ---------- Los 6 roles generales y fijos (DT-05) ----------------------------------
insert into platform.roles (codigo, nombre, nivel, descripcion, orden) values
  ('super_admin',   'Super Admin',   'plataforma', 'Equipo Elius: administra la plataforma, tenants, planes y plugins. No ve datos de negocio.', 1),
  ('soporte',       'Soporte',       'plataforma', 'Equipo Elius: entra a un tenant solo con autorización del Administrador, por tiempo limitado y auditado.', 2),
  ('administrador', 'Administrador', 'tenant',     'Dueño o gerente: configura su negocio sin conocimientos técnicos.', 3),
  ('operador',      'Operador',      'tenant',     'Atiende el día a día: recepción, veterinario, mesero, cajero, cocina, domiciliario, ventas.', 4),
  ('analista',      'Analista',      'tenant',     'Consulta reportes y métricas y los exporta. No modifica nada.', 5),
  ('eli',           'Eli',           'tenant',     'Identidad del agente de IA: crea contactos, conversaciones, reservas y órdenes.', 6);

-- ---------- Plugins (microkernel, DT-09) --------------------------------------------
insert into platform.plugins (codigo, nombre, esquema, verticales, manifiesto) values
  ('vet', 'Veterinaria', 'plugin_vet', '{veterinaria}',
   '{"modulos": ["vet.pacientes"], "accesos_especiales": ["vet.historia_clinica"], "cargos": ["Veterinario", "Recepción", "Auxiliar"]}'),
  ('restaurant', 'Restaurante', 'plugin_restaurant', '{restaurante}',
   '{"modulos": ["restaurant.menu", "restaurant.cocina"], "accesos_especiales": ["restaurant.reversos"], "cargos": ["Mesero", "Cajero", "Cocina", "Domiciliario"]}'),
  ('airline', 'Aerolínea', 'plugin_airline', '{aerolinea}',
   '{"modulos": ["airline.vuelos", "airline.reservas"], "accesos_especiales": ["airline.documentos"], "cargos": ["Agente de counter", "Ventas", "Operaciones"]}');

-- ---------- Catálogo de permisos (módulos) -------------------------------------------
insert into platform.permisos (plugin_id, codigo, modulo, descripcion, es_acceso_especial, protege_dato_sensible)
select (select id from platform.plugins where codigo = x.plugin), x.codigo, x.modulo, x.descr, x.especial, x.sensible
from (values
  (null, 'plataforma',     'plataforma',    'Tenants, planes y plugins disponibles', false, false),
  (null, 'configuracion',  'configuracion', 'Configuración del negocio, de Eli, canales, parámetros y pasarelas', false, false),
  (null, 'usuarios',       'usuarios',      'Usuarios, invitaciones, accesos especiales y de soporte', false, false),
  (null, 'contactos',      'contactos',     'Clientes finales, direcciones y consentimientos', false, false),
  (null, 'conversaciones', 'conversaciones','Conversaciones con Eli, mensajes y escalamientos', false, false),
  (null, 'catalogo',       'catalogo',      'Productos, servicios, paquetes, adicionales y fotos', false, false),
  (null, 'reservas',       'reservas',      'Recursos, horarios, reservas y asignaciones', false, false),
  (null, 'ordenes',        'ordenes',       'Órdenes, líneas y entregas', false, false),
  (null, 'pagos',          'pagos',         'Pagos, comprobantes y recaudos', false, false),
  (null, 'conocimiento',   'conocimiento',  'Base de conocimiento de Eli', false, false),
  (null, 'reportes',       'reportes',      'Métricas, embudo y consumo de IA', false, false),
  (null, 'auditoria',      'auditoria',     'Bitácora de cambios', false, false),
  (null, 'ext',            'ext',           'Extensión de Chrome', false, false),
  ('vet',        'vet.pacientes',        'veterinaria', 'Mascotas, propietarios, atenciones y vacunas', false, false),
  ('vet',        'vet.historia_clinica', 'veterinaria', 'Historia clínica (acceso especial para veterinarios)', true, true),
  ('restaurant', 'restaurant.menu',      'restaurante', 'Menú, alérgenos, modificadores y menú del día', false, false),
  ('restaurant', 'restaurant.cocina',    'restaurante', 'Comandas, estaciones, opciones y celebraciones', false, false),
  ('restaurant', 'restaurant.reversos',  'restaurante', 'Reversar pedidos pagados (acceso especial)', true, false),
  ('airline',    'airline.vuelos',       'aerolinea',   'Aeronaves, rutas, vuelos y tarifas', false, false),
  ('airline',    'airline.reservas',     'aerolinea',   'Pasajeros, tramos, tiquetes y equipaje', false, false),
  ('airline',    'airline.documentos',   'aerolinea',   'Documentos y necesidades de salud de pasajeros (acceso especial)', true, true)
) as x(plugin, codigo, modulo, descr, especial, sensible);

-- ---------- Matriz rol → permiso → nivel (sección 10.1) -------------------------------
insert into platform.rol_permisos (rol_id, permiso_id, nivel, origen)
select r.id, p.id, x.nivel, case when x.permiso like '%.%' then split_part(x.permiso, '.', 1) else 'nucleo' end
from (values
  -- Super Admin: solo la plataforma
  ('super_admin', 'plataforma', 'total'),
  -- Soporte: lee la plataforma y entra al negocio solo con autorización
  ('soporte', 'plataforma', 'lectura'),
  ('soporte', 'configuracion', 'con_autorizacion'), ('soporte', 'usuarios', 'con_autorizacion'),
  ('soporte', 'contactos', 'con_autorizacion'), ('soporte', 'conversaciones', 'con_autorizacion'),
  ('soporte', 'catalogo', 'con_autorizacion'), ('soporte', 'reservas', 'con_autorizacion'),
  ('soporte', 'ordenes', 'con_autorizacion'), ('soporte', 'pagos', 'con_autorizacion'),
  ('soporte', 'conocimiento', 'con_autorizacion'), ('soporte', 'reportes', 'con_autorizacion'),
  ('soporte', 'ext', 'con_autorizacion'), ('soporte', 'vet.pacientes', 'con_autorizacion'),
  ('soporte', 'restaurant.menu', 'con_autorizacion'), ('soporte', 'restaurant.cocina', 'con_autorizacion'),
  ('soporte', 'airline.vuelos', 'con_autorizacion'), ('soporte', 'airline.reservas', 'con_autorizacion'),
  -- Administrador: todo su negocio, incluidos los datos sensibles
  ('administrador', 'configuracion', 'total'), ('administrador', 'usuarios', 'total'),
  ('administrador', 'contactos', 'total'), ('administrador', 'conversaciones', 'total'),
  ('administrador', 'catalogo', 'total'), ('administrador', 'reservas', 'total'),
  ('administrador', 'ordenes', 'total'), ('administrador', 'pagos', 'total'),
  ('administrador', 'conocimiento', 'total'), ('administrador', 'reportes', 'total'),
  ('administrador', 'auditoria', 'lectura'), ('administrador', 'ext', 'total'),
  ('administrador', 'vet.pacientes', 'total'), ('administrador', 'vet.historia_clinica', 'total'),
  ('administrador', 'restaurant.menu', 'total'), ('administrador', 'restaurant.cocina', 'total'),
  ('administrador', 'restaurant.reversos', 'total'),
  ('administrador', 'airline.vuelos', 'total'), ('administrador', 'airline.reservas', 'total'),
  ('administrador', 'airline.documentos', 'total'),
  -- Operador: el día a día; lo sensible solo con acceso especial
  ('operador', 'contactos', 'escritura'), ('operador', 'conversaciones', 'escritura'),
  ('operador', 'reservas', 'escritura'), ('operador', 'ordenes', 'escritura'), ('operador', 'pagos', 'escritura'),
  ('operador', 'catalogo', 'lectura'), ('operador', 'conocimiento', 'lectura'), ('operador', 'ext', 'escritura'),
  ('operador', 'vet.pacientes', 'escritura'),
  ('operador', 'restaurant.menu', 'lectura'), ('operador', 'restaurant.cocina', 'escritura'),
  ('operador', 'airline.vuelos', 'lectura'), ('operador', 'airline.reservas', 'escritura'),
  -- Analista: solo lectura y reportes
  ('analista', 'contactos', 'lectura'), ('analista', 'conversaciones', 'lectura'), ('analista', 'catalogo', 'lectura'),
  ('analista', 'reservas', 'lectura'), ('analista', 'ordenes', 'lectura'), ('analista', 'pagos', 'lectura'),
  ('analista', 'conocimiento', 'lectura'), ('analista', 'reportes', 'lectura'),
  ('analista', 'vet.pacientes', 'lectura'), ('analista', 'restaurant.menu', 'lectura'),
  ('analista', 'restaurant.cocina', 'lectura'), ('analista', 'airline.vuelos', 'lectura'),
  ('analista', 'airline.reservas', 'lectura'),
  -- Eli: atiende clientes; no ve usuarios, auditoría ni datos sensibles
  ('eli', 'contactos', 'escritura'), ('eli', 'conversaciones', 'escritura'), ('eli', 'reservas', 'escritura'),
  ('eli', 'ordenes', 'escritura'), ('eli', 'pagos', 'escritura'), ('eli', 'catalogo', 'lectura'),
  ('eli', 'conocimiento', 'lectura'), ('eli', 'configuracion', 'lectura'), ('eli', 'reportes', 'escritura'),
  ('eli', 'vet.pacientes', 'escritura'), ('eli', 'restaurant.menu', 'lectura'), ('eli', 'restaurant.cocina', 'escritura'),
  ('eli', 'airline.vuelos', 'lectura'), ('eli', 'airline.reservas', 'escritura')
) as x(rol, permiso, nivel)
join platform.roles r on r.codigo = x.rol
join platform.permisos p on p.codigo = x.permiso;

-- ---------- Aeropuertos de referencia (RN-A01, códigos IATA) --------------------------
insert into plugin_airline.aeropuertos (codigo_iata, nombre, ciudad, pais, zona_horaria) values
  ('BOG', 'El Dorado', 'Bogotá', 'CO', 'America/Bogota'),
  ('MDE', 'José María Córdova', 'Rionegro', 'CO', 'America/Bogota'),
  ('CLO', 'Alfonso Bonilla Aragón', 'Cali', 'CO', 'America/Bogota'),
  ('CTG', 'Rafael Núñez', 'Cartagena', 'CO', 'America/Bogota'),
  ('BAQ', 'Ernesto Cortissoz', 'Barranquilla', 'CO', 'America/Bogota'),
  ('SMR', 'Simón Bolívar', 'Santa Marta', 'CO', 'America/Bogota'),
  ('BGA', 'Palonegro', 'Bucaramanga', 'CO', 'America/Bogota'),
  ('PEI', 'Matecaña', 'Pereira', 'CO', 'America/Bogota'),
  ('ADZ', 'Gustavo Rojas Pinilla', 'San Andrés', 'CO', 'America/Bogota'),
  ('MIA', 'Miami International', 'Miami', 'US', 'America/New_York'),
  ('MAD', 'Adolfo Suárez Madrid-Barajas', 'Madrid', 'ES', 'Europe/Madrid'),
  ('MEX', 'Benito Juárez', 'Ciudad de México', 'MX', 'America/Mexico_City');
-- =============================================================================
-- ELIUS · Migración 1000 · Funciones para las Edge Functions (solo service_role)
-- Factus Pay (DT-18) y secretos en Supabase Vault.
-- Viven en el esquema elius (expuesto en la API) para que la Edge Function pueda
-- llamarlas con supabase.rpc(), pero solo service_role tiene permiso de ejecutarlas.
-- Llevan el prefijo srv_ para distinguirlas de las que usan los paneles.
-- =============================================================================

-- Lee un secreto de Supabase Vault (credenciales de Factus, token de WhatsApp…).
-- Solo la usa el backend; nunca un usuario. En un PostgreSQL sin Vault la función
-- se crea igual (plpgsql) pero no se puede ejecutar.
create or replace function elius.srv_secreto(p_id uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  execute 'select decrypted_secret from vault.decrypted_secrets where id = $1' into v using p_id;
  return v;
end $$;

-- Rota un secreto (por ejemplo, el token de Factus cuando la API responde 401)
create or replace function elius.srv_actualizar_secreto(p_id uuid, p_valor text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  execute 'select vault.update_secret($1, $2)' using p_id, p_valor;
end $$;

-- Datos que la Edge Function del webhook necesita de la pasarela (sin exponerla a usuarios)
create or replace function elius.srv_pasarela_webhook(p_pasarela uuid)
returns table (tenant_id uuid, ambiente text, referencia_clave_webhook uuid, referencia_credenciales uuid, activa boolean)
language sql stable security definer set search_path = '' as $$
  select p.tenant_id, p.ambiente, p.referencia_clave_webhook, p.referencia_credenciales, p.activa
  from elius.pasarelas_pago p where p.id = p_pasarela;
$$;

-- Punto de entrada del webhook de Factus para la Edge Function.
-- Fija el tenant de la pasarela solo dentro de esta transacción y aplica el pago.
create or replace function elius.webhook_factus(p_pasarela uuid, p_clave_valida boolean, p_carga jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid;
begin
  select tenant_id into v_tenant from elius.pasarelas_pago where id = p_pasarela;
  if v_tenant is null then
    return 'sin_recaudo';
  end if;
  perform set_config('app.tenant_id', v_tenant::text, true);
  return elius.procesar_webhook_factus(p_pasarela, p_clave_valida, p_carga);
end $$;

revoke execute on function elius.srv_secreto(uuid), elius.srv_actualizar_secreto(uuid, text), elius.srv_pasarela_webhook(uuid),
  elius.webhook_factus(uuid, boolean, jsonb) from public, anon, authenticated, elius_app;
grant execute on function elius.srv_secreto(uuid), elius.srv_actualizar_secreto(uuid, text), elius.srv_pasarela_webhook(uuid),
  elius.webhook_factus(uuid, boolean, jsonb) to service_role;
-- =============================================================================
-- ELIUS · Migración 1100 · Consola SQL de revisión (para el profesor / auditor)
-- Permite consultar todo, insertar, actualizar y crear objetos SOLO en el esquema
-- "practica". No permite DROP, TRUNCATE, DELETE, ALTER, GRANT ni tocar el sistema.
-- Se ejecuta con el rol elius_revisor (sin superusuario, sin BYPASSRLS), con el
-- RLS del Administrador que la usa: solo ve y escribe en su propio negocio.
-- =============================================================================
create schema if not exists practica;
comment on schema practica is 'Esquema de práctica para la consola de revisión: aquí sí se puede CREATE';

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'elius_revisor') then
    create role elius_revisor nologin nosuperuser nocreatedb nocreaterole noreplication nobypassrls in role authenticated;
  end if;
end $$;
-- Quien se conecta (authenticator en Supabase, postgres desde el editor SQL) puede cambiar a este rol
grant elius_revisor to postgres;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'authenticator') then
    execute 'grant elius_revisor to authenticator';
  end if;
end $$;

grant usage on schema practica to elius_revisor;
grant create on schema practica to elius_revisor;
grant usage on schema reportes to elius_revisor;
grant select on all tables in schema platform, audit, elius, ext, plugin_vet, plugin_restaurant, plugin_airline, reportes to elius_revisor;
grant insert, update on all tables in schema elius, ext, plugin_vet, plugin_restaurant, plugin_airline to elius_revisor;
grant all on all tables in schema practica to elius_revisor;
alter default privileges in schema practica grant all on tables to elius_revisor;
-- El diccionario de datos y los triggers se leen del catálogo
grant select on information_schema.tables, information_schema.columns to elius_revisor;

-- La bitácora la escribe una función aparte (SECURITY DEFINER), porque SET ROLE no se permite dentro de una
create or replace function elius.consola_auditar(p_sql text) returns void
language sql security definer set search_path = '' as $$
  insert into audit.registros_auditoria (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_nuevos)
  values (app.current_tenant_id(), auth.uid(), 'administrador', 'app', 'elius', 'consola_sql', gen_random_uuid(), 'INSERT',
          jsonb_build_object('sentencia', p_sql));
$$;
revoke execute on function elius.consola_auditar(text) from public, anon;
grant execute on function elius.consola_auditar(text) to authenticated;

-- SECURITY INVOKER: corre con los permisos de quien llama y luego baja a elius_revisor
create or replace function elius.consola_sql(p_sql text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_sql   text := regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '');
  v_low   text := lower(v_sql);
  v_filas jsonb;
  v_n     bigint := 0;
  v_tipo  text;
begin
  if auth.uid() is null or not app.puede('configuracion', 'total') then
    raise exception 'Solo un Administrador puede usar la consola SQL';
  end if;
  if v_sql = '' then raise exception 'Escribe una sentencia'; end if;
  if v_sql ~ ';' then raise exception 'Una sola sentencia por ejecución'; end if;
  if v_low ~ '(--|/\*)' then raise exception 'No se permiten comentarios dentro de la sentencia'; end if;

  v_tipo := (regexp_match(v_low, '^\s*(select|with|insert|update|create)\M'))[1];
  if v_tipo is null then
    raise exception 'Solo se permiten SELECT, INSERT, UPDATE y CREATE';
  end if;
  if v_low ~ '\m(drop|truncate|delete|alter|grant|revoke|copy|vacuum|reindex|cluster|lock|listen|notify|refresh|import|load|reset|do|call)\M'
     or v_low ~ '\mset\s+(local|session|role|search_path|constraints)\M'
     or v_low ~ '\m(set_config|current_setting|pg_sleep|pg_terminate_backend|pg_cancel_backend|dblink|lo_import|lo_export|pg_read_file|pg_ls_dir)\M'
     or v_low ~ '\mcomment\s+on\M' then
    raise exception 'Sentencia no permitida en la consola (DROP, TRUNCATE, DELETE, ALTER, GRANT, SET… están bloqueados)';
  end if;
  if v_tipo = 'create' then
    if v_low !~ 'practica\.' then
      raise exception 'CREATE solo se permite en el esquema practica (ej. CREATE TABLE practica.prueba (...))';
    end if;
    if v_low ~ '\mcreate\s+(or\s+replace\s+)?(schema|role|user|database|extension|policy|publication|subscription|event|rule|server|foreign|materialized)\M' then
      raise exception 'Ese tipo de CREATE no está permitido';
    end if;
  end if;

  perform elius.consola_auditar(v_sql);

  perform set_config('statement_timeout', '8000', true);
  execute 'set local role elius_revisor';
  if v_tipo in ('select', 'with') then
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from (%s) q limit 500) t', v_sql)
      into v_filas;
    v_n := jsonb_array_length(v_filas);
  else
    execute v_sql;
    get diagnostics v_n = row_count;
    v_filas := '[]'::jsonb;
  end if;
  return jsonb_build_object('tipo', v_tipo, 'filas', v_filas, 'afectadas', v_n);
end $$;

revoke execute on function elius.consola_sql(text) from public, anon;
grant execute on function elius.consola_sql(text) to authenticated;
comment on function elius.consola_sql(text) is 'Consola SQL restringida para revisión: SELECT/INSERT/UPDATE y CREATE solo en practica';
-- =============================================================================
-- 1200 · Casos de prueba por vertical (restaurante, veterinaria, aerolínea)
-- La profesora elige un caso en el panel: se crea su negocio con catálogo (5 ítems con imagen) y llegan
-- 20 clientes de prueba. Tres conversaciones llegan hasta el pago: el cliente envía el comprobante,
-- queda en Comprobantes y, cuando quien revisa lo aprueba o lo rechaza, Eli continúa la conversación.
-- =============================================================================

create or replace function elius.datos_caso_demo(p_vertical text)
returns jsonb language sql immutable set search_path = '' as $$
  select case p_vertical
    when 'restaurante' then '{"negocio": "Restaurante Sabor Criollo", "categorias": ["Platos fuertes", "Bebidas", "Postres", "Celebraciones y eventos"], "contactos": [["Camila", "Rojas", "+573001110001"], ["Andrés", "Pardo", "+573001110002"], ["Laura", "Gómez", "+573001110003"], ["Felipe", "Martínez", "+573001110004"], ["Valentina", "Ortiz", "+573001110005"], ["Daniel", "Herrera", "+573001110006"], ["Sofía", "Vargas", "+573001110007"], ["Juan", "Castillo", "+573001110008"], ["Mariana", "Suárez", "+573001110009"], ["Camilo", "Reyes", "+573001110010"], ["Natalia", "Moreno", "+573001110011"], ["Esteban", "Cárdenas", "+573001110012"], ["Paula", "Jiménez", "+573001110013"], ["Sebastián", "Ruiz", "+573001110014"], ["Isabela", "Pineda", "+573001110015"], ["Tomás", "Aguirre", "+573001110016"], ["Gabriela", "Salazar", "+573001110017"], ["Mateo", "Duarte", "+573001110018"], ["Alejandra", "Rincón", "+573001110019"], ["Nicolás", "Quintero", "+573001110020"]], "items": [{"cat": 0, "tipo": "producto", "sku": "RES-01", "nombre": "Bandeja paisa", "desc": "Frijoles, arroz, carne molida, chicharrón, chorizo, huevo, plátano maduro y arepa.", "precio": 38000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "producto", "sku": "RES-02", "nombre": "Hamburguesa de la casa", "desc": "Carne de res 180 g, queso, tocineta y papas a la francesa.", "precio": 28000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "producto", "sku": "RES-03", "nombre": "Arepa rellena de pollo", "desc": "Arepa de maíz rellena de pollo desmechado con guacamole.", "precio": 16000, "iva": 0, "dur": null}, {"cat": 1, "tipo": "producto", "sku": "RES-04", "nombre": "Limonada de coco", "desc": "Limonada cremada con coco, servida bien fría.", "precio": 12000, "iva": 0, "dur": null}, {"cat": 2, "tipo": "producto", "sku": "RES-05", "nombre": "Tres leches", "desc": "Bizcocho bañado en tres leches con crema y canela.", "precio": 14000, "iva": 0, "dur": null}, {"cat": 3, "tipo": "servicio", "sku": "RES-06", "nombre": "Pack cumpleaños", "desc": "Decoración de mesa con globos y letrero de feliz cumpleaños para tu celebración en el restaurante.", "precio": 50000, "iva": 0, "dur": 120}, {"cat": 3, "tipo": "servicio", "sku": "RES-07", "nombre": "Cena de aniversario", "desc": "Mesa para dos con decoración romántica, velas, flores y postre de cortesía.", "precio": 80000, "iva": 0, "dur": 120}, {"cat": 3, "tipo": "servicio", "sku": "RES-08", "nombre": "Pack bautizo", "desc": "Mesa decorada en tonos suaves y torta de bautizo para tu celebración.", "precio": 90000, "iva": 0, "dur": 180}, {"cat": 3, "tipo": "servicio", "sku": "RES-09", "nombre": "Pack grado", "desc": "Arco de globos, torta personalizada y mesa decorada para celebrar tu grado.", "precio": 65000, "iva": 0, "dur": 180}, {"cat": 3, "tipo": "servicio", "sku": "RES-10", "nombre": "Aniversario premium", "desc": "Cena de aniversario para dos con decoración completa, flores, velas y botella de vino.", "precio": 160000, "iva": 0, "dur": 180}, {"cat": 3, "tipo": "servicio", "sku": "RES-11", "nombre": "Pack adicional de globos", "desc": "Arco de globos y mesa de dulces para sumar a cualquier celebración.", "precio": 69000, "iva": 0, "dur": 60}, {"cat": 3, "tipo": "servicio", "sku": "RES-12", "nombre": "Celebración sin decoración", "desc": "Reserva de mesa para tu celebración, sin decoración (la traes tú).", "precio": 30000, "iva": 0, "dur": 120}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, quiero la cena de aniversario para mi esposo y para mí", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Camila! Anoto 1 Cena de aniversario. Total $80.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Buenas, quiero pedir a domicilio una bandeja paisa", "img": null, "comp": null}, {"conv": 1, "emisor": "eli", "texto": "¡Hola Andrés! Esta es nuestra Bandeja paisa ($38.000): frijoles, arroz, carne molida, chicharrón, chorizo, huevo, plátano y arepa. ¿A qué dirección la enviamos?", "img": 1, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Hola, ¿ustedes tienen opciones sin gluten?", "img": null, "comp": null}, {"conv": 2, "emisor": "eli", "texto": "Hola Laura 😊 La Arepa rellena de pollo ($16.000) es de maíz y no lleva gluten. Si tu alergia es severa te paso con el administrador para confirmar con cocina.", "img": 3, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "¿Cuánto vale la hamburguesa?", "img": null, "comp": null}, {"conv": 3, "emisor": "eli", "texto": "Hola Felipe, la Hamburguesa de la casa cuesta $28.000: carne de res de 180 g, queso, tocineta y papas a la francesa.", "img": 2, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Hola, quiero la cena de aniversario premium", "img": null, "comp": null}, {"conv": 4, "emisor": "eli", "texto": "¡Hola Valentina! Anoto 1 Aniversario premium. Total $160.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 0}, {"conv": 0, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "Hola, quiero el pack de cumpleaños para mi hija", "img": null, "comp": null}, {"conv": 5, "emisor": "eli", "texto": "¡Hola Daniel! Anoto 1 Pack cumpleaños. Total $50.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "Hola, ¿a qué hora abren hoy?", "img": null, "comp": null}, {"conv": 6, "emisor": "eli", "texto": "Hola Sofía, hoy atendemos de 12:00 m. a 10:00 p. m. ¿Quieres que te reserve una mesa?", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "Necesito reservar para 12 personas el sábado", "img": null, "comp": null}, {"conv": 7, "emisor": "eli", "texto": "Hola Juan, para grupos grandes aviso de inmediato al administrador para organizar la mesa. ¿Me confirmas la hora y un teléfono de contacto?", "img": null, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 1}, {"conv": 4, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "Hola, necesito el pack adicional de globos y mesa de dulces", "img": null, "comp": null}, {"conv": 8, "emisor": "eli", "texto": "¡Hola Mariana! Anoto 1 Pack adicional de globos. Total $69.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 2}, {"conv": 5, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 9, "emisor": "cliente", "texto": "¿Hacen domicilios a Chapinero?", "img": null, "comp": null}, {"conv": 9, "emisor": "eli", "texto": "Sí, Camilo, llegamos a Chapinero. El domicilio vale $5.000 y tarda unos 40 minutos. ¿Qué te provoca pedir?", "img": null, "comp": null}, {"conv": 10, "emisor": "cliente", "texto": "¿La bandeja paisa alcanza para dos?", "img": null, "comp": null}, {"conv": 10, "emisor": "eli", "texto": "Hola Natalia, la Bandeja paisa es generosa y para dos personas puede alcanzar si piden entradas. Aquí te la muestro 😊", "img": 1, "comp": null}, {"conv": 11, "emisor": "cliente", "texto": "Quiero cancelar mi reserva de mañana", "img": null, "comp": null}, {"conv": 11, "emisor": "eli", "texto": "Listo Esteban, ¿me confirmas a nombre de quién estaba? Cancelo la reserva y te aviso. La consignación se puede reagendar según disponibilidad.", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 3}, {"conv": 8, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "Hola, quiero el pack de grado para mi hermano", "img": null, "comp": null}, {"conv": 12, "emisor": "eli", "texto": "¡Hola Paula! Anoto 1 Pack grado. Total $65.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "Hola, quiero reservar mesa para celebrar, sin decoración", "img": null, "comp": null}, {"conv": 13, "emisor": "eli", "texto": "¡Hola Sebastián! Anoto 1 Celebración sin decoración. Total $30.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "¿Tienen menú para niños?", "img": null, "comp": null}, {"conv": 14, "emisor": "eli", "texto": "Hola Isabela, tenemos porciones pequeñas: la Hamburguesa de la casa en tamaño infantil. Aquí está la versión normal para que la veas.", "img": 2, "comp": null}, {"conv": 15, "emisor": "cliente", "texto": "Quiero la bandeja paisa y un tres leches", "img": null, "comp": null}, {"conv": 15, "emisor": "eli", "texto": "¡Buena elección, Tomás! 1 Bandeja paisa ($38.000) + 1 Tres leches ($14.000) = $52.000. ¿Lo enviamos a domicilio?", "img": 5, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "Hola, quiero el pack de cumpleaños", "img": null, "comp": null}, {"conv": 16, "emisor": "eli", "texto": "¡Hola Gabriela! Anoto 1 Pack cumpleaños. Total $50.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "📎 Comprobante de pago Bancolombia", "img": null, "comp": 4}, {"conv": 12, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "📎 Comprobante de pago Transferencia", "img": null, "comp": 5}, {"conv": 13, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 17, "emisor": "cliente", "texto": "¿Se puede reservar en la terraza?", "img": null, "comp": null}, {"conv": 17, "emisor": "eli", "texto": "Claro, Mateo 🌿 Te dejé reservada una mesa en la terraza hoy a las 7:30 p. m. para 4 personas. ¡Te esperamos!", "img": null, "comp": null}, {"conv": 18, "emisor": "cliente", "texto": "Mi pedido no ha llegado, llevo una hora esperando", "img": null, "comp": null}, {"conv": 18, "emisor": "eli", "texto": "Lamento la demora, Alejandra. Ya aviso al administrador para que lo revise de inmediato y te escribe una persona del equipo en unos minutos.", "img": null, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 6}, {"conv": 16, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 19, "emisor": "cliente", "texto": "Gracias, todo estuvo delicioso 😍", "img": null, "comp": null}, {"conv": 19, "emisor": "eli", "texto": "¡Qué alegría, Nicolás! Gracias por visitarnos. Te esperamos pronto en Sabor Criollo 🍽️", "img": null, "comp": null}], "imagenes": {"RES-01": "https://commons.wikimedia.org/wiki/Special:FilePath/Bandeja%20Paisa%20%28Bogot%C3%A1%29.jpg?width=640", "RES-02": "https://commons.wikimedia.org/wiki/Special:FilePath/Cheeseburger%20and%20fries.jpg?width=640", "RES-03": "https://commons.wikimedia.org/wiki/Special:FilePath/Colombian%20Food%2C%20Arepas.jpg?width=640", "RES-04": "https://commons.wikimedia.org/wiki/Special:FilePath/Limonada%20de%20coco.jpg?width=640", "RES-05": "https://commons.wikimedia.org/wiki/Special:FilePath/Tres%20leches%20cake.jpg?width=640", "RES-06": "https://commons.wikimedia.org/wiki/Special:FilePath/Birthday%20decoration.jpg?width=640", "RES-07": "https://commons.wikimedia.org/wiki/Special:FilePath/DZ6%202628%20Cozy%20candlelit%20dinner%20for%20two%20elegant%20Thai%20restaurant%20setting%20with%20twinkling%20lights%20and%20a%20delicate%20orchid%20centerpiece.jpg?width=640", "RES-08": "https://commons.wikimedia.org/wiki/Special:FilePath/Christening%20Cake%20%289696366409%29.jpg?width=640", "RES-09": "/demo/restaurante-9.jpg", "RES-10": "https://commons.wikimedia.org/wiki/Special:FilePath/DZ6%202648%20A%20cozy%20candlelit%20dinner%20setup%20a%20delicate%20orchid%20soft%20lamp%20glow%20and%20an%20empty%20wine%20glass%20waiting%20for%20the%20evening%20to%20begin.jpg?width=640", "RES-11": "https://commons.wikimedia.org/wiki/Special:FilePath/Organic%20Arch%202016%20balloon%20decorations.jpg?width=640", "RES-12": "https://commons.wikimedia.org/wiki/Special:FilePath/Table%20set%20for%20dinner%20in%20a%20restaurant.jpg?width=640"}, "recursos": [["mesa", "Terraza 1", 4], ["mesa", "Mesa 2", 2]], "efectos": [{"escalar": "Alergia alimentaria: confirmar ingredientes con cocina", "resumen": "Laura pregunta por opciones sin gluten por una alergia; Eli ofreció la arepa de pollo y pasó el caso al administrador.", "tras": 5}, {"escalar": "Reclamo: pedido demorado más de una hora", "resumen": "Alejandra lleva una hora esperando su pedido; requiere revisar con cocina y domicilio.", "tras": 55}, {"reserva": "mesa", "h": 19.5, "personas": 4, "recurso": "Terraza 1", "tras": 53}], "agenda": [[0, 21.5, 7, "mesa", 12, "Terraza 1", "pendiente_pago", false], [1, 19.5, 4, "mesa", 2, "Mesa 2", "confirmada", false], [1, 20, 5, "mesa", 6, "Terraza 1", "confirmada", false], [2, 13, 9, "mesa", 4, "Mesa 2", "confirmada", false], [3, 20.5, 10, "mesa", 2, "Mesa 2", "confirmada", false], [4, 19, 12, "mesa", 8, "Terraza 1", "confirmada", false], [5, 13.5, 13, "mesa", 4, "Terraza 1", "pendiente_pago", false], [6, 14, 14, "mesa", 5, "Terraza 1", "confirmada", false], [8, 20, 15, "mesa", 4, "Mesa 2", "confirmada", false], [9, 19, 16, "mesa", 10, "Terraza 1", "confirmada", false], [11, 13, 19, "mesa", 2, "Mesa 2", "confirmada", false]], "pagos": [{"items": [["RES-07", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-2", "monto": 80000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M25797932", "fecha": "18 de julio de 2026 a las 08:33 p. m.", "hash": "demo-restaurante-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Cena de aniversario por $80.000) Quedó reservada con su decoración. ¡Feliz aniversario! 💐"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Camila. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Camila, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-10", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-1", "monto": 160000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M26257385", "fecha": "14 de julio de 2026 a las 11:16 p. m.", "hash": "demo-restaurante-2"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Aniversario premium por $160.000) Quedó reservada con decoración completa y vino. ¡Feliz aniversario! 🍷"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Valentina. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Valentina, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-06", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-3", "monto": 50000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M16356689", "fecha": "09 de julio de 2026 a las 05:11 p. m.", "hash": "demo-restaurante-3"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Pack cumpleaños por $50.000) Quedó reservada la decoración de cumpleaños 🎈"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Daniel. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Daniel, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-11", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-5", "monto": 69000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M19936704", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-restaurante-4"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Pack adicional de globos por $69.000) Quedó agregado a tu celebración 🎈"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Mariana. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Mariana, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-09", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-4", "monto": 65000, "destinatario": "Luis Rodriguez", "app": "Bancolombia", "ref": "TRrUw0H9AIEC", "fecha": "11 de julio de 2026 a las 9:27 a. m.", "hash": "demo-restaurante-5"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Pack grado por $65.000) Quedó reservado el pack de grado 🎓"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Paula. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Paula, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-12", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-6", "monto": 30000, "destinatario": "Luis Rodriguez", "app": "Transferencia", "ref": "T120712-1104", "fecha": "12 de julio de 2026 a las 11:04 a. m.", "hash": "demo-restaurante-6"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Celebración sin decoración por $30.000) Quedó reservada tu mesa para la celebración."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Sebastián. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Sebastián, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["RES-06", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-res-7", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M19936704", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-restaurante-7"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Pack cumpleaños por $50.000) Quedó reservada la decoración de cumpleaños 🎈"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Gabriela. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Gabriela, el comprobante es por $75.000 y tu pedido es de $50.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Gabriela 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}]}'::jsonb
    when 'veterinaria' then '{"negocio": "Clínica Veterinaria Huellitas", "categorias": ["Consultas y cirugía", "Prevención", "Estética"], "contactos": [["Mariana", "Ruiz", "+573002220001"], ["Julián", "Castro", "+573002220002"], ["Paola", "Díaz", "+573002220003"], ["Camilo", "Torres", "+573002220004"], ["Lucía", "Ramírez", "+573002220005"], ["Andrés", "Cifuentes", "+573002220006"], ["Diana", "Mejía", "+573002220007"], ["Santiago", "Londoño", "+573002220008"], ["Carolina", "Ospina", "+573002220009"], ["Mauricio", "Gil", "+573002220010"], ["Juliana", "Arango", "+573002220011"], ["Ricardo", "Bermúdez", "+573002220012"], ["Manuela", "Parra", "+573002220013"], ["Felipe", "Osorio", "+573002220014"], ["Angélica", "Mora", "+573002220015"], ["Jorge", "Villa", "+573002220016"], ["Natalia", "Cortés", "+573002220017"], ["Oscar", "Franco", "+573002220018"], ["Daniela", "Peña", "+573002220019"], ["Esteban", "Vega", "+573002220020"]], "items": [{"cat": 0, "tipo": "servicio", "sku": "VET-01", "nombre": "Consulta general", "desc": "Examen clínico completo con orientación de tratamiento.", "precio": 60000, "iva": 0, "dur": 30}, {"cat": 1, "tipo": "servicio", "sku": "VET-02", "nombre": "Vacuna múltiple", "desc": "Esquema anual para perros y gatos, con carné actualizado.", "precio": 75000, "iva": 0, "dur": 20}, {"cat": 2, "tipo": "servicio", "sku": "VET-03", "nombre": "Baño y peluquería", "desc": "Baño medicado, corte de pelo y de uñas, limpieza de oídos.", "precio": 55000, "iva": 0, "dur": 90}, {"cat": 1, "tipo": "servicio", "sku": "VET-04", "nombre": "Desparasitación", "desc": "Desparasitante interno y externo según el peso de la mascota.", "precio": 35000, "iva": 0, "dur": 15}, {"cat": 0, "tipo": "servicio", "sku": "VET-05", "nombre": "Esterilización canina", "desc": "Cirugía con anestesia, exámenes previos y control posoperatorio.", "precio": 320000, "iva": 0, "dur": 120}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, mi perro Max tiene las vacunas atrasadas, ¿puedo sacar cita?", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Mariana! 🐶 Para Max tenemos la Vacuna múltiple ($75.000). Hay cupo el jueves a las 10:00 a. m. o a las 3:00 p. m. ¿Cuál te sirve?", "img": 2, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "El jueves a las 10", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Agendado: jueves 10:00 a. m. Para dejar la cita confirmada se paga la vacuna por adelantado: Nequi al 300 416 5923 por $75.000. Envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Mi gata Luna lleva dos días sin comer y está decaída", "img": null, "comp": null}, {"conv": 1, "emisor": "eli", "texto": "Hola Julián, lamento que Luna esté así 🐱 Dos días sin comer requiere revisión pronta. Te doy cita de Consulta general ($60.000) hoy a las 4:00 p. m.", "img": 1, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Tengo un cachorro de 3 meses, ¿qué necesita?", "img": null, "comp": null}, {"conv": 2, "emisor": "eli", "texto": "¡Hola Paola, qué ternura! 🐕 A los 3 meses necesita esquema de vacunas y desparasitación ($35.000). Te muestro cómo es.", "img": 4, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "Hola, quiero el baño y peluquería para mi golden", "img": null, "comp": null}, {"conv": 3, "emisor": "eli", "texto": "¡Hola Camilo! Anoto 1 Baño y peluquería. Total $55.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Quiero esterilizar a mi perra, ¿cuánto vale?", "img": null, "comp": null}, {"conv": 4, "emisor": "eli", "texto": "Hola Lucía, la Esterilización canina cuesta $320.000 con exámenes previos, anestesia y control posoperatorio. Agendamos primero una consulta de valoración.", "img": 5, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Ya pagué por Nequi", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Gracias Mariana, envíame la foto del comprobante para validarlo.", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 0}, {"conv": 0, "emisor": "eli", "texto": "Recibido ✅ Lo pasé al equipo para validar el monto y confirmarte la cita.", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "Mi perro se comió un chocolate, ¿qué hago?", "img": null, "comp": null}, {"conv": 5, "emisor": "eli", "texto": "Andrés, es una urgencia: llévalo ya a la clínica. Aviso al veterinario de turno para que lo reciba de inmediato. ¿Cuánto pesa y cuánto comió?", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "¿Atienden los sábados?", "img": null, "comp": null}, {"conv": 6, "emisor": "eli", "texto": "Hola Diana, sí, los sábados atendemos de 8:00 a. m. a 1:00 p. m. ¿Quieres que te agende una consulta?", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 2}, {"conv": 3, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "Hola, necesito desparasitar a mis dos gatos", "img": null, "comp": null}, {"conv": 7, "emisor": "eli", "texto": "¡Hola Santiago! Anoto 2 Desparasitación. Total $70.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "¿Tienen servicio de peluquería para un schnauzer?", "img": null, "comp": null}, {"conv": 8, "emisor": "eli", "texto": "Claro, Carolina 🐾 El Baño y peluquería ($55.000) incluye corte de raza. Hay cupo mañana a las 9:00 a. m.", "img": 3, "comp": null}, {"conv": 9, "emisor": "cliente", "texto": "Mi perro cojea desde ayer", "img": null, "comp": null}, {"conv": 9, "emisor": "eli", "texto": "Hola Mauricio, conviene que lo vea el veterinario pronto. Te agendo una Consulta general ($60.000) hoy o mañana a primera hora. ¿Cuál prefieres?", "img": 1, "comp": null}, {"conv": 10, "emisor": "cliente", "texto": "¿A qué edad se esteriliza una gata?", "img": null, "comp": null}, {"conv": 10, "emisor": "eli", "texto": "Hola Juliana, normalmente desde los 6 meses, según su peso y salud. Lo ideal es una consulta para valorarla antes de agendar.", "img": null, "comp": null}, {"conv": 11, "emisor": "cliente", "texto": "Quiero cancelar la cita de hoy", "img": null, "comp": null}, {"conv": 11, "emisor": "eli", "texto": "Listo Ricardo, ¿me confirmas el nombre de la mascota? Cancelo la cita y te ofrezco otra fecha cuando quieras.", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 3}, {"conv": 7, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "¿Cuánto cuesta la consulta?", "img": null, "comp": null}, {"conv": 12, "emisor": "eli", "texto": "Hola Manuela, la Consulta general cuesta $60.000. Aquí te muestro el servicio.", "img": 1, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "¿Atienden urgencias en la noche?", "img": null, "comp": null}, {"conv": 13, "emisor": "eli", "texto": "Hola Felipe, las urgencias las atendemos hasta las 10:00 p. m. Pasada esa hora te recomiendo una clínica 24 horas; si quieres te paso la dirección.", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "Hola, quiero la vacuna múltiple para mi gata Nina", "img": null, "comp": null}, {"conv": 14, "emisor": "eli", "texto": "¡Hola Angélica! Anoto 1 Vacuna múltiple. Total $75.000. Para confirmarlo paga por Nequi al 300 416 5923 y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 15, "emisor": "cliente", "texto": "¿Tienen guardería para perros?", "img": null, "comp": null}, {"conv": 15, "emisor": "eli", "texto": "Hola Jorge, por ahora no ofrecemos guardería, pero sí consulta, vacunas, baño y cirugías. ¿Te ayudo con alguno?", "img": null, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "Mi cachorro tiene diarrea hace 2 días", "img": null, "comp": null}, {"conv": 16, "emisor": "eli", "texto": "Hola Natalia, en cachorros la diarrea puede deshidratar rápido. Te agendo una Consulta general ($60.000) hoy mismo y aviso al veterinario.", "img": 1, "comp": null}, {"conv": 17, "emisor": "cliente", "texto": "¿Cómo es el procedimiento de la esterilización?", "img": null, "comp": null}, {"conv": 17, "emisor": "eli", "texto": "Hola Óscar, se hace con anestesia y exámenes previos; la mascota sale el mismo día con indicaciones de cuidado. Te muestro el servicio.", "img": 5, "comp": null}, {"conv": 18, "emisor": "cliente", "texto": "¿Puedo llevar a mi mascota sin cita?", "img": null, "comp": null}, {"conv": 18, "emisor": "eli", "texto": "Hola Daniela, para urgencias sí; para consultas de rutina es mejor agendar y así no esperas. ¿Te busco un cupo?", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "📎 Comprobante de pago Nequi", "img": null, "comp": 1}, {"conv": 14, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 19, "emisor": "cliente", "texto": "Gracias por atender tan rápido a Luna 🐱", "img": null, "comp": null}, {"conv": 19, "emisor": "eli", "texto": "¡Gracias a ti, Esteban! Nos alegra que Luna esté mejor. Cualquier duda, aquí estoy.", "img": null, "comp": null}], "imagenes": {"VET-01": "https://commons.wikimedia.org/wiki/Special:FilePath/Close-up%20of%20a%20veterinarian%20examining%20a%20maltese%20dog%20with%20a%20stethoscope.%20%2851687314898%29.jpg?width=640", "VET-02": "https://commons.wikimedia.org/wiki/Special:FilePath/USMC-04462.jpg?width=640", "VET-03": "https://commons.wikimedia.org/wiki/Special:FilePath/Dog%20Groomer%20Norwich.jpg?width=640", "VET-04": "https://commons.wikimedia.org/wiki/Special:FilePath/U.S.%20Army%20Capt.%20Brooke%20Henderson%2C%20left%2C%20a%20veterinarian%20with%20the%20993rd%20Medical%20Detachment%2C%20U.S.%20Army%20Reserve%2C%20examines%20a%20Maltese%20mix%20puppy%20while%20Sgt.%20Andrew%20King%2C%20with%20the%20949th%20Medical%20Detachment%2C%20holds%20the%20dog%20120418-F-ZH346-001.jpg?width=640", "VET-05": "https://commons.wikimedia.org/wiki/Special:FilePath/Surgery%20on%20a%20dog%2C%20University%20of%20Agricultural%20Sciences%20and%20Veterinary%20Medicine%2C%20Cluj-Napoka.jpg?width=640"}, "recursos": [["consultorio", "Consultorio 1", 1]], "efectos": [{"reserva": "cita", "h": 16, "personas": 1, "recurso": "Consultorio 1", "urgente": true, "tras": 5}, {"escalar": "Posible urgencia: cachorro con diarrea de 2 días", "resumen": "Cachorro con diarrea hace 2 días: riesgo de deshidratación; Eli agendó consulta y pide valoración del veterinario.", "tras": 45}], "agenda": [[0, 17.5, 2, "cita", 1, "Consultorio 1", "confirmada", false], [1, 9, 5, "cita", 1, "Consultorio 1", "confirmada", true], [1, 15, 9, "cita", 1, "Consultorio 1", "confirmada", false], [2, 10, 10, "cita", 1, "Consultorio 1", "confirmada", false], [3, 16, 12, "cita", 1, "Consultorio 1", "pendiente_pago", false], [4, 11, 13, "cita", 1, "Consultorio 1", "confirmada", false], [6, 9.5, 15, "cita", 1, "Consultorio 1", "confirmada", false], [7, 14, 17, "cita", 1, "Consultorio 1", "confirmada", false], [9, 10, 18, "cita", 1, "Consultorio 1", "confirmada", false], [10, 15.5, 19, "cita", 1, "Consultorio 1", "pendiente_pago", false]], "pagos": [{"items": [["VET-02", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M19936704", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ La cita de Max quedó confirmada para el jueves a las 10:00 a. m. (orden #{orden}). Trae su carné de vacunación."}, {"emisor": "cliente", "texto": "Perfecto, ahí estaremos"}, {"emisor": "eli", "texto": "Los esperamos, Mariana. ¡Un abrazo a Max! 🐾"}], "rechazado": [{"emisor": "eli", "texto": "Mariana, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["VET-02", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20015838", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-2"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Vacuna múltiple por $75.000) Quedó agendada para mañana a las 9:00 a. m. Trae su carné."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Angélica. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Angélica, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["VET-03", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20023757", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-3"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Baño y peluquería por $55.000) Quedó agendado para mañana a las 11:00 a. m."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Camilo. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Camilo, el comprobante es por $75.000 y tu pedido es de $55.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Camilo 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}, {"items": [["VET-04", 2]], "entrega": "no_aplica", "comp": {"img": "comprobante-veterinaria", "monto": 75000, "destinatario": "Luis Rodriguez", "app": "Nequi", "ref": "M20031676", "fecha": "10 de julio de 2026 a las 06:32 p. m.", "hash": "demo-veterinaria-4"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (2 Desparasitación por $70.000) Quedó agendado para mañana a las 2:00 p. m."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Santiago. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Santiago, el comprobante es por $75.000 y tu pedido es de $70.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Santiago 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}]}'::jsonb
    when 'aerolinea' then '{"negocio": "Aerolínea Cóndor Andino", "categorias": ["Tarifas", "Servicios adicionales"], "contactos": [["Sergio", "Molina", "+573003330001"], ["Daniela", "Vargas", "+573003330002"], ["Carlos", "Núñez", "+573003330003"], ["Laura", "Cárdenas", "+573003330004"], ["Andrés", "Rojas", "+573003330005"], ["Paula", "Medina", "+573003330006"], ["Julián", "Pardo", "+573003330007"], ["Camila", "Soto", "+573003330008"], ["Felipe", "Gómez", "+573003330009"], ["Valeria", "Sánchez", "+573003330010"], ["Mateo", "Arias", "+573003330011"], ["Sara", "Londoño", "+573003330012"], ["Nicolás", "Ibarra", "+573003330013"], ["Isabella", "Rey", "+573003330014"], ["David", "Correa", "+573003330015"], ["Luisa", "Bernal", "+573003330016"], ["Diego", "Vásquez", "+573003330017"], ["Mónica", "Pacheco", "+573003330018"], ["Alejandro", "Ríos", "+573003330019"], ["Juliana", "Cano", "+573003330020"]], "items": [{"cat": 0, "tipo": "tarifa", "sku": "AER-01", "nombre": "Bogotá – Medellín (Light)", "desc": "Solo equipaje de mano. Sin cambios ni devolución.", "precio": 189000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "tarifa", "sku": "AER-02", "nombre": "Bogotá – Cartagena (Flex)", "desc": "Maleta de 23 kg incluida y un cambio de fecha sin costo.", "precio": 275000, "iva": 0, "dur": null}, {"cat": 0, "tipo": "tarifa", "sku": "AER-03", "nombre": "Bogotá – San Andrés (Promo)", "desc": "Tarifa promocional con equipaje de mano, cupos limitados.", "precio": 415000, "iva": 0, "dur": null}, {"cat": 1, "tipo": "adicional", "sku": "AER-04", "nombre": "Maleta de bodega 23 kg", "desc": "Equipaje adicional para tu vuelo.", "precio": 85000, "iva": 0, "dur": null}, {"cat": 1, "tipo": "adicional", "sku": "AER-05", "nombre": "Selección de asiento", "desc": "Elige ventana o pasillo antes del check-in.", "precio": 25000, "iva": 0, "dur": null}], "guion": [{"conv": 0, "emisor": "cliente", "texto": "Hola, necesito un vuelo Bogotá–Cartagena el 20 de diciembre, con maleta", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "¡Hola Sergio! ✈️ El 20 de diciembre a Cartagena tengo la tarifa Flex en $275.000 (cambio de fecha sin costo). La Maleta de bodega de 23 kg son $85.000. Total $360.000. ¿Te reservo?", "img": 2, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Sí, a nombre de Sergio Molina, cédula 1.020.345.678", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Reservado ✅ Tu reserva se mantiene 24 horas. Paga $360.000 por DaviPlata o Nequi al 300 416 5923 y envíame el comprobante para emitir el tiquete.", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Hola, quiero el vuelo a Cartagena del 20 de diciembre con maleta", "img": null, "comp": null}, {"conv": 1, "emisor": "eli", "texto": "¡Hola Daniela! Anoto 1 Bogotá – Cartagena (Flex) y 1 Maleta de bodega 23 kg. Total $360.000. Para confirmarlo paga por Nequi al 300 416 5923 o DaviPlata y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Hola, quiero la tarifa promo a San Andrés en enero", "img": null, "comp": null}, {"conv": 2, "emisor": "eli", "texto": "¡Hola Carlos! Anoto 1 Bogotá – San Andrés (Promo). Total $415.000. Para confirmarlo paga por Nequi al 300 416 5923 o DaviPlata y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 3, "emisor": "cliente", "texto": "¿Cuánto cuesta agregar una maleta?", "img": null, "comp": null}, {"conv": 3, "emisor": "eli", "texto": "Hola Laura, la Maleta de bodega de 23 kg cuesta $85.000 por trayecto si la agregas antes del viaje.", "img": 4, "comp": null}, {"conv": 4, "emisor": "cliente", "texto": "Quiero elegir asiento de ventana", "img": null, "comp": null}, {"conv": 4, "emisor": "eli", "texto": "Claro, Andrés. La Selección de asiento cuesta $25.000 y puedes elegir ventana o pasillo antes del check-in.", "img": 5, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "Ya hice el pago por DaviPlata", "img": null, "comp": null}, {"conv": 0, "emisor": "eli", "texto": "Gracias Sergio, envíame la foto del comprobante para validarlo.", "img": null, "comp": null}, {"conv": 0, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 0}, {"conv": 0, "emisor": "eli", "texto": "Recibido ✅ Lo pasé al equipo para validar el monto y emitir tu tiquete.", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 1, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 1}, {"conv": 1, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 2, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 3}, {"conv": 2, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 5, "emisor": "cliente", "texto": "¿Puedo cambiar la fecha de mi vuelo?", "img": null, "comp": null}, {"conv": 5, "emisor": "eli", "texto": "Hola Paula, con la tarifa Flex tienes un cambio de fecha sin costo; con Light no hay cambios. ¿Qué tarifa compraste?", "img": 2, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "Hola, necesito 3 tiquetes Bogotá–Medellín para el viernes", "img": null, "comp": null}, {"conv": 6, "emisor": "eli", "texto": "¡Hola Julián! Anoto 3 Bogotá – Medellín (Light). Total $567.000. Para confirmarlo paga por Nequi al 300 416 5923 o DaviPlata y envíame el comprobante 📸", "img": null, "comp": null}, {"conv": 7, "emisor": "cliente", "texto": "¿Cuánto equipaje puedo llevar en la tarifa Light?", "img": null, "comp": null}, {"conv": 7, "emisor": "eli", "texto": "Hola Camila, la tarifa Light incluye solo equipaje de mano. Si necesitas maleta puedes agregarla por $85.000.", "img": 4, "comp": null}, {"conv": 8, "emisor": "cliente", "texto": "Mi cédula es 1.020.345.678, ¿ya quedó mi reserva?", "img": null, "comp": null}, {"conv": 8, "emisor": "eli", "texto": "Gracias Felipe. Tu reserva se mantiene por 24 horas mientras envías el comprobante de pago.", "img": null, "comp": null}, {"conv": 9, "emisor": "cliente", "texto": "¿Cómo pago el tiquete?", "img": null, "comp": null}, {"conv": 9, "emisor": "eli", "texto": "Hola Valeria, pagas por consignación o transferencia y envías la foto del comprobante; una persona verifica el monto y emitimos el tiquete.", "img": null, "comp": null}, {"conv": 10, "emisor": "cliente", "texto": "¿Puedo viajar con un menor de edad solo?", "img": null, "comp": null}, {"conv": 10, "emisor": "eli", "texto": "Hola Mateo, los menores de 12 años viajan con un adulto; entre 12 y 17 años se requiere permiso notarial. Si necesitas más detalle te paso con una persona del equipo.", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "Ya pagué, aquí va el comprobante", "img": null, "comp": null}, {"conv": 6, "emisor": "cliente", "texto": "📎 Comprobante de pago DaviPlata", "img": null, "comp": 2}, {"conv": 6, "emisor": "eli", "texto": "Recibido ✅ Lo paso al equipo para validar el monto. En cuanto lo confirmen te aviso por aquí.", "img": null, "comp": null}, {"conv": 11, "emisor": "cliente", "texto": "¿Hay vuelos a Cartagena en diciembre con maleta incluida?", "img": null, "comp": null}, {"conv": 11, "emisor": "eli", "texto": "Sí, Sara: la tarifa Flex a Cartagena ($275.000) incluye maleta de 23 kg. ¿Qué fechas tienes?", "img": 2, "comp": null}, {"conv": 12, "emisor": "cliente", "texto": "Quiero cancelar mi vuelo", "img": null, "comp": null}, {"conv": 12, "emisor": "eli", "texto": "Hola Nicolás, ¿me confirmas tu código de reserva? Reviso las condiciones de tu tarifa: Light no tiene devolución y Flex permite un cambio de fecha.", "img": null, "comp": null}, {"conv": 13, "emisor": "cliente", "texto": "¿A qué hora sale el vuelo a San Andrés?", "img": null, "comp": null}, {"conv": 13, "emisor": "eli", "texto": "Hola Isabella, el vuelo a San Andrés sale a las 6:30 a. m. y llega a las 8:20 a. m. Aquí te muestro la tarifa Promo.", "img": 3, "comp": null}, {"conv": 14, "emisor": "cliente", "texto": "¿Puedo viajar con mi mascota?", "img": null, "comp": null}, {"conv": 14, "emisor": "eli", "texto": "Hola David, aceptamos mascotas pequeñas en cabina con guacal y certificado. Te paso con una persona del equipo para confirmar requisitos.", "img": null, "comp": null}, {"conv": 15, "emisor": "cliente", "texto": "Somos 2 adultos y un niño de 5 años", "img": null, "comp": null}, {"conv": 15, "emisor": "eli", "texto": "Hola Luisa, el niño paga tarifa completa si ocupa asiento. Para 3 pasajeros en Light a Medellín serían $567.000. ¿Fecha de viaje?", "img": 1, "comp": null}, {"conv": 16, "emisor": "cliente", "texto": "¿Cuánto cuesta la maleta de bodega para San Andrés?", "img": null, "comp": null}, {"conv": 16, "emisor": "eli", "texto": "Hola Diego, la Maleta de bodega de 23 kg cuesta $85.000 por trayecto.", "img": 4, "comp": null}, {"conv": 17, "emisor": "cliente", "texto": "Quiero que mi asiento quede junto a mi esposo", "img": null, "comp": null}, {"conv": 17, "emisor": "eli", "texto": "Claro, Mónica. Con la Selección de asiento ($25.000 c/u) eligen asientos contiguos antes del check-in. Tu vuelo de hoy sale a las 6:30 p. m.", "img": 5, "comp": null}, {"conv": 18, "emisor": "cliente", "texto": "Perdí mi tiquete, ¿me lo reenvían?", "img": null, "comp": null}, {"conv": 18, "emisor": "eli", "texto": "Hola Alejandro, claro. Te lo reenvío por este chat; ¿me confirmas tu número de documento para ubicarlo?", "img": null, "comp": null}, {"conv": 19, "emisor": "cliente", "texto": "Gracias, excelente servicio ✈️", "img": null, "comp": null}, {"conv": 19, "emisor": "eli", "texto": "¡Gracias a ti, Juliana! Buen viaje y aquí estamos para lo que necesites.", "img": null, "comp": null}], "imagenes": {"AER-01": "https://commons.wikimedia.org/wiki/Special:FilePath/Valley%20of%20Medell%C3%ADn-%20skyline.jpg?width=640", "AER-02": "https://commons.wikimedia.org/wiki/Special:FilePath/The%20Clock%20Tower%2C%20Las%20Murallas%2C%20the%20walls%20of%20Cartagena%2C%20Colombia%20%2823955879634%29.jpg?width=640", "AER-03": "https://commons.wikimedia.org/wiki/Special:FilePath/San%20andres%20Island%20-%20Colombia.jpg?width=640", "AER-04": "https://commons.wikimedia.org/wiki/Special:FilePath/Bag%20drop%20self%20service%20Luggage%20check-in%20Baggage%20registration%20Conveyor%20belt%20%28selvbetjent%20bagasjeinnlevering%20innsjekking%20automat%20rulleb%C3%A5nd%29%20Avinor%20SAS%20Norwegian%20Wideroe%20Bergen%20Airport%20Flesland%2C%20Norway%202019-11-29%20DSC01301.jpg?width=640", "AER-05": "https://commons.wikimedia.org/wiki/Special:FilePath/Window%20seat.jpg?width=640"}, "recursos": [["otro", "Vuelo BOG–MDE 6:30 p. m.", 180]], "efectos": [{"escalar": "Reenvío de tiquete: validar documento de identidad", "resumen": "Alejandro perdió su tiquete; Eli pidió el documento y requiere validación humana antes de reenviarlo.", "tras": 52}, {"reserva": "vuelo", "h": 18.5, "personas": 2, "recurso": "Vuelo BOG–MDE 6:30 p. m.", "tras": 50}], "agenda": [[0, 21, 3, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [1, 18.5, 4, "vuelo", 2, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [2, 7, 5, "vuelo", 3, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [3, 18.5, 8, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "pendiente_pago", false], [5, 7, 9, "vuelo", 2, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [6, 18.5, 10, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [8, 7, 12, "vuelo", 4, "Vuelo BOG–MDE 6:30 p. m.", "confirmada", false], [10, 18.5, 13, "vuelo", 1, "Vuelo BOG–MDE 6:30 p. m.", "pendiente_pago", false]], "pagos": [{"items": [["AER-02", 1], ["AER-04", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "948312", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-1"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu tiquete Bogotá–Cartagena del 20 de diciembre quedó emitido (orden #{orden}). Te lo envío por este chat. ¡Buen viaje!"}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "A ti, Sergio. ¡Que tengas un excelente vuelo! ✈️"}], "rechazado": [{"emisor": "eli", "texto": "Sergio, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["AER-02", 1], ["AER-04", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "948622", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-2"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Bogotá – Cartagena (Flex) y 1 Maleta de bodega 23 kg por $360.000) Tu tiquete quedó emitido y te lo envío por este chat."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Daniela. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Daniela, no pudimos validar tu comprobante. ¿Me lo envías de nuevo?"}]}, {"items": [["AER-01", 3]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "948933", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-3"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (3 Bogotá – Medellín (Light) por $567.000) Tus tiquetes quedaron emitidos."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Julián. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Julián, el comprobante es por $360.000 y tu pedido es de $567.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Julián 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}, {"items": [["AER-03", 1]], "entrega": "no_aplica", "comp": {"img": "comprobante-aerolinea", "monto": 360000, "destinatario": "Luis Fernando Rodríguez Sandoval", "app": "DaviPlata", "ref": "949244", "fecha": "Julio 09 de 2026 - 05:39 p. m.", "hash": "demo-aerolinea-4"}, "aprobado": [{"emisor": "eli", "texto": "¡Pago confirmado! ✅ Tu pedido #{orden} (1 Bogotá – San Andrés (Promo) por $415.000) Tu tiquete quedó emitido."}, {"emisor": "cliente", "texto": "Muchas gracias"}, {"emisor": "eli", "texto": "Con gusto, Carlos. ¡Estamos para servirte!"}], "rechazado": [{"emisor": "eli", "texto": "Carlos, el comprobante es por $360.000 y tu pedido es de $415.000, así que no pudimos validarlo. ¿Me envías el comprobante correcto?"}, {"emisor": "cliente", "texto": "Uy, tienes razón, me equivoqué de comprobante. Ahora lo envío"}, {"emisor": "eli", "texto": "Tranquilo, Carlos 😊 Cuando lo tengas me lo envías y lo revisamos de inmediato."}]}]}'::jsonb
  end;
$$;

-- Los negocios de prueba son borrables en bloque: se permite borrar sus pagos aprobados (RN-C12 sigue vigente en el resto)
create or replace function app.proteger_pago()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.estado = 'aprobado' and not (tg_op = 'DELETE' and exists (
        select 1 from platform.tenants t where t.id = old.tenant_id and t.slug like 'demo-%')) then
    raise exception 'RN-C12: un pago aprobado no se modifica; registre un reverso' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- El revisor ve la foto del comprobante y a qué conversación pertenece
create or replace view elius.v_comprobantes_pendientes with (security_invoker = true) as
select cp.tenant_id, cp.id as comprobante_id, cp.creado_en, cp.monto_leido, cp.monto_esperado, cp.coincide,
       cp.app_origen, cp.referencia, cp.destinatario, cp.motivo,
       coalesce(cp.motivo like 'ALERTA:%', false) as tiene_alerta,
       o.numero as orden_numero, c.nombres as cliente,
       cp.url_archivo, cp.conversacion_id
from elius.comprobantes_pago cp
join elius.conversaciones cv on cv.tenant_id = cp.tenant_id and cv.id = cp.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join elius.ordenes o on o.tenant_id = cp.tenant_id and o.id = cp.orden_id
where cp.veredicto = 'pendiente';

-- Borra lo sembrado (clientes, chats, órdenes y comprobantes) y deja el caso listo desde cero
create or replace function elius.limpiar_caso_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from plugin_vet.mascotas where tenant_id = p_tenant;
  delete from plugin_restaurant.menus_dia where tenant_id = p_tenant;
  delete from plugin_restaurant.estaciones_cocina where tenant_id = p_tenant;
  delete from elius.pagos where tenant_id = p_tenant;
  delete from elius.comprobantes_pago where tenant_id = p_tenant;
  delete from elius.entregas where tenant_id = p_tenant;
  delete from elius.ordenes where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from plugin_airline.vuelos where tenant_id = p_tenant;
  delete from plugin_airline.rutas where tenant_id = p_tenant;
  delete from plugin_airline.aeronaves where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.contactos where tenant_id = p_tenant;   -- cascada: identidades, conversaciones y mensajes
  delete from elius.parametros_negocio where tenant_id = p_tenant and clave like 'demo\_%';
end $$;

-- Datos de ejemplo del plugin del negocio (solo el de su vertical), para que las sentencias sugeridas devuelvan filas
create or replace function elius.sembrar_plugin_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_mem uuid; v_item uuid; v_menu uuid; v_ruta uuid; v_vuelo uuid; v_tv uuid; v_at uuid; v_masc uuid; v_rp uuid; v_tr uuid;
  v_aer uuid; v_o uuid; v_d uuid; r record; k int;
begin
  select id into v_mem from platform.membresias where tenant_id = p_tenant order by creado_en limit 1;

  if p_vertical = 'veterinaria' then
    k := 0;
    for r in select id, nombres from elius.contactos where tenant_id = p_tenant order by telefono limit 8 loop
      k := k + 1;
      insert into plugin_vet.mascotas (tenant_id, nombre, especie, raza, sexo, fecha_nacimiento, peso_kg, esterilizada, alergias)
      values (p_tenant,
        (array['Max','Luna','Toby','Mia','Rocky','Nala','Simón','Kira'])[k],
        (array['perro','gato','perro','gato','perro','perro','gato','perro'])[k],
        (array['Labrador','Criollo','Beagle','Siamés','Schnauzer','Golden','Persa','Bulldog'])[k],
        (array['macho','hembra'])[1 + k % 2],
        current_date - ((k + 1) * 280),
        (array[28.5,4.2,11.3,3.8,9.6,26.1,4.9,22.4])[k],
        k % 3 = 0,
        case when k in (2, 5) then array['pollo']::text[] when k = 7 then array['penicilina']::text[] else array[]::text[] end)
      returning id into v_masc;
      insert into plugin_vet.propietarios_mascota (tenant_id, contacto_id, mascota_id, tipo, puede_autorizar, desde)
      values (p_tenant, r.id, v_masc, 'principal', true, current_date - 400);
      -- vacuna aplicada, con refuerzo próximo para varias mascotas
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = 'VET-02';
      insert into plugin_vet.aplicaciones_vacuna (tenant_id, mascota_id, vacuna_id, aplicada_por, lote, aplicada_en, proxima_dosis_en)
      values (p_tenant, v_masc, v_item, v_mem, 'LT-' || (2400 + k), current_date - (330 + k * 3), current_date + (k * 4 - 6));
    end loop;
    -- atenciones de las citas ya agendadas, con su historia clínica
    k := 0;
    for r in select rs.id as reserva_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'cita' order by rs.inicio limit 5 loop
      k := k + 1;
      select id into v_masc from plugin_vet.mascotas where tenant_id = p_tenant order by nombre offset k - 1 limit 1;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = 'VET-01';
      insert into plugin_vet.atenciones (tenant_id, reserva_id, mascota_id, servicio_id, profesional_id, motivo, estado, peso_kg, temperatura_c)
      values (p_tenant, r.reserva_id, v_masc, v_item, v_mem,
        (array['Control anual','Vómito desde ayer','Cojera en pata trasera','Picazón y enrojecimiento','Revisión posoperatoria'])[k],
        'programada', null, null) returning id into v_at;
      insert into plugin_vet.registros_clinicos (tenant_id, atencion_id, autor_id, tipo, contenido)
      values (p_tenant, v_at, v_mem, 'anamnesis', (array['Sin novedades, come y bebe bien.','Dos episodios de vómito, sin fiebre.','Cojea al levantarse.','Se rasca las orejas hace tres días.','Herida cerrando bien.'])[k]);
    end loop;

  elsif p_vertical = 'restaurante' then
    insert into plugin_restaurant.estaciones_cocina (tenant_id, nombre, tiempo_objetivo_min) values
      (p_tenant, 'Cocina caliente', 18), (p_tenant, 'Cocina fría y bar', 8), (p_tenant, 'Postres', 10);
    insert into plugin_restaurant.menus_dia (tenant_id, fecha, precio_base, confirmado_por, confirmado_en, activo)
    values (p_tenant, (now() at time zone 'America/Bogota')::date, 22000, v_mem, now(), true) returning id into v_menu;
    for r in select * from (values ('RES-03','entrada',1), ('RES-01','principal',2), ('RES-02','principal',3), ('RES-04','bebida',4), ('RES-05','postre',5)) t(sku, sec, pos) loop
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      insert into plugin_restaurant.menu_dia_items (tenant_id, menu_id, item_id, seccion, posicion) values (p_tenant, v_menu, v_item, r.sec, r.pos);
    end loop;
    k := 0;
    for r in select rs.id as reserva_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'mesa' order by rs.inicio limit 5 loop
      k := k + 1;
      insert into plugin_restaurant.celebraciones (tenant_id, reserva_id, tipo_celebracion, festejado, decoracion, notas)
      values (p_tenant, r.reserva_id,
        (array['cumpleaños','aniversario','grado','bautizo','cumpleaños'])[k],
        (array['Valentina','Pareja Ríos','Camilo','Sofía','Don Hernán'])[k],
        (array['Globos rosados','Velas y flores','Arco de globos','Tonos suaves','Letrero dorado'])[k],
        (array['Torta llega a las 7 p. m.','Mesa junto a la ventana','Traen su propia torta','Sin frutos secos','Sorpresa: apagar luces'])[k]);
    end loop;

  elsif p_vertical = 'aerolinea' then
    insert into plugin_airline.aeropuertos (codigo_iata, nombre, ciudad, pais, zona_horaria)
    select t.c, t.n, t.ci, 'CO', 'America/Bogota' from (values
      ('BOG','El Dorado','Bogotá'), ('MDE','José María Córdova','Medellín'), ('CTG','Rafael Núñez','Cartagena'), ('ADZ','Gustavo Rojas Pinilla','San Andrés')) t(c, n, ci)
    where not exists (select 1 from plugin_airline.aeropuertos a where a.codigo_iata = t.c);
    insert into plugin_airline.aeronaves (tenant_id, matricula, modelo, capacidad) values
      (p_tenant, 'HK-4501', 'Airbus A320', 180), (p_tenant, 'HK-4502', 'Airbus A319', 144);
    select id into v_aer from plugin_airline.aeronaves where tenant_id = p_tenant order by matricula limit 1;
    select id into v_o from plugin_airline.aeropuertos where codigo_iata = 'BOG';
    k := 0;
    for r in select * from (values ('MDE','AER-01',55,70,19000), ('CTG','AER-02',90,75,22000), ('ADZ','AER-03',140,120,41500)) t(dest, sku, dur, km, pre) loop
      k := k + 1;
      select id into v_d from plugin_airline.aeropuertos where codigo_iata = r.dest;
      insert into plugin_airline.rutas (tenant_id, origen_id, destino_id, distancia_km, duracion_min)
      values (p_tenant, v_o, v_d, r.km * 10, r.dur) returning id into v_ruta;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      for k in 1..2 loop
        insert into plugin_airline.vuelos (tenant_id, ruta_id, aeronave_id, numero_vuelo, salida_programada, llegada_programada, estado, puerta)
        values (p_tenant, v_ruta, v_aer, 'EL' || (100 + (select count(*) from plugin_airline.vuelos where tenant_id = p_tenant) + 1),
          date_trunc('day', now()) + (k * interval '1 day') + interval '23 hours', date_trunc('day', now()) + (k * interval '1 day') + interval '23 hours' + (r.dur * interval '1 minute'),
          'programado', 'A' || (3 + k)) returning id into v_vuelo;
        insert into plugin_airline.tarifas_vuelo (tenant_id, vuelo_id, tarifa_id, precio, cupos_totales, cupos_vendidos)
        values (p_tenant, v_vuelo, v_item, (select precio from elius.items_catalogo where id = v_item) + (k - 1) * 15000, 30, case when r.dest = 'ADZ' then 27 + k when k = 1 then 18 else 6 end);
      end loop;
    end loop;
    -- pasajeros, tramos y tiquetes de las reservas de vuelo ya agendadas
    select tv.id into v_tv from plugin_airline.tarifas_vuelo tv where tv.tenant_id = p_tenant order by tv.creado_en limit 1;
    k := 0;
    for r in select rs.id as reserva_id, rs.contacto_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'vuelo' order by rs.inicio limit 6 loop
      k := k + 1;
      insert into plugin_airline.reserva_pasajeros (tenant_id, reserva_id, contacto_id, tipo_pasajero, necesidades_especiales)
      values (p_tenant, r.reserva_id, r.contacto_id, 'ADT', case when k in (2, 5) then (array['Silla de ruedas hasta la puerta','Menú sin gluten'])[1 + k % 2] else null end)
      returning id into v_rp;
      insert into plugin_airline.tramos_reserva (tenant_id, reserva_id, tarifa_vuelo_id, orden_tramo, estado)
      values (p_tenant, r.reserva_id, v_tv, 1, 'confirmado') returning id into v_tr;
      insert into plugin_airline.tiquetes (tenant_id, reserva_pasajero_id, tramo_id, numero_tiquete, silla, estado, checkin_en)
      values (p_tenant, v_rp, v_tr, '8' || substr(md5(random()::text), 1, 12), (10 + k) || 'A', case when k <= 2 then 'usado' else 'emitido' end,
              case when k <= 2 then now() - interval '1 hour' else null end);
    end loop;
  end if;
end $$;

-- Crea los clientes del caso (uno por conversación) y deja el catálogo con los datos actuales
create or replace function elius.sembrar_clientes_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_canal uuid; v_contacto uuid; v_ident uuid; r jsonb; v_ini timestamptz; v_res uuid; v_cat uuid; v_item uuid; rr record;
begin
  select id into v_canal from elius.canales where tenant_id = p_tenant order by creado_en limit 1;
  perform elius.limpiar_caso_demo(p_tenant);
  -- categorías e ítems con su imagen (se crean los que falten y se actualizan los existentes)
  for rr in select value, ordinality - 1 as i from jsonb_array_elements(v_d->'categorias') with ordinality loop
    insert into elius.categorias_catalogo (tenant_id, nombre, orden)
    select p_tenant, rr.value #>> '{}', rr.i::int
    where not exists (select 1 from elius.categorias_catalogo where tenant_id = p_tenant and nombre = rr.value #>> '{}');
  end loop;
  for rr in select value, ordinality as k from jsonb_array_elements(v_d->'items') with ordinality loop
    select id into v_cat from elius.categorias_catalogo
    where tenant_id = p_tenant and nombre = (v_d->'categorias') ->> ((rr.value->>'cat')::int);
    insert into elius.items_catalogo (tenant_id, categoria_id, tipo, sku, nombre, descripcion, precio, impuesto_pct, duracion_min)
    values (p_tenant, v_cat, rr.value->>'tipo', rr.value->>'sku', rr.value->>'nombre', rr.value->>'desc',
            (rr.value->>'precio')::numeric, (rr.value->>'iva')::numeric, nullif(rr.value->>'dur', '')::int)
    on conflict (tenant_id, sku) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, precio = excluded.precio,
           impuesto_pct = excluded.impuesto_pct, categoria_id = excluded.categoria_id, disponible = true;
    select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = rr.value->>'sku';
    -- las fotos que puso el dueño se respetan; las del demo (propias o de Wikimedia Commons) se actualizan
    delete from elius.medios_item where tenant_id = p_tenant and item_id = v_item
      and (url like '/demo/%' or url like 'https://commons.wikimedia.org/%');
    if not exists (select 1 from elius.medios_item where tenant_id = p_tenant and item_id = v_item) then
      insert into elius.medios_item (tenant_id, item_id, tipo_archivo, url, descripcion, orden)
      values (p_tenant, v_item, 'foto', coalesce(v_d->'imagenes'->>(rr.value->>'sku'), '/demo/' || p_vertical || '-' || rr.k || '.svg'), rr.value->>'nombre', 0);
    end if;
  end loop;
  for r in select * from jsonb_array_elements(v_d->'recursos') loop
    insert into elius.recursos (tenant_id, tipo, nombre, capacidad)
    select p_tenant, r->>0, r->>1, (r->>2)::int
    where not exists (select 1 from elius.recursos where tenant_id = p_tenant and nombre = r->>1);
  end loop;
  for r in select * from jsonb_array_elements(v_d->'contactos') loop
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (p_tenant, r->>0, r->>1, r->>2, 'whatsapp') returning id into v_contacto;
    insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
    values (p_tenant, v_contacto, v_canal, r->>2, (r->>0) || ' ' || (r->>1)) returning id into v_ident;
    insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (p_tenant, v_ident, 'general');
  end loop;
  for r in select * from jsonb_array_elements(v_d->'agenda') loop
    select c.id into v_contacto from elius.contactos c where c.tenant_id = p_tenant
    order by c.telefono offset (r->>2)::int limit 1;
    v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + (r->>0)::int * interval '1 day' + ((r->>1)::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
    insert into elius.reservas (tenant_id, contacto_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
    values (p_tenant, v_contacto, 'R-' || upper(substr(md5(random()::text), 1, 5)), r->>3, r->>6, v_ini, v_ini + interval '1 hour',
            (r->>4)::int, (r->>7)::boolean, true) returning id into v_res;
    begin
      insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
      select p_tenant, v_res, rc.id, v_ini, v_ini + interval '1 hour' from elius.recursos rc where rc.tenant_id = p_tenant and rc.nombre = r->>5;
    exception when exclusion_violation then null;
    end;
  end loop;
  perform elius.sembrar_plugin_demo(p_tenant, p_vertical);
  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion) values
    (p_tenant, 'demo_indice', '0', 'numero', 'Mensajes de prueba ya entregados (caso de demostración)'),
    (p_tenant, 'demo_version', '9', 'texto', 'Versión del guion sembrado');
end $$;

-- Crea (o reutiliza) el negocio de prueba del caso para el usuario que llama y lo deja activo
create or replace function platform.cargar_caso_demo(p_vertical text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_slug text;
  v_tenant uuid; v_agente uuid; v_canal uuid;
  
begin
  if v_uid is null then raise exception 'Debe iniciar sesión' using errcode = '42501'; end if;
  if v_d is null then raise exception 'Caso desconocido: %', p_vertical; end if;
  v_slug := 'demo-' || p_vertical || '-' || substr(replace(v_uid::text, '-', ''), 1, 6);

  select id into v_tenant from platform.tenants where slug = v_slug;
  if v_tenant is not null then
    -- si quedó de una versión anterior del caso, se vuelve a sembrar
    if coalesce((select valor from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_version'), '') <> '9' then
      perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
    end if;
    perform platform.cambiar_tenant(v_tenant);
    return v_tenant;
  end if;

  v_tenant := platform.crear_tenant(v_d->>'negocio', v_slug, p_vertical);
  select id into v_agente from elius.agentes where tenant_id = v_tenant limit 1;
  insert into elius.canales (tenant_id, agente_id, tipo, nombre, identificador_externo)
  values (v_tenant, v_agente, 'whatsapp', 'WhatsApp de prueba', 'demo-' || v_slug) returning id into v_canal;

  perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
  perform platform.cambiar_tenant(v_tenant);
  return v_tenant;
end $$;

-- Lo que Eli deja registrado al responder: consumo de IA y, según el guion, un caso pendiente o una reserva de hoy
create or replace function elius.efectos_demo(p_tenant uuid, p_conv uuid, p_msg uuid, p_texto text, p_efectos jsonb, p_tras int)
returns void language plpgsql security definer set search_path = '' as $$
declare e jsonb; v_contacto uuid; v_reserva uuid; v_recurso uuid; v_ini timestamptz;
begin
  insert into elius.consumos_llm (tenant_id, conversacion_id, mensaje_id, proveedor, modelo, tokens_entrada, tokens_salida, tokens_cache, costo_usd, latencia_ms)
  values (p_tenant, p_conv, p_msg, 'anthropic', 'claude-sonnet-5-5', 900 + length(p_texto) * 2, 40 + length(p_texto) / 3, 600,
          round((0.0009 + length(p_texto) * 0.000004)::numeric, 6), 900 + (length(p_texto) * 7) % 1400);
  for e in select * from jsonb_array_elements(coalesce(p_efectos, '[]'::jsonb)) where (value->>'tras')::int = p_tras loop
    if e ? 'escalar' then
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
      values (p_tenant, p_conv, e->>'escalar',
              (select m.contenido from elius.mensajes m where m.tenant_id = p_tenant and m.conversacion_id = p_conv and m.emisor = 'cliente' order by m.creado_en desc limit 1),
              e->>'resumen');
    elsif e ? 'reserva' then
      select i.contacto_id into v_contacto from elius.conversaciones c
      join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
      where c.tenant_id = p_tenant and c.id = p_conv;
      v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + ((e->>'h')::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
      values (p_tenant, v_contacto, p_conv, 'R-' || upper(substr(md5(random()::text), 1, 5)), e->>'reserva', 'confirmada',
              v_ini, v_ini + interval '1 hour', coalesce((e->>'personas')::int, 1), coalesce((e->>'urgente')::boolean, false), true)
      returning id into v_reserva;
      select id into v_recurso from elius.recursos where tenant_id = p_tenant and nombre = e->>'recurso';
      if v_recurso is not null then
        begin
          insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
          values (p_tenant, v_reserva, v_recurso, v_ini, v_ini + interval '1 hour');
        exception when exclusion_violation then null;   -- el recurso ya estaba ocupado a esa hora: la reserva queda sin recurso
        end;
      end if;
    end if;
  end loop;
end $$;

-- Cuántos comprobantes de la prueba esperan decisión y cuántos mensajes posteriores faltan por entregar
create or replace function elius.estado_demo(p_tenant uuid, p_d jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_pidx int; v_esperando int := 0; v_post int := 0; v_ver text; v_k int; v_p jsonb;
begin
  for v_pidx in 0 .. coalesce(jsonb_array_length(p_d->'pagos'), 0) - 1 loop
    v_p := p_d->'pagos'->v_pidx;
    select cp.veredicto into v_ver from elius.comprobantes_pago cp
    where cp.tenant_id = p_tenant and cp.media_id = 'demo-' || v_pidx order by cp.creado_en desc limit 1;
    if v_ver = 'pendiente' then
      v_esperando := v_esperando + 1;
    elsif v_ver in ('aprobado', 'rechazado') then
      select coalesce(valor::int, 0) into v_k from elius.parametros_negocio where tenant_id = p_tenant and clave = 'demo_post_' || v_pidx;
      if coalesce(v_k, 0) < jsonb_array_length(v_p->v_ver) then v_post := v_post + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('esperando', v_esperando, 'post', v_post);
end $$;

-- Entrega el siguiente mensaje del guion. El panel lo llama cada pocos segundos.
-- 1) Si quien revisa ya decidió un comprobante, Eli continúa esa conversación (antes que lo demás).
-- 2) Si no, llega el siguiente mensaje de la cola; el comprobante se registra al enviarlo el cliente.
-- Si una persona tomó la conversación, Eli no responde en ella (RN-C19) y se salta ese mensaje.
create or replace function elius.siguiente_mensaje_demo()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_vertical text; v_slug text; v_d jsonb; v_guion jsonb; v_pagos jsonb; v_i int; v_total int;
  v_g jsonb; v_conv uuid; v_estado text; v_texto text; v_k int; v_p jsonb; v_pidx int;
  v_ver text; v_orden uuid; v_contacto uuid; v_esperado numeric; v_url text; v_it jsonb; v_emisor text;
  v_est jsonb; v_clientes int; v_fin boolean; v_tipo text; v_dir uuid; v_mid uuid;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select slug, vertical into v_slug, v_vertical from platform.tenants where id = v_tenant;
  if v_slug not like 'demo-%' then raise exception 'Este negocio no es un caso de prueba'; end if;
  v_d := elius.datos_caso_demo(v_vertical);
  v_guion := v_d->'guion'; v_pagos := coalesce(v_d->'pagos', '[]'::jsonb); v_total := jsonb_array_length(v_guion);
  select valor::int into v_i from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_indice';

  -- 1) continuar las conversaciones cuyo comprobante ya fue decidido
  for v_pidx in 0 .. jsonb_array_length(v_pagos) - 1 loop
    v_p := v_pagos->v_pidx;
    select cp.veredicto, cp.conversacion_id, cp.orden_id into v_ver, v_conv, v_orden
    from elius.comprobantes_pago cp where cp.tenant_id = v_tenant and cp.media_id = 'demo-' || v_pidx
    order by cp.creado_en desc limit 1;
    continue when v_ver is null or v_ver = 'pendiente';
    select coalesce(valor::int, 0) into v_k from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_post_' || v_pidx;
    v_k := coalesce(v_k, 0);
    if v_k < jsonb_array_length(v_p->v_ver) then
      v_g := (v_p->v_ver)->v_k;
      v_emisor := v_g->>'emisor';
      v_texto := replace(v_g->>'texto', '{orden}', coalesce((select numero::text from elius.ordenes where tenant_id = v_tenant and id = v_orden), ''));
      select estado into v_estado from elius.conversaciones where tenant_id = v_tenant and id = v_conv;
      if not (v_emisor = 'eli' and v_estado in ('humano', 'pausa')) then
        insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, estado_entrega, procesado)
        values (v_tenant, v_conv, v_emisor, 'texto', v_texto, case when v_emisor = 'cliente' then 'recibido' else 'entregado' end, true)
        returning id into v_mid;
        if v_emisor = 'eli' then perform elius.efectos_demo(v_tenant, v_conv, v_mid, v_texto, null, -1); end if;
      end if;
      insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
      values (v_tenant, 'demo_post_' || v_pidx, (v_k + 1)::text, 'numero', 'Mensajes posteriores a la decisión ya entregados')
      on conflict (tenant_id, clave) do update set valor = (v_k + 1)::text;
      v_est := elius.estado_demo(v_tenant, v_d);
      select count(distinct conversacion_id) into v_clientes from elius.mensajes where tenant_id = v_tenant and emisor = 'cliente';
      return jsonb_build_object('terminado', v_i >= v_total and (v_est->>'esperando')::int = 0 and (v_est->>'post')::int = 0,
        'indice', v_i, 'total', v_total, 'emisor', v_emisor, 'conversacion_id', v_conv, 'clientes', v_clientes,
        'esperando', (v_est->>'esperando')::int, 'decision', v_ver);
    end if;
  end loop;

  -- 2) siguiente mensaje de la cola principal
  loop
    exit when v_i >= v_total;
    v_g := v_guion -> v_i;
    select c.id, c.estado into v_conv, v_estado
    from elius.conversaciones c
    join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
    where c.tenant_id = v_tenant order by i.id_externo offset (v_g->>'conv')::int limit 1;
    exit when not (v_g->>'emisor' = 'eli' and v_estado in ('humano', 'pausa'));
    v_i := v_i + 1;
  end loop;

  if v_i < v_total then
    v_texto := v_g->>'texto';
    v_url := case when (v_g->>'img') is not null then
              coalesce(v_d->'imagenes'->>(v_d->'items'->((v_g->>'img')::int - 1)->>'sku'), '/demo/' || v_vertical || '-' || (v_g->>'img') || '.svg') end;
    v_tipo := case when v_texto like '📎%' or v_url is not null then 'imagen' else 'texto' end;

    if (v_g->>'comp') is not null then
      -- el cliente envía el comprobante: se crea su orden y el comprobante queda pendiente de revisión
      v_pidx := (v_g->>'comp')::int; v_p := v_pagos->v_pidx;
      v_url := '/demo/' || (v_p->'comp'->>'img') || '.jpg';
      select i.contacto_id into v_contacto from elius.conversaciones c
      join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
      where c.tenant_id = v_tenant and c.id = v_conv;
      if v_p->>'entrega' = 'domicilio' then
        insert into elius.direcciones (tenant_id, contacto_id, etiqueta, direccion, ciudad, es_principal)
        values (v_tenant, v_contacto, 'Casa', 'Calle 45 # 12-30', 'Bogotá', true) returning id into v_dir;
      else v_dir := null; end if;
      insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega, direccion_entrega_id)
      values (v_tenant, v_contacto, v_conv, 'whatsapp', v_p->>'entrega', v_dir) returning id into v_orden;
      for v_it in select * from jsonb_array_elements(v_p->'items') loop
        insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad)
        select v_tenant, v_orden, it.id, (v_it->>1)::numeric from elius.items_catalogo it
        where it.tenant_id = v_tenant and it.sku = (v_it->>0);
      end loop;
      update elius.ordenes set estado = 'esperando_pago' where tenant_id = v_tenant and id = v_orden;
      select saldo_pendiente into v_esperado from elius.v_saldo_ordenes where tenant_id = v_tenant and orden_id = v_orden;
      insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, destinatario,
                                           app_origen, referencia, fecha_texto, hash_archivo, url_archivo, media_id)
      values (v_tenant, v_orden, v_conv, (v_p->'comp'->>'monto')::numeric, v_esperado, v_p->'comp'->>'destinatario',
              v_p->'comp'->>'app', v_p->'comp'->>'ref', v_p->'comp'->>'fecha', v_p->'comp'->>'hash', v_url, 'demo-' || v_pidx);
      v_tipo := 'imagen';
    end if;

    insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, url_adjunto, estado_entrega, procesado)
    values (v_tenant, v_conv, v_g->>'emisor', v_tipo, v_texto, v_url,
            case when v_g->>'emisor' = 'cliente' then 'recibido' else 'entregado' end, true)
    returning id into v_mid;
    if v_g->>'emisor' = 'eli' then perform elius.efectos_demo(v_tenant, v_conv, v_mid, v_texto, v_d->'efectos', v_i); end if;
    v_i := v_i + 1;
    update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
    v_emisor := v_g->>'emisor';
  else
    update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
    v_emisor := null; v_conv := null;
  end if;

  v_est := elius.estado_demo(v_tenant, v_d);
  select count(distinct conversacion_id) into v_clientes from elius.mensajes where tenant_id = v_tenant and emisor = 'cliente';
  v_fin := v_i >= v_total and (v_est->>'esperando')::int = 0 and (v_est->>'post')::int = 0;
  return jsonb_build_object('terminado', v_fin, 'indice', v_i, 'total', v_total, 'emisor', v_emisor, 'conversacion_id', v_conv,
                            'clientes', v_clientes, 'esperando', (v_est->>'esperando')::int);
end $$;

-- Vuelve a empezar la demostración del negocio de prueba actual
create or replace function elius.reiniciar_demo()
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_vertical text;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select vertical into v_vertical from platform.tenants where id = v_tenant and slug like 'demo-%';
  if v_vertical is null then raise exception 'Este negocio no es un caso de prueba'; end if;
  perform elius.sembrar_clientes_demo(v_tenant, v_vertical);
end $$;

revoke execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() from public, anon;
revoke execute on function elius.efectos_demo(uuid, uuid, uuid, text, jsonb, int), elius.sembrar_clientes_demo(uuid, text), elius.sembrar_plugin_demo(uuid, text), elius.limpiar_caso_demo(uuid), elius.estado_demo(uuid, jsonb) from public, anon, authenticated;
grant execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() to authenticated;
comment on function platform.cargar_caso_demo(text) is 'Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes';
comment on function elius.siguiente_mensaje_demo() is 'Entrega el siguiente mensaje del guion del caso de prueba; tras aprobar o rechazar un comprobante, Eli continúa esa conversación';
-- =============================================================================
-- 1300 · Agenda tipo calendario y cambio de rol en los casos de prueba
-- =============================================================================

-- Agenda de cualquier día (el calendario del panel pide un mes completo)
create or replace view elius.v_agenda_calendario with (security_invoker = true) as
select r.tenant_id, r.id as reserva_id, r.codigo, r.tipo, r.estado, r.inicio, r.fin, r.personas,
       r.urgente, r.visto, r.llegada_en, r.notas,
       c.nombres || coalesce(' ' || c.apellidos, '') as cliente, c.telefono,
       string_agg(rc.nombre, ', ' order by rc.nombre) as recursos,
       m.cargo as responsable_cargo
from elius.reservas r
join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
left join elius.asignaciones_recurso ar on ar.tenant_id = r.tenant_id and ar.reserva_id = r.id and ar.estado = 'activa'
left join elius.recursos rc on rc.tenant_id = ar.tenant_id and rc.id = ar.recurso_id
left join platform.membresias m on m.tenant_id = r.tenant_id and m.id = r.responsable_id
group by r.tenant_id, r.id, c.nombres, c.apellidos, c.telefono, m.cargo;
comment on view elius.v_agenda_calendario is 'Todas las reservas con cliente y recursos (calendario del panel)';
grant select on elius.v_agenda_calendario to authenticated, service_role, elius_app;

-- El día de la agenda se cuenta en hora de Colombia, no en UTC
create or replace view elius.v_agenda_dia with (security_invoker = true) as
select tenant_id, reserva_id, codigo, tipo, estado, inicio, fin, personas, urgente, visto, llegada_en,
       cliente, telefono, recursos, responsable_cargo
from elius.v_agenda_calendario
where inicio >= (date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota')
  and inicio <  ((date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day') at time zone 'America/Bogota')
  and estado in ('pendiente_pago', 'confirmada', 'asistio');

-- Quien prueba un caso puede ver el panel con cada rol del negocio (la seguridad la sigue aplicando la base)
create or replace function elius.cambiar_rol_demo(p_rol text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_rol uuid;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  if not exists (select 1 from platform.tenants where id = v_tenant and slug like 'demo-%') then
    raise exception 'Solo en los casos de prueba';
  end if;
  select id into v_rol from platform.roles where codigo = p_rol and codigo in ('administrador', 'operador', 'analista');
  if v_rol is null then raise exception 'Rol no disponible en la prueba: %', p_rol; end if;
  update platform.membresias set rol_id = v_rol, cargo = initcap(p_rol)
  where tenant_id = v_tenant and usuario_id = auth.uid();
end $$;
revoke execute on function elius.cambiar_rol_demo(text) from public, anon;
grant execute on function elius.cambiar_rol_demo(text) to authenticated;
comment on function elius.cambiar_rol_demo(text) is 'Cambia el rol de quien prueba un caso (administrador, operador o analista) para ver el panel de cada uno';

-- En los casos de prueba quien prueba puede cambiar su propio rol (el negocio de prueba es descartable)
create or replace function app.proteger_ultimo_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_admin uuid;
begin
  select id into v_admin from platform.roles where codigo = 'administrador';
  if old.rol_id = v_admin and old.estado = 'activo'
     and (tg_op = 'DELETE' or new.rol_id <> v_admin or new.estado <> 'activo')
     and not exists (select 1 from platform.membresias m
                     where m.tenant_id = old.tenant_id and m.id <> old.id and m.rol_id = v_admin and m.estado = 'activo')
     and exists (select 1 from platform.tenants t where t.id = old.tenant_id and t.slug not like 'demo-%') then
    raise exception 'RN-P04: el tenant debe conservar al menos un Administrador activo' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
-- =============================================================================
-- 1400 · Validaciones de datos, auditoría consultable y reportes por mes
-- =============================================================================

-- ---------- 1. Validaciones (NOT VALID: se aplican a todo dato nuevo sin reventar el histórico) ----------
-- Correo: debe traer dominio completo (usuario@dominio.ext)
alter table elius.contactos drop constraint if exists ck_contactos_email;
alter table elius.contactos add constraint ck_contactos_email
  check (email is null or email ~* '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$') not valid;
alter table platform.invitaciones drop constraint if exists ck_invitaciones_email;
alter table platform.invitaciones add constraint ck_invitaciones_email
  check (email ~* '^[a-z0-9._%+-]+@[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$') not valid;

-- Documento: cédula, tarjeta, NIT… solo números; el pasaporte admite letras y números
alter table elius.contactos add constraint ck_contactos_tipo_documento
  check (tipo_documento is null or tipo_documento in ('CC', 'CE', 'TI', 'RC', 'NIT', 'PA')) not valid;
alter table elius.contactos add constraint ck_contactos_documento
  check (numero_documento is null
         or (tipo_documento = 'PA' and numero_documento ~ '^[A-Za-z0-9]{5,15}$')
         or (coalesce(tipo_documento, 'CC') <> 'PA' and numero_documento ~ '^[0-9]{5,15}$')) not valid;

-- Precios e impuestos: ya existen ck_items_precio (>= 0), ck_items_impuesto (0 a 100) y ck_items_duracion (> 0)
comment on constraint ck_items_precio on elius.items_catalogo is 'El precio de venta no puede ser negativo';
comment on constraint ck_contactos_documento on elius.contactos is 'Cédula y demás documentos: solo números (pasaporte: letras y números)';
comment on constraint ck_contactos_email on elius.contactos is 'Correo con dominio completo';

-- ---------- 2. Auditoría consultable desde el panel (el esquema audit no está expuesto a la API) ----------
create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id;
comment on view elius.v_auditoria is 'Bitácora legible: quién (cargo y rol), qué tabla, qué operación y qué campos cambiaron o qué consulta ejecutó';
grant select on elius.v_auditoria to authenticated, service_role, elius_app;

-- ---------- 3. Vistas reutilizables por mes (se construyen sobre las vistas diarias ya existentes) ----------
create or replace view elius.v_resumen_mensual with (security_invoker = true) as
select tenant_id, mes,
       coalesce(v.ordenes, 0) as ordenes, coalesce(v.ventas, 0) as ventas, v.ticket_promedio,
       coalesce(c.conversaciones, 0) as conversaciones, coalesce(c.escaladas, 0) as escaladas,
       case when coalesce(c.conversaciones, 0) > 0
            then round(100.0 * (c.conversaciones - c.escaladas) / c.conversaciones, 1) end as pct_resueltas_por_eli
from (select tenant_id, date_trunc('month', dia)::date as mes, sum(ordenes) as ordenes, sum(ventas) as ventas,
             round(sum(ventas) / nullif(sum(ordenes), 0), 2) as ticket_promedio
      from elius.v_ventas_diarias group by 1, 2) v
full join (select tenant_id, date_trunc('month', dia)::date as mes, sum(conversaciones) as conversaciones, sum(escaladas) as escaladas
           from elius.v_metricas_conversaciones group by 1, 2) c using (tenant_id, mes);
comment on view elius.v_resumen_mensual is 'Un renglón por mes: órdenes, ventas, ticket promedio y atención de Eli (reutiliza v_ventas_diarias y v_metricas_conversaciones)';

create or replace view elius.v_items_mas_vendidos_mensual with (security_invoker = true) as
select oi.tenant_id, date_trunc('month', o.colocada_en)::date as mes, ic.id as item_id, ic.nombre, ic.tipo,
       sum(oi.cantidad) as unidades, sum(oi.total_linea) as ventas
from elius.orden_items oi
join elius.ordenes o on o.tenant_id = oi.tenant_id and o.id = oi.orden_id and o.estado not in ('cotizando', 'cancelada')
join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
group by oi.tenant_id, 2, ic.id, ic.nombre, ic.tipo;
comment on view elius.v_items_mas_vendidos_mensual is 'Ítems más vendidos por mes (filtra por la columna mes)';
grant select on elius.v_resumen_mensual, elius.v_items_mas_vendidos_mensual to authenticated, service_role, elius_app;
-- =============================================================================
-- 1500 · El equipo registra que el cliente NO llegó (complemento de marcar_llegada)
-- Pasa la reserva a "no_asistio" y libera la mesa, consultorio o recurso asignado.
-- =============================================================================
create or replace function elius.marcar_no_llegada(p_reserva uuid)
returns void language plpgsql set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id();
begin
  update elius.reservas set estado = 'no_asistio', visto = true
  where id = p_reserva and tenant_id = v_tenant and estado = 'confirmada' and llegada_en is null;
  if found then
    update elius.asignaciones_recurso set estado = 'liberada' where tenant_id = v_tenant and reserva_id = p_reserva;
  end if;
end $$;
-- =============================================================================
-- 1600 · Permisos por rol más estrictos
--  · Solo el Administrador aprueba o rechaza comprobantes (el Operador los ve).
--  · El Operador y el Analista solo consultan el catálogo (ya lo exige la matriz de permisos; aquí se prueba).
--  · La consola SQL (y las vistas que se crean con ella) la usan el Administrador y el Super Admin.
-- =============================================================================
create or replace function app.solo_admin_decide_comprobantes()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.veredicto is distinct from old.veredicto and auth.uid() is not null and not app.puede('pagos', 'total') then
    raise exception 'Solo el Administrador puede aprobar o rechazar comprobantes' using errcode = '42501';
  end if;
  return new;
end $$;
drop trigger if exists t53_solo_admin_decide on elius.comprobantes_pago;
create trigger t53_solo_admin_decide before update of veredicto on elius.comprobantes_pago
  for each row execute function app.solo_admin_decide_comprobantes();

create or replace function elius.consola_sql(p_sql text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_sql   text := regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '');
  v_low   text := lower(v_sql);
  v_filas jsonb;
  v_n     bigint := 0;
  v_tipo  text;
begin
  if auth.uid() is null or not (app.puede('configuracion', 'total') or app.es_super_admin()) then
    raise exception 'Solo un Administrador (o el Super Admin) puede usar la consola SQL';
  end if;
  if v_sql = '' then raise exception 'Escribe una sentencia'; end if;
  if v_sql ~ ';' then raise exception 'Una sola sentencia por ejecución'; end if;
  if v_low ~ '(--|/\*)' then raise exception 'No se permiten comentarios dentro de la sentencia'; end if;

  v_tipo := (regexp_match(v_low, '^\s*(select|with|insert|update|create)\M'))[1];
  if v_tipo is null then
    raise exception 'Solo se permiten SELECT, INSERT, UPDATE y CREATE';
  end if;
  if v_low ~ '\m(drop|truncate|delete|alter|grant|revoke|copy|vacuum|reindex|cluster|lock|listen|notify|refresh|import|load|reset|do|call)\M'
     or v_low ~ '\mset\s+(local|session|role|search_path|constraints)\M'
     or v_low ~ '\m(set_config|current_setting|pg_sleep|pg_terminate_backend|pg_cancel_backend|dblink|lo_import|lo_export|pg_read_file|pg_ls_dir)\M'
     or v_low ~ '\mcomment\s+on\M' then
    raise exception 'Sentencia no permitida en la consola (DROP, TRUNCATE, DELETE, ALTER, GRANT, SET… están bloqueados)';
  end if;
  if v_tipo = 'create' then
    if v_low !~ 'practica\.' then
      raise exception 'CREATE solo se permite en el esquema practica (ej. CREATE TABLE practica.prueba (...))';
    end if;
    if v_low ~ '\mcreate\s+(or\s+replace\s+)?(schema|role|user|database|extension|policy|publication|subscription|event|rule|server|foreign|materialized)\M' then
      raise exception 'Ese tipo de CREATE no está permitido';
    end if;
  end if;

  perform elius.consola_auditar(v_sql);

  perform set_config('statement_timeout', '8000', true);
  execute 'set local role elius_revisor';
  if v_tipo in ('select', 'with') then
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from (%s) q limit 500) t', v_sql)
      into v_filas;
    v_n := jsonb_array_length(v_filas);
  else
    execute v_sql;
    get diagnostics v_n = row_count;
    v_filas := '[]'::jsonb;
  end if;
  return jsonb_build_object('tipo', v_tipo, 'filas', v_filas, 'afectadas', v_n);
end $$;
-- =============================================================================
-- 1700 · Aviso al celular cuando llega un comprobante por revisar
--  · Envía una notificación push a la app gratuita ntfy (https://ntfy.sh) en el celular de quien revisa.
--  · El tema (topic) es un nombre secreto guardado en platform.ajustes_globales; cada negocio puede
--    tener el suyo en parametros_negocio ('ntfy_topic').
--  · Usa pg_net (viene con Supabase). Si no está disponible o falla, el comprobante se guarda igual.
-- =============================================================================
do $$ begin
  create extension if not exists pg_net with schema extensions;
exception when others then raise notice 'pg_net no está disponible: no se enviarán avisos al celular';
end $$;

create table if not exists platform.ajustes_globales (
  clave text primary key,
  valor text not null,
  descripcion text
);
alter table platform.ajustes_globales enable row level security;   -- sin políticas: solo lo leen las funciones de confianza
comment on table platform.ajustes_globales is 'Ajustes de toda la plataforma (no por negocio). Sin acceso desde el panel.';

insert into platform.ajustes_globales (clave, valor, descripcion) values
  ('ntfy_topic', 'elius-pagos-' || substr(md5(random()::text || clock_timestamp()::text), 1, 14), 'Tema secreto de ntfy para avisar comprobantes por revisar'),
  ('panel_url', 'https://chatbot-elius-panel.zaqd7q.easypanel.host', 'Dirección del panel (se abre al tocar el aviso)')
on conflict (clave) do nothing;

create or replace function app.avisar_comprobante_celular()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_topic text; v_panel text; v_cliente text; v_negocio text; v_texto text; v_alerta boolean;
begin
  begin
    v_topic := coalesce(nullif(app.parametro(new.tenant_id, 'ntfy_topic'), ''),
                        (select valor from platform.ajustes_globales where clave = 'ntfy_topic'));
    v_panel := coalesce((select valor from platform.ajustes_globales where clave = 'panel_url'), '');
    if v_topic is null or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return null; end if;
    select c.nombres into v_cliente from elius.ordenes o join elius.contactos c on c.tenant_id = o.tenant_id and c.id = o.contacto_id
      where o.tenant_id = new.tenant_id and o.id = new.orden_id;
    select nombre into v_negocio from platform.tenants where id = new.tenant_id;
    v_alerta := coalesce(new.motivo, '') like 'ALERTA%';
    v_texto := coalesce(v_cliente, 'Un cliente') || ' envió un comprobante por $' || to_char(coalesce(new.monto_leido, 0), 'FM999G999G999')
               || ' en ' || coalesce(v_negocio, 'tu negocio') || case when v_alerta then ' · ⚠ el monto no coincide con el pedido' else '' end;
    execute 'select net.http_post($1, $2, $3, $4, $5)' using
      'https://ntfy.sh', jsonb_build_object('topic', v_topic, 'title', 'Comprobante por revisar', 'message', v_texto,
        'priority', case when v_alerta then 5 else 4 end, 'tags', jsonb_build_array('money_with_wings'),
        'click', v_panel || '/#/comprobantes',
        'actions', jsonb_build_array(jsonb_build_object('action', 'view', 'label', 'Aprobar o rechazar', 'url', v_panel || '/#/comprobantes'))),
      '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 5000;
  exception when others then
    raise notice 'No se pudo avisar al celular: %', sqlerrm;
  end;
  return null;
end $$;
drop trigger if exists t56_aviso_celular_comprobante on elius.comprobantes_pago;
create trigger t56_aviso_celular_comprobante after insert on elius.comprobantes_pago
  for each row execute function app.avisar_comprobante_celular();

-- Orden de nombres de triggers: el que limita la decisión al Administrador pasa de t53 a t55 (t53 y t54 ya existían)
drop trigger if exists t53_solo_admin_decide on elius.comprobantes_pago;
drop trigger if exists t55_solo_admin_decide on elius.comprobantes_pago;
create trigger t55_solo_admin_decide before update of veredicto on elius.comprobantes_pago
  for each row execute function app.solo_admin_decide_comprobantes();
-- =============================================================================
-- 1800 · El Administrador ve en el panel a qué tema suscribir el celular y puede mandar un aviso de prueba
-- =============================================================================
create or replace function elius.avisos_celular_info()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_topic text;
begin
  if auth.uid() is null or not app.puede('configuracion', 'total') then
    raise exception 'Solo un Administrador puede ver los avisos al celular' using errcode = '42501';
  end if;
  v_topic := coalesce(nullif(app.parametro(app.current_tenant_id(), 'ntfy_topic'), ''),
                      (select valor from platform.ajustes_globales where clave = 'ntfy_topic'));
  return jsonb_build_object('tema', v_topic, 'servidor', 'https://ntfy.sh');
end $$;

create or replace function elius.enviar_aviso_prueba()
returns void language plpgsql security definer set search_path = '' as $$
declare v_topic text; v_panel text;
begin
  if auth.uid() is null or not app.puede('configuracion', 'total') then
    raise exception 'Solo un Administrador puede enviar el aviso de prueba' using errcode = '42501';
  end if;
  v_topic := coalesce(nullif(app.parametro(app.current_tenant_id(), 'ntfy_topic'), ''),
                      (select valor from platform.ajustes_globales where clave = 'ntfy_topic'));
  v_panel := coalesce((select valor from platform.ajustes_globales where clave = 'panel_url'), '');
  if to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then
    raise exception 'El envío de avisos no está disponible en esta base';
  end if;
  execute 'select net.http_post($1, $2, $3, $4, $5)' using
    'https://ntfy.sh', jsonb_build_object('topic', v_topic, 'title', 'Prueba de aviso',
      'message', 'Si ves esto en tu celular, los avisos de comprobantes funcionan.', 'priority', 4,
      'tags', jsonb_build_array('white_check_mark'), 'click', v_panel || '/#/comprobantes'),
    '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 5000;
end $$;

revoke execute on function elius.avisos_celular_info(), elius.enviar_aviso_prueba() from public, anon;
grant execute on function elius.avisos_celular_info(), elius.enviar_aviso_prueba() to authenticated;
-- =============================================================================
-- 1900 · Notificaciones push en el navegador/celular (PWA) cuando llega un comprobante
--  · Cada Administrador activa las notificaciones en su dispositivo desde Comprobantes (se guarda su suscripción).
--  · Al llegar un comprobante, la base llama al servicio `notificaciones/` (Easypanel), que cifra y envía el push.
--  · El servicio no guarda nada: la base le manda las suscripciones en cada llamada.
--  · Ajustes en platform.ajustes_globales: vapid_public (pública), push_service_url (se llena al desplegar el servicio),
--    push_service_token (secreto compartido con el servicio, se genera aquí).
-- =============================================================================
create table if not exists platform.push_suscripciones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid not null,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  dispositivo text,
  activo boolean not null default true,
  creado_en timestamptz not null default now()
);
alter table platform.push_suscripciones enable row level security;   -- sin políticas: solo las funciones de confianza
create index if not exists ix_push_suscripciones_usuario on platform.push_suscripciones (usuario_id) where activo;
comment on table platform.push_suscripciones is 'Dispositivos de cada usuario suscritos a notificaciones push (Web Push)';

insert into platform.ajustes_globales (clave, valor, descripcion) values
  ('vapid_public', 'BPnLJKdx9esiNICaQgzmSq67h1-VNbBhdpnUXWcfvRX1txl4srT8XAtH1PbdXxvoh__DQXThPJGYiRjR3DnEJdM', 'Llave pública VAPID del servicio de notificaciones (la privada vive solo en el servicio)'),
  ('push_service_url', '', 'Dirección pública del servicio de notificaciones, sin barra final (se llena al desplegarlo)'),
  ('push_service_token', encode(extensions.gen_random_bytes(24), 'hex'), 'Secreto compartido con el servicio de notificaciones')
on conflict (clave) do nothing;

-- El panel necesita la llave pública para suscribir el navegador
create or replace function elius.push_clave_publica()
returns text language sql stable security definer set search_path = '' as $$
  select valor from platform.ajustes_globales where clave = 'vapid_public' and auth.uid() is not null;
$$;

create or replace function elius.guardar_suscripcion_push(p_endpoint text, p_p256dh text, p_auth text, p_dispositivo text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not app.puede('configuracion', 'total') then
    raise exception 'Solo un Administrador activa las notificaciones' using errcode = '42501';
  end if;
  insert into platform.push_suscripciones (usuario_id, endpoint, p256dh, auth, dispositivo)
  values (auth.uid(), p_endpoint, p_p256dh, p_auth, p_dispositivo)
  on conflict (endpoint) do update set usuario_id = auth.uid(), p256dh = excluded.p256dh, auth = excluded.auth,
    dispositivo = excluded.dispositivo, activo = true;
end $$;

create or replace function elius.quitar_suscripcion_push(p_endpoint text)
returns void language sql security definer set search_path = '' as $$
  update platform.push_suscripciones set activo = false where endpoint = p_endpoint and usuario_id = auth.uid();
$$;

create or replace function elius.estado_push()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'dispositivos', (select count(*) from platform.push_suscripciones where usuario_id = auth.uid() and activo),
    'servicio', coalesce((select valor <> '' from platform.ajustes_globales where clave = 'push_service_url'), false));
$$;

-- Envía un push a los Administradores activos del negocio (o solo a un usuario)
create or replace function app.enviar_push_tenant(p_tenant uuid, p_mensaje jsonb, p_usuario uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_url text; v_token text; v_subs jsonb;
begin
  select valor into v_url from platform.ajustes_globales where clave = 'push_service_url';
  select valor into v_token from platform.ajustes_globales where clave = 'push_service_token';
  if coalesce(v_url, '') = '' or to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is null then return; end if;
  select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)) into v_subs
  from platform.push_suscripciones s
  where s.activo and (
        (p_usuario is not null and s.usuario_id = p_usuario)
     or (p_usuario is null and exists (
          select 1 from platform.membresias m join platform.roles r on r.id = m.rol_id and r.codigo = 'administrador'
          where m.tenant_id = p_tenant and m.usuario_id = s.usuario_id and m.estado = 'activo')));
  if v_subs is null then return; end if;
  execute 'select net.http_post($1, $2, $3, $4, $5)' using
    v_url || '/enviar', jsonb_build_object('subs', v_subs, 'mensaje', p_mensaje), '{}'::jsonb,
    jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_token), 8000;
exception when others then
  raise notice 'No se pudo enviar el push: %', sqlerrm;
end $$;
revoke execute on function app.enviar_push_tenant(uuid, jsonb, uuid) from public, anon, authenticated;

create or replace function elius.enviar_push_prueba()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null or not app.puede('configuracion', 'total') then
    raise exception 'Solo un Administrador puede enviar la notificación de prueba' using errcode = '42501';
  end if;
  perform app.enviar_push_tenant(app.current_tenant_id(),
    jsonb_build_object('titulo', 'Prueba de notificación', 'cuerpo', 'Si ves esto, las notificaciones de Elius funcionan en este dispositivo.',
                       'url', '/#/comprobantes', 'tag', 'prueba'), auth.uid());
end $$;

revoke execute on function elius.push_clave_publica(), elius.guardar_suscripcion_push(text, text, text, text), elius.quitar_suscripcion_push(text),
  elius.estado_push(), elius.enviar_push_prueba() from public, anon;
grant execute on function elius.push_clave_publica(), elius.guardar_suscripcion_push(text, text, text, text), elius.quitar_suscripcion_push(text),
  elius.estado_push(), elius.enviar_push_prueba() to authenticated;

-- El aviso de cada comprobante ahora también sale como push al navegador/celular (además de ntfy, si hay tema)
create or replace function app.avisar_comprobante_celular()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_topic text; v_panel text; v_cliente text; v_negocio text; v_texto text; v_alerta boolean;
begin
  begin
    select c.nombres into v_cliente from elius.ordenes o join elius.contactos c on c.tenant_id = o.tenant_id and c.id = o.contacto_id
      where o.tenant_id = new.tenant_id and o.id = new.orden_id;
    select nombre into v_negocio from platform.tenants where id = new.tenant_id;
    v_alerta := coalesce(new.motivo, '') like 'ALERTA%';
    v_texto := coalesce(v_cliente, 'Un cliente') || ' envió un comprobante por $' || to_char(coalesce(new.monto_leido, 0), 'FM999G999G999')
               || ' en ' || coalesce(v_negocio, 'tu negocio') || case when v_alerta then ' · ⚠ el monto no coincide con el pedido' else '' end;
    perform app.enviar_push_tenant(new.tenant_id, jsonb_build_object('titulo', case when v_alerta then '⚠ Comprobante por revisar' else 'Comprobante por revisar' end,
              'cuerpo', v_texto, 'url', '/#/comprobantes', 'tag', 'comprobante-' || new.id));
    v_topic := coalesce(nullif(app.parametro(new.tenant_id, 'ntfy_topic'), ''),
                        (select valor from platform.ajustes_globales where clave = 'ntfy_topic'));
    v_panel := coalesce((select valor from platform.ajustes_globales where clave = 'panel_url'), '');
    if v_topic is not null and to_regprocedure('net.http_post(text,jsonb,jsonb,jsonb,integer)') is not null then
      execute 'select net.http_post($1, $2, $3, $4, $5)' using
        'https://ntfy.sh', jsonb_build_object('topic', v_topic, 'title', 'Comprobante por revisar', 'message', v_texto,
          'priority', case when v_alerta then 5 else 4 end, 'tags', jsonb_build_array('money_with_wings'),
          'click', v_panel || '/#/comprobantes',
          'actions', jsonb_build_array(jsonb_build_object('action', 'view', 'label', 'Aprobar o rechazar', 'url', v_panel || '/#/comprobantes'))),
        '{}'::jsonb, '{"Content-Type": "application/json"}'::jsonb, 5000;
    end if;
  exception when others then
    raise notice 'No se pudo avisar al celular: %', sqlerrm;
  end;
  return null;
end $$;
-- 2000 · Llave foránea de las suscripciones push hacia auth.users (platform.usuarios en el modelo).
-- Al borrar un usuario se borran sus dispositivos. Antes la columna no tenía llave.
delete from platform.push_suscripciones s where not exists (select 1 from auth.users u where u.id = s.usuario_id);
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'fk_push_suscripciones_usuario_id') then
    alter table platform.push_suscripciones add constraint fk_push_suscripciones_usuario_id
      foreign key (usuario_id) references auth.users (id) on delete cascade;
  end if;
end $$;
-- 0900 · La consola no elimina: tampoco con baja lógica.
-- Antes un UPDATE de eliminado_en permitía "borrar" un cliente. Ahora la consola rechaza cualquier sentencia que
-- toque eliminado_en o que apague/cancele registros (activo = false, estado cancelado/inactivo/eliminado).
create or replace function elius.consola_sql(p_sql text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_sql   text := regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '');
  v_low   text := lower(v_sql);
  v_filas jsonb;
  v_n     bigint := 0;
  v_tipo  text;
begin
  if auth.uid() is null or not (app.puede('configuracion', 'total') or app.es_super_admin()) then
    raise exception 'Solo un Administrador (o el Super Admin) puede usar la consola SQL';
  end if;
  if v_sql = '' then raise exception 'Escribe una sentencia'; end if;
  if v_sql ~ ';' then raise exception 'Una sola sentencia por ejecución'; end if;
  if v_low ~ '(--|/\*)' then raise exception 'No se permiten comentarios dentro de la sentencia'; end if;

  v_tipo := (regexp_match(v_low, '^\s*(select|with|insert|update|create)\M'))[1];
  if v_tipo is null then
    raise exception 'Solo se permiten SELECT, INSERT, UPDATE y CREATE';
  end if;
  if v_low ~ '\m(drop|truncate|delete|alter|grant|revoke|copy|vacuum|reindex|cluster|lock|listen|notify|refresh|import|load|reset|do|call)\M'
     or v_low ~ '\mset\s+(local|session|role|search_path|constraints)\M'
     or v_low ~ '\m(set_config|current_setting|pg_sleep|pg_terminate_backend|pg_cancel_backend|dblink|lo_import|lo_export|pg_read_file|pg_ls_dir)\M'
     or v_low ~ '\mcomment\s+on\M' then
    raise exception 'Sentencia no permitida en la consola (DROP, TRUNCATE, DELETE, ALTER, GRANT, SET… están bloqueados)';
  end if;
  if v_low ~ '\meliminado_en\M' or v_low ~ '\m(activo|estado)\s*=\s*(false|''(cancelad[oa]|inactiv[oa]|eliminad[oa])'')' then
    raise exception 'No se permite eliminar ni dar de baja registros desde la consola (tampoco con eliminado_en). Solo se consulta, se inserta y se corrige.';
  end if;
  if v_tipo = 'create' then
    if v_low !~ 'practica\.' then
      raise exception 'CREATE solo se permite en el esquema practica (ej. CREATE TABLE practica.prueba (...))';
    end if;
    if v_low ~ '\mcreate\s+(or\s+replace\s+)?(schema|role|user|database|extension|policy|publication|subscription|event|rule|server|foreign|materialized)\M' then
      raise exception 'Ese tipo de CREATE no está permitido';
    end if;
  end if;

  perform elius.consola_auditar(v_sql);

  perform set_config('statement_timeout', '8000', true);
  execute 'set local role elius_revisor';
  if v_tipo in ('select', 'with') then
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from (%s) q limit 500) t', v_sql)
      into v_filas;
    v_n := jsonb_array_length(v_filas);
  else
    execute v_sql;
    get diagnostics v_n = row_count;
    v_filas := '[]'::jsonb;
  end if;
  return jsonb_build_object('tipo', v_tipo, 'filas', v_filas, 'afectadas', v_n);
end $$;
-- 1000 · La consola registra también los intentos bloqueados, y deja consultar eliminado_en.
-- Antes: una sentencia prohibida levantaba un error y el error deshacía hasta el registro de auditoría.
-- Ahora: la sentencia prohibida se audita como "BLOQUEADO" y la función devuelve tipo = 'bloqueada' con el motivo
-- (el panel lo muestra como error). Solo se prohíbe MODIFICAR eliminado_en / apagar registros; leerlos es libre.
drop function if exists elius.consola_auditar(text);
create or replace function elius.consola_auditar(p_sql text, p_motivo text default null) returns void
language sql security definer set search_path = '' as $$
  insert into audit.registros_auditoria (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_nuevos)
  values (app.current_tenant_id(), auth.uid(), 'administrador', 'app', 'elius', 'consola_sql', gen_random_uuid(), 'INSERT',
          jsonb_build_object('sentencia', p_sql) || case when p_motivo is null then '{}'::jsonb else jsonb_build_object('bloqueada', true, 'motivo', p_motivo) end);
$$;
revoke execute on function elius.consola_auditar(text, text) from public, anon;
grant execute on function elius.consola_auditar(text, text) to authenticated;

create or replace function elius.consola_sql(p_sql text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_sql    text := regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '');
  v_low    text := lower(v_sql);
  v_antes  text := split_part(lower(regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '')), ' where ', 1);
  v_filas  jsonb;
  v_n      bigint := 0;
  v_tipo   text;
  v_motivo text;
begin
  if auth.uid() is null or not (app.puede('configuracion', 'total') or app.es_super_admin()) then
    raise exception 'Solo un Administrador (o el Super Admin) puede usar la consola SQL';
  end if;
  if v_sql = '' then raise exception 'Escribe una sentencia'; end if;

  v_tipo := (regexp_match(v_low, '^\s*(select|with|insert|update|create)\M'))[1];
  if v_sql ~ ';' then v_motivo := 'Una sola sentencia por ejecución';
  elsif v_low ~ '(--|/\*)' then v_motivo := 'No se permiten comentarios dentro de la sentencia';
  elsif v_tipo is null then v_motivo := 'Solo se permiten SELECT, INSERT, UPDATE y CREATE';
  elsif v_low ~ '\m(drop|truncate|delete|alter|grant|revoke|copy|vacuum|reindex|cluster|lock|listen|notify|refresh|import|load|reset|do|call)\M'
     or v_low ~ '\mset\s+(local|session|role|search_path|constraints)\M'
     or v_low ~ '\m(set_config|current_setting|pg_sleep|pg_terminate_backend|pg_cancel_backend|dblink|lo_import|lo_export|pg_read_file|pg_ls_dir)\M'
     or v_low ~ '\mcomment\s+on\M' then
    v_motivo := 'Sentencia no permitida en la consola (DROP, TRUNCATE, DELETE, ALTER, GRANT, SET… están bloqueados)';
  elsif (v_tipo in ('update', 'insert') or (v_tipo = 'with' and v_low ~ '\m(update|insert)\M'))
        and (v_antes ~ '\meliminado_en\M' or v_antes ~ '\m(activo|estado)\s*=\s*(false|''(cancelad[oa]|inactiv[oa]|eliminad[oa])'')') then
    v_motivo := 'No se permite eliminar ni dar de baja registros desde la consola (tampoco con eliminado_en). Solo se consulta, se inserta y se corrige.';
  elsif v_tipo = 'create' and v_low !~ 'practica\.' then
    v_motivo := 'CREATE solo se permite en el esquema practica (ej. CREATE TABLE practica.prueba (...))';
  elsif v_tipo = 'create' and v_low ~ '\mcreate\s+(or\s+replace\s+)?(schema|role|user|database|extension|policy|publication|subscription|event|rule|server|foreign|materialized)\M' then
    v_motivo := 'Ese tipo de CREATE no está permitido';
  end if;

  if v_motivo is not null then
    perform elius.consola_auditar(v_sql, v_motivo);          -- queda en la auditoría: quién intentó qué
    return jsonb_build_object('tipo', 'bloqueada', 'mensaje', v_motivo, 'filas', '[]'::jsonb, 'afectadas', 0);
  end if;

  perform elius.consola_auditar(v_sql);

  perform set_config('statement_timeout', '8000', true);
  execute 'set local role elius_revisor';
  if v_tipo in ('select', 'with') then
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from (%s) q limit 500) t', v_sql)
      into v_filas;
    v_n := jsonb_array_length(v_filas);
  else
    execute v_sql;
    get diagnostics v_n = row_count;
    v_filas := '[]'::jsonb;
  end if;
  return jsonb_build_object('tipo', v_tipo, 'filas', v_filas, 'afectadas', v_n);
end $$;

-- La bitácora legible distingue las consultas de los intentos bloqueados
create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id;
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
-- 1100 · El Operador también usa la consola SQL (con las mismas reglas) y toda acción de un rol queda en la auditoría del Administrador.
--  · Consola: Administrador, Super Admin y Operador. El Operador además no modifica catálogo, precios ni vuelos (y la RLS lo respalda).
--  · La bitácora anota el rol real de quien consulta (antes ponía siempre 'administrador').
--  · Los mensajes que un humano envía a un cliente ahora quedan auditados (solo datos de control, no el texto).
create or replace function elius.consola_auditar(p_sql text, p_motivo text default null) returns void
language sql security definer set search_path = '' as $$
  insert into audit.registros_auditoria (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_nuevos)
  values (app.current_tenant_id(), auth.uid(), coalesce(app.mi_rol(), 'super_admin'), 'app', 'elius', 'consola_sql', gen_random_uuid(), 'INSERT',
          jsonb_build_object('sentencia', p_sql) || case when p_motivo is null then '{}'::jsonb else jsonb_build_object('bloqueada', true, 'motivo', p_motivo) end);
$$;

create or replace function elius.consola_sql(p_sql text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  v_sql    text := regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '');
  v_low    text := lower(v_sql);
  v_antes  text := split_part(lower(regexp_replace(btrim(coalesce(p_sql, '')), ';\s*$', '')), ' where ', 1);
  v_filas  jsonb;
  v_n      bigint := 0;
  v_tipo   text;
  v_motivo text;
begin
  if auth.uid() is null or not (app.puede('configuracion', 'total') or app.es_super_admin() or app.mi_rol() = 'operador') then
    raise exception 'Solo un Administrador, un Operador (o el Super Admin) puede usar la consola SQL';
  end if;
  if v_sql = '' then raise exception 'Escribe una sentencia'; end if;

  v_tipo := (regexp_match(v_low, '^\s*(select|with|insert|update|create)\M'))[1];
  if v_sql ~ ';' then v_motivo := 'Una sola sentencia por ejecución';
  elsif v_low ~ '(--|/\*)' then v_motivo := 'No se permiten comentarios dentro de la sentencia';
  elsif v_tipo is null then v_motivo := 'Solo se permiten SELECT, INSERT, UPDATE y CREATE';
  elsif v_low ~ '\m(drop|truncate|delete|alter|grant|revoke|copy|vacuum|reindex|cluster|lock|listen|notify|refresh|import|load|reset|do|call)\M'
     or v_low ~ '\mset\s+(local|session|role|search_path|constraints)\M'
     or v_low ~ '\m(set_config|current_setting|pg_sleep|pg_terminate_backend|pg_cancel_backend|dblink|lo_import|lo_export|pg_read_file|pg_ls_dir)\M'
     or v_low ~ '\mcomment\s+on\M' then
    v_motivo := 'Sentencia no permitida en la consola (DROP, TRUNCATE, DELETE, ALTER, GRANT, SET… están bloqueados)';
  elsif (v_tipo in ('update', 'insert') or (v_tipo = 'with' and v_low ~ '\m(update|insert)\M'))
        and (v_antes ~ '\meliminado_en\M' or v_antes ~ '\m(activo|estado)\s*=\s*(false|''(cancelad[oa]|inactiv[oa]|eliminad[oa])'')') then
    v_motivo := 'No se permite eliminar ni dar de baja registros desde la consola (tampoco con eliminado_en). Solo se consulta, se inserta y se corrige.';
  elsif app.mi_rol() = 'operador'
        and (v_tipo in ('update', 'insert') or (v_tipo = 'with' and v_low ~ '\m(update|insert)\M'))
        and v_low ~ '\m(items_catalogo|categorias_catalogo|item_adicionales|medios_item|menus_dia|menu_dia_items|grupos_modificador|opciones_modificador|item_grupos_modificador|alergenos|item_alergenos|tarifas_vuelo|vuelos|rutas|aeronaves|aeropuertos|precio|precio_base|precio_venta)\M' then
    v_motivo := 'El Operador solo consulta el catálogo, los precios y los vuelos: no los cambia.';
  elsif v_tipo = 'create' and v_low !~ 'practica\.' then
    v_motivo := 'CREATE solo se permite en el esquema practica (ej. CREATE TABLE practica.prueba (...))';
  elsif v_tipo = 'create' and v_low ~ '\mcreate\s+(or\s+replace\s+)?(schema|role|user|database|extension|policy|publication|subscription|event|rule|server|foreign|materialized)\M' then
    v_motivo := 'Ese tipo de CREATE no está permitido';
  end if;

  if v_motivo is not null then
    perform elius.consola_auditar(v_sql, v_motivo);          -- queda en la auditoría: quién intentó qué
    return jsonb_build_object('tipo', 'bloqueada', 'mensaje', v_motivo, 'filas', '[]'::jsonb, 'afectadas', 0);
  end if;

  perform elius.consola_auditar(v_sql);

  perform set_config('statement_timeout', '8000', true);
  execute 'set local role elius_revisor';
  if v_tipo in ('select', 'with') then
    execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from (select * from (%s) q limit 500) t', v_sql)
      into v_filas;
    v_n := jsonb_array_length(v_filas);
  else
    execute v_sql;
    get diagnostics v_n = row_count;
    v_filas := '[]'::jsonb;
  end if;
  return jsonb_build_object('tipo', v_tipo, 'filas', v_filas, 'afectadas', v_n);
end $$;

-- Mensajes enviados por una persona (Operador o Administrador desde el panel): quién, en qué conversación, no el contenido
create or replace function app.auditar_mensaje_humano() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into audit.registros_auditoria (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_nuevos)
  values (new.tenant_id, auth.uid(), coalesce(app.mi_rol(), 'sistema'), case when auth.uid() is null then 'sistema' else 'app' end,
          'elius', 'mensajes', new.id, 'INSERT',
          jsonb_build_object('conversacion_id', new.conversacion_id, 'tipo_contenido', new.tipo_contenido, 'caracteres', length(coalesce(new.contenido, ''))));
  return null;
end $$;
drop trigger if exists t02_auditoria_mensaje_humano on elius.mensajes;
create trigger t02_auditoria_mensaje_humano after insert on elius.mensajes
  for each row when (new.emisor = 'humano') execute function app.auditar_mensaje_humano();

create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.tabla = 'mensajes' then 'Respondió a un cliente en una conversación (' || coalesce(a.datos_nuevos ->> 'caracteres', '0') || ' caracteres)'
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id;
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
-- 1200 · Auditoría legible: se ocultan los movimientos automáticos del motor de la demostración.
-- Con la demo corriendo se generaban cientos de filas por hora (contador demo_indice, última actividad de la conversación y
-- del contacto) que escondían lo que hacen las personas. Siguen guardadas en audit.registros_auditoria; solo no se listan.
create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.tabla = 'mensajes' then 'Respondió a un cliente en una conversación (' || coalesce(a.datos_nuevos ->> 'caracteres', '0') || ' caracteres)'
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id
where not (a.tabla = 'parametros_negocio' and coalesce(a.datos_nuevos ->> 'clave', '') like 'demo\_%')
  and not (a.operacion = 'UPDATE' and a.tabla in ('conversaciones', 'identidades_contacto') and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k
          and k not in ('actualizado_en', 'ultimo_mensaje_en', 'ultimo_contacto_en')));
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
-- 1300 · Auditoría limpia: solo lo que hacen las personas.
--  · El motor de la demostración (reiniciar, cargar caso, siguiente mensaje, cambiar de vista) ya no escribe en la auditoría:
--    app.auditar() omite lo que ocurre dentro de esas llamadas.
--  · La lista ya no muestra el historial anterior a esta limpieza ni las actualizaciones sin cambios reales (siguen guardados).
create or replace function app.auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_fila   jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_rol    text  := app.mi_rol();
  v_tenant uuid  := nullif(v_fila ->> 'tenant_id', '')::uuid;
begin
  if current_query() ~* '(siguiente_mensaje_demo|reiniciar_demo|cargar_caso_demo|cambiar_rol_demo|cambiar_tenant)' then
    return null;   -- movimientos automáticos del motor de la demostración
  end if;
  insert into audit.registros_auditoria
    (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_anteriores, datos_nuevos)
  values (
    v_tenant, auth.uid(), coalesce(v_rol, 'sistema'),
    case when v_rol = 'eli' then 'eli' when v_rol = 'soporte' then 'soporte'
         when auth.uid() is null then 'sistema' else 'app' end,
    tg_table_schema, tg_table_name, (v_fila ->> 'id')::uuid, tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return null;
end $$;

create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.tabla = 'mensajes' then 'Respondió a un cliente en una conversación (' || coalesce(a.datos_nuevos ->> 'caracteres', '0') || ' caracteres)'
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id
where a.creado_en >= timestamptz '2026-11-24 07:05:00+00'                 -- historial anterior a la limpieza del 24-nov: no se lista (sigue guardado)
  and not (a.tabla = 'parametros_negocio' and coalesce(a.datos_nuevos ->> 'clave', '') like 'demo\_%')
  and not (a.operacion = 'UPDATE' and not exists (                -- actualizaciones sin ningún dato realmente distinto
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'))
  and not (a.operacion = 'UPDATE' and a.tabla in ('conversaciones', 'identidades_contacto') and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k
          and k not in ('actualizado_en', 'ultimo_mensaje_en', 'ultimo_contacto_en')))
  and not (a.tabla = 'membresias' and a.operacion = 'UPDATE' and a.usuario_id::text = a.datos_nuevos ->> 'usuario_id');  -- cambiar de vista o de negocio uno mismo
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
-- =============================================================================
-- 2600 · Datos de ejemplo del plugin de cada caso de prueba
-- Cada negocio de demostración recibe filas en SU plugin (veterinaria, restaurante o aerolínea) para que las
-- sentencias sugeridas del panel devuelvan resultados. Versión del guion sembrado: 9 (se vuelve a sembrar al elegir el caso).
-- =============================================================================

create or replace function elius.limpiar_caso_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from plugin_vet.mascotas where tenant_id = p_tenant;
  delete from plugin_restaurant.menus_dia where tenant_id = p_tenant;
  delete from plugin_restaurant.estaciones_cocina where tenant_id = p_tenant;
  delete from elius.pagos where tenant_id = p_tenant;
  delete from elius.comprobantes_pago where tenant_id = p_tenant;
  delete from elius.entregas where tenant_id = p_tenant;
  delete from elius.ordenes where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from plugin_airline.vuelos where tenant_id = p_tenant;
  delete from plugin_airline.rutas where tenant_id = p_tenant;
  delete from plugin_airline.aeronaves where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.contactos where tenant_id = p_tenant;   -- cascada: identidades, conversaciones y mensajes
  delete from elius.parametros_negocio where tenant_id = p_tenant and clave like 'demo\_%';
end $$;

create or replace function elius.sembrar_plugin_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_mem uuid; v_item uuid; v_menu uuid; v_ruta uuid; v_vuelo uuid; v_tv uuid; v_at uuid; v_masc uuid; v_rp uuid; v_tr uuid;
  v_aer uuid; v_o uuid; v_d uuid; r record; k int;
begin
  select id into v_mem from platform.membresias where tenant_id = p_tenant order by creado_en limit 1;

  if p_vertical = 'veterinaria' then
    k := 0;
    for r in select id, nombres from elius.contactos where tenant_id = p_tenant order by telefono limit 8 loop
      k := k + 1;
      insert into plugin_vet.mascotas (tenant_id, nombre, especie, raza, sexo, fecha_nacimiento, peso_kg, esterilizada, alergias)
      values (p_tenant,
        (array['Max','Luna','Toby','Mia','Rocky','Nala','Simón','Kira'])[k],
        (array['perro','gato','perro','gato','perro','perro','gato','perro'])[k],
        (array['Labrador','Criollo','Beagle','Siamés','Schnauzer','Golden','Persa','Bulldog'])[k],
        (array['macho','hembra'])[1 + k % 2],
        current_date - ((k + 1) * 280),
        (array[28.5,4.2,11.3,3.8,9.6,26.1,4.9,22.4])[k],
        k % 3 = 0,
        case when k in (2, 5) then array['pollo']::text[] when k = 7 then array['penicilina']::text[] else array[]::text[] end)
      returning id into v_masc;
      insert into plugin_vet.propietarios_mascota (tenant_id, contacto_id, mascota_id, tipo, puede_autorizar, desde)
      values (p_tenant, r.id, v_masc, 'principal', true, current_date - 400);
      -- vacuna aplicada, con refuerzo próximo para varias mascotas
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = 'VET-02';
      insert into plugin_vet.aplicaciones_vacuna (tenant_id, mascota_id, vacuna_id, aplicada_por, lote, aplicada_en, proxima_dosis_en)
      values (p_tenant, v_masc, v_item, v_mem, 'LT-' || (2400 + k), current_date - (330 + k * 3), current_date + (k * 4 - 6));
    end loop;
    -- atenciones de las citas ya agendadas, con su historia clínica
    k := 0;
    for r in select rs.id as reserva_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'cita' order by rs.inicio limit 5 loop
      k := k + 1;
      select id into v_masc from plugin_vet.mascotas where tenant_id = p_tenant order by nombre offset k - 1 limit 1;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = 'VET-01';
      insert into plugin_vet.atenciones (tenant_id, reserva_id, mascota_id, servicio_id, profesional_id, motivo, estado, peso_kg, temperatura_c)
      values (p_tenant, r.reserva_id, v_masc, v_item, v_mem,
        (array['Control anual','Vómito desde ayer','Cojera en pata trasera','Picazón y enrojecimiento','Revisión posoperatoria'])[k],
        'programada', null, null) returning id into v_at;
      insert into plugin_vet.registros_clinicos (tenant_id, atencion_id, autor_id, tipo, contenido)
      values (p_tenant, v_at, v_mem, 'anamnesis', (array['Sin novedades, come y bebe bien.','Dos episodios de vómito, sin fiebre.','Cojea al levantarse.','Se rasca las orejas hace tres días.','Herida cerrando bien.'])[k]);
    end loop;

  elsif p_vertical = 'restaurante' then
    insert into plugin_restaurant.estaciones_cocina (tenant_id, nombre, tiempo_objetivo_min) values
      (p_tenant, 'Cocina caliente', 18), (p_tenant, 'Cocina fría y bar', 8), (p_tenant, 'Postres', 10);
    insert into plugin_restaurant.menus_dia (tenant_id, fecha, precio_base, confirmado_por, confirmado_en, activo)
    values (p_tenant, (now() at time zone 'America/Bogota')::date, 22000, v_mem, now(), true) returning id into v_menu;
    for r in select * from (values ('RES-03','entrada',1), ('RES-01','principal',2), ('RES-02','principal',3), ('RES-04','bebida',4), ('RES-05','postre',5)) t(sku, sec, pos) loop
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      insert into plugin_restaurant.menu_dia_items (tenant_id, menu_id, item_id, seccion, posicion) values (p_tenant, v_menu, v_item, r.sec, r.pos);
    end loop;
    k := 0;
    for r in select rs.id as reserva_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'mesa' order by rs.inicio limit 5 loop
      k := k + 1;
      insert into plugin_restaurant.celebraciones (tenant_id, reserva_id, tipo_celebracion, festejado, decoracion, notas)
      values (p_tenant, r.reserva_id,
        (array['cumpleaños','aniversario','grado','bautizo','cumpleaños'])[k],
        (array['Valentina','Pareja Ríos','Camilo','Sofía','Don Hernán'])[k],
        (array['Globos rosados','Velas y flores','Arco de globos','Tonos suaves','Letrero dorado'])[k],
        (array['Torta llega a las 7 p. m.','Mesa junto a la ventana','Traen su propia torta','Sin frutos secos','Sorpresa: apagar luces'])[k]);
    end loop;

  elsif p_vertical = 'aerolinea' then
    insert into plugin_airline.aeropuertos (codigo_iata, nombre, ciudad, pais, zona_horaria)
    select t.c, t.n, t.ci, 'CO', 'America/Bogota' from (values
      ('BOG','El Dorado','Bogotá'), ('MDE','José María Córdova','Medellín'), ('CTG','Rafael Núñez','Cartagena'), ('ADZ','Gustavo Rojas Pinilla','San Andrés')) t(c, n, ci)
    where not exists (select 1 from plugin_airline.aeropuertos a where a.codigo_iata = t.c);
    insert into plugin_airline.aeronaves (tenant_id, matricula, modelo, capacidad) values
      (p_tenant, 'HK-4501', 'Airbus A320', 180), (p_tenant, 'HK-4502', 'Airbus A319', 144);
    select id into v_aer from plugin_airline.aeronaves where tenant_id = p_tenant order by matricula limit 1;
    select id into v_o from plugin_airline.aeropuertos where codigo_iata = 'BOG';
    k := 0;
    for r in select * from (values ('MDE','AER-01',55,70,19000), ('CTG','AER-02',90,75,22000), ('ADZ','AER-03',140,120,41500)) t(dest, sku, dur, km, pre) loop
      k := k + 1;
      select id into v_d from plugin_airline.aeropuertos where codigo_iata = r.dest;
      insert into plugin_airline.rutas (tenant_id, origen_id, destino_id, distancia_km, duracion_min)
      values (p_tenant, v_o, v_d, r.km * 10, r.dur) returning id into v_ruta;
      select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = r.sku;
      for k in 1..2 loop
        insert into plugin_airline.vuelos (tenant_id, ruta_id, aeronave_id, numero_vuelo, salida_programada, llegada_programada, estado, puerta)
        values (p_tenant, v_ruta, v_aer, 'EL' || (100 + (select count(*) from plugin_airline.vuelos where tenant_id = p_tenant) + 1),
          date_trunc('day', now()) + (k * interval '1 day') + interval '23 hours', date_trunc('day', now()) + (k * interval '1 day') + interval '23 hours' + (r.dur * interval '1 minute'),
          'programado', 'A' || (3 + k)) returning id into v_vuelo;
        insert into plugin_airline.tarifas_vuelo (tenant_id, vuelo_id, tarifa_id, precio, cupos_totales, cupos_vendidos)
        values (p_tenant, v_vuelo, v_item, (select precio from elius.items_catalogo where id = v_item) + (k - 1) * 15000, 30, case when r.dest = 'ADZ' then 27 + k when k = 1 then 18 else 6 end);
      end loop;
    end loop;
    -- pasajeros, tramos y tiquetes de las reservas de vuelo ya agendadas
    select tv.id into v_tv from plugin_airline.tarifas_vuelo tv where tv.tenant_id = p_tenant order by tv.creado_en limit 1;
    k := 0;
    for r in select rs.id as reserva_id, rs.contacto_id from elius.reservas rs where rs.tenant_id = p_tenant and rs.tipo = 'vuelo' order by rs.inicio limit 6 loop
      k := k + 1;
      insert into plugin_airline.reserva_pasajeros (tenant_id, reserva_id, contacto_id, tipo_pasajero, necesidades_especiales)
      values (p_tenant, r.reserva_id, r.contacto_id, 'ADT', case when k in (2, 5) then (array['Silla de ruedas hasta la puerta','Menú sin gluten'])[1 + k % 2] else null end)
      returning id into v_rp;
      insert into plugin_airline.tramos_reserva (tenant_id, reserva_id, tarifa_vuelo_id, orden_tramo, estado)
      values (p_tenant, r.reserva_id, v_tv, 1, 'confirmado') returning id into v_tr;
      insert into plugin_airline.tiquetes (tenant_id, reserva_pasajero_id, tramo_id, numero_tiquete, silla, estado, checkin_en)
      values (p_tenant, v_rp, v_tr, '8' || substr(md5(random()::text), 1, 12), (10 + k) || 'A', case when k <= 2 then 'usado' else 'emitido' end,
              case when k <= 2 then now() - interval '1 hour' else null end);
    end loop;
  end if;
end $$;

create or replace function elius.sembrar_clientes_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_canal uuid; v_contacto uuid; v_ident uuid; r jsonb; v_ini timestamptz; v_res uuid; v_cat uuid; v_item uuid; rr record;
begin
  select id into v_canal from elius.canales where tenant_id = p_tenant order by creado_en limit 1;
  perform elius.limpiar_caso_demo(p_tenant);
  -- categorías e ítems con su imagen (se crean los que falten y se actualizan los existentes)
  for rr in select value, ordinality - 1 as i from jsonb_array_elements(v_d->'categorias') with ordinality loop
    insert into elius.categorias_catalogo (tenant_id, nombre, orden)
    select p_tenant, rr.value #>> '{}', rr.i::int
    where not exists (select 1 from elius.categorias_catalogo where tenant_id = p_tenant and nombre = rr.value #>> '{}');
  end loop;
  for rr in select value, ordinality as k from jsonb_array_elements(v_d->'items') with ordinality loop
    select id into v_cat from elius.categorias_catalogo
    where tenant_id = p_tenant and nombre = (v_d->'categorias') ->> ((rr.value->>'cat')::int);
    insert into elius.items_catalogo (tenant_id, categoria_id, tipo, sku, nombre, descripcion, precio, impuesto_pct, duracion_min)
    values (p_tenant, v_cat, rr.value->>'tipo', rr.value->>'sku', rr.value->>'nombre', rr.value->>'desc',
            (rr.value->>'precio')::numeric, (rr.value->>'iva')::numeric, nullif(rr.value->>'dur', '')::int)
    on conflict (tenant_id, sku) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, precio = excluded.precio,
           impuesto_pct = excluded.impuesto_pct, categoria_id = excluded.categoria_id, disponible = true;
    select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = rr.value->>'sku';
    -- las fotos que puso el dueño se respetan; las del demo (propias o de Wikimedia Commons) se actualizan
    delete from elius.medios_item where tenant_id = p_tenant and item_id = v_item
      and (url like '/demo/%' or url like 'https://commons.wikimedia.org/%');
    if not exists (select 1 from elius.medios_item where tenant_id = p_tenant and item_id = v_item) then
      insert into elius.medios_item (tenant_id, item_id, tipo_archivo, url, descripcion, orden)
      values (p_tenant, v_item, 'foto', coalesce(v_d->'imagenes'->>(rr.value->>'sku'), '/demo/' || p_vertical || '-' || rr.k || '.svg'), rr.value->>'nombre', 0);
    end if;
  end loop;
  for r in select * from jsonb_array_elements(v_d->'recursos') loop
    insert into elius.recursos (tenant_id, tipo, nombre, capacidad)
    select p_tenant, r->>0, r->>1, (r->>2)::int
    where not exists (select 1 from elius.recursos where tenant_id = p_tenant and nombre = r->>1);
  end loop;
  for r in select * from jsonb_array_elements(v_d->'contactos') loop
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (p_tenant, r->>0, r->>1, r->>2, 'whatsapp') returning id into v_contacto;
    insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
    values (p_tenant, v_contacto, v_canal, r->>2, (r->>0) || ' ' || (r->>1)) returning id into v_ident;
    insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (p_tenant, v_ident, 'general');
  end loop;
  for r in select * from jsonb_array_elements(v_d->'agenda') loop
    select c.id into v_contacto from elius.contactos c where c.tenant_id = p_tenant
    order by c.telefono offset (r->>2)::int limit 1;
    v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + (r->>0)::int * interval '1 day' + ((r->>1)::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
    insert into elius.reservas (tenant_id, contacto_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
    values (p_tenant, v_contacto, 'R-' || upper(substr(md5(random()::text), 1, 5)), r->>3, r->>6, v_ini, v_ini + interval '1 hour',
            (r->>4)::int, (r->>7)::boolean, true) returning id into v_res;
    begin
      insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
      select p_tenant, v_res, rc.id, v_ini, v_ini + interval '1 hour' from elius.recursos rc where rc.tenant_id = p_tenant and rc.nombre = r->>5;
    exception when exclusion_violation then null;
    end;
  end loop;
  perform elius.sembrar_plugin_demo(p_tenant, p_vertical);
  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion) values
    (p_tenant, 'demo_indice', '0', 'numero', 'Mensajes de prueba ya entregados (caso de demostración)'),
    (p_tenant, 'demo_version', '9', 'texto', 'Versión del guion sembrado');
end $$;

revoke execute on function elius.sembrar_plugin_demo(uuid, text), elius.sembrar_clientes_demo(uuid, text), elius.limpiar_caso_demo(uuid) from public, anon, authenticated;
-- =============================================================================
-- 2700 · Conexiones directas a la base de datos, una por rol (como en MySQL Workbench)
-- Usuarios con login: elius_superadmin, elius_administrador, elius_trabajador, elius_soporte.
-- Cada uno se conecta desde Workbench/DBeaver/psql con SU usuario y SU contraseña, y tiene los permisos de su rol:
-- la misma RLS y la misma matriz rol × permiso que el panel. Ven todos los negocios (cambian con platform.usar_negocio).
--   · Ninguno puede DROP / ALTER (no son dueños de nada). CREATE solo en el esquema practica.
--   · Administrador, Trabajador y Soporte NO pueden borrar (DELETE/TRUNCATE) ni dar de baja (eliminado_en).
--   · Todo lo que hacen queda en la Auditoría con su rol.
-- Las contraseñas NO están en el repositorio: se asignan en Supabase (ver docs).
-- =============================================================================

-- 1. Qué usuario de la aplicación representa cada usuario de base de datos
create table if not exists platform.accesos_bd (
  usuario_bd  text primary key,
  usuario_id  uuid not null unique references auth.users (id) on delete cascade,
  descripcion text not null,
  creado_en   timestamptz not null default now()
);
comment on table platform.accesos_bd is 'Usuarios de base de datos con login (uno por rol) y la identidad de la aplicación que representan';
alter table platform.accesos_bd enable row level security;
revoke all on platform.accesos_bd from public, anon, authenticated;

-- 2. Identidad efectiva: una conexión directa usa la identidad ligada a su usuario de BD (no se puede falsear con claims)
create or replace function app.uid()
returns uuid language sql stable security definer set search_path = '' as $$
  select coalesce((select a.usuario_id from platform.accesos_bd a where a.usuario_bd = session_user), auth.uid());
$$;

-- 3. Negocio activo: por JWT (panel) o, en conexión directa, el elegido con platform.usar_negocio (por defecto el primero)
create or replace function app.current_tenant_id()
returns uuid language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid    uuid;
  v_claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
  v_txt    text;
  v_hdr    text;
begin
  select a.usuario_id into v_uid from platform.accesos_bd a where a.usuario_bd = session_user;
  if v_uid is not null then
    v_txt := nullif(current_setting('app.tenant_id', true), '');
    if v_txt is null then
      select t.id::text into v_txt from platform.tenants t where app.tiene_acceso_tenant(v_uid, t.id) order by t.creado_en limit 1;
    end if;
    if app.es_uuid(v_txt) and app.tiene_acceso_tenant(v_uid, v_txt::uuid) then return v_txt::uuid; end if;
    return null;
  end if;

  v_uid := auth.uid();
  if v_uid is null then
    if v_claims ->> 'role' = 'service_role'
       or session_user in ('elius_app', 'elius_admin', 'postgres', 'supabase_admin') then
      v_txt := nullif(current_setting('app.tenant_id', true), '');
      return case when app.es_uuid(v_txt) then v_txt::uuid end;
    end if;
    return null;
  end if;

  v_hdr := nullif(current_setting('request.headers', true), '');
  if v_hdr is not null then
    v_txt := v_hdr::jsonb ->> 'x-tenant-id';
  end if;
  v_txt := coalesce(v_txt, v_claims ->> 'tenant_id');
  if not app.es_uuid(v_txt) then
    return null;
  end if;
  if app.tiene_acceso_tenant(v_uid, v_txt::uuid) then
    return v_txt::uuid;
  end if;
  return null;
end $$;

-- 4. Las funciones y políticas que leían auth.uid() pasan a leer app.uid()
do $$ declare rf record; rp record; d text; u text; w text;
begin
  for rf in select fp.oid from pg_proc fp join pg_namespace n on n.oid = fp.pronamespace
           where n.nspname in ('app', 'elius', 'platform', 'audit') and fp.prokind = 'f'
             and fp.prosrc like '%auth.uid()%' and not (n.nspname = 'app' and fp.proname in ('uid', 'current_tenant_id')) loop
    d := replace(pg_get_functiondef(rf.oid), 'auth.uid()', 'app.uid()');
    execute d;
  end loop;
  for rp in select pol.polname, c.relname, n.nspname, pg_get_expr(pol.polqual, pol.polrelid) as q, pg_get_expr(pol.polwithcheck, pol.polrelid) as w
           from pg_policy pol join pg_class c on c.oid = pol.polrelid join pg_namespace n on n.oid = c.relnamespace
           where n.nspname in ('app', 'elius', 'platform', 'audit', 'ext', 'plugin_vet', 'plugin_restaurant', 'plugin_airline')
             and (coalesce(pg_get_expr(pol.polqual, pol.polrelid), '') like '%auth.uid()%' or coalesce(pg_get_expr(pol.polwithcheck, pol.polrelid), '') like '%auth.uid()%') loop
    u := case when rp.q is not null then ' using (' || replace(rp.q, 'auth.uid()', 'app.uid()') || ')' else '' end;
    w := case when rp.w is not null then ' with check (' || replace(rp.w, 'auth.uid()', 'app.uid()') || ')' else '' end;
    execute format('alter policy %I on %I.%I%s%s', rp.polname, rp.nspname, rp.relname, u, w);
  end loop;
end $$;

-- 5. Los usuarios de conexión directa no cuentan para el límite de usuarios del plan ni como "otro administrador"
create or replace function app.validar_limite_usuarios()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_max int; v_actual int;
begin
  if exists (select 1 from platform.accesos_bd where usuario_id = new.usuario_id) then return new; end if;
  select p.max_usuarios into v_max from platform.tenants t join platform.planes p on p.id = t.plan_id where t.id = new.tenant_id;
  select count(*) into v_actual from platform.membresias m
  where m.tenant_id = new.tenant_id and m.estado <> 'inactivo' and not exists (select 1 from platform.accesos_bd b where b.usuario_id = m.usuario_id);
  if v_actual >= v_max then
    raise exception 'RN-P10: el plan permite máximo % usuarios', v_max using errcode = '23514';
  end if;
  return new;
end $$;

create or replace function app.proteger_ultimo_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_admin uuid;
begin
  select id into v_admin from platform.roles where codigo = 'administrador';
  if old.rol_id = v_admin and old.estado = 'activo'
     and (tg_op = 'DELETE' or new.rol_id <> v_admin or new.estado <> 'activo')
     and not exists (select 1 from platform.membresias m
                     where m.tenant_id = old.tenant_id and m.id <> old.id and m.rol_id = v_admin and m.estado = 'activo'
                       and not exists (select 1 from platform.accesos_bd b where b.usuario_id = m.usuario_id))
     and exists (select 1 from platform.tenants t where t.id = old.tenant_id and t.slug not like 'demo-%') then
    raise exception 'RN-P04: el tenant debe conservar al menos un Administrador activo' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- Los escalamientos no se asignan a la cuenta de conexión directa (solo a Operadores reales)
do $$ declare d text;
begin
  d := replace(pg_get_functiondef('app.asignar_escalamiento'::regproc),
    'where m.tenant_id = new.tenant_id and m.estado = ''activo''',
    'where m.tenant_id = new.tenant_id and m.estado = ''activo'' and not exists (select 1 from platform.accesos_bd b where b.usuario_id = m.usuario_id)');
  if position('accesos_bd' in d) = 0 then raise exception 'no se pudo ajustar asignar_escalamiento'; end if;
  execute d;
end $$;

-- 6. Sin bajas desde conexión directa (Administrador, Trabajador y Soporte)
create or replace function app.bloquear_baja_directa()
returns trigger language plpgsql set search_path = '' as $$
begin
  if session_user in ('elius_administrador', 'elius_trabajador', 'elius_soporte') then
    if tg_op in ('DELETE', 'TRUNCATE') then
      raise exception 'Tu usuario no puede eliminar datos (%): no se permite DELETE ni TRUNCATE.', tg_table_name using errcode = '42501';
    elsif tg_op = 'UPDATE' and (to_jsonb(new) ->> 'eliminado_en') is distinct from (to_jsonb(old) ->> 'eliminado_en') then
      raise exception 'Tu usuario no puede dar de baja registros (eliminado_en).' using errcode = '42501';
    end if;
  end if;
  return case when tg_op = 'DELETE' then old when tg_op = 'TRUNCATE' then null else new end;
end $$;

do $$ declare t record;
begin
  for t in select n.nspname, c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where c.relkind in ('r', 'p') and n.nspname in ('platform', 'elius', 'ext', 'plugin_vet', 'plugin_restaurant', 'plugin_airline') loop
    execute format('drop trigger if exists t00_sin_baja_directa on %I.%I', t.nspname, t.relname);
    execute format('create trigger t00_sin_baja_directa before delete or update on %I.%I for each row execute function app.bloquear_baja_directa()', t.nspname, t.relname);
    execute format('drop trigger if exists t00_sin_truncate_directo on %I.%I', t.nspname, t.relname);
    execute format('create trigger t00_sin_truncate_directo before truncate on %I.%I for each statement execute function app.bloquear_baja_directa()', t.nspname, t.relname);
  end loop;
end $$;

-- 7. Los cuatro usuarios de base de datos (sin contraseña: no pueden conectarse hasta que se les asigne una)
do $$ declare r text;
begin
  foreach r in array array['elius_superadmin', 'elius_administrador', 'elius_trabajador', 'elius_soporte'] loop
    if not exists (select 1 from pg_roles where rolname = r) then
      execute format('create role %I login nosuperuser nocreatedb nocreaterole noreplication nobypassrls in role authenticated', r);
    end if;
    execute format('alter role %I set statement_timeout = ''30s''', r);
    execute format('grant usage, create on schema practica to %I', r);
  end loop;
end $$;

-- 8. Su identidad en la aplicación (usuario sin contraseña de panel) y sus permisos
do $$ declare x record; v_id uuid;
begin
  for x in select * from (values
      ('elius_superadmin',    '00000000-0000-0000-0000-00000000bd01'::uuid, 'bd.superadmin@elius.local',    'Super Administrador (conexión directa)'),
      ('elius_administrador', '00000000-0000-0000-0000-00000000bd02'::uuid, 'bd.administrador@elius.local', 'Administrador (conexión directa)'),
      ('elius_trabajador',    '00000000-0000-0000-0000-00000000bd03'::uuid, 'bd.trabajador@elius.local',    'Trabajador (conexión directa)'),
      ('elius_soporte',       '00000000-0000-0000-0000-00000000bd04'::uuid, 'bd.soporte@elius.local',       'Soporte al cliente (conexión directa)')) t(bd, id, email, d) loop
    if not exists (select 1 from auth.users where id = x.id) then
      insert into auth.users (id, email) values (x.id, x.email);
      if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = 'aud') then
        execute 'update auth.users set aud = ''authenticated'', role = ''authenticated'' where id = $1' using x.id;
      end if;
    end if;
    insert into platform.accesos_bd (usuario_bd, usuario_id, descripcion) values (x.bd, x.id, x.d) on conflict do nothing;
  end loop;
  -- Super Admin de plataforma y Soporte de plataforma
  select id into v_id from platform.roles where codigo = 'super_admin';
  insert into platform.asignaciones_plataforma (usuario_id, rol_id, asignado_por)
  select '00000000-0000-0000-0000-00000000bd01', v_id, '00000000-0000-0000-0000-00000000bd01'
  where not exists (select 1 from platform.asignaciones_plataforma where usuario_id = '00000000-0000-0000-0000-00000000bd01' and rol_id = v_id);
  select id into v_id from platform.roles where codigo = 'soporte';
  insert into platform.asignaciones_plataforma (usuario_id, rol_id, asignado_por)
  select '00000000-0000-0000-0000-00000000bd04', v_id, '00000000-0000-0000-0000-00000000bd01'
  where not exists (select 1 from platform.asignaciones_plataforma where usuario_id = '00000000-0000-0000-0000-00000000bd04' and rol_id = v_id);
end $$;

-- 9. Acceso a todos los negocios (y a los que se creen después)
create or replace function platform.sincronizar_accesos_bd(p_tenant uuid default null)
returns int language plpgsql security definer set search_path = '' as $$
declare t record; v_n int := 0; v_adm uuid; v_ope uuid;
begin
  select id into v_adm from platform.roles where codigo = 'administrador';
  select id into v_ope from platform.roles where codigo = 'operador';
  for t in select id from platform.tenants where eliminado_en is null and (p_tenant is null or id = p_tenant) loop
    insert into platform.membresias (tenant_id, usuario_id, rol_id, estado, cargo) values
      (t.id, '00000000-0000-0000-0000-00000000bd01', v_adm, 'activo', 'Super Administrador (BD)'),
      (t.id, '00000000-0000-0000-0000-00000000bd02', v_adm, 'activo', 'Administrador (BD)'),
      (t.id, '00000000-0000-0000-0000-00000000bd03', v_ope, 'activo', 'Trabajador (BD)')
    on conflict (tenant_id, usuario_id) do nothing;
    -- Soporte: autorización vigente de 7 días (el máximo permitido), renovable con platform.renovar_soporte_bd()
    if not exists (select 1 from platform.accesos_soporte a where a.tenant_id = t.id and a.usuario_soporte_id = '00000000-0000-0000-0000-00000000bd04'
                   and a.revocado_en is null and a.vence_en > now() + interval '1 day') then
      insert into platform.accesos_soporte (tenant_id, usuario_soporte_id, autorizado_por, inicio, vence_en, motivo)
      values (t.id, '00000000-0000-0000-0000-00000000bd04', '00000000-0000-0000-0000-00000000bd01', now(), now() + interval '7 days', 'Conexión directa de soporte al cliente');
    end if;
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
revoke execute on function platform.sincronizar_accesos_bd(uuid) from public, anon, authenticated;

create or replace function platform.renovar_soporte_bd() returns int language sql security definer set search_path = '' as $$
  select platform.sincronizar_accesos_bd(null);
$$;
revoke execute on function platform.renovar_soporte_bd() from public, anon, authenticated;
grant execute on function platform.renovar_soporte_bd() to elius_superadmin;
comment on function platform.renovar_soporte_bd() is 'Renueva por 7 días el acceso del usuario de Soporte (conexión directa) a todos los negocios';

create or replace function platform.sincronizar_accesos_bd_trg() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform platform.sincronizar_accesos_bd(new.id);
  return new;
end $$;
drop trigger if exists t90_accesos_bd on platform.tenants;
create trigger t90_accesos_bd after insert on platform.tenants for each row execute function platform.sincronizar_accesos_bd_trg();

select platform.sincronizar_accesos_bd(null);

-- 10. Para elegir con qué negocio trabajar desde la conexión directa
create or replace function platform.mis_negocios()
returns table (slug text, nombre text, vertical text, rol text, activo boolean)
language sql stable security definer set search_path = '' as $$
  select t.slug, t.nombre, t.vertical,
         coalesce((select r.codigo from platform.membresias m join platform.roles r on r.id = m.rol_id
                   where m.tenant_id = t.id and m.usuario_id = app.uid() and m.estado = 'activo'), 'soporte (autorizado)'),
         t.id = app.current_tenant_id()
  from platform.tenants t
  where app.tiene_acceso_tenant(app.uid(), t.id) order by t.creado_en;
$$;

create or replace function platform.usar_negocio(p_slug text)
returns text language plpgsql security definer set search_path = '' as $$
declare t record;
begin
  if not exists (select 1 from platform.accesos_bd where usuario_bd = session_user) then
    raise exception 'Solo para las conexiones directas por rol';
  end if;
  select * into t from platform.tenants where slug = p_slug and app.tiene_acceso_tenant(app.uid(), id);
  if not found then raise exception 'No tienes acceso a un negocio con ese slug (mira platform.mis_negocios())'; end if;
  perform set_config('app.tenant_id', t.id::text, false);
  return 'Negocio activo: ' || t.nombre || ' (' || t.vertical || ')';
end $$;

revoke execute on function platform.mis_negocios(), platform.usar_negocio(text) from public, anon, authenticated;
grant execute on function platform.mis_negocios(), platform.usar_negocio(text) to elius_superadmin, elius_administrador, elius_trabajador, elius_soporte;
comment on function platform.mis_negocios() is 'Negocios a los que tiene acceso la conexión directa (cuál está activo)';
comment on function platform.usar_negocio(text) is 'Elige el negocio de la sesión en una conexión directa: select platform.usar_negocio(''slug'')';
