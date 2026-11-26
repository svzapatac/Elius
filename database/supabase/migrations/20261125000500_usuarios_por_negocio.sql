-- Un solo login para todos: cada persona entra con su correo y contraseña y el panel la lleva a SU negocio y a SU rol.
-- Se crean usuarios de ejemplo por tipo de negocio (solo en los negocios de demostración), sin contraseña (la fija quien instala):
--   trabajador.restaurante@ / trabajador.veterinaria@ / trabajador.aerolinea@  (Trabajador de ese negocio)
--   admin.restaurante@      / admin.veterinaria@      / admin.aerolinea@       (Administrador de ese negocio)

create or replace function platform.completar_usuarios_auth() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'auth' and table_name = 'users' and column_name = 'instance_id') then
    update auth.users set
      instance_id = coalesce(instance_id, '00000000-0000-0000-0000-000000000000'),
      aud = coalesce(aud, 'authenticated'), role = coalesce(role, 'authenticated'),
      created_at = coalesce(created_at, now()), updated_at = coalesce(updated_at, now()),
      email_confirmed_at = coalesce(email_confirmed_at, now()),
      raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || '{"provider":"email","providers":["email"]}'::jsonb,
      confirmation_token = coalesce(confirmation_token, ''), recovery_token = coalesce(recovery_token, ''),
      email_change = coalesce(email_change, ''), email_change_token_new = coalesce(email_change_token_new, ''),
      email_change_token_current = coalesce(email_change_token_current, ''), phone_change = coalesce(phone_change, ''),
      phone_change_token = coalesce(phone_change_token, ''), reauthentication_token = coalesce(reauthentication_token, '')
    where email like '%@elius.local';
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    select gen_random_uuid(), u.id, u.id::text,
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
           'email', now(), now(), now()
    from auth.users u
    where u.email like '%@elius.local'
      and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email');
  end if;
end $$;
revoke execute on function platform.completar_usuarios_auth() from public, anon, authenticated;

create or replace function platform.asignar_usuarios_por_negocio(p_tenant uuid default null)
returns int language plpgsql security definer set search_path = '' as $$
declare x record; t record; v_n int := 0; v_adm uuid; v_ope uuid;
begin
  select id into v_adm from platform.roles where codigo = 'administrador';
  select id into v_ope from platform.roles where codigo = 'operador';
  for x in select * from (values
      ('00000000-0000-0000-0000-00000000c101'::uuid, 'trabajador.restaurante@elius.local', 'restaurante', 'operador'),
      ('00000000-0000-0000-0000-00000000c102'::uuid, 'trabajador.veterinaria@elius.local', 'veterinaria', 'operador'),
      ('00000000-0000-0000-0000-00000000c103'::uuid, 'trabajador.aerolinea@elius.local',   'aerolinea',   'operador'),
      ('00000000-0000-0000-0000-00000000c201'::uuid, 'admin.restaurante@elius.local',      'restaurante', 'administrador'),
      ('00000000-0000-0000-0000-00000000c202'::uuid, 'admin.veterinaria@elius.local',      'veterinaria', 'administrador'),
      ('00000000-0000-0000-0000-00000000c203'::uuid, 'admin.aerolinea@elius.local',        'aerolinea',   'administrador')) v(id, email, vertical, rol) loop
    if not exists (select 1 from auth.users where id = x.id) then
      insert into auth.users (id, email) values (x.id, x.email);
    end if;
    for t in select id from platform.tenants
             where eliminado_en is null and vertical = x.vertical and slug like 'demo-%' and (p_tenant is null or id = p_tenant) loop
      insert into platform.membresias (tenant_id, usuario_id, rol_id, estado, cargo)
      values (t.id, x.id, case x.rol when 'administrador' then v_adm else v_ope end, 'activo',
              case x.rol when 'administrador' then 'Administrador' else 'Trabajador' end || ' de ' || x.vertical)
      on conflict (tenant_id, usuario_id) do nothing;
      v_n := v_n + 1;
    end loop;
  end loop;
  perform platform.completar_usuarios_auth();
  return v_n;
end $$;
revoke execute on function platform.asignar_usuarios_por_negocio(uuid) from public, anon, authenticated;

create or replace function platform.asignar_usuarios_por_negocio_trg() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform platform.asignar_usuarios_por_negocio(new.id);
  return new;
end $$;
drop trigger if exists t91_usuarios_por_negocio on platform.tenants;
create trigger t91_usuarios_por_negocio after insert on platform.tenants for each row execute function platform.asignar_usuarios_por_negocio_trg();

select platform.asignar_usuarios_por_negocio(null);
