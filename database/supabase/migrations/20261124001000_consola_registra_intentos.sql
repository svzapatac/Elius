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
