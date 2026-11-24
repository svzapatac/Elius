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
