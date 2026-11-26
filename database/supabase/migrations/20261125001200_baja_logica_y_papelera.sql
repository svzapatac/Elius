-- 3800 · "Eliminar" es DESACTIVAR. Borrar de verdad solo lo hace el CIS adm.
--  · El Administrador puede eliminar productos y clientes desde el panel: la fila queda marcada (eliminado_en), sale de las listas
--    y se puede restaurar desde la Papelera. No se pierde el historial (órdenes, reservas, auditoría).
--  · Un DELETE real sobre cualquier tabla del negocio, hecho desde el panel o desde una conexión directa, solo lo permite el CIS adm.
--  · Operador y Soporte no pueden dar de baja ni restaurar.
create or replace function app.bloquear_baja_directa()
returns trigger language plpgsql set search_path = '' as $$
declare
  v_login boolean := current_user in ('elius_administrador', 'elius_trabajador', 'elius_soporte');   -- conexión directa
  v_panel boolean := current_user in ('authenticated', 'anon') or v_login;                           -- panel (API) o conexión directa
  v_cis   boolean := session_user = 'elius_superadmin' or coalesce((select app.es_super_admin()), false);
  v_rol   text    := (select app.mi_rol());
begin
  if tg_op = 'TRUNCATE' then
    if v_panel then raise exception 'TRUNCATE no está permitido: vaciaría la tabla completa (%).', tg_table_name using errcode = '42501'; end if;
    return null;
  end if;

  if tg_op = 'DELETE' then
    if v_panel and not v_cis and tg_table_name <> 'medios_item' then   -- medios_item: galería de fotos de un producto, sin historial
      raise exception 'Solo el CIS adm elimina definitivamente (%). Usa Eliminar: el registro se desactiva y se puede restaurar desde la Papelera.', tg_table_name
        using errcode = '42501';
    end if;
    return old;
  end if;

  -- UPDATE: dar de baja (eliminado_en) o restaurar
  if v_panel and (to_jsonb(new) ->> 'eliminado_en') is distinct from (to_jsonb(old) ->> 'eliminado_en') then
    if not v_cis and coalesce(v_rol, '') <> 'administrador' then
      raise exception 'Solo el Administrador puede eliminar (desactivar) o restaurar registros.' using errcode = '42501';
    end if;
  end if;
  return new;
end $$;

-- Papelera: lo que se eliminó (desactivó) y se puede restaurar.
create or replace view elius.v_papelera with (security_invoker = true) as
select 'producto'::text as tipo, i.id, i.nombre::text as nombre, coalesce(i.sku, '')::text as detalle, i.eliminado_en
from elius.items_catalogo i
where i.eliminado_en is not null and (app.mi_rol() = 'administrador' or app.es_super_admin())
union all
select 'cliente', c.id, btrim(c.nombres || ' ' || coalesce(c.apellidos, '')), coalesce(c.telefono, c.email, ''), c.eliminado_en
from elius.contactos c
where c.eliminado_en is not null and (app.mi_rol() = 'administrador' or app.es_super_admin());
grant select on elius.v_papelera to authenticated, service_role, elius_app;
comment on view elius.v_papelera is 'Productos y clientes eliminados (desactivados) del negocio; el Administrador los restaura, el CIS adm los borra de verdad';

-- Eliminar definitivamente: SOLO el CIS adm, y solo algo que ya está en la Papelera.
create or replace function elius.eliminar_definitivo(p_tipo text, p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_n int;
begin
  if not coalesce((select app.es_super_admin()), false) then
    raise exception 'Solo el CIS adm elimina definitivamente' using errcode = '42501';
  end if;
  if p_tipo = 'producto' then
    delete from elius.items_catalogo where id = p_id and tenant_id = app.current_tenant_id() and eliminado_en is not null;
  elsif p_tipo = 'cliente' then
    delete from elius.contactos where id = p_id and tenant_id = app.current_tenant_id() and eliminado_en is not null;
  else
    raise exception 'Tipo no válido: usa producto o cliente';
  end if;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'No está en la Papelera (primero se elimina, luego se borra definitivamente)'; end if;
  return 'eliminado definitivamente';
exception when foreign_key_violation then
  raise exception 'No se puede borrar de verdad: tiene historial (órdenes, reservas o conversaciones). Se queda desactivado.' using errcode = '23503';
end $$;
revoke all on function elius.eliminar_definitivo(text, uuid) from public, anon;
grant execute on function elius.eliminar_definitivo(text, uuid) to authenticated;
comment on function elius.eliminar_definitivo(text, uuid) is 'Borrado real de un producto o cliente que ya está en la Papelera; solo CIS adm';

do $$ declare r record;
begin
  for r in select n.nspname as esq, c.relname as tabla from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
           where t.tgname = 't00_sin_baja_directa' loop
    execute format('comment on trigger t00_sin_baja_directa on %I.%I is %L', r.esq, r.tabla,
      'Baja lógica: eliminar = desactivar (eliminado_en). Solo el Administrador desactiva o restaura; el DELETE real solo lo hace el CIS adm.');
  end loop;
end $$;
