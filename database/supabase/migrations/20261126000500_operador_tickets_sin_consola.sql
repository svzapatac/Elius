-- 0500 · El Operador ya no usa la consola SQL; sí crea tickets (con categoría y prioridad) y ve su estado y solución.
--  · Consola: solo Administrador y Super Admin.
--  · v_mis_reportes: incluye los tickets creados desde el panel (origen 'panel') además de los reportes rápidos.
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


drop view if exists elius.v_mis_reportes;
create view elius.v_mis_reportes as
  select t.id, t.creado_en, (t.codigo || ' · ' || t.asunto) as mensaje, t.resuelto_en, t.solucion as notas, (t.estado <> 'resuelto') as abierto,
         t.categoria, t.prioridad, t.estado, t.creado_por = auth.uid() as es_mio
  from elius.tickets t
  where t.tenant_id = app.current_tenant_id() and t.origen in ('reporte', 'panel')
    and app.mi_rol() in ('operador', 'administrador')
    and (app.mi_rol() = 'administrador' or t.creado_por = auth.uid());
grant select on elius.v_mis_reportes to authenticated;
comment on view elius.v_mis_reportes is 'Tickets que la persona creó (el Administrador ve los de todo el negocio): estado y solución que les da Soporte';
