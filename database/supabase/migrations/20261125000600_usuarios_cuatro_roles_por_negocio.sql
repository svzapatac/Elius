-- Cuatro roles por cada tipo de negocio (restaurante, veterinaria, aerolínea) = 12 usuarios de ejemplo, sin contraseña:
--   superadmin.<negocio>@  Super Administrador: administrador del negocio + rol de plataforma super_admin (puede borrar; no puede hacer DROP)
--   admin.<negocio>@       Administrador del negocio
--   trabajador.<negocio>@  Trabajador (panel especializado del negocio)
--   soporte.<negocio>@     Soporte al cliente: solo ve lo técnico de ESE negocio, con autorización de 7 días renovable
-- Los usuarios de ejemplo (@elius.local) no cuentan para el límite de usuarios del plan (RN-P10)
create or replace function app.validar_limite_usuarios()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_max int; v_actual int;
begin
  if exists (select 1 from platform.accesos_bd where usuario_id = new.usuario_id)
     or exists (select 1 from auth.users u where u.id = new.usuario_id and u.email like '%@elius.local') then return new; end if;
  select p.max_usuarios into v_max from platform.tenants t join platform.planes p on p.id = t.plan_id where t.id = new.tenant_id;
  select count(*) into v_actual from platform.membresias m
  where m.tenant_id = new.tenant_id and m.estado <> 'inactivo'
    and not exists (select 1 from platform.accesos_bd b where b.usuario_id = m.usuario_id)
    and not exists (select 1 from auth.users u where u.id = m.usuario_id and u.email like '%@elius.local');
  if v_actual >= v_max then
    raise exception 'RN-P10: el plan permite máximo % usuarios', v_max using errcode = '23514';
  end if;
  return new;
end $$;

create or replace function platform.asignar_usuarios_por_negocio(p_tenant uuid default null)
returns int language plpgsql security definer set search_path = '' as $$
declare x record; t record; v_n int := 0; v_adm uuid; v_ope uuid; v_sa uuid; v_sop uuid;
begin
  select id into v_adm from platform.roles where codigo = 'administrador';
  select id into v_ope from platform.roles where codigo = 'operador';
  select id into v_sa  from platform.roles where codigo = 'super_admin';
  select id into v_sop from platform.roles where codigo = 'soporte';
  for x in select * from (values
      ('00000000-0000-0000-0000-00000000c001'::uuid, 'superadmin.restaurante@elius.local', 'restaurante', 'super_admin'),
      ('00000000-0000-0000-0000-00000000c002'::uuid, 'superadmin.veterinaria@elius.local', 'veterinaria', 'super_admin'),
      ('00000000-0000-0000-0000-00000000c003'::uuid, 'superadmin.aerolinea@elius.local',   'aerolinea',   'super_admin'),
      ('00000000-0000-0000-0000-00000000c201'::uuid, 'admin.restaurante@elius.local',      'restaurante', 'administrador'),
      ('00000000-0000-0000-0000-00000000c202'::uuid, 'admin.veterinaria@elius.local',      'veterinaria', 'administrador'),
      ('00000000-0000-0000-0000-00000000c203'::uuid, 'admin.aerolinea@elius.local',        'aerolinea',   'administrador'),
      ('00000000-0000-0000-0000-00000000c101'::uuid, 'trabajador.restaurante@elius.local', 'restaurante', 'operador'),
      ('00000000-0000-0000-0000-00000000c102'::uuid, 'trabajador.veterinaria@elius.local', 'veterinaria', 'operador'),
      ('00000000-0000-0000-0000-00000000c103'::uuid, 'trabajador.aerolinea@elius.local',   'aerolinea',   'operador'),
      ('00000000-0000-0000-0000-00000000c301'::uuid, 'soporte.restaurante@elius.local',    'restaurante', 'soporte'),
      ('00000000-0000-0000-0000-00000000c302'::uuid, 'soporte.veterinaria@elius.local',    'veterinaria', 'soporte'),
      ('00000000-0000-0000-0000-00000000c303'::uuid, 'soporte.aerolinea@elius.local',      'aerolinea',   'soporte')) v(id, email, vertical, rol) loop
    if not exists (select 1 from auth.users where id = x.id) then
      insert into auth.users (id, email) values (x.id, x.email);
    end if;
    -- Rol de plataforma (una sola vez por usuario)
    if x.rol in ('super_admin', 'soporte') and not exists (select 1 from platform.asignaciones_plataforma where usuario_id = x.id and hasta is null) then
      insert into platform.asignaciones_plataforma (usuario_id, rol_id, asignado_por)
      values (x.id, case x.rol when 'super_admin' then v_sa else v_sop end, '00000000-0000-0000-0000-00000000bd01');
    end if;
    for t in select id from platform.tenants
             where eliminado_en is null and vertical = x.vertical and slug like 'demo-%' and (p_tenant is null or id = p_tenant) loop
      if x.rol = 'soporte' then
        -- Soporte no es parte del equipo del negocio: solo entra con una autorización vigente (máximo 7 días)
        if not exists (select 1 from platform.accesos_soporte a where a.tenant_id = t.id and a.usuario_soporte_id = x.id
                       and a.revocado_en is null and a.vence_en > now() + interval '1 day') then
          insert into platform.accesos_soporte (tenant_id, usuario_soporte_id, autorizado_por, inicio, vence_en, motivo)
          values (t.id, x.id, '00000000-0000-0000-0000-00000000bd01', now(), now() + interval '7 days', 'Soporte al cliente de este negocio');
        end if;
      else
        insert into platform.membresias (tenant_id, usuario_id, rol_id, estado, cargo)
        values (t.id, x.id, case when x.rol = 'operador' then v_ope else v_adm end, 'activo',
                case x.rol when 'super_admin' then 'Super Administrador' when 'administrador' then 'Administrador' else 'Trabajador' end || ' de ' || x.vertical)
        on conflict (tenant_id, usuario_id) do nothing;
      end if;
      v_n := v_n + 1;
    end loop;
  end loop;
  perform platform.completar_usuarios_auth();
  return v_n;
end $$;
revoke execute on function platform.asignar_usuarios_por_negocio(uuid) from public, anon, authenticated;

-- Renovar a la vez el soporte de las conexiones directas y el de estos usuarios
create or replace function platform.renovar_soporte_bd() returns int language sql security definer set search_path = '' as $$
  select platform.sincronizar_accesos_bd(null) + platform.asignar_usuarios_por_negocio(null);
$$;
revoke execute on function platform.renovar_soporte_bd() from public, anon, authenticated;
grant execute on function platform.renovar_soporte_bd() to elius_superadmin;

select platform.asignar_usuarios_por_negocio(null) as asignaciones;
