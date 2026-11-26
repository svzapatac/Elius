-- =============================================================================
-- 4200 · El Administrador crea pedidos y reservas a mano y los elimina (baja lógica → Papelera)
--   · ordenes y reservas ganan eliminado_en. Una política RESTRICTIVA de lectura oculta lo eliminado en todas las vistas y listas, sin tocarlas.
--   · Se elimina y se restaura con procedimientos (solo Administrador); el borrado real solo lo hace el CIS adm desde la Papelera.
--   · Un pedido con pagos aprobados NO se elimina (RN-C12: el dinero no se borra; se corrige con un reverso). Una reserva atendida tampoco.
--   · Crear: crear_pedido_manual (con sus líneas, los totales los calcula la base) y agendar_reserva (ya existente).
-- =============================================================================
alter table elius.ordenes add column eliminado_en timestamptz;
alter table elius.reservas add column eliminado_en timestamptz;
comment on column elius.ordenes.eliminado_en is 'Baja lógica: si tiene fecha, el pedido está en la Papelera';
comment on column elius.reservas.eliminado_en is 'Baja lógica: si tiene fecha, la reserva está en la Papelera';

create policy sin_eliminados on elius.ordenes as restrictive for select using (eliminado_en is null);
create policy sin_eliminados on elius.reservas as restrictive for select using (eliminado_en is null);


-- Qué no se puede eliminar
create or replace function app.proteger_baja_pedido_reserva()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.eliminado_en is not null and old.eliminado_en is null then
    if tg_table_name = 'ordenes' and exists (select 1 from elius.pagos p where p.orden_id = old.id and p.estado = 'aprobado') then
      raise exception 'RN-C12: un pedido con pagos aprobados no se elimina; registra un reverso del pago' using errcode = '23514';
    end if;
    if tg_table_name = 'reservas' and old.estado in ('asistio') then
      raise exception 'RN-C09: una reserva ya atendida no se elimina; es parte del historial' using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger t07_proteger_baja before update of eliminado_en on elius.ordenes for each row execute function app.proteger_baja_pedido_reserva();
create trigger t07_proteger_baja before update of eliminado_en on elius.reservas for each row execute function app.proteger_baja_pedido_reserva();
comment on trigger t07_proteger_baja on elius.ordenes is 'RN-C12: un pedido con pagos aprobados no se puede eliminar (desactivar); el dinero no se borra, se corrige con un reverso';
comment on trigger t07_proteger_baja on elius.reservas is 'RN-C09: una reserva ya atendida no se puede eliminar; queda como historial';

-- Procedimientos de baja y restauración (solo Administrador)
create or replace function elius.eliminar_pedido(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador elimina pedidos' using errcode = '42501'; end if;
  update elius.ordenes set eliminado_en = now() where id = p_id and tenant_id = app.current_tenant_id() and eliminado_en is null;
  if not found then raise exception 'El pedido no existe o ya fue eliminado'; end if;
end $$;
create or replace function elius.restaurar_pedido(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if app.mi_rol() is distinct from 'administrador' and not coalesce(app.es_super_admin(), false) then raise exception 'Solo el Administrador restaura pedidos' using errcode = '42501'; end if;
  update elius.ordenes set eliminado_en = null where id = p_id and tenant_id = app.current_tenant_id() and eliminado_en is not null;
  if not found then raise exception 'El pedido no está en la Papelera'; end if;
end $$;
create or replace function elius.eliminar_reserva(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador elimina reservas' using errcode = '42501'; end if;
  update elius.reservas set eliminado_en = now() where id = p_id and tenant_id = app.current_tenant_id() and eliminado_en is null;
  if not found then raise exception 'La reserva no existe o ya fue eliminada'; end if;
end $$;
create or replace function elius.restaurar_reserva(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
begin
  if app.mi_rol() is distinct from 'administrador' and not coalesce(app.es_super_admin(), false) then raise exception 'Solo el Administrador restaura reservas' using errcode = '42501'; end if;
  update elius.reservas set eliminado_en = null where id = p_id and tenant_id = app.current_tenant_id() and eliminado_en is not null;
  if not found then raise exception 'La reserva no está en la Papelera'; end if;
end $$;

-- Pedido manual: el Administrador lo arma desde el panel. Los precios y el total los pone la base de datos (t41, t42).
create or replace function elius.crear_pedido_manual(p_contacto uuid, p_tipo_entrega text, p_items jsonb)
returns uuid language plpgsql set search_path = '' as $$
declare v_orden uuid; v_it jsonb;
begin
  if app.mi_rol() is distinct from 'administrador' then raise exception 'Solo el Administrador crea pedidos a mano' using errcode = '42501'; end if;
  if p_contacto is null then raise exception 'Elige el cliente'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Agrega al menos un producto al pedido'; end if;
  v_orden := elius.crear_orden(p_contacto, 'presencial', coalesce(nullif(p_tipo_entrega, ''), 'recoger'));
  for v_it in select * from jsonb_array_elements(p_items) loop
    perform elius.agregar_item(v_orden, (v_it ->> 'item_id')::uuid, coalesce((v_it ->> 'cantidad')::numeric, 1), nullif(v_it ->> 'notas', ''));
  end loop;
  return v_orden;
end $$;

-- Papelera con pedidos y reservas (vista con rol comprobado dentro: la política de lectura oculta lo eliminado a las demás vistas)
drop view if exists elius.v_papelera;
create view elius.v_papelera as
select 'producto'::text as tipo, i.id, i.nombre::text as nombre, coalesce(i.sku, '')::text as detalle, i.eliminado_en
from elius.items_catalogo i
where i.eliminado_en is not null and i.tenant_id = app.current_tenant_id() and (app.mi_rol() = 'administrador' or app.es_super_admin())
union all
select 'cliente', c.id, btrim(c.nombres || ' ' || coalesce(c.apellidos, '')), coalesce(c.telefono, c.email, ''), c.eliminado_en
from elius.contactos c
where c.eliminado_en is not null and c.tenant_id = app.current_tenant_id() and (app.mi_rol() = 'administrador' or app.es_super_admin())
union all
select 'pedido', o.id, 'Pedido #' || o.numero, 'Total ' || o.total::text || ' · ' || coalesce((select btrim(c.nombres || ' ' || coalesce(c.apellidos, '')) from elius.contactos c where c.id = o.contacto_id), 'sin cliente'), o.eliminado_en
from elius.ordenes o
where o.eliminado_en is not null and o.tenant_id = app.current_tenant_id() and (app.mi_rol() = 'administrador' or app.es_super_admin())
union all
select 'reserva', r.id, 'Reserva ' || r.codigo, to_char(r.inicio at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI') || ' · ' || r.personas::text || ' pers. · ' || coalesce((select btrim(c.nombres || ' ' || coalesce(c.apellidos, '')) from elius.contactos c where c.id = r.contacto_id), 'sin cliente'), r.eliminado_en
from elius.reservas r
where r.eliminado_en is not null and r.tenant_id = app.current_tenant_id() and (app.mi_rol() = 'administrador' or app.es_super_admin());
grant select on elius.v_papelera to authenticated, service_role, elius_app;
comment on view elius.v_papelera is 'Productos, clientes, pedidos y reservas eliminados (desactivados) del negocio; el Administrador los restaura, el CIS adm los borra de verdad';

-- Borrado real (CIS adm): ahora también pedidos y reservas que ya estén en la Papelera
create or replace function elius.eliminar_definitivo(p_tipo text, p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_n int; t uuid := app.current_tenant_id();
begin
  if not coalesce((select app.es_super_admin()), false) then
    raise exception 'Solo el CIS adm elimina definitivamente' using errcode = '42501';
  end if;
  if p_tipo = 'producto' then
    delete from elius.items_catalogo where id = p_id and tenant_id = t and eliminado_en is not null;
  elsif p_tipo = 'cliente' then
    delete from elius.contactos where id = p_id and tenant_id = t and eliminado_en is not null;
  elsif p_tipo = 'pedido' then
    if exists (select 1 from elius.ordenes where id = p_id and tenant_id = t and eliminado_en is not null) then
      delete from elius.comprobantes_pago where orden_id = p_id and tenant_id = t;
      delete from elius.orden_items where orden_id = p_id and tenant_id = t;
    end if;
    delete from elius.ordenes where id = p_id and tenant_id = t and eliminado_en is not null;
  elsif p_tipo = 'reserva' then
    if exists (select 1 from elius.reservas where id = p_id and tenant_id = t and eliminado_en is not null) then
      delete from elius.asignaciones_recurso where reserva_id = p_id and tenant_id = t;
    end if;
    delete from elius.reservas where id = p_id and tenant_id = t and eliminado_en is not null;
  else
    raise exception 'Tipo no válido: usa producto, cliente, pedido o reserva';
  end if;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'No está en la Papelera (primero se elimina, luego se borra definitivamente)'; end if;
  return 'eliminado definitivamente';
exception when foreign_key_violation then
  raise exception 'No se puede borrar de verdad: tiene historial relacionado. Se queda desactivado.' using errcode = '23503';
end $$;

revoke all on function elius.eliminar_pedido(uuid), elius.restaurar_pedido(uuid), elius.eliminar_reserva(uuid), elius.restaurar_reserva(uuid),
  elius.crear_pedido_manual(uuid, text, jsonb) from public, anon;
grant execute on function elius.eliminar_pedido(uuid), elius.restaurar_pedido(uuid), elius.eliminar_reserva(uuid), elius.restaurar_reserva(uuid),
  elius.crear_pedido_manual(uuid, text, jsonb) to authenticated;
comment on function elius.eliminar_pedido(uuid) is 'Elimina (desactiva) un pedido: va a la Papelera. Solo Administrador; no aplica si tiene pagos aprobados';
comment on function elius.eliminar_reserva(uuid) is 'Elimina (desactiva) una reserva: va a la Papelera. Solo Administrador';
comment on function elius.crear_pedido_manual(uuid, text, jsonb) is 'El Administrador crea un pedido a mano con sus líneas; precios y total los calcula la base de datos';

-- Descripción de los triggers nuevos
do $$
declare r record; v_desc text;
begin
  for r in select c.relname, t.tgname from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'elius' and c.relname in ('ordenes', 'reservas') and not t.tgisinternal and obj_description(t.oid, 'pg_trigger') is null loop
    select obj_description(t2.oid, 'pg_trigger') into v_desc from pg_trigger t2 join pg_class c2 on c2.oid = t2.tgrelid join pg_namespace n2 on n2.oid = c2.relnamespace
     where n2.nspname = 'elius' and c2.relname = 'contactos' and t2.tgname = r.tgname and not t2.tgisinternal;
    if v_desc is not null then execute format('comment on trigger %I on elius.%I is %L', r.tgname, r.relname, v_desc); end if;
  end loop;
end $$;
