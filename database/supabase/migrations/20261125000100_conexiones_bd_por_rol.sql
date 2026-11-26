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
