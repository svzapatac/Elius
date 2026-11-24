-- (Opcional) Crea un negocio de demostración propio del dueño del proyecto.
-- La profesora NO entra a este negocio: al iniciar sesión ella elige un caso de prueba
-- (restaurante, veterinaria o aerolínea) y el panel le crea el suyo (platform.cargar_caso_demo).
-- Antes: crea el usuario en Authentication > Users y cambia el correo de abajo.
do $$
declare
  v_dueno uuid; v_tenant uuid;
begin
  select id into v_dueno from auth.users where email = 'CORREO_DEL_DUENO@ejemplo.com';
  if v_dueno is null then raise exception 'Falta crear el usuario del dueño en Authentication'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
  v_tenant := platform.crear_tenant('Potrillos Terraza (demo)', 'potrillos-demo', 'restaurante');
  raise notice 'Negocio demo creado: %', v_tenant;
end $$;
