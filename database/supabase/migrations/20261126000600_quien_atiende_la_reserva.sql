-- 0600 · Quién tomó / atendió cada reserva queda guardado y lo ve el Administrador en Agenda y Reservas (sin paneles nuevos).
--  · reservas.marcada_por: quién marcó "Llegó" o "No llegó" (lo pone un trigger, automático).
--  · Si nadie la había tomado, quien marca la llegada queda como responsable.
--  · Las vistas de agenda muestran el correo y el cargo de esa persona.
alter table elius.reservas add column if not exists marcada_por uuid;
comment on column elius.reservas.marcada_por is 'Usuario que marcó Llegó / No llegó (automático)';

-- correo de una persona del mismo negocio (auth.users no es legible desde el panel)
create or replace function app.correo_miembro(p_usuario uuid) returns text
language sql stable security definer set search_path = '' as $$
  select u.email::text from auth.users u
  where u.id = p_usuario and app.current_tenant_id() is not null
    and exists (select 1 from platform.membresias m where m.usuario_id = u.id and m.tenant_id = app.current_tenant_id());
$$;
revoke execute on function app.correo_miembro(uuid) from public, anon;
grant execute on function app.correo_miembro(uuid) to authenticated, service_role, elius_app;

create or replace function app.reserva_marcada_por() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estado in ('asistio', 'no_asistio') and new.estado is distinct from old.estado and auth.uid() is not null then
    new.marcada_por := auth.uid();
    if new.responsable_id is null and app.mi_rol() in ('administrador', 'operador') then new.responsable_id := app.mi_membresia(); end if;
  end if;
  return new;
end $$;
drop trigger if exists t06_marcada_por on elius.reservas;
create trigger t06_marcada_por before update on elius.reservas for each row execute function app.reserva_marcada_por();
comment on trigger t06_marcada_por on elius.reservas is 'Guarda quién marcó Llegó / No llegó y, si no tenía responsable, lo deja como responsable';

create or replace view elius.v_agenda_calendario with (security_invoker = true) as
select r.tenant_id, r.id as reserva_id, r.codigo, r.tipo, r.estado, r.inicio, r.fin, r.personas,
       r.urgente, r.visto, r.llegada_en, r.notas,
       c.nombres || coalesce(' ' || c.apellidos, '') as cliente, c.telefono,
       string_agg(rc.nombre, ', ' order by rc.nombre) as recursos,
       m.cargo as responsable_cargo,
       app.correo_miembro(m.usuario_id) as responsable_correo,
       app.correo_miembro(r.marcada_por) as marcada_por_correo
from elius.reservas r
join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
left join elius.asignaciones_recurso ar on ar.tenant_id = r.tenant_id and ar.reserva_id = r.id and ar.estado = 'activa'
left join elius.recursos rc on rc.tenant_id = ar.tenant_id and rc.id = ar.recurso_id
left join platform.membresias m on m.tenant_id = r.tenant_id and m.id = r.responsable_id
group by r.tenant_id, r.id, c.nombres, c.apellidos, c.telefono, m.cargo, m.usuario_id, r.marcada_por;

create or replace view elius.v_agenda_dia with (security_invoker = true) as
select tenant_id, reserva_id, codigo, tipo, estado, inicio, fin, personas, urgente, visto, llegada_en,
       cliente, telefono, recursos, responsable_cargo, responsable_correo, marcada_por_correo
from elius.v_agenda_calendario
where inicio >= (date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota')
  and inicio <  ((date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day') at time zone 'America/Bogota')
  and estado in ('pendiente_pago', 'confirmada', 'asistio');
