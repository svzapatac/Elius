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
