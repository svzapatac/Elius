-- Paso final: convertir TU usuario en Super Admin de la plataforma.
-- 1) Crea tu usuario en Supabase: Authentication > Users > Add user (correo y contraseña).
-- 2) Cambia el correo de abajo por el tuyo y ejecuta.
insert into platform.asignaciones_plataforma (usuario_id, rol_id, asignado_por, desde)
select u.id, r.id, u.id, now()
  from auth.users u, platform.roles r
 where u.email = 'TU_CORREO@ejemplo.com' and r.codigo = 'super_admin';
-- Debe responder "INSERT 0 1". Si responde "INSERT 0 0", el correo no existe en Authentication.
