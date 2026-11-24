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
