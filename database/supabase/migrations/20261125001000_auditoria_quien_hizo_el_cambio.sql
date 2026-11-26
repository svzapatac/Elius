-- 3600 · La auditoría dice QUIÉN (correo/usuario) hizo el cambio, no solo el rol.
--  · Nueva columna usuario_email, llenada por el mismo trigger t00 (correo del token; si no hay, el de auth.users; si no, el login de BD).
--  · Los movimientos que ya existían se completan: correo por usuario_id, y la instancia/base/puerto de esta única instancia.
alter table audit.registros_auditoria add column if not exists usuario_email text;

create or replace function audit.completar_origen_conexion()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_hdr text := nullif(current_setting('request.headers', true), '');
  v_ip  text;
  v_mail text;
begin
  begin
    v_ip := nullif(trim(split_part(coalesce(v_hdr::jsonb ->> 'x-forwarded-for', ''), ',', 1)), '');
  exception when others then v_ip := null; end;
  begin v_mail := nullif(auth.jwt() ->> 'email', ''); exception when others then v_mail := null; end;
  if v_mail is null and new.usuario_id is not null then
    select email into v_mail from auth.users where id = new.usuario_id;
  end if;
  new.usuario_email := coalesce(new.usuario_email, v_mail, 'login BD: ' || session_user);
  new.instancia  := coalesce(new.instancia, host(inet_server_addr()), nullif(current_setting('cluster_name', true), ''), 'instancia-local');
  new.base_datos := coalesce(new.base_datos, current_database());
  new.puerto     := coalesce(new.puerto, inet_server_port(), nullif(current_setting('port', true), '')::int);
  new.ip_cliente := coalesce(new.ip_cliente, v_ip, host(inet_client_addr()), 'socket local');
  new.login_bd   := coalesce(new.login_bd, session_user);
  new.aplicacion := coalesce(new.aplicacion, nullif(current_setting('application_name', true), ''), 'sin nombre');
  return new;
end $$;

-- Completar lo anterior (una sola instancia: los datos de servicio son los mismos; la IP de entonces no se guardó).
update audit.registros_auditoria a set
  usuario_email = coalesce(a.usuario_email, (select u.email from auth.users u where u.id = a.usuario_id), 'script SQL (sin usuario del panel)'),
  instancia  = coalesce(a.instancia, host(inet_server_addr()), nullif(current_setting('cluster_name', true), ''), 'instancia-local'),
  base_datos = coalesce(a.base_datos, current_database()),
  puerto     = coalesce(a.puerto, inet_server_port(), nullif(current_setting('port', true), '')::int),
  ip_cliente = coalesce(a.ip_cliente, 'no registrada (anterior)'),
  login_bd   = coalesce(a.login_bd, 'no registrado (anterior)')
where a.usuario_email is null or a.instancia is null;

create or replace view elius.v_auditoria with (security_invoker = true) as
select a.id, a.tenant_id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
       m.cargo,
       case
         when a.tabla = 'consola_sql' and a.datos_nuevos ->> 'bloqueada' = 'true'
              then 'INTENTO BLOQUEADO: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 160) || ' → ' || coalesce(a.datos_nuevos ->> 'motivo', '')
         when a.tabla = 'consola_sql' then 'Consulta: ' || left(coalesce(a.datos_nuevos ->> 'sentencia', ''), 200)
         when a.tabla = 'mensajes' then 'Respondió a un cliente en una conversación (' || coalesce(a.datos_nuevos ->> 'caracteres', '0') || ' caracteres)'
         when a.operacion = 'UPDATE' then 'Cambió: ' || coalesce((
              select string_agg(k, ', ' order by k) from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'), 'sin cambios de datos')
         when a.operacion = 'INSERT' then 'Registro nuevo'
         else 'Registro eliminado'
       end as detalle,
       a.datos_anteriores, a.datos_nuevos,
       a.instancia, a.base_datos, a.puerto, a.ip_cliente, a.login_bd, a.aplicacion, a.usuario_email
from audit.registros_auditoria a
left join platform.membresias m on m.tenant_id = a.tenant_id and m.usuario_id = a.usuario_id
where a.creado_en >= timestamptz '2026-11-24 07:05:00+00'
  and not (a.tabla = 'parametros_negocio' and coalesce(a.datos_nuevos ->> 'clave', '') like 'demo\_%')
  and not (a.operacion = 'UPDATE' and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en'))
  and not (a.operacion = 'UPDATE' and a.tabla in ('conversaciones', 'identidades_contacto') and not exists (
        select 1 from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
        where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k
          and k not in ('actualizado_en', 'ultimo_mensaje_en', 'ultimo_contacto_en')))
  and not (a.tabla = 'membresias' and a.operacion = 'UPDATE' and a.usuario_id::text = a.datos_nuevos ->> 'usuario_id');
grant select on elius.v_auditoria to authenticated, service_role, elius_app;
