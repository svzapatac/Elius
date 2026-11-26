-- =============================================================================
-- 2800 · Paneles funcionales por rol: Trabajador y Soporte al cliente
-- Soporte deja de tener acceso amplio (antes: «con autorización» en contactos, pagos, órdenes, configuración…).
-- Ahora solo ve lo técnico, sin datos del cliente, a través de vistas y funciones acotadas:
--   · errores de Eli (elius.errores_agente) y eventos de salida fallidos (elius.eventos_salida), sin su contenido
--   · auditoría técnica: quién (rol), qué tabla, qué operación y qué columnas cambiaron, sin los valores
--   · estado de las integraciones (conteos)
--   · acciones puntuales: marcar un error como resuelto (con nota) y reintentar un evento fallido
-- El Trabajador puede reportar un problema (llega a Soporte) y tomar una reserva (queda como responsable).
-- =============================================================================

-- 1. Soporte: fuera de los datos del negocio (solo conserva su permiso de plataforma)
delete from platform.rol_permisos rp
using platform.roles r, platform.permisos p
where r.id = rp.rol_id and r.codigo = 'soporte' and p.id = rp.permiso_id and p.codigo <> 'plataforma';

-- 2. Reportar un problema (Trabajador, Administrador o Soporte) → queda en los errores que atiende Soporte
create or replace function elius.reportar_problema(p_mensaje text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol(); v_id uuid;
begin
  if v_rol is null or v_rol not in ('administrador', 'operador', 'soporte') then
    raise exception 'No tienes permiso para reportar problemas' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_mensaje, ''))) < 5 then raise exception 'Describe el problema (mínimo 5 caracteres)'; end if;
  insert into elius.errores_agente (tenant_id, origen, mensaje, detalle)
  values (app.current_tenant_id(), 'reporte:' || v_rol, left(btrim(p_mensaje), 500), jsonb_build_object('reportado_por_rol', v_rol))
  returning id into v_id;
  return v_id;
end $$;

-- 3. Vistas técnicas (sin datos del cliente). Solo Soporte autorizado y el Administrador del negocio
create or replace view elius.v_soporte_errores as
  select e.id, e.creado_en, e.origen, e.mensaje, e.resuelto_en, e.notas, (e.resuelto_en is null) as abierto
  from elius.errores_agente e
  where e.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador');

create or replace view elius.v_soporte_eventos as
  select v.id, v.creado_en, v.tipo_evento, v.entidad, v.estado, v.intentos, v.procesado_en
  from elius.eventos_salida v
  where v.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador');

create or replace view elius.v_soporte_auditoria as
  select x.id, x.creado_en, x.rol, x.origen, x.esquema, x.tabla, x.operacion, x.columnas_cambiadas
  from (
    select a.id, a.creado_en, a.rol, a.origen, a.esquema, a.tabla, a.operacion,
           case when a.operacion = 'UPDATE' then
             (select coalesce(array_agg(k order by k), '{}') from jsonb_object_keys(coalesce(a.datos_nuevos, '{}'::jsonb)) k
              where a.datos_nuevos -> k is distinct from a.datos_anteriores -> k and k <> 'actualizado_en')
           end as columnas_cambiadas
    from audit.registros_auditoria a
    where a.tenant_id = app.current_tenant_id() and app.mi_rol() in ('soporte', 'administrador')
      and a.creado_en >= now() - interval '30 days'
      and a.tabla not in ('consola_sql', 'mensajes')
      and not (a.tabla = 'parametros_negocio' and coalesce(a.datos_nuevos ->> 'clave', '') like 'demo\_%')
  ) x
  where x.operacion <> 'UPDATE' or cardinality(x.columnas_cambiadas) > 0;

grant select on elius.v_soporte_errores, elius.v_soporte_eventos, elius.v_soporte_auditoria to authenticated;

-- 4. Acciones acotadas de Soporte
create or replace function elius.soporte_resolver_error(p_id uuid, p_nota text)
returns void language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol();
begin
  if v_rol is null or v_rol not in ('soporte', 'administrador') then raise exception 'Solo Soporte o el Administrador' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_nota, ''))) < 3 then raise exception 'Escribe una nota de cómo se resolvió'; end if;
  update elius.errores_agente
     set resuelto_en = now(), resuelto_por = app.mi_membresia(),
         notas = left(coalesce(notas || E'\n', '') || initcap(v_rol) || ': ' || btrim(p_nota), 1000)
   where id = p_id and tenant_id = app.current_tenant_id() and resuelto_en is null;
  if not found then raise exception 'El error no existe o ya está resuelto'; end if;
end $$;

create or replace function elius.soporte_reintentar_evento(p_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol();
begin
  if v_rol is null or v_rol not in ('soporte', 'administrador') then raise exception 'Solo Soporte o el Administrador' using errcode = '42501'; end if;
  update elius.eventos_salida set estado = 'pendiente'
   where id = p_id and tenant_id = app.current_tenant_id() and estado = 'fallido';
  if not found then raise exception 'El evento no existe o no está fallido'; end if;
end $$;

create or replace function elius.soporte_estado_integraciones()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_rol text := app.mi_rol(); t uuid := app.current_tenant_id();
begin
  if v_rol is null or v_rol not in ('soporte', 'administrador') then raise exception 'Solo Soporte o el Administrador' using errcode = '42501'; end if;
  return jsonb_build_object(
    'errores_abiertos', (select count(*) from elius.errores_agente where tenant_id = t and resuelto_en is null),
    'eventos_fallidos', (select count(*) from elius.eventos_salida where tenant_id = t and estado = 'fallido'),
    'eventos_pendientes', (select count(*) from elius.eventos_salida where tenant_id = t and estado = 'pendiente'),
    'ultimo_evento_enviado', (select max(procesado_en) from elius.eventos_salida where tenant_id = t and estado = 'enviado'),
    'avisos_push_configurados', exists (select 1 from platform.ajustes_globales where clave = 'push_service_url' and coalesce(valor, '') <> ''),
    'dispositivos_con_avisos', (select count(*) from platform.push_suscripciones s join platform.membresias m on m.usuario_id = s.usuario_id and m.tenant_id = t where s.activo),
    'eli_encendida', coalesce((select a.activo from elius.agentes a where a.tenant_id = t order by a.version desc limit 1), false));
end $$;

-- 5. Negocios que le autorizaron a Soporte (el panel de Soporte los lista; no ve más datos del negocio)
create or replace function platform.negocios_autorizados_soporte()
returns table (id uuid, nombre text, slug text, vertical text, vence_en timestamptz)
language sql stable security definer set search_path = '' as $$
  select t.id, t.nombre, t.slug, t.vertical, max(a.vence_en)
  from platform.accesos_soporte a join platform.tenants t on t.id = a.tenant_id
  where a.usuario_soporte_id = app.uid() and a.revocado_en is null and now() >= a.inicio and now() < a.vence_en
  group by t.id, t.nombre, t.slug, t.vertical order by t.nombre;
$$;

-- 6. El Trabajador toma una reserva: queda como responsable (quién la atiende)
create or replace function elius.tomar_reserva(p_reserva uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare v_m uuid := app.mi_membresia(); v_cargo text;
begin
  if app.mi_rol() not in ('administrador', 'operador') or v_m is null then raise exception 'Solo el equipo del negocio toma reservas' using errcode = '42501'; end if;
  update elius.reservas set responsable_id = v_m, visto = true
   where id = p_reserva and tenant_id = app.current_tenant_id() and (responsable_id is null or responsable_id = v_m) and estado in ('confirmada', 'pendiente_pago');
  if not found then raise exception 'La reserva ya la tiene otra persona o no está disponible'; end if;
  select coalesce(cargo, 'Equipo') into v_cargo from platform.membresias where id = v_m;
  return v_cargo;
end $$;

revoke execute on function elius.reportar_problema(text), elius.soporte_resolver_error(uuid, text), elius.soporte_reintentar_evento(uuid),
  elius.soporte_estado_integraciones(), platform.negocios_autorizados_soporte(), elius.tomar_reserva(uuid) from public, anon;
grant execute on function elius.reportar_problema(text), elius.soporte_resolver_error(uuid, text), elius.soporte_reintentar_evento(uuid),
  elius.soporte_estado_integraciones(), platform.negocios_autorizados_soporte(), elius.tomar_reserva(uuid) to authenticated;
comment on function elius.reportar_problema(text) is 'El Trabajador (o el Administrador) reporta un problema; queda en los errores que atiende Soporte';
comment on function elius.soporte_resolver_error(uuid, text) is 'Soporte/Administrador marca un error como resuelto, con una nota';
comment on function elius.soporte_reintentar_evento(uuid) is 'Soporte/Administrador deja un evento de salida fallido otra vez en pendiente para que se reintente';
comment on function elius.soporte_estado_integraciones() is 'Conteos de salud (errores, eventos, avisos) sin datos del cliente';
comment on function platform.negocios_autorizados_soporte() is 'Negocios con una autorización vigente para el usuario de Soporte';
comment on function elius.tomar_reserva(uuid) is 'El Trabajador toma una reserva y queda como su responsable';
