-- =============================================================================
-- 4100 · Comprobante de prueba para la demostración (negocios demo)
--   El Administrador genera, con un botón del panel, un pedido real con su comprobante de pago para ver actuar los triggers:
--   t41/t42 (precio y total), t52 (alertas del comprobante), t53 (evento), t56 (aviso al celular), t55 (solo el Administrador decide),
--   t51 (confirma la orden al cubrirse el total) y t50 (un pago aprobado no se modifica).
--   Casos: 'exacto' (monto correcto), 'distinto' (monto menor al esperado → alerta) y 'repetido' (mismo comprobante enviado dos veces).
-- =============================================================================
create or replace function elius.generar_comprobante_prueba(p_caso text default 'exacto')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id(); v_n int := 100 + floor(random() * 900)::int;
  v_contacto uuid; v_orden uuid; v_item uuid; v_comp uuid; v_num bigint; v_canal uuid; v_ident uuid; v_conv uuid; v_total numeric; v_monto numeric;
  v_hash text; v_ref text; v_prev_id uuid; v_prev_hash text; v_prev_ref text;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador genera comprobantes de prueba' using errcode = '42501'; end if;
  if not exists (select 1 from platform.tenants where id = t and slug like 'demo-%') then raise exception 'Solo disponible en los negocios de demostración'; end if;
  if p_caso not in ('exacto', 'distinto', 'repetido') then raise exception 'Caso no válido: exacto, distinto o repetido'; end if;

  if p_caso = 'repetido' then
    select id, hash_archivo, referencia into v_prev_id, v_prev_hash, v_prev_ref from elius.comprobantes_pago where tenant_id = t and hash_archivo like 'demo-%' order by creado_en desc limit 1;
  end if;

  select id into v_item from elius.items_catalogo where tenant_id = t and eliminado_en is null and precio > 0 and disponible order by precio limit 1;
  if v_item is null then raise exception 'El catálogo no tiene productos con precio'; end if;

  insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
  values (t, 'Cliente', 'Pago ' || v_n, '+57320' || lpad((floor(random() * 10000000))::int::text, 7, '0'), 'panel') returning id into v_contacto;
  insert into elius.ordenes (tenant_id, contacto_id, canal_venta, tipo_entrega) values (t, v_contacto, 'whatsapp', 'recoger') returning id, numero into v_orden, v_num;
  insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item, 2);
  select total into v_total from elius.ordenes where id = v_orden;
  select id into v_canal from elius.canales where tenant_id = t order by creado_en limit 1;
  if v_canal is null then raise exception 'El negocio no tiene un canal de atención configurado'; end if;
  insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
  values (t, v_contacto, v_canal, '57320' || v_n || gen_random_uuid()::text, 'Cliente Pago ' || v_n) returning id into v_ident;
  insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (t, v_ident, 'pago') returning id into v_conv;

  v_monto := case p_caso when 'distinto' then round(v_total / 2) else v_total end;
  v_hash := case when p_caso = 'repetido' and v_prev_id is not null then v_prev_hash else 'demo-' || gen_random_uuid()::text end;
  v_ref := case when p_caso = 'repetido' and v_prev_id is not null then v_prev_ref else 'DEMO' || v_n || lpad((floor(random() * 100000))::int::text, 5, '0') end;

  insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, destinatario, app_origen, referencia, hash_archivo)
  values (t, v_orden, v_conv, v_monto, v_total, 'Cliente Pago ' || v_n, null, 'Nequi', v_ref, v_hash) returning id into v_comp;

  return jsonb_build_object('comprobante_id', v_comp, 'orden', v_num, 'total', v_total, 'monto_enviado', v_monto, 'caso', p_caso,
                            'repetido_de_otro', p_caso = 'repetido' and v_prev_id is not null);
end $$;
revoke execute on function elius.generar_comprobante_prueba(text) from public, anon;
grant execute on function elius.generar_comprobante_prueba(text) to authenticated;
comment on function elius.generar_comprobante_prueba(text) is 'Crea un cliente, un pedido y un comprobante de pago de prueba (exacto, de monto distinto o repetido) para ver actuar los triggers; solo Administrador en negocios demo';
