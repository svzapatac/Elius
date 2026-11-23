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
