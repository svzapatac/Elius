-- Los 4 usuarios de conexión directa (bd.*@elius.local) también pueden entrar al panel con correo y contraseña.
-- Supabase Auth necesita en cada usuario: id de instancia, fechas, textos vacíos (no nulos) y una identidad de correo.
-- Esta migración es idempotente: si ya estaba bien, no cambia nada. La contraseña NO se fija aquí (la pone quien instala).
do $$
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
    where email like 'bd.%@elius.local';
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    select gen_random_uuid(), u.id, u.id::text,
           jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
           'email', now(), now(), now()
    from auth.users u
    where u.email like 'bd.%@elius.local'
      and not exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email');
  end if;
end $$;
