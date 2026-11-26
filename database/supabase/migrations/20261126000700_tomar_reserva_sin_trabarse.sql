-- 0700 · Arreglo: tomar una reserva ya no se "pega".
--  · Causa: el panel decidía si estaba libre mirando el cargo de quien la tenía; si el cargo estaba vacío parecía libre
--    pero la base la daba por tomada y el Trabajador no podía tomarla. Ahora las vistas traen responsable_id.
--  · Tomar la reserva es del Operador; el Administrador no la toma, la ve y puede liberarla para que otro la tome.
--  · Llegó / No llegó siempre guarda quién lo marcó, aunque la reserva la tenga otra persona.
create or replace function elius.tomar_reserva(p_reserva uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_m uuid := app.mi_membresia(); v_actual uuid; v_cargo text;
begin
  if app.mi_rol() <> 'operador' or v_m is null then raise exception 'Solo el Operador toma reservas (el Administrador las asigna liberándolas)' using errcode = '42501'; end if;
  select responsable_id into v_actual from elius.reservas
   where id = p_reserva and tenant_id = app.current_tenant_id() and eliminado_en is null and estado in ('confirmada', 'pendiente_pago');
  if not found then raise exception 'La reserva no está disponible'; end if;
  if v_actual is not null and v_actual <> v_m then raise exception 'La reserva ya la tiene otra persona'; end if;
  update elius.reservas set responsable_id = v_m, visto = true where id = p_reserva and tenant_id = app.current_tenant_id();
  select coalesce(cargo, 'Equipo') into v_cargo from platform.membresias where id = v_m;
  return v_cargo;
end $$;

create or replace function elius.liberar_reserva(p_reserva uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if app.mi_rol() <> 'administrador' then raise exception 'Solo el Administrador libera una reserva' using errcode = '42501'; end if;
  update elius.reservas set responsable_id = null
   where id = p_reserva and tenant_id = app.current_tenant_id() and eliminado_en is null and estado in ('confirmada', 'pendiente_pago');
  if not found then raise exception 'La reserva no está disponible'; end if;
end $$;
revoke execute on function elius.liberar_reserva(uuid), elius.tomar_reserva(uuid) from public, anon;
grant execute on function elius.liberar_reserva(uuid), elius.tomar_reserva(uuid) to authenticated;
comment on function elius.liberar_reserva(uuid) is 'El Administrador quita al responsable de una reserva para que otro Operador la tome';
comment on function elius.tomar_reserva(uuid) is 'El Operador toma una reserva libre y queda como su responsable';

create or replace view elius.v_agenda_calendario with (security_invoker = true) as
select r.tenant_id, r.id as reserva_id, r.codigo, r.tipo, r.estado, r.inicio, r.fin, r.personas,
       r.urgente, r.visto, r.llegada_en, r.notas,
       c.nombres || coalesce(' ' || c.apellidos, '') as cliente, c.telefono,
       string_agg(rc.nombre, ', ' order by rc.nombre) as recursos,
       m.cargo as responsable_cargo,
       app.correo_miembro(m.usuario_id) as responsable_correo,
       app.correo_miembro(r.marcada_por) as marcada_por_correo,
       r.responsable_id
from elius.reservas r
join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
left join elius.asignaciones_recurso ar on ar.tenant_id = r.tenant_id and ar.reserva_id = r.id and ar.estado = 'activa'
left join elius.recursos rc on rc.tenant_id = ar.tenant_id and rc.id = ar.recurso_id
left join platform.membresias m on m.tenant_id = r.tenant_id and m.id = r.responsable_id
group by r.tenant_id, r.id, c.nombres, c.apellidos, c.telefono, m.cargo, m.usuario_id, r.marcada_por;

create or replace view elius.v_agenda_dia with (security_invoker = true) as
select tenant_id, reserva_id, codigo, tipo, estado, inicio, fin, personas, urgente, visto, llegada_en,
       cliente, telefono, recursos, responsable_cargo, responsable_correo, marcada_por_correo, responsable_id
from elius.v_agenda_calendario
where inicio >= (date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota')
  and inicio <  ((date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day') at time zone 'America/Bogota')
  and estado in ('pendiente_pago', 'confirmada', 'asistio');
