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
