-- Crea el negocio de demostración y deja al profesor como Administrador.
-- Antes: crea los usuarios en Authentication > Users y cambia los dos correos de abajo.
do $$
declare
  v_dueno uuid; v_profe uuid; v_tenant uuid; v_rol uuid;
begin
  select id into v_dueno from auth.users where email = 'CORREO_DEL_DUENO@ejemplo.com';
  select id into v_profe from auth.users where email = 'CORREO_DEL_PROFESOR@ejemplo.com';
  if v_dueno is null or v_profe is null then raise exception 'Falta crear alguno de los dos usuarios en Authentication'; end if;

  -- Se actúa como el dueño (así lo hace el panel con su token)
  perform set_config('request.jwt.claims', json_build_object('sub', v_dueno, 'role', 'authenticated')::text, true);
  v_tenant := platform.crear_tenant('Potrillos Terraza (demo)', 'potrillos-demo', 'restaurante');

  select id into v_rol from platform.roles where codigo = 'administrador';
  insert into platform.membresias (tenant_id, usuario_id, rol_id, cargo, es_predeterminada)
  values (v_tenant, v_profe, v_rol, 'Profesor (revisión)', true);
  raise notice 'Negocio demo creado: %', v_tenant;
end $$;
