-- =============================================================================
-- ELIUS · Migración 0500 · Triggers
-- Cada trigger hace cumplir una regla de negocio (código RN-…) que no se puede
-- expresar con CHECK porque consulta otras filas o tablas.
-- Las funciones de trigger son SECURITY DEFINER solo cuando deben escribir en
-- tablas que el usuario no puede tocar (auditoría, eventos, contadores).
-- Los triggers de los plugins viven en el esquema del plugin: el modelo general
-- nunca depende de un plugin.
-- =============================================================================

-- =============================================================================
-- T01 · actualizado_en en todas las tablas que lo tienen
-- =============================================================================
do $$
declare r record;
begin
  for r in
    select c.table_schema, c.table_name from information_schema.columns c
    join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
    where c.column_name = 'actualizado_en'
      and c.table_schema in ('platform', 'elius', 'ext', 'plugin_vet', 'plugin_restaurant', 'plugin_airline')
  loop
    execute format('create trigger t01_actualizado_en before update on %I.%I for each row execute function app.set_actualizado_en()',
                   r.table_schema, r.table_name);
  end loop;
end $$;

-- =============================================================================
-- T02 · Auditoría (RN-P15, RNF-06, DT-12)
-- Guarda quién, con qué rol, desde dónde, qué tabla, qué fila, y el antes y el después.
-- =============================================================================
create or replace function app.auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_fila   jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_rol    text  := app.mi_rol();
  v_tenant uuid  := nullif(v_fila ->> 'tenant_id', '')::uuid;
begin
  insert into audit.registros_auditoria
    (tenant_id, usuario_id, rol, origen, esquema, tabla, registro_id, operacion, datos_anteriores, datos_nuevos)
  values (
    v_tenant, auth.uid(), coalesce(v_rol, 'sistema'),
    case when v_rol = 'eli' then 'eli' when v_rol = 'soporte' then 'soporte'
         when auth.uid() is null then 'sistema' else 'app' end,
    tg_table_schema, tg_table_name, (v_fila ->> 'id')::uuid, tg_op,
    case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
    case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return null;
end $$;

-- Se audita todo menos las tablas de alto volumen o técnicas
do $$
declare r record;
begin
  for r in
    select t.table_schema, t.table_name from information_schema.tables t
    where t.table_type = 'BASE TABLE'
      and t.table_schema in ('platform', 'elius', 'ext', 'plugin_vet', 'plugin_restaurant', 'plugin_airline')
      and (t.table_schema || '.' || t.table_name) not in (
        'elius.mensajes', 'elius.consumos_llm', 'elius.eventos_embudo', 'elius.eventos_salida',
        'elius.fragmentos_conocimiento', 'elius.notificaciones_pasarela', 'elius.suscripciones_push',
        'ext.mensajes_capturados', 'ext.evidencias_patron', 'platform.consumos_periodo')
  loop
    execute format('create trigger t02_auditoria after insert or update or delete on %I.%I for each row execute function app.auditar()',
                   r.table_schema, r.table_name);
  end loop;
end $$;

-- =============================================================================
-- T03 · Eventos de salida para n8n (DT-16): una tabla que n8n lee o un webhook de BD
-- =============================================================================
create or replace function app.emitir_evento(p_tenant uuid, p_tipo text, p_entidad text, p_id uuid, p_carga jsonb default '{}')
returns void language sql security definer set search_path = '' as $$
  insert into elius.eventos_salida (tenant_id, tipo_evento, entidad, entidad_id, carga)
  values (p_tenant, p_tipo, p_entidad, p_id, coalesce(p_carga, '{}'::jsonb));
$$;

create or replace function app.parametro(p_tenant uuid, p_clave text)
returns text language sql stable security definer set search_path = '' as $$
  select valor from elius.parametros_negocio where tenant_id = p_tenant and clave = p_clave;
$$;

-- =============================================================================
-- PLATFORM
-- =============================================================================
-- T10 · RN-P13: el rol de una membresía es de nivel tenant; el de plataforma, de nivel plataforma
create or replace function app.validar_nivel_rol()
returns trigger language plpgsql set search_path = '' as $$
declare v_nivel text;
begin
  select nivel into v_nivel from platform.roles where id = new.rol_id;
  if tg_table_name = 'membresias' and v_nivel <> 'tenant' then
    raise exception 'RN-P13: el rol de una membresía debe ser de nivel tenant' using errcode = '23514';
  elsif tg_table_name = 'asignaciones_plataforma' and v_nivel <> 'plataforma' then
    raise exception 'RN-P13: solo Super Admin y Soporte se asignan a nivel plataforma' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t10_nivel_rol before insert or update of rol_id on platform.membresias
  for each row execute function app.validar_nivel_rol();
create trigger t10_nivel_rol before insert or update of rol_id on platform.asignaciones_plataforma
  for each row execute function app.validar_nivel_rol();

-- T11 · RN-P04: el último Administrador activo no se elimina, no se desactiva ni cambia de rol
create or replace function app.proteger_ultimo_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_admin uuid;
begin
  select id into v_admin from platform.roles where codigo = 'administrador';
  if old.rol_id = v_admin and old.estado = 'activo'
     and (tg_op = 'DELETE' or new.rol_id <> v_admin or new.estado <> 'activo')
     and not exists (select 1 from platform.membresias m
                     where m.tenant_id = old.tenant_id and m.id <> old.id and m.rol_id = v_admin and m.estado = 'activo')
     and exists (select 1 from platform.tenants t where t.id = old.tenant_id) then
    raise exception 'RN-P04: el tenant debe conservar al menos un Administrador activo' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger t11_ultimo_admin before update or delete on platform.membresias
  for each row execute function app.proteger_ultimo_admin();

-- T12 · RN-P10: no superar los usuarios del plan
create or replace function app.validar_limite_usuarios()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_max int; v_actual int;
begin
  select p.max_usuarios into v_max from platform.tenants t join platform.planes p on p.id = t.plan_id where t.id = new.tenant_id;
  select count(*) into v_actual from platform.membresias where tenant_id = new.tenant_id and estado <> 'inactivo';
  if v_actual >= v_max then
    raise exception 'RN-P10: el plan permite máximo % usuarios', v_max using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t12_limite_usuarios before insert on platform.membresias
  for each row execute function app.validar_limite_usuarios();

-- =============================================================================
-- ELIUS · conversaciones (RN-C06, RN-C18, RN-C19, RN-C20)
-- =============================================================================
-- T20 · Antes de guardar un mensaje: Eli no habla si la conversación es de un humano
--       o si está apagada; un mensaje del cliente reabre una conversación cerrada.
create or replace function app.antes_de_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_estado text; v_agente_activo boolean;
begin
  select c.estado, coalesce(a.activo, false) into v_estado, v_agente_activo
  from elius.conversaciones c
  join elius.identidades_contacto i on i.tenant_id = c.tenant_id and i.id = c.identidad_id
  join elius.canales ca on ca.tenant_id = i.tenant_id and ca.id = i.canal_id
  left join elius.agentes a on a.tenant_id = ca.tenant_id and a.id = ca.agente_id
  where c.tenant_id = new.tenant_id and c.id = new.conversacion_id;

  if new.emisor = 'eli' and v_estado in ('humano', 'pausa') then
    raise exception 'RN-C19: la conversación la atiende una persona; Eli no responde' using errcode = '23514';
  end if;
  if new.emisor = 'eli' and not v_agente_activo then
    raise exception 'RN-C20: Eli está apagado para este negocio' using errcode = '23514';
  end if;
  if new.emisor = 'cliente' and v_estado = 'cerrada' then
    update elius.conversaciones set estado = 'en_progreso', cerrada_en = null
    where tenant_id = new.tenant_id and id = new.conversacion_id;
  end if;
  return new;
end $$;
create trigger t20_antes_de_mensaje before insert on elius.mensajes
  for each row execute function app.antes_de_mensaje();

create or replace function app.despues_de_mensaje()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update elius.conversaciones set ultimo_mensaje_en = new.enviado_en
  where tenant_id = new.tenant_id and id = new.conversacion_id and ultimo_mensaje_en < new.enviado_en;
  update elius.identidades_contacto i set ultimo_contacto_en = new.enviado_en
  from elius.conversaciones c
  where c.tenant_id = new.tenant_id and c.id = new.conversacion_id and i.tenant_id = c.tenant_id and i.id = c.identidad_id
    and new.emisor = 'cliente';
  return null;
end $$;
create trigger t21_despues_de_mensaje after insert on elius.mensajes
  for each row execute function app.despues_de_mensaje();

-- T22 · RN-C18: los escalamientos se reparten por turnos entre los Operadores activos
--       (al que tenga menos casos abiertos; empate: al que hace más tiempo no recibe uno)
create or replace function app.asignar_escalamiento()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.asignado_a is null then
    select m.id into new.asignado_a
    from platform.membresias m
    join platform.roles r on r.id = m.rol_id and r.codigo = 'operador'
    where m.tenant_id = new.tenant_id and m.estado = 'activo'
    order by (select count(*) from elius.escalamientos e
              where e.tenant_id = m.tenant_id and e.asignado_a = m.id and e.resuelto_en is null),
             (select max(e.creado_en) from elius.escalamientos e
              where e.tenant_id = m.tenant_id and e.asignado_a = m.id) nulls first,
             m.fecha_ingreso
    limit 1;
  end if;
  return new;
end $$;
create trigger t22_asignar_escalamiento before insert on elius.escalamientos
  for each row execute function app.asignar_escalamiento();

-- T23 · RN-C19: al escalar, la conversación pasa a humano; al resolver el último, queda libre
create or replace function app.despues_de_escalamiento()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    update elius.conversaciones set estado = 'humano', asignado_a = new.asignado_a
    where tenant_id = new.tenant_id and id = new.conversacion_id;
    perform app.emitir_evento(new.tenant_id, 'escalamiento.creado', 'escalamientos', new.id,
                              jsonb_build_object('motivo', new.motivo, 'asignado_a', new.asignado_a));
  elsif new.resuelto_en is not null and old.resuelto_en is null
        and not exists (select 1 from elius.escalamientos e
                        where e.tenant_id = new.tenant_id and e.conversacion_id = new.conversacion_id
                          and e.resuelto_en is null and e.id <> new.id) then
    update elius.conversaciones set asignado_a = null
    where tenant_id = new.tenant_id and id = new.conversacion_id;
  end if;
  return null;
end $$;
create trigger t23_despues_de_escalamiento after insert or update of resuelto_en on elius.escalamientos
  for each row execute function app.despues_de_escalamiento();

-- =============================================================================
-- ELIUS · reservas (RN-C08, RN-C09, RN-R08, RN-R10)
-- =============================================================================
-- T30 · Código visible de la reserva (localizador) único por tenant
create or replace function app.codigo_reserva()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.codigo is null then
    loop
      new.codigo := app.codigo_aleatorio(6);
      exit when not exists (select 1 from elius.reservas where tenant_id = new.tenant_id and codigo = new.codigo);
    end loop;
  end if;
  return new;
end $$;
create trigger t30_codigo_reserva before insert on elius.reservas
  for each row execute function app.codigo_reserva();

-- T31 · RN-C08 y RN-R10: no reservar en el pasado ni más allá de la anticipación máxima
create or replace function app.validar_fecha_reserva()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_dias int := coalesce(app.parametro(new.tenant_id, 'dias_anticipacion_max')::int, 365);
begin
  if new.inicio < now() - interval '5 minutes' then
    raise exception 'RN-C08: no se puede reservar en el pasado' using errcode = '23514';
  end if;
  if new.inicio > now() + make_interval(days => v_dias) then
    raise exception 'RN-R10: solo se reserva con máximo % días de anticipación', v_dias using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t31_fecha_reserva before insert or update of inicio on elius.reservas
  for each row execute function app.validar_fecha_reserva();

-- T32 · RN-C09: solo transiciones de estado válidas
create or replace function app.validar_transicion_reserva()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.estado is distinct from old.estado and not (
       (old.estado = 'pendiente_pago' and new.estado in ('confirmada', 'cancelada'))
    or (old.estado = 'confirmada'     and new.estado in ('asistio', 'no_asistio', 'cancelada'))) then
    raise exception 'RN-C09: una reserva no puede pasar de % a %', old.estado, new.estado using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t32_transicion_reserva before update of estado on elius.reservas
  for each row execute function app.validar_transicion_reserva();

-- T33 · Eventos de reservas para n8n (aviso al equipo, calendario) y RN-R08 grupo grande
create or replace function app.eventos_reserva()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_umbral int := app.parametro(new.tenant_id, 'umbral_grupo_grande')::int;
begin
  if tg_op = 'INSERT' then
    perform app.emitir_evento(new.tenant_id, 'reserva.creada', 'reservas', new.id,
                              jsonb_build_object('codigo', new.codigo, 'inicio', new.inicio, 'personas', new.personas));
    if v_umbral is not null and new.personas >= v_umbral then
      perform app.emitir_evento(new.tenant_id, 'reserva.grupo_grande', 'reservas', new.id,
                                jsonb_build_object('personas', new.personas, 'umbral', v_umbral));
    end if;
  elsif new.estado is distinct from old.estado then
    perform app.emitir_evento(new.tenant_id, 'reserva.' || new.estado, 'reservas', new.id,
                              jsonb_build_object('codigo', new.codigo));
  end if;
  return null;
end $$;
create trigger t33_eventos_reserva after insert or update of estado on elius.reservas
  for each row execute function app.eventos_reserva();

-- =============================================================================
-- ELIUS · órdenes (RN-C10, RN-C11, RN-C12, RN-R03)
-- =============================================================================
-- T40 · RN-C10: consecutivo de orden por tenant (bloqueo por tenant para evitar repetidos)
create or replace function app.numero_orden()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.numero is null then
    perform pg_advisory_xact_lock(hashtext('ordenes:' || new.tenant_id::text));
    select coalesce(max(numero), 0) + 1 into new.numero from elius.ordenes where tenant_id = new.tenant_id;
  end if;
  return new;
end $$;
create trigger t40_numero_orden before insert on elius.ordenes
  for each row execute function app.numero_orden();

-- T41 · Línea de orden: precio desde el catálogo, total de línea, ítem disponible y orden abierta
create or replace function app.antes_de_linea()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_estado text; v_disponible boolean; v_precio numeric;
begin
  select estado into v_estado from elius.ordenes
  where tenant_id = coalesce(new.tenant_id, old.tenant_id) and id = coalesce(new.orden_id, old.orden_id);
  if v_estado not in ('cotizando', 'esperando_pago') then
    raise exception 'RN-C12: la orden ya está % y no se puede modificar', v_estado using errcode = '23514';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  select disponible, precio into v_disponible, v_precio from elius.items_catalogo
  where tenant_id = new.tenant_id and id = new.item_id and eliminado_en is null;
  if not coalesce(v_disponible, false) then
    raise exception 'RN-R03: el ítem está agotado o no existe' using errcode = '23514';
  end if;
  new.precio_unitario := coalesce(new.precio_unitario, v_precio);
  new.total_linea := round(new.cantidad * new.precio_unitario + new.recargos - new.descuento, 2);
  if new.total_linea < 0 then
    raise exception 'El descuento no puede superar el valor de la línea' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger t41_antes_de_linea before insert or update or delete on elius.orden_items
  for each row execute function app.antes_de_linea();

-- T42 · RN-C11: el total de la orden siempre se calcula desde sus líneas
create or replace function app.recalcular_orden(p_tenant uuid, p_orden uuid)
returns void language sql security definer set search_path = '' as $$
  update elius.ordenes o set
    subtotal  = coalesce(l.subtotal, 0),
    impuestos = coalesce(l.impuestos, 0),
    total     = greatest(coalesce(l.subtotal, 0) - o.descuento + coalesce(l.impuestos, 0), 0)
  from (select sum(oi.total_linea) as subtotal,
               round(sum(oi.total_linea * ic.impuesto_pct / 100), 2) as impuestos
        from elius.orden_items oi
        join elius.items_catalogo ic on ic.tenant_id = oi.tenant_id and ic.id = oi.item_id
        where oi.tenant_id = p_tenant and oi.orden_id = p_orden) l
  where o.tenant_id = p_tenant and o.id = p_orden;
$$;

create or replace function app.despues_de_linea()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app.recalcular_orden(coalesce(new.tenant_id, old.tenant_id), coalesce(new.orden_id, old.orden_id));
  return null;
end $$;
create trigger t42_recalcular_orden after insert or update or delete on elius.orden_items
  for each row execute function app.despues_de_linea();

-- T43 · RN-C11: los montos de la orden no se escriben a mano
create or replace function app.proteger_totales_orden()
returns trigger language plpgsql set search_path = '' as $$
begin
  if pg_trigger_depth() = 1 and (new.subtotal, new.impuestos, new.total) is distinct from (old.subtotal, old.impuestos, old.total) then
    raise exception 'RN-C11: los totales se calculan desde las líneas de la orden' using errcode = '23514';
  end if;
  if new.descuento is distinct from old.descuento then
    new.total := greatest(new.subtotal - new.descuento + new.impuestos, 0);
  end if;
  return new;
end $$;
create trigger t43_proteger_totales before update on elius.ordenes
  for each row execute function app.proteger_totales_orden();

-- T44 · Evento cuando una orden cambia de estado (cocina, domiciliario, cliente)
create or replace function app.eventos_orden()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado is distinct from old.estado then
    perform app.emitir_evento(new.tenant_id, 'orden.' || new.estado, 'ordenes', new.id,
                              jsonb_build_object('numero', new.numero, 'total', new.total, 'tipo_entrega', new.tipo_entrega));
  end if;
  return null;
end $$;
create trigger t44_eventos_orden after update of estado on elius.ordenes
  for each row execute function app.eventos_orden();

-- =============================================================================
-- ELIUS · pagos, comprobantes y Factus Pay (RN-C12, RN-C16, RN-C17, RN-C22)
-- =============================================================================
-- T50 · RN-C12: un pago aprobado no se modifica ni se borra; se reversa con otro pago negativo
create or replace function app.proteger_pago()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.estado = 'aprobado' then
    raise exception 'RN-C12: un pago aprobado no se modifica; registre un reverso' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger t50_proteger_pago before update or delete on elius.pagos
  for each row execute function app.proteger_pago();

-- T51 · RN-C17: cuando lo pagado cubre el total, la orden (y su reserva) quedan confirmadas
create or replace function app.aplicar_pago()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_total numeric; v_pagado numeric; v_estado text; v_reserva uuid; v_contra numeric;
begin
  if new.estado <> 'aprobado' then
    return null;
  end if;
  select total, estado, reserva_id into v_total, v_estado, v_reserva
  from elius.ordenes where tenant_id = new.tenant_id and id = new.orden_id for update;
  select coalesce(sum(monto), 0) into v_pagado from elius.pagos
  where tenant_id = new.tenant_id and orden_id = new.orden_id and estado = 'aprobado';
  select coalesce(sum(cobro_contra_entrega), 0) into v_contra from elius.entregas
  where tenant_id = new.tenant_id and orden_id = new.orden_id and estado <> 'fallida';

  if v_estado in ('cotizando', 'esperando_pago') and v_pagado + v_contra >= v_total and v_total > 0 then
    update elius.ordenes set estado = 'confirmada' where tenant_id = new.tenant_id and id = new.orden_id;
    if v_reserva is not null then
      update elius.reservas set estado = 'confirmada'
      where tenant_id = new.tenant_id and id = v_reserva and estado = 'pendiente_pago';
    end if;
  elsif v_estado = 'cotizando' then
    update elius.ordenes set estado = 'esperando_pago' where tenant_id = new.tenant_id and id = new.orden_id;
  end if;
  return null;
end $$;
create trigger t51_aplicar_pago after insert or update of estado on elius.pagos
  for each row execute function app.aplicar_pago();

-- T52 · RN-C16: alertas del comprobante (repetido, monto distinto, destinatario raro)
create or replace function app.revisar_comprobante()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_alertas text[] := '{}';
  v_cuentas text := app.parametro(new.tenant_id, 'cuentas_pago');
begin
  if exists (select 1 from elius.comprobantes_pago c
             where c.tenant_id = new.tenant_id and c.id <> new.id
               and ((new.hash_archivo is not null and c.hash_archivo = new.hash_archivo)
                 or (new.referencia is not null and c.app_origen is not distinct from new.app_origen and c.referencia = new.referencia))) then
    v_alertas := array_append(v_alertas, 'comprobante repetido');
  end if;
  if new.monto_leido is not null and new.monto_esperado is not null then
    new.coincide := new.monto_leido = new.monto_esperado;
    if not new.coincide then
      v_alertas := array_append(v_alertas, format('monto %s distinto al esperado %s', new.monto_leido, new.monto_esperado));
    end if;
  end if;
  if v_cuentas is not null and new.destinatario is not null
     and position(lower(new.destinatario) in lower(v_cuentas)) = 0 then
    v_alertas := array_append(v_alertas, 'destinatario distinto a las cuentas del negocio');
  end if;
  if array_length(v_alertas, 1) > 0 then
    new.motivo := 'ALERTA: ' || array_to_string(v_alertas, '; ');
  end if;
  return new;
end $$;
create trigger t52_revisar_comprobante before insert on elius.comprobantes_pago
  for each row execute function app.revisar_comprobante();

create or replace function app.evento_comprobante()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform app.emitir_evento(new.tenant_id, 'comprobante.recibido', 'comprobantes_pago', new.id,
                            jsonb_build_object('monto', new.monto_leido, 'alerta', new.motivo));
  return null;
end $$;
create trigger t53_evento_comprobante after insert on elius.comprobantes_pago
  for each row execute function app.evento_comprobante();

-- T54 · RN-C22: un recaudo de Factus pagado crea su pago aprobado (una sola vez)
create or replace function app.recaudo_pagado()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado = 'pagado' and old.estado is distinct from 'pagado'
     and not exists (select 1 from elius.pagos p where p.tenant_id = new.tenant_id and p.recaudo_id = new.id) then
    insert into elius.pagos (tenant_id, orden_id, recaudo_id, metodo, proveedor, referencia_externa, monto, estado, pagado_en)
    values (new.tenant_id, new.orden_id, new.id, 'breb_factus', 'factus_pay', new.codigo_referencia,
            new.monto, 'aprobado', new.cobrado_en);
  end if;
  return null;
end $$;
create trigger t54_recaudo_pagado after update of estado on elius.recaudos
  for each row execute function app.recaudo_pagado();

-- =============================================================================
-- PLUGIN VETERINARIA (RN-V04, RN-V06)
-- =============================================================================
create or replace function plugin_vet.no_atender_fallecida()
returns trigger language plpgsql set search_path = '' as $$
begin
  if exists (select 1 from plugin_vet.mascotas m
             where m.tenant_id = new.tenant_id and m.id = new.mascota_id and m.fallecida_en is not null) then
    raise exception 'RN-V06: la mascota está registrada como fallecida' using errcode = '23514';
  end if;
  return new;
end $$;
create trigger tv1_no_atender_fallecida before insert on plugin_vet.atenciones
  for each row execute function plugin_vet.no_atender_fallecida();

create or replace function plugin_vet.historia_inmutable()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.registrado_en < now() - interval '24 hours' then
    raise exception 'RN-V04: la historia clínica no se edita después de 24 horas; agregue una corrección' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger tv2_historia_inmutable before update or delete on plugin_vet.registros_clinicos
  for each row execute function plugin_vet.historia_inmutable();

-- =============================================================================
-- PLUGIN RESTAURANTE (RN-R04 recargos de opciones)
-- =============================================================================
-- Las opciones elegidas suman su recargo a la línea del núcleo (orden_items.recargos)
create or replace function plugin_restaurant.sumar_recargos()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_linea uuid := coalesce(new.orden_item_id, old.orden_item_id);
        v_tenant uuid := coalesce(new.tenant_id, old.tenant_id);
begin
  update elius.orden_items oi set recargos = coalesce((
    select sum(o.cantidad * o.precio_aplicado) from plugin_restaurant.orden_item_opciones o
    where o.tenant_id = v_tenant and o.orden_item_id = v_linea), 0)
  where oi.tenant_id = v_tenant and oi.id = v_linea;
  return null;
end $$;
create trigger tr1_sumar_recargos after insert or update or delete on plugin_restaurant.orden_item_opciones
  for each row execute function plugin_restaurant.sumar_recargos();

create or replace function plugin_restaurant.precio_opcion()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.precio_aplicado = 0 then
    select precio_adicional into new.precio_aplicado from plugin_restaurant.opciones_modificador
    where tenant_id = new.tenant_id and id = new.opcion_id;
  end if;
  return new;
end $$;
create trigger tr0_precio_opcion before insert on plugin_restaurant.orden_item_opciones
  for each row execute function plugin_restaurant.precio_opcion();

-- =============================================================================
-- PLUGIN AEROLÍNEA (RN-A04, RN-A06, RN-A07, RN-A09)
-- =============================================================================
-- RN-A04: los cupos de las tarifas de un vuelo no superan la capacidad de la aeronave
create or replace function plugin_airline.validar_capacidad()
returns trigger language plpgsql set search_path = '' as $$
declare v_cap int; v_cupos int;
begin
  select a.capacidad into v_cap from plugin_airline.vuelos v
  join plugin_airline.aeronaves a on a.tenant_id = v.tenant_id and a.id = v.aeronave_id
  where v.tenant_id = new.tenant_id and v.id = new.vuelo_id;
  select coalesce(sum(cupos_totales), 0) into v_cupos from plugin_airline.tarifas_vuelo
  where tenant_id = new.tenant_id and vuelo_id = new.vuelo_id and id <> new.id;
  if v_cupos + new.cupos_totales > v_cap then
    raise exception 'RN-A04: los cupos (%) superan la capacidad de la aeronave (%)', v_cupos + new.cupos_totales, v_cap
      using errcode = '23514';
  end if;
  return new;
end $$;
create trigger ta1_capacidad before insert or update of cupos_totales on plugin_airline.tarifas_vuelo
  for each row execute function plugin_airline.validar_capacidad();

-- RN-A04: cada tramo reservado ocupa un cupo por pasajero de la reserva
create or replace function plugin_airline.ocupar_cupo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_pax int;
begin
  select greatest(count(*) filter (where tipo_pasajero <> 'INF'), 1) into v_pax
  from plugin_airline.reserva_pasajeros where tenant_id = new.tenant_id and reserva_id = new.reserva_id;
  update plugin_airline.tarifas_vuelo set cupos_vendidos = cupos_vendidos + v_pax
  where tenant_id = new.tenant_id and id = new.tarifa_vuelo_id;   -- el CHECK de cupos impide sobreventa
  return new;
end $$;
create trigger ta2_ocupar_cupo before insert on plugin_airline.tramos_reserva
  for each row execute function plugin_airline.ocupar_cupo();

-- RN-A06: en cada reserva los infantes no superan a los adultos (se revisa al final de la transacción)
create or replace function plugin_airline.validar_infantes()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select count(*) filter (where tipo_pasajero = 'INF') > count(*) filter (where tipo_pasajero = 'ADT')
      from plugin_airline.reserva_pasajeros where tenant_id = new.tenant_id and reserva_id = new.reserva_id) then
    raise exception 'RN-A06: cada infante debe viajar con un adulto' using errcode = '23514';
  end if;
  return null;
end $$;
create constraint trigger ta3_infantes after insert or update on plugin_airline.reserva_pasajeros
  deferrable initially deferred for each row execute function plugin_airline.validar_infantes();

-- RN-A07: una silla no se asigna a dos pasajeros del mismo vuelo
create or replace function plugin_airline.validar_silla()
returns trigger language plpgsql set search_path = '' as $$
declare v_vuelo uuid;
begin
  if new.silla is null then
    return new;
  end if;
  select tv.vuelo_id into v_vuelo from plugin_airline.tramos_reserva tr
  join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
  where tr.tenant_id = new.tenant_id and tr.id = new.tramo_id;
  if exists (select 1 from plugin_airline.tiquetes t
             join plugin_airline.tramos_reserva tr on tr.tenant_id = t.tenant_id and tr.id = t.tramo_id
             join plugin_airline.tarifas_vuelo tv on tv.tenant_id = tr.tenant_id and tv.id = tr.tarifa_vuelo_id
             where t.tenant_id = new.tenant_id and tv.vuelo_id = v_vuelo and t.silla = new.silla
               and t.id <> new.id and t.estado <> 'anulado') then
    raise exception 'RN-A07: la silla % ya está asignada en este vuelo', new.silla using errcode = '23505';
  end if;
  return new;
end $$;
create trigger ta4_silla before insert or update of silla on plugin_airline.tiquetes
  for each row execute function plugin_airline.validar_silla();

-- RN-A09: si un vuelo se cancela o se retrasa se avisa a sus pasajeros (evento para n8n)
create or replace function plugin_airline.evento_vuelo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.estado in ('cancelado', 'retrasado') and new.estado is distinct from old.estado then
    perform app.emitir_evento(new.tenant_id, 'vuelo.' || new.estado, 'vuelos', new.id,
                              jsonb_build_object('numero_vuelo', new.numero_vuelo, 'salida', new.salida_programada));
  end if;
  return null;
end $$;
create trigger ta5_evento_vuelo after update of estado on plugin_airline.vuelos
  for each row execute function plugin_airline.evento_vuelo();
