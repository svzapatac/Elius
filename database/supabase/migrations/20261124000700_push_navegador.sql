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
