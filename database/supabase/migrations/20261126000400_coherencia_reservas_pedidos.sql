-- =============================================================================
-- 4300 · Coherencia entre reservas, pedidos, mesas y clientes
--   Lo que el Administrador cree, cancele o elimine deja todo consistente, y el Trabajador solo registra lo que corresponde al día:
--   · Llegada: solo el día de la reserva, y solo si está confirmada (con el pago aprobado). «No llegó»: solo cuando ya pasó la hora.
--   · Cancelar reserva (Administrador, con motivo): libera la mesa o recurso, cancela el pedido sin pago y avisa si hay pago aprobado.
--   · Eliminar reserva: libera la mesa y manda a la Papelera el pedido sin pago; restaurar vuelve a ocupar la mesa (si sigue libre).
--   · Un pedido ligado a una reserva activa no se elimina solo; un cliente con reservas o pedidos abiertos no se elimina.
--   · Con un comprobante por revisar o un pago aprobado no se cancela ni elimina nada hasta resolver el dinero.
-- =============================================================================

-- 1. El Trabajador registra la llegada y la no llegada con reglas
create or replace function elius.marcar_llegada(p_reserva uuid)
returns void language plpgsql set search_path = '' as $$
declare r record; v_tz text := coalesce((select zona_horaria from platform.tenants where id = app.current_tenant_id()), 'America/Bogota');
begin
  if app.mi_rol() is null or app.mi_rol() not in ('administrador', 'operador') then raise exception 'Solo el equipo del negocio registra llegadas' using errcode = '42501'; end if;
  select id, estado, inicio, llegada_en into r from elius.reservas where id = p_reserva and tenant_id = app.current_tenant_id();
  if not found then raise exception 'La reserva no existe o fue eliminada'; end if;
  if r.estado = 'pendiente_pago' then raise exception 'RN-C09: la reserva está pendiente de pago; se registra la llegada cuando el pago esté aprobado' using errcode = '23514'; end if;
  if r.estado = 'cancelada' then raise exception 'RN-C09: la reserva fue cancelada' using errcode = '23514'; end if;
  if r.estado <> 'confirmada' then raise exception 'RN-C09: la reserva ya está en estado %', r.estado using errcode = '23514'; end if;
  if (r.inicio at time zone v_tz)::date <> (now() at time zone v_tz)::date then
    raise exception 'RN-R07: la llegada solo se registra el día de la reserva' using errcode = '23514';
  end if;
  update elius.reservas set llegada_en = now(), estado = 'asistio', visto = true where id = p_reserva and tenant_id = app.current_tenant_id();
end $$;

create or replace function elius.marcar_no_llegada(p_reserva uuid)
returns void language plpgsql set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); r record;
begin
  if app.mi_rol() is null or app.mi_rol() not in ('administrador', 'operador') then raise exception 'Solo el equipo del negocio registra llegadas' using errcode = '42501'; end if;
  select id, estado, inicio into r from elius.reservas where id = p_reserva and tenant_id = v_tenant;
  if not found then raise exception 'La reserva no existe o fue eliminada'; end if;
  if r.estado <> 'confirmada' then raise exception 'RN-C09: solo una reserva confirmada puede marcarse como no llegó (estado actual: %)', r.estado using errcode = '23514'; end if;
  if r.inicio > now() then raise exception 'RN-R07: todavía no es la hora de la reserva' using errcode = '23514'; end if;
  update elius.reservas set estado = 'no_asistio', visto = true where id = p_reserva and tenant_id = v_tenant;
  update elius.asignaciones_recurso set estado = 'liberada' where tenant_id = v_tenant and reserva_id = p_reserva;
end $$;

-- 2. Dinero pendiente de una reserva: bloquea cancelar o eliminar hasta resolverlo
create or replace function app.dinero_de_reserva(p_reserva uuid)
returns text language plpgsql stable security definer set search_path = '' as $$
begin
  if exists (select 1 from elius.comprobantes_pago c join elius.ordenes o on o.id = c.orden_id
              where o.reserva_id = p_reserva and c.veredicto = 'pendiente') then return 'comprobante_pendiente'; end if;
  if exists (select 1 from elius.pagos p join elius.ordenes o on o.id = p.orden_id where o.reserva_id = p_reserva and p.estado = 'aprobado') then return 'pago_aprobado'; end if;
  return null;
end $$;
revoke execute on function app.dinero_de_reserva(uuid) from public, anon, authenticated;

-- 3. Cancelar una reserva (Administrador)
create or replace function elius.cancelar_reserva(p_id uuid, p_motivo text)
returns text language plpgsql security definer set search_path = '' as $$
declare t uuid := app.current_tenant_id(); r record; v_din text; v_msg text := 'Reserva cancelada.'; v_n int;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador cancela reservas' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_motivo, ''))) < 5 then raise exception 'Escribe el motivo de la cancelación (mínimo 5 caracteres)'; end if;
  select id, estado, codigo, notas into r from elius.reservas where id = p_id and tenant_id = t;
  if not found then raise exception 'La reserva no existe o fue eliminada'; end if;
  if r.estado not in ('pendiente_pago', 'confirmada') then raise exception 'RN-C09: una reserva % no se cancela', r.estado using errcode = '23514'; end if;
  v_din := app.dinero_de_reserva(p_id);
  if v_din = 'comprobante_pendiente' then raise exception 'Hay un comprobante por revisar de esta reserva: apruébalo o recházalo antes de cancelarla' using errcode = '23514'; end if;

  update elius.reservas set estado = 'cancelada', notas = btrim(coalesce(notas, '') || E'\nCancelada: ' || btrim(p_motivo)) where id = p_id and tenant_id = t;
  update elius.asignaciones_recurso set estado = 'liberada' where tenant_id = t and reserva_id = p_id;
  update elius.ordenes set estado = 'cancelada'
   where tenant_id = t and reserva_id = p_id and estado in ('cotizando', 'esperando_pago')
     and not exists (select 1 from elius.pagos p where p.orden_id = elius.ordenes.id and p.estado = 'aprobado');
  get diagnostics v_n = row_count;
  if v_n > 0 then v_msg := v_msg || ' Se canceló ' || v_n || ' pedido(s) sin pago y se liberó la mesa o recurso.'; else v_msg := v_msg || ' Se liberó la mesa o recurso.'; end if;
  if v_din = 'pago_aprobado' then
    update elius.reservas set notas = notas || E'\nTiene un pago aprobado: gestionar el reembolso al cliente' where id = p_id and tenant_id = t;
    v_msg := v_msg || ' Ojo: tiene un pago aprobado, queda anotado que falta el reembolso.';
  end if;
  return v_msg;
end $$;

-- 4. Eliminar y restaurar una reserva (reemplazan a las anteriores: ahora coherentes con mesas y pedidos)
create or replace function elius.eliminar_reserva(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare t uuid := app.current_tenant_id(); v_din text; v_ts timestamptz := now();
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador elimina reservas' using errcode = '42501'; end if;
  v_din := app.dinero_de_reserva(p_id);
  if v_din is not null then
    raise exception 'RN-C12: la reserva tiene dinero de por medio (%): una reserva con pago se cancela, no se elimina', replace(v_din, '_', ' ') using errcode = '23514';
  end if;
  update elius.reservas set eliminado_en = v_ts where id = p_id and tenant_id = t and eliminado_en is null;
  if not found then raise exception 'La reserva no existe o ya fue eliminada'; end if;
  update elius.asignaciones_recurso set estado = 'liberada' where tenant_id = t and reserva_id = p_id;
  update elius.ordenes set eliminado_en = v_ts where tenant_id = t and reserva_id = p_id and eliminado_en is null;
end $$;

create or replace function elius.restaurar_reserva(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare t uuid := app.current_tenant_id(); v_ts timestamptz;
begin
  if app.mi_rol() is distinct from 'administrador' and not coalesce(app.es_super_admin(), false) then raise exception 'Solo el Administrador restaura reservas' using errcode = '42501'; end if;
  select eliminado_en into v_ts from elius.reservas where id = p_id and tenant_id = t and eliminado_en is not null;
  if not found then raise exception 'La reserva no está en la Papelera'; end if;
  begin
    update elius.reservas set eliminado_en = null where id = p_id and tenant_id = t;
    update elius.asignaciones_recurso set estado = 'activa' where tenant_id = t and reserva_id = p_id and estado = 'liberada'
      and exists (select 1 from elius.reservas r where r.id = p_id and r.estado in ('pendiente_pago', 'confirmada'));
    update elius.ordenes set eliminado_en = null where tenant_id = t and reserva_id = p_id and eliminado_en = v_ts;
  exception when exclusion_violation then
    raise exception 'No se puede restaurar: la mesa o recurso ya fue tomada por otra reserva en ese horario' using errcode = '23P01';
  end;
end $$;

-- 5. Eliminar un pedido: no si está ligado a una reserva activa ni si tiene un comprobante por revisar
create or replace function elius.eliminar_pedido(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare t uuid := app.current_tenant_id(); v_res uuid; v_est text;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador elimina pedidos' using errcode = '42501'; end if;
  select reserva_id into v_res from elius.ordenes where id = p_id and tenant_id = t;
  if v_res is not null then
    select estado into v_est from elius.reservas where id = v_res and tenant_id = t;
    if v_est in ('pendiente_pago', 'confirmada') then
      raise exception 'RN-C09: este pedido pertenece a una reserva activa; cancela o elimina la reserva y el pedido se resuelve con ella' using errcode = '23514';
    end if;
  end if;
  if exists (select 1 from elius.comprobantes_pago where orden_id = p_id and tenant_id = t and veredicto = 'pendiente') then
    raise exception 'El pedido tiene un comprobante por revisar: apruébalo o recházalo antes de eliminarlo' using errcode = '23514';
  end if;
  update elius.ordenes set eliminado_en = now() where id = p_id and tenant_id = t and eliminado_en is null;
  if not found then raise exception 'El pedido no existe o ya fue eliminado'; end if;
end $$;

-- 6. Un cliente con reservas activas o pedidos abiertos no se elimina
create or replace function app.proteger_baja_cliente()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.eliminado_en is not null and old.eliminado_en is null then
    if exists (select 1 from elius.reservas r where r.tenant_id = old.tenant_id and r.contacto_id = old.id and r.eliminado_en is null and r.estado in ('pendiente_pago', 'confirmada')) then
      raise exception 'RN-C13: el cliente tiene reservas activas; cancélalas antes de eliminarlo' using errcode = '23514';
    end if;
    if exists (select 1 from elius.ordenes o where o.tenant_id = old.tenant_id and o.contacto_id = old.id and o.eliminado_en is null and o.estado not in ('entregada', 'cancelada')) then
      raise exception 'RN-C13: el cliente tiene pedidos abiertos; ciérralos o cancélalos antes de eliminarlo' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger t07_proteger_baja before update of eliminado_en on elius.contactos for each row execute function app.proteger_baja_cliente();
comment on trigger t07_proteger_baja on elius.contactos is 'RN-C13: un cliente con reservas activas o pedidos abiertos no se puede eliminar (desactivar)';

revoke execute on function elius.cancelar_reserva(uuid, text), elius.marcar_llegada(uuid), elius.marcar_no_llegada(uuid) from public, anon;
grant execute on function elius.cancelar_reserva(uuid, text), elius.marcar_llegada(uuid), elius.marcar_no_llegada(uuid) to authenticated;
comment on function elius.cancelar_reserva(uuid, text) is 'El Administrador cancela una reserva con motivo: libera la mesa, cancela el pedido sin pago y avisa si hay pago aprobado';
comment on function elius.marcar_llegada(uuid) is 'El equipo registra que el cliente llegó: solo el día de la reserva y si está confirmada';
comment on function elius.marcar_no_llegada(uuid) is 'El equipo registra que el cliente no llegó: solo cuando ya pasó la hora; libera la mesa o recurso';
