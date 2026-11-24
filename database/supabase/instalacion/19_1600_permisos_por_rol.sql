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
