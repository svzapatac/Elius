-- =============================================================================
-- 4200 · Flujos de prueba del restaurante (negocio de demostración)
--   El Administrador ejecuta, paso a paso desde el panel, la parte del "cliente" de cada flujo; las acciones de los
--   roles (aprobar, tomar, cambiar precio…) las hace él mismo en el panel, y la consola SQL sirve para ver antes y después.
--   Flujos: 1 pedido con cambio de precio y pago parcial · 2 comprobantes sospechosos · 3 un humano toma la conversación
--           4 reserva grande y ciclo de la reserva · 5 intentar romper el sistema
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

-- Ejecuta un paso automático de un flujo. Devuelve qué pasó, para mostrarlo en el panel.
create or replace function elius.paso_flujo_prueba(p_flujo int, p_paso int)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  t uuid := app.current_tenant_id();
  c uuid[]; v_item record; v_orden uuid; v_num bigint; v_total numeric; v_dir uuid; v_comp uuid; v_r uuid; v_res uuid; v_conv uuid; v_contacto uuid;
  v_ref text; v_hash text; v_prev_hash text; v_prev_ref text; v_monto numeric; v_err text; v_ini timestamptz; k int;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador ejecuta los flujos de prueba' using errcode = '42501'; end if;
  if not exists (select 1 from platform.tenants where id = t and slug like 'demo-restaurante%') then
    raise exception 'Los flujos de prueba son del restaurante de demostración'; end if;

  -- ───────── Flujo 1: pedido con cambio de precio y pago parcial ─────────
  if p_flujo = 1 and p_paso = 1 then
    select i.id, i.nombre, i.precio into v_item from elius.items_catalogo i
      join elius.categorias_catalogo cg on cg.tenant_id = i.tenant_id and cg.id = i.categoria_id
      where i.tenant_id = t and cg.nombre = 'Platos fuertes' and i.disponible and i.eliminado_en is null and i.precio > 0 order by i.precio desc limit 1;
    if v_item.id is null then raise exception 'No hay platos fuertes con precio en el catálogo'; end if;
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 1', 'ventas'); v_contacto := c[1]; v_conv := c[2];
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Hola, quiero 2 ' || v_item.nombre || ' para domicilio a la Calle 45 # 12-30');
    insert into elius.direcciones (tenant_id, contacto_id, etiqueta, direccion, ciudad, es_principal) values (t, v_contacto, 'Casa', 'Calle 45 # 12-30', 'Bogotá', true) returning id into v_dir;
    insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega, direccion_entrega_id)
      values (t, v_contacto, v_conv, 'whatsapp', 'domicilio', v_dir) returning id, numero into v_orden, v_num;
    insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item.id, 2);
    update elius.ordenes set estado = 'esperando_pago' where tenant_id = t and id = v_orden;
    select total into v_total from elius.ordenes where id = v_orden;
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', format('¡Con gusto! Pedido #%s: 2 x %s, total $%s con domicilio. Págalo por Nequi o transferencia y envíame el comprobante.', v_num, v_item.nombre, v_total));
    return jsonb_build_object('mensaje', format('Llegó el cliente. Eli armó el pedido #%s: 2 x %s a precio de catálogo $%s (total $%s).', v_num, v_item.nombre, v_item.precio, v_total),
                              'orden', v_num, 'producto', v_item.nombre, 'precio_catalogo', v_item.precio, 'total', v_total);
  elsif p_flujo = 1 and p_paso = 3 then
    select o.id, o.numero, o.conversacion_id, o.total into v_orden, v_num, v_conv, v_total from elius.ordenes o
      join elius.conversaciones cv on cv.tenant_id = o.tenant_id and cv.id = o.conversacion_id and cv.flujo = 'ventas'
      where o.tenant_id = t and o.eliminado_en is null order by o.creado_en desc limit 1;
    if v_orden is null then raise exception 'Primero ejecuta el paso 1'; end if;
    v_monto := round(v_total / 2);
    insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, app_origen, referencia, hash_archivo)
      values (t, v_orden, v_conv, v_monto, v_total, 'Cliente Flujo 1', 'Nequi', 'F1' || floor(random() * 1000000)::int, 'flujo-' || gen_random_uuid()::text) returning id into v_comp;
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '📎 Te pago la mitad por Nequi y el resto cuando llegue el domicilio', '/demo/comprobante-res-1.jpg');
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Recibí tu comprobante. El dueño lo está verificando y te confirmo en un momento.');
    return jsonb_build_object('mensaje', format('El cliente envió un comprobante de $%s sobre un total de $%s del pedido #%s. Está pendiente en Comprobantes.', v_monto, v_total, v_num), 'orden', v_num);

  -- ───────── Flujo 2: comprobantes sospechosos ─────────
  elsif p_flujo = 2 and p_paso between 1 and 4 then
    if p_paso = 2 then
      select hash_archivo, referencia into v_prev_hash, v_prev_ref from elius.comprobantes_pago where tenant_id = t and hash_archivo like 'flujo2-%' order by creado_en desc limit 1;
      if v_prev_hash is null then raise exception 'Primero ejecuta el paso 1 (el repetido copia el comprobante anterior)'; end if;
    end if;
    select i.id, i.precio into v_item from elius.items_catalogo i where i.tenant_id = t and i.disponible and i.eliminado_en is null and i.precio > 0 order by i.precio limit 1;
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 2.' || p_paso, 'pago'); v_contacto := c[1]; v_conv := c[2];
    insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega) values (t, v_contacto, v_conv, 'whatsapp', 'recoger') returning id, numero into v_orden, v_num;
    insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item.id, 2);
    update elius.ordenes set estado = 'esperando_pago' where tenant_id = t and id = v_orden;
    select total into v_total from elius.ordenes where id = v_orden;
    v_monto := case p_paso when 1 then round(v_total / 2) else v_total end;
    v_hash := case when p_paso = 2 then v_prev_hash else 'flujo2-' || gen_random_uuid()::text end;
    v_ref := case when p_paso = 2 then v_prev_ref else 'F2' || p_paso || floor(random() * 1000000)::int end;
    if p_paso = 3 and app.parametro(t, 'cuentas_pago') is null then
      insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
      values (t, 'cuentas_pago', 'Sabor Criollo', 'texto', 'Cuentas del negocio para validar el destinatario de los comprobantes') on conflict (tenant_id, clave) do nothing;
    end if;
    insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, destinatario, app_origen, referencia, hash_archivo)
      values (t, v_orden, v_conv, v_monto, v_total, 'Cliente Flujo 2.' || p_paso, case when p_paso = 3 then 'Juan Pérez 3009999999' when p_paso = 4 then 'Sabor Criollo' end, 'Nequi', v_ref, v_hash) returning id into v_comp;
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '📎 Aquí está mi comprobante', '/demo/comprobante-res-' || p_paso || '.jpg');
    return jsonb_build_object('mensaje', format('Pedido #%s por $%s con comprobante de $%s (%s). Revisa la alerta en Comprobantes.', v_num, v_total, v_monto,
      case p_paso when 1 then 'monto distinto' when 2 then 'repetido' when 3 then 'destinatario distinto' else 'correcto' end), 'orden', v_num);

  -- ───────── Flujo 3: un humano toma la conversación ─────────
  elsif p_flujo = 3 and p_paso = 1 then
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 3', 'ventas'); v_conv := c[2];
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Mi pedido de ayer llegó frío y faltó una bebida. Quiero hablar con una persona.');
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Lamento lo ocurrido. Te paso con una persona del equipo para resolverlo.');
    insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
      values (t, v_conv, 'Queja', 'Mi pedido de ayer llegó frío y faltó una bebida', 'Cliente molesto por un pedido frío e incompleto');
    return jsonb_build_object('mensaje', 'Eli escaló la queja. Debe aparecer en Pendientes, asignada por turnos a un Operador.');
  elsif p_flujo = 3 and p_paso in (3, 4, 6) then
    select cv.id into v_conv from elius.conversaciones cv join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
      where cv.tenant_id = t and i.nombre_en_canal = 'Cliente Flujo 3 Prueba' order by cv.creado_en desc limit 1;
    if v_conv is null then raise exception 'Primero ejecuta el paso 1'; end if;
    if p_paso = 3 then
      perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', '¿Alguien me va a responder?');
      return jsonb_build_object('mensaje', 'El cliente escribió otra vez. Si un Operador tomó la conversación, Eli no debe contestar.');
    elsif p_paso = 4 then
      begin
        perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Hola, soy Eli. ¿En qué te ayudo?');
        return jsonb_build_object('mensaje', 'Eli pudo responder: la conversación NO está tomada por una persona (o Eli estaba activo).', 'bloqueado', false);
      exception when others then
        get stacked diagnostics v_err = message_text;
        return jsonb_build_object('mensaje', 'Eli intentó responder y la base lo bloqueó: ' || v_err, 'bloqueado', true);
      end;
    else
      perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Gracias por esperar. Ya está resuelto con el equipo; quedo atenta si necesitas algo más.');
      return jsonb_build_object('mensaje', 'Eli retomó la conversación y respondió.');
    end if;

  -- ───────── Flujo 4: reserva grande y ciclo de la reserva ─────────
  elsif p_flujo = 4 and p_paso = 1 then
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 4', 'reservas'); v_contacto := c[1]; v_conv := c[2];
    perform elius.flujo_mensaje_prueba(t, v_conv, 'cliente', 'Quiero reservar para 24 personas, una celebración de empresa');
    v_ini := date_trunc('hour', now() + interval '1 day' + interval '3 hours');
    insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
      values (t, v_contacto, v_conv, 'R-' || upper(substr(md5(random()::text), 1, 5)), 'mesa', 'confirmada', v_ini, v_ini + interval '2 hours', 24, true);
    perform elius.flujo_mensaje_prueba(t, v_conv, 'eli', 'Listo: dejé tu reserva para 24 personas. Como es un grupo grande, el equipo te confirmará los detalles.');
    return jsonb_build_object('mensaje', 'Reserva de 24 personas creada: el Administrador debe recibir el aviso de grupo grande (evento de salida).');
  elsif p_flujo = 4 and p_paso = 2 then
    select id into v_r from elius.recursos where tenant_id = t and tipo = 'mesa' order by capacidad desc limit 1;
    if v_r is null then raise exception 'El restaurante no tiene mesas'; end if;
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 4b', 'reservas'); v_contacto := c[1];
    v_ini := date_trunc('hour', now() + interval '2 days' + interval '5 hours');
    for k in 1..2 loop
      begin
        insert into elius.reservas (tenant_id, contacto_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
          values (t, v_contacto, 'R-' || upper(substr(md5(random()::text), 1, 5)), 'mesa', 'confirmada', v_ini, v_ini + interval '1 hour', 2, true) returning id into v_res;
        insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin) values (t, v_res, v_r, v_ini, v_ini + interval '1 hour');
      exception when exclusion_violation then
        delete from elius.reservas where tenant_id = t and id = v_res;
        return jsonb_build_object('mensaje', 'La primera reserva ocupó la mesa. La segunda, a la misma hora y en la misma mesa, fue rechazada por cruce (RN-C07).', 'bloqueado', true);
      end;
    end loop;
    return jsonb_build_object('mensaje', 'No se detectó cruce (revisar).', 'bloqueado', false);
  elsif p_flujo = 4 and p_paso = 3 then
    for k in 1..3 loop
      c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 4.' || k, 'reservas');
      v_ini := now() + (k * interval '20 minutes');
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, creada_por_eli)
        values (t, c[1], c[2], 'R-' || upper(substr(md5(random()::text), 1, 5)), 'mesa', 'confirmada', v_ini, v_ini + interval '1 hour', 2 + k, true);
    end loop;
    return jsonb_build_object('mensaje', 'Se crearon 3 reservas para hoy, sin responsable, listas para tomar, marcar llegada o no llegada.');

  -- ───────── Flujo 5: intentar romper el sistema ─────────
  elsif p_flujo = 5 and p_paso = 1 then
    select i.id into v_item from elius.items_catalogo i where i.tenant_id = t and i.disponible and i.eliminado_en is null and i.precio > 0 order by i.precio limit 1;
    -- un pedido pagado (no se puede eliminar)
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 5 pagado', 'pago');
    insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega) values (t, c[1], c[2], 'whatsapp', 'recoger') returning id, numero into v_orden, v_num;
    insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item.id, 1);
    update elius.ordenes set estado = 'esperando_pago' where tenant_id = t and id = v_orden;
    select total into v_total from elius.ordenes where id = v_orden;
    insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, remitente, destinatario, app_origen, referencia, hash_archivo)
      values (t, v_orden, c[2], v_total, v_total, 'Cliente Flujo 5', 'Sabor Criollo', 'Nequi', 'F5' || floor(random() * 1000000)::int, 'flujo5-' || gen_random_uuid()::text) returning id into v_comp;
    perform elius.aprobar_comprobante(v_comp, false);
    -- un pedido sin pago (sí se puede eliminar)
    c := elius.flujo_cliente_prueba(t, 'Cliente Flujo 5 libre', 'ventas');
    insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega) values (t, c[1], c[2], 'whatsapp', 'recoger') returning id into v_orden;
    insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad) values (t, v_orden, v_item.id, 1);
    select numero into v_num from elius.ordenes where id = v_orden;
    return jsonb_build_object('mensaje', format('Listos: un pedido PAGADO (no se puede eliminar) y el pedido #%s SIN pago (sí se puede eliminar y restaurar).', v_num));
  end if;
  raise exception 'Paso no válido para el flujo %', p_flujo;
end $$;

revoke execute on function elius.flujo_cliente_prueba(uuid, text, text), elius.flujo_mensaje_prueba(uuid, uuid, text, text, text) from public, anon, authenticated;
revoke execute on function elius.paso_flujo_prueba(int, int) from public, anon;
grant execute on function elius.paso_flujo_prueba(int, int) to authenticated;
comment on function elius.paso_flujo_prueba(int, int) is 'Ejecuta un paso automático (la parte del cliente o de Eli) de un flujo de prueba del restaurante de demostración; solo Administrador';
