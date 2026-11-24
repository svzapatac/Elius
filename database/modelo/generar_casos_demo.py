"""Genera la migración 1200 (casos de prueba con conversaciones completas hasta el pago).
Uso: python3 database/modelo/generar_casos_demo.py"""
import json, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from casos_demo import CASOS, SKU

VERSION = '8'   # súbela si cambia el guion o el catálogo: los negocios de prueba existentes se vuelven a sembrar

def q(s): return s.replace("'", "''")

def datos_sql(v):
    c = CASOS[v]
    d = {'negocio': c['negocio'], 'categorias': c['categoria'], 'contactos': c['contactos'],
         'items': [dict(cat=i[0], tipo=i[1], sku=i[2], nombre=i[3], desc=i[4], precio=i[5], iva=0, dur=i[7]) for i in c['items']],   # precios con impuestos incluidos
         'guion': [dict(conv=g[0], emisor=g[1], texto=g[2], img=g[3], comp=g[4]) for g in c['guion']],
         'imagenes': c.get('imagenes', {}), 'recursos': [list(r) for r in c['recursos']], 'efectos': c['efectos'], 'agenda': [list(a) for a in c['agenda']],
         'pagos': [dict(items=[list(x) for x in p['items']], entrega=p['entrega'], comp=p['comp'], aprobado=p['aprobado'], rechazado=p['rechazado']) for p in c['pagos']]}
    return json.dumps(d, ensure_ascii=False)

ramas = '\n'.join(f"    when '{v}' then '{q(datos_sql(v))}'::jsonb" for v in CASOS)
sql = f"""-- =============================================================================
-- 1200 · Casos de prueba por vertical (restaurante, veterinaria, aerolínea)
-- La profesora elige un caso en el panel: se crea su negocio con catálogo (5 ítems con imagen) y llegan
-- 20 clientes de prueba. Tres conversaciones llegan hasta el pago: el cliente envía el comprobante,
-- queda en Comprobantes y, cuando quien revisa lo aprueba o lo rechaza, Eli continúa la conversación.
-- =============================================================================

create or replace function elius.datos_caso_demo(p_vertical text)
returns jsonb language sql immutable set search_path = '' as $$
  select case p_vertical
{ramas}
  end;
$$;

-- Los negocios de prueba son borrables en bloque: se permite borrar sus pagos aprobados (RN-C12 sigue vigente en el resto)
create or replace function app.proteger_pago()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.estado = 'aprobado' and not (tg_op = 'DELETE' and exists (
        select 1 from platform.tenants t where t.id = old.tenant_id and t.slug like 'demo-%')) then
    raise exception 'RN-C12: un pago aprobado no se modifica; registre un reverso' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- El revisor ve la foto del comprobante y a qué conversación pertenece
create or replace view elius.v_comprobantes_pendientes with (security_invoker = true) as
select cp.tenant_id, cp.id as comprobante_id, cp.creado_en, cp.monto_leido, cp.monto_esperado, cp.coincide,
       cp.app_origen, cp.referencia, cp.destinatario, cp.motivo,
       coalesce(cp.motivo like 'ALERTA:%', false) as tiene_alerta,
       o.numero as orden_numero, c.nombres as cliente,
       cp.url_archivo, cp.conversacion_id
from elius.comprobantes_pago cp
join elius.conversaciones cv on cv.tenant_id = cp.tenant_id and cv.id = cp.conversacion_id
join elius.identidades_contacto i on i.tenant_id = cv.tenant_id and i.id = cv.identidad_id
join elius.contactos c on c.tenant_id = i.tenant_id and c.id = i.contacto_id
left join elius.ordenes o on o.tenant_id = cp.tenant_id and o.id = cp.orden_id
where cp.veredicto = 'pendiente';

-- Borra lo sembrado (clientes, chats, órdenes y comprobantes) y deja el caso listo desde cero
create or replace function elius.limpiar_caso_demo(p_tenant uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from elius.pagos where tenant_id = p_tenant;
  delete from elius.comprobantes_pago where tenant_id = p_tenant;
  delete from elius.entregas where tenant_id = p_tenant;
  delete from elius.ordenes where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.asignaciones_recurso where tenant_id = p_tenant;
  delete from elius.reservas where tenant_id = p_tenant;
  delete from elius.escalamientos where tenant_id = p_tenant;
  delete from elius.consumos_llm where tenant_id = p_tenant;
  delete from elius.contactos where tenant_id = p_tenant;   -- cascada: identidades, conversaciones y mensajes
  delete from elius.parametros_negocio where tenant_id = p_tenant and clave like 'demo\\_%';
end $$;

-- Crea los clientes del caso (uno por conversación) y deja el catálogo con los datos actuales
create or replace function elius.sembrar_clientes_demo(p_tenant uuid, p_vertical text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_canal uuid; v_contacto uuid; v_ident uuid; r jsonb; v_ini timestamptz; v_res uuid; v_cat uuid; v_item uuid; rr record;
begin
  select id into v_canal from elius.canales where tenant_id = p_tenant order by creado_en limit 1;
  perform elius.limpiar_caso_demo(p_tenant);
  -- categorías e ítems con su imagen (se crean los que falten y se actualizan los existentes)
  for rr in select value, ordinality - 1 as i from jsonb_array_elements(v_d->'categorias') with ordinality loop
    insert into elius.categorias_catalogo (tenant_id, nombre, orden)
    select p_tenant, rr.value #>> '{{}}', rr.i::int
    where not exists (select 1 from elius.categorias_catalogo where tenant_id = p_tenant and nombre = rr.value #>> '{{}}');
  end loop;
  for rr in select value, ordinality as k from jsonb_array_elements(v_d->'items') with ordinality loop
    select id into v_cat from elius.categorias_catalogo
    where tenant_id = p_tenant and nombre = (v_d->'categorias') ->> ((rr.value->>'cat')::int);
    insert into elius.items_catalogo (tenant_id, categoria_id, tipo, sku, nombre, descripcion, precio, impuesto_pct, duracion_min)
    values (p_tenant, v_cat, rr.value->>'tipo', rr.value->>'sku', rr.value->>'nombre', rr.value->>'desc',
            (rr.value->>'precio')::numeric, (rr.value->>'iva')::numeric, nullif(rr.value->>'dur', '')::int)
    on conflict (tenant_id, sku) do update set nombre = excluded.nombre, descripcion = excluded.descripcion, precio = excluded.precio,
           impuesto_pct = excluded.impuesto_pct, categoria_id = excluded.categoria_id, disponible = true;
    select id into v_item from elius.items_catalogo where tenant_id = p_tenant and sku = rr.value->>'sku';
    -- las fotos que puso el dueño se respetan; las del demo (propias o de Wikimedia Commons) se actualizan
    delete from elius.medios_item where tenant_id = p_tenant and item_id = v_item
      and (url like '/demo/%' or url like 'https://commons.wikimedia.org/%');
    if not exists (select 1 from elius.medios_item where tenant_id = p_tenant and item_id = v_item) then
      insert into elius.medios_item (tenant_id, item_id, tipo_archivo, url, descripcion, orden)
      values (p_tenant, v_item, 'foto', coalesce(v_d->'imagenes'->>(rr.value->>'sku'), '/demo/' || p_vertical || '-' || rr.k || '.svg'), rr.value->>'nombre', 0);
    end if;
  end loop;
  for r in select * from jsonb_array_elements(v_d->'recursos') loop
    insert into elius.recursos (tenant_id, tipo, nombre, capacidad)
    select p_tenant, r->>0, r->>1, (r->>2)::int
    where not exists (select 1 from elius.recursos where tenant_id = p_tenant and nombre = r->>1);
  end loop;
  for r in select * from jsonb_array_elements(v_d->'contactos') loop
    insert into elius.contactos (tenant_id, nombres, apellidos, telefono, origen)
    values (p_tenant, r->>0, r->>1, r->>2, 'whatsapp') returning id into v_contacto;
    insert into elius.identidades_contacto (tenant_id, contacto_id, canal_id, id_externo, nombre_en_canal)
    values (p_tenant, v_contacto, v_canal, r->>2, (r->>0) || ' ' || (r->>1)) returning id into v_ident;
    insert into elius.conversaciones (tenant_id, identidad_id, flujo) values (p_tenant, v_ident, 'general');
  end loop;
  for r in select * from jsonb_array_elements(v_d->'agenda') loop
    select c.id into v_contacto from elius.contactos c where c.tenant_id = p_tenant
    order by c.telefono offset (r->>2)::int limit 1;
    v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + (r->>0)::int * interval '1 day' + ((r->>1)::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
    insert into elius.reservas (tenant_id, contacto_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
    values (p_tenant, v_contacto, 'R-' || upper(substr(md5(random()::text), 1, 5)), r->>3, r->>6, v_ini, v_ini + interval '1 hour',
            (r->>4)::int, (r->>7)::boolean, true) returning id into v_res;
    begin
      insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
      select p_tenant, v_res, rc.id, v_ini, v_ini + interval '1 hour' from elius.recursos rc where rc.tenant_id = p_tenant and rc.nombre = r->>5;
    exception when exclusion_violation then null;
    end;
  end loop;
  insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion) values
    (p_tenant, 'demo_indice', '0', 'numero', 'Mensajes de prueba ya entregados (caso de demostración)'),
    (p_tenant, 'demo_version', '{VERSION}', 'texto', 'Versión del guion sembrado');
end $$;

-- Crea (o reutiliza) el negocio de prueba del caso para el usuario que llama y lo deja activo
create or replace function platform.cargar_caso_demo(p_vertical text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_d jsonb := elius.datos_caso_demo(p_vertical);
  v_slug text;
  v_tenant uuid; v_agente uuid; v_canal uuid;
  
begin
  if v_uid is null then raise exception 'Debe iniciar sesión' using errcode = '42501'; end if;
  if v_d is null then raise exception 'Caso desconocido: %', p_vertical; end if;
  v_slug := 'demo-' || p_vertical || '-' || substr(replace(v_uid::text, '-', ''), 1, 6);

  select id into v_tenant from platform.tenants where slug = v_slug;
  if v_tenant is not null then
    -- si quedó de una versión anterior del caso, se vuelve a sembrar
    if coalesce((select valor from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_version'), '') <> '{VERSION}' then
      perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
    end if;
    perform platform.cambiar_tenant(v_tenant);
    return v_tenant;
  end if;

  v_tenant := platform.crear_tenant(v_d->>'negocio', v_slug, p_vertical);
  select id into v_agente from elius.agentes where tenant_id = v_tenant limit 1;
  insert into elius.canales (tenant_id, agente_id, tipo, nombre, identificador_externo)
  values (v_tenant, v_agente, 'whatsapp', 'WhatsApp de prueba', 'demo-' || v_slug) returning id into v_canal;

  perform elius.sembrar_clientes_demo(v_tenant, p_vertical);
  perform platform.cambiar_tenant(v_tenant);
  return v_tenant;
end $$;

-- Lo que Eli deja registrado al responder: consumo de IA y, según el guion, un caso pendiente o una reserva de hoy
create or replace function elius.efectos_demo(p_tenant uuid, p_conv uuid, p_msg uuid, p_texto text, p_efectos jsonb, p_tras int)
returns void language plpgsql security definer set search_path = '' as $$
declare e jsonb; v_contacto uuid; v_reserva uuid; v_recurso uuid; v_ini timestamptz;
begin
  insert into elius.consumos_llm (tenant_id, conversacion_id, mensaje_id, proveedor, modelo, tokens_entrada, tokens_salida, tokens_cache, costo_usd, latencia_ms)
  values (p_tenant, p_conv, p_msg, 'anthropic', 'claude-sonnet-5-5', 900 + length(p_texto) * 2, 40 + length(p_texto) / 3, 600,
          round((0.0009 + length(p_texto) * 0.000004)::numeric, 6), 900 + (length(p_texto) * 7) % 1400);
  for e in select * from jsonb_array_elements(coalesce(p_efectos, '[]'::jsonb)) where (value->>'tras')::int = p_tras loop
    if e ? 'escalar' then
      insert into elius.escalamientos (tenant_id, conversacion_id, motivo, mensaje_cliente, resumen)
      values (p_tenant, p_conv, e->>'escalar',
              (select m.contenido from elius.mensajes m where m.tenant_id = p_tenant and m.conversacion_id = p_conv and m.emisor = 'cliente' order by m.creado_en desc limit 1),
              e->>'resumen');
    elsif e ? 'reserva' then
      select i.contacto_id into v_contacto from elius.conversaciones c
      join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
      where c.tenant_id = p_tenant and c.id = p_conv;
      v_ini := greatest(((date_trunc('day', now() at time zone 'America/Bogota') + ((e->>'h')::numeric * interval '1 hour')) at time zone 'America/Bogota'), now() + interval '10 minutes');
      insert into elius.reservas (tenant_id, contacto_id, conversacion_id, codigo, tipo, estado, inicio, fin, personas, urgente, creada_por_eli)
      values (p_tenant, v_contacto, p_conv, 'R-' || upper(substr(md5(random()::text), 1, 5)), e->>'reserva', 'confirmada',
              v_ini, v_ini + interval '1 hour', coalesce((e->>'personas')::int, 1), coalesce((e->>'urgente')::boolean, false), true)
      returning id into v_reserva;
      select id into v_recurso from elius.recursos where tenant_id = p_tenant and nombre = e->>'recurso';
      if v_recurso is not null then
        begin
          insert into elius.asignaciones_recurso (tenant_id, reserva_id, recurso_id, inicio, fin)
          values (p_tenant, v_reserva, v_recurso, v_ini, v_ini + interval '1 hour');
        exception when exclusion_violation then null;   -- el recurso ya estaba ocupado a esa hora: la reserva queda sin recurso
        end;
      end if;
    end if;
  end loop;
end $$;

-- Cuántos comprobantes de la prueba esperan decisión y cuántos mensajes posteriores faltan por entregar
create or replace function elius.estado_demo(p_tenant uuid, p_d jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_pidx int; v_esperando int := 0; v_post int := 0; v_ver text; v_k int; v_p jsonb;
begin
  for v_pidx in 0 .. coalesce(jsonb_array_length(p_d->'pagos'), 0) - 1 loop
    v_p := p_d->'pagos'->v_pidx;
    select cp.veredicto into v_ver from elius.comprobantes_pago cp
    where cp.tenant_id = p_tenant and cp.media_id = 'demo-' || v_pidx order by cp.creado_en desc limit 1;
    if v_ver = 'pendiente' then
      v_esperando := v_esperando + 1;
    elsif v_ver in ('aprobado', 'rechazado') then
      select coalesce(valor::int, 0) into v_k from elius.parametros_negocio where tenant_id = p_tenant and clave = 'demo_post_' || v_pidx;
      if coalesce(v_k, 0) < jsonb_array_length(v_p->v_ver) then v_post := v_post + 1; end if;
    end if;
  end loop;
  return jsonb_build_object('esperando', v_esperando, 'post', v_post);
end $$;

-- Entrega el siguiente mensaje del guion. El panel lo llama cada pocos segundos.
-- 1) Si quien revisa ya decidió un comprobante, Eli continúa esa conversación (antes que lo demás).
-- 2) Si no, llega el siguiente mensaje de la cola; el comprobante se registra al enviarlo el cliente.
-- Si una persona tomó la conversación, Eli no responde en ella (RN-C19) y se salta ese mensaje.
create or replace function elius.siguiente_mensaje_demo()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_tenant uuid := app.current_tenant_id();
  v_vertical text; v_slug text; v_d jsonb; v_guion jsonb; v_pagos jsonb; v_i int; v_total int;
  v_g jsonb; v_conv uuid; v_estado text; v_texto text; v_k int; v_p jsonb; v_pidx int;
  v_ver text; v_orden uuid; v_contacto uuid; v_esperado numeric; v_url text; v_it jsonb; v_emisor text;
  v_est jsonb; v_clientes int; v_fin boolean; v_tipo text; v_dir uuid; v_mid uuid;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select slug, vertical into v_slug, v_vertical from platform.tenants where id = v_tenant;
  if v_slug not like 'demo-%' then raise exception 'Este negocio no es un caso de prueba'; end if;
  v_d := elius.datos_caso_demo(v_vertical);
  v_guion := v_d->'guion'; v_pagos := coalesce(v_d->'pagos', '[]'::jsonb); v_total := jsonb_array_length(v_guion);
  select valor::int into v_i from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_indice';

  -- 1) continuar las conversaciones cuyo comprobante ya fue decidido
  for v_pidx in 0 .. jsonb_array_length(v_pagos) - 1 loop
    v_p := v_pagos->v_pidx;
    select cp.veredicto, cp.conversacion_id, cp.orden_id into v_ver, v_conv, v_orden
    from elius.comprobantes_pago cp where cp.tenant_id = v_tenant and cp.media_id = 'demo-' || v_pidx
    order by cp.creado_en desc limit 1;
    continue when v_ver is null or v_ver = 'pendiente';
    select coalesce(valor::int, 0) into v_k from elius.parametros_negocio where tenant_id = v_tenant and clave = 'demo_post_' || v_pidx;
    v_k := coalesce(v_k, 0);
    if v_k < jsonb_array_length(v_p->v_ver) then
      v_g := (v_p->v_ver)->v_k;
      v_emisor := v_g->>'emisor';
      v_texto := replace(v_g->>'texto', '{{orden}}', coalesce((select numero::text from elius.ordenes where tenant_id = v_tenant and id = v_orden), ''));
      select estado into v_estado from elius.conversaciones where tenant_id = v_tenant and id = v_conv;
      if not (v_emisor = 'eli' and v_estado in ('humano', 'pausa')) then
        insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, estado_entrega, procesado)
        values (v_tenant, v_conv, v_emisor, 'texto', v_texto, case when v_emisor = 'cliente' then 'recibido' else 'entregado' end, true)
        returning id into v_mid;
        if v_emisor = 'eli' then perform elius.efectos_demo(v_tenant, v_conv, v_mid, v_texto, null, -1); end if;
      end if;
      insert into elius.parametros_negocio (tenant_id, clave, valor, tipo_dato, descripcion)
      values (v_tenant, 'demo_post_' || v_pidx, (v_k + 1)::text, 'numero', 'Mensajes posteriores a la decisión ya entregados')
      on conflict (tenant_id, clave) do update set valor = (v_k + 1)::text;
      v_est := elius.estado_demo(v_tenant, v_d);
      select count(distinct conversacion_id) into v_clientes from elius.mensajes where tenant_id = v_tenant and emisor = 'cliente';
      return jsonb_build_object('terminado', v_i >= v_total and (v_est->>'esperando')::int = 0 and (v_est->>'post')::int = 0,
        'indice', v_i, 'total', v_total, 'emisor', v_emisor, 'conversacion_id', v_conv, 'clientes', v_clientes,
        'esperando', (v_est->>'esperando')::int, 'decision', v_ver);
    end if;
  end loop;

  -- 2) siguiente mensaje de la cola principal
  loop
    exit when v_i >= v_total;
    v_g := v_guion -> v_i;
    select c.id, c.estado into v_conv, v_estado
    from elius.conversaciones c
    join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
    where c.tenant_id = v_tenant order by i.id_externo offset (v_g->>'conv')::int limit 1;
    exit when not (v_g->>'emisor' = 'eli' and v_estado in ('humano', 'pausa'));
    v_i := v_i + 1;
  end loop;

  if v_i < v_total then
    v_texto := v_g->>'texto';
    v_url := case when (v_g->>'img') is not null then
              coalesce(v_d->'imagenes'->>(v_d->'items'->((v_g->>'img')::int - 1)->>'sku'), '/demo/' || v_vertical || '-' || (v_g->>'img') || '.svg') end;
    v_tipo := case when v_texto like '📎%' or v_url is not null then 'imagen' else 'texto' end;

    if (v_g->>'comp') is not null then
      -- el cliente envía el comprobante: se crea su orden y el comprobante queda pendiente de revisión
      v_pidx := (v_g->>'comp')::int; v_p := v_pagos->v_pidx;
      v_url := '/demo/' || (v_p->'comp'->>'img') || '.jpg';
      select i.contacto_id into v_contacto from elius.conversaciones c
      join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
      where c.tenant_id = v_tenant and c.id = v_conv;
      if v_p->>'entrega' = 'domicilio' then
        insert into elius.direcciones (tenant_id, contacto_id, etiqueta, direccion, ciudad, es_principal)
        values (v_tenant, v_contacto, 'Casa', 'Calle 45 # 12-30', 'Bogotá', true) returning id into v_dir;
      else v_dir := null; end if;
      insert into elius.ordenes (tenant_id, contacto_id, conversacion_id, canal_venta, tipo_entrega, direccion_entrega_id)
      values (v_tenant, v_contacto, v_conv, 'whatsapp', v_p->>'entrega', v_dir) returning id into v_orden;
      for v_it in select * from jsonb_array_elements(v_p->'items') loop
        insert into elius.orden_items (tenant_id, orden_id, item_id, cantidad)
        select v_tenant, v_orden, it.id, (v_it->>1)::numeric from elius.items_catalogo it
        where it.tenant_id = v_tenant and it.sku = (v_it->>0);
      end loop;
      update elius.ordenes set estado = 'esperando_pago' where tenant_id = v_tenant and id = v_orden;
      select saldo_pendiente into v_esperado from elius.v_saldo_ordenes where tenant_id = v_tenant and orden_id = v_orden;
      insert into elius.comprobantes_pago (tenant_id, orden_id, conversacion_id, monto_leido, monto_esperado, destinatario,
                                           app_origen, referencia, fecha_texto, hash_archivo, url_archivo, media_id)
      values (v_tenant, v_orden, v_conv, (v_p->'comp'->>'monto')::numeric, v_esperado, v_p->'comp'->>'destinatario',
              v_p->'comp'->>'app', v_p->'comp'->>'ref', v_p->'comp'->>'fecha', v_p->'comp'->>'hash', v_url, 'demo-' || v_pidx);
      v_tipo := 'imagen';
    end if;

    insert into elius.mensajes (tenant_id, conversacion_id, emisor, tipo_contenido, contenido, url_adjunto, estado_entrega, procesado)
    values (v_tenant, v_conv, v_g->>'emisor', v_tipo, v_texto, v_url,
            case when v_g->>'emisor' = 'cliente' then 'recibido' else 'entregado' end, true)
    returning id into v_mid;
    if v_g->>'emisor' = 'eli' then perform elius.efectos_demo(v_tenant, v_conv, v_mid, v_texto, v_d->'efectos', v_i); end if;
    v_i := v_i + 1;
    update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
    v_emisor := v_g->>'emisor';
  else
    update elius.parametros_negocio set valor = v_i::text where tenant_id = v_tenant and clave = 'demo_indice';
    v_emisor := null; v_conv := null;
  end if;

  v_est := elius.estado_demo(v_tenant, v_d);
  select count(distinct conversacion_id) into v_clientes from elius.mensajes where tenant_id = v_tenant and emisor = 'cliente';
  v_fin := v_i >= v_total and (v_est->>'esperando')::int = 0 and (v_est->>'post')::int = 0;
  return jsonb_build_object('terminado', v_fin, 'indice', v_i, 'total', v_total, 'emisor', v_emisor, 'conversacion_id', v_conv,
                            'clientes', v_clientes, 'esperando', (v_est->>'esperando')::int);
end $$;

-- Vuelve a empezar la demostración del negocio de prueba actual
create or replace function elius.reiniciar_demo()
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_vertical text;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  select vertical into v_vertical from platform.tenants where id = v_tenant and slug like 'demo-%';
  if v_vertical is null then raise exception 'Este negocio no es un caso de prueba'; end if;
  perform elius.sembrar_clientes_demo(v_tenant, v_vertical);
end $$;

revoke execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() from public, anon;
revoke execute on function elius.efectos_demo(uuid, uuid, uuid, text, jsonb, int), elius.sembrar_clientes_demo(uuid, text), elius.limpiar_caso_demo(uuid), elius.estado_demo(uuid, jsonb) from public, anon, authenticated;
grant execute on function platform.cargar_caso_demo(text), elius.siguiente_mensaje_demo(), elius.reiniciar_demo() to authenticated;
comment on function platform.cargar_caso_demo(text) is 'Crea el negocio de prueba de un caso (restaurante/veterinaria/aerolinea) con catálogo e imágenes';
comment on function elius.siguiente_mensaje_demo() is 'Entrega el siguiente mensaje del guion del caso de prueba; tras aprobar o rechazar un comprobante, Eli continúa esa conversación';
"""
base = os.path.join(os.path.dirname(__file__), '..', 'supabase')
open(os.path.join(base, 'migrations', '20261123001200_casos_demo.sql'), 'w').write(sql)
open(os.path.join(base, 'instalacion', '15_1200_casos_demo.sql'), 'w').write(sql)
print('SQL generado', len(sql))
