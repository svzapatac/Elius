-- 3400 · El Trabajador ve el estado de los problemas que reportó (y la nota con la que Soporte los resolvió), en vivo.
create or replace function elius.reportar_problema(p_mensaje text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_rol text := app.mi_rol(); v_id uuid;
begin
  if v_rol is null or v_rol not in ('administrador', 'operador', 'soporte') then
    raise exception 'No tienes permiso para reportar problemas' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_mensaje, ''))) < 5 then raise exception 'Describe el problema (mínimo 5 caracteres)'; end if;
  insert into elius.errores_agente (tenant_id, origen, mensaje, detalle)
  values (app.current_tenant_id(), 'reporte:' || v_rol, left(btrim(p_mensaje), 500),
          jsonb_build_object('reportado_por_rol', v_rol, 'membresia', app.mi_membresia()))
  returning id into v_id;
  return v_id;
end $$;

create or replace view elius.v_mis_reportes as
  select e.id, e.creado_en, e.mensaje, e.resuelto_en, e.notas, (e.resuelto_en is null) as abierto
  from elius.errores_agente e
  where e.tenant_id = app.current_tenant_id()
    and e.origen like 'reporte:%'
    and app.mi_rol() in ('operador', 'administrador')
    and (app.mi_rol() = 'administrador' or e.detalle ->> 'membresia' = app.mi_membresia()::text);
grant select on elius.v_mis_reportes to authenticated;
comment on view elius.v_mis_reportes is 'Problemas reportados por la persona (el Administrador ve los de todo el negocio) con el estado que les da Soporte';
