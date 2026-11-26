-- =============================================================================
-- 4200 · Flujos de prueba del restaurante (negocio de demostración)
--   Cinco flujos: los dos primeros llevan una conversación predeterminada que llega mensaje a mensaje (la parte del cliente
--   y de Eli la pone esta función; las acciones de cada rol las hace la persona en su panel). Los otros tres son manuales,
--   en vivo, y solo usan la consola SQL para ver antes y después.
--   1 pedido con cambio de precio y pago parcial · 2 un humano toma la conversación (predeterminados)
--   3 comprobantes sospechosos · 4 reserva grande y ciclo de la reserva · 5 intentar romper el sistema (manuales)
-- =============================================================================
create or replace function elius.flujo_cliente_prueba(p_tenant uuid, p_nombre text, p_flujo text)
returns uuid[] language plpgsql security definer set search_path = '' as $$
declare v_canal uuid; v_contacto uuid; v_ident uuid; v_conv uuid; v_tel text := '+57311' || lpad((floor(random() * 10000000))::int::text, 7, '0');
begin
  select id into v_canal from elius.canales where tenant_id = p_tenant order by creado_en limit 1;
  if v_canal is null then raise exception 'El negocio no tiene un canal de atención configurado'; end if;
  insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen) values (p_tenant, p_nombre, 'Prueba', v_tel, 'whatsapp') returning id into v_contacto;
  insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
  values (p_tenant, v_contacto, v_canal, v_tel, p_nombre || ' Prueba') returning id into v_ident;
  insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (p_tenant, v_ident, p_flujo) returning id into v_conv;
  return array[v_contacto, v_conv];
end $$;

create or replace function elius.flujo_mensaje_prueba(p_tenant uuid, p_conv uuid, p_emisor text, p_texto text, p_url text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_mid uuid;
begin
  insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, url_adjunto, estado_entrega, procesado)
  values (p_tenant, p_conv, p_emisor, case when p_url is null then 'texto' else 'imagen' end, p_texto, p_url,
          case when p_emisor = 'cliente' then 'recibido' else 'entregado' end, true) returning id into v_mid;
  if p_emisor = 'eli' then perform elius.efectos_demo(p_tenant, p_conv, v_mid, p_texto, null, -1); end if;
end $$;

-- Ejecuta un paso de una conversación predeterminada. Devuelve qué pasó, para mostrarlo en el panel.
--   Flujo 1: 11 llega el cliente y pide · 12 Eli arma el pedido · 3 el cliente envía el comprobante de la mitad
--   Flujo 2: 11 el cliente se queja · 12 Eli escala · 3 el cliente escribe otra vez · 4 Eli intenta responder · 6 Eli retoma
create or replace function elius.paso_flujo_prueba(p_flujo int, p_paso int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id();
  c uuid[]; v_item record; v_orden uuid; v_num bigint; v_total numeric; v_dir uuid; v_comp uuid; v_conv uuid; v_contacto uuid;
  v_monto numeric; v_err text;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador ejecuta los flujos de prueba' using errcode = '42501'; end if;
  if not exists (select 1 from platform.tenants where id = t and slug like 'demo-restaurante%') then
    raise exception 'Los flujos de prueba son del restaurante de demostración'; end if;

  -- ───────── Flujo 1: pedido con cambio de precio y pago parcial ─────────
  if p_flujo = 1 and p_paso = 11 then
    select i.id, i.nombre, i.precio into v_item from elius.items_catalogo i
      join elius.categorias_catalogo cg on cg.tenant_id = i.tenant_id and cg.id = i.categoria_id
      where i.tenant_id = t and cg.nombre = 'Platos fuertes' and i.disponible and i.eliminado_en is null and i.precio > 0 order by i.precio desc limit 1;
    if v_item.id is null then raise exception 'No hay platos fuertes con precio en el catálogo'; end if;
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 1', 'ventas'); v_conv := c[2];
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, quiero 2 ' || v_item.nombre || ' para domicilio a la Calle 45 # 12-30');
    return jsonb_build_object('mensaje', format('Llegó el cliente y pidió 2 x %s (precio de catálogo $%s).', v_item.nombre, v_item.precio), 'precio_catalogo', v_item.precio);
  elsif p_flujo = 1 and p_paso = 12 then
    select cv.id, i.contacto_id into v_conv, v_contacto from elius.conversaciones cv join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
      where cv.tenant_id = t and i.nombre_en_canal = 'Cliente Flujo 1 Prueba' order by cv.creado_en desc limit 1;
    if v_conv is null then raise exception 'Primero ejecuta el paso 11 (llega el cliente)'; end if;
    select i.id, i.nombre into v_item from elius.items_catalogo i
      join elius.categorias_catalogo cg on cg.tenant_id = i.tenant_id and cg.id = i.categoria_id
      where i.tenant_id = t and cg.nombre = 'Platos fuertes' and i.disponible and i.eliminado_en is null and i.precio > 0 order by i.precio desc limit 1;
    insert into elius.direcciones (tenant_id, contacto_id, etiqueta, direccion, ciudad, es_principal) values (t, v_contacto, 'Casa', 'Calle 45 # 12-30', 'Bogotá', true) returning id into v_dir;
    insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega, direccion_entrega_id)
      values (t, v_contacto, v_conv, 'whatsapp', 'domicilio', v_dir) returning id, numero into v_orden, v_num;
    insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item.id, 2);
    update elius.ordenes set estado = 'esperando_pago' where tenant_id = t and id = v_orden;
    select total into v_total from elius.ordenes where id = v_orden;
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('¡Con gusto! Pedido #%s: 2 x %s, total $%s con domicilio. Págalo por Nequi o transferencia y envíame el comprobante.', v_num, v_item.nombre, v_total));
    return jsonb_build_object('mensaje', format('Eli armó el pedido #%s (total $%s) al precio de catálogo del momento y le respondió al cliente.', v_num, v_total), 'orden', v_num, 'total', v_total);
  elsif p_flujo = 1 and p_paso = 3 then
    select o.id, o.numero, o.conversacion_id, o.total into v_orden, v_num, v_conv, v_total from elius.ordenes o
      join elius.conversaciones cv on cv.tenant_id = o.tenant_id and cv.id = o.conversacion_id and cv.flujo = 'ventas'
      join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id and i.nombre_en_canal = 'Cliente Flujo 1 Prueba'
      where o.tenant_id = t and o.eliminado_en is null order by o.creado_en desc limit 1;
    if v_orden is null then raise exception 'Primero ejecuta los pasos anteriores'; end if;
    v_monto := round(v_total / 2);
    insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, app_origen, referencia, hash_archivo)
      values (t, v_orden, v_conv, v_monto, v_total, 'Cliente Flujo 1', 'Nequi', 'F1' || floor(random() * 1000000)::int, 'flujo-' || gen_random_uuid()::text) returning id into v_comp;
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '📎 Te pago la mitad por Nequi y el resto cuando llegue el domicilio', '/demo/comprobante-res-1.jpg');
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Recibí tu comprobante. El dueño lo está verificando y te confirmo en un momento.');
    return jsonb_build_object('mensaje', format('El cliente envió un comprobante de $%s sobre un total de $%s del pedido #%s. Está pendiente en Comprobantes.', v_monto, v_total, v_num), 'orden', v_num);

  -- ───────── Flujo 2: un humano toma la conversación ─────────
  elsif p_flujo = 2 and p_paso = 11 then
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 2', 'ventas'); v_conv := c[2];
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Mi pedido de ayer llegó frío y faltó una bebida. Quiero hablar con una persona.');
    return jsonb_build_object('mensaje', 'El cliente se queja y pide hablar con una persona.');
  elsif p_flujo = 2 and p_paso in (12, 3, 4, 6) then
    select cv.id into v_conv from elius.conversaciones cv join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
      where cv.tenant_id = t and i.nombre_en_canal = 'Cliente Flujo 2 Prueba' order by cv.creado_en desc limit 1;
    if v_conv is null then raise exception 'Primero ejecuta el paso 11 (llega el cliente)'; end if;
    if p_paso = 12 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Lamento lo ocurrido. Te paso con una persona del equipo para resolverlo.');
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
        values (t, v_conv, 'Queja', 'Mi pedido de ayer llegó frío y faltó una bebida', 'Cliente molesto por un pedido frío e incompleto');
      return jsonb_build_object('mensaje', 'Eli escaló la queja. Debe aparecer en Pendientes, asignada por turnos a un Operador.');
    elsif p_paso = 3 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '¿Alguien me va a responder?');
      return jsonb_build_object('mensaje', 'El cliente escribió otra vez.');
    elsif p_paso = 4 then
      begin
        perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Hola, soy Eli. ¿En qué te ayudo?');
        return jsonb_build_object('mensaje', 'Eli pudo responder: la conversación NO está en manos de una persona.', 'bloqueado', false);
      exception when others then
        get stacked diagnostics v_err = message_text;
        return jsonb_build_object('mensaje', 'Eli intentó responder y la base lo bloqueó: ' || v_err, 'bloqueado', true);
      end;
    else
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Gracias por esperar. Ya está resuelto con el equipo; quedo atenta si necesitas algo más.');
      return jsonb_build_object('mensaje', 'Eli retomó la conversación y respondió.');
    end if;
  end if;
  raise exception 'Paso no válido para el flujo %', p_flujo;
end $$;

revoke execute on function elius.flujo_cliente_prueba(uuid, text, text), elius.flujo_mensaje_prueba(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke execute on function elius.paso_flujo_prueba(int, int) from public, anon;
grant execute on function elius.paso_flujo_prueba(int, int) to authenticated;
comment on function elius.paso_flujo_prueba(int, int) is 'Ejecuta un paso de una conversación predeterminada (flujos 1 y 2) del restaurante de demostración; solo Administrador';
