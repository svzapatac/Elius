-- =============================================================================
-- 1300 · Agenda tipo calendario y cambio de rol en los casos de prueba
-- =============================================================================

-- Agenda de cualquier día (el calendario del panel pide un mes completo)
create or replace view elius.v_agenda_calendario with (security_invoker = true) as
select r.tenant_id, r.id as reserva_id, r.codigo, r.tipo, r.estado, r.inicio, r.fin, r.personas,
       r.urgente, r.visto, r.llegada_en, r.notas,
       c.nombres || coalesce(' ' || c.apellidos, '') as cliente, c.telefono,
       string_agg(rc.nombre, ', ' order by rc.nombre) as recursos,
       m.cargo as responsable_cargo
from elius.reservas r
join elius.contactos c on c.tenant_id = r.tenant_id and c.id = r.contacto_id
left join elius.asignaciones_recurso ar on ar.tenant_id = r.tenant_id and ar.reserva_id = r.id and ar.estado = 'activa'
left join elius.recursos rc on rc.tenant_id = ar.tenant_id and rc.id = ar.recurso_id
left join platform.membresias m on m.tenant_id = r.tenant_id and m.id = r.responsable_id
group by r.tenant_id, r.id, c.nombres, c.apellidos, c.telefono, m.cargo;
comment on view elius.v_agenda_calendario is 'Todas las reservas con cliente y recursos (calendario del panel)';
grant select on elius.v_agenda_calendario to authenticated, service_role, elius_app;

-- El día de la agenda se cuenta en hora de Colombia, no en UTC
create or replace view elius.v_agenda_dia with (security_invoker = true) as
select tenant_id, reserva_id, codigo, tipo, estado, inicio, fin, personas, urgente, visto, llegada_en,
       cliente, telefono, recursos, responsable_cargo
from elius.v_agenda_calendario
where inicio >= (date_trunc('day', now() at time zone 'America/Bogota') at time zone 'America/Bogota')
  and inicio <  ((date_trunc('day', now() at time zone 'America/Bogota') + interval '1 day') at time zone 'America/Bogota')
  and estado in ('pendiente_pago', 'confirmada', 'asistio');

-- Quien prueba un caso puede ver el panel con cada rol del negocio (la seguridad la sigue aplicando la base)
create or replace function elius.cambiar_rol_demo(p_rol text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_tenant uuid := app.current_tenant_id(); v_rol uuid;
begin
  if v_tenant is null or not app.tiene_acceso_tenant(auth.uid(), v_tenant) then
    raise exception 'Sin acceso al negocio' using errcode = '42501';
  end if;
  if not exists (select 1 from platform.tenants where id = v_tenant and slug like 'demo-%') then
    raise exception 'Solo en los casos de prueba';
  end if;
  select id into v_rol from platform.roles where codigo = p_rol and codigo in ('administrador', 'operador', 'analista');
  if v_rol is null then raise exception 'Rol no disponible en la prueba: %', p_rol; end if;
  update platform.membresias set rol_id = v_rol, cargo = initcap(p_rol)
  where tenant_id = v_tenant and usuario_id = auth.uid();
end $$;
revoke execute on function elius.cambiar_rol_demo(text) from public, anon;
grant execute on function elius.cambiar_rol_demo(text) to authenticated;
comment on function elius.cambiar_rol_demo(text) is 'Cambia el rol de quien prueba un caso (administrador, operador o analista) para ver el panel de cada uno';

-- En los casos de prueba quien prueba puede cambiar su propio rol (el negocio de prueba es descartable)
create or replace function app.proteger_ultimo_admin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_admin uuid;
begin
  select id into v_admin from platform.roles where codigo = 'administrador';
  if old.rol_id = v_admin and old.estado = 'activo'
     and (tg_op = 'DELETE' or new.rol_id <> v_admin or new.estado <> 'activo')
     and not exists (select 1 from platform.membresias m
                     where m.tenant_id = old.tenant_id and m.id <> old.id and m.rol_id = v_admin and m.estado = 'activo')
     and exists (select 1 from platform.tenants t where t.id = old.tenant_id and t.slug not like 'demo-%') then
    raise exception 'RN-P04: el tenant debe conservar al menos un Administrador activo' using errcode = '23514';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
